## File Service
## Coordinates file operations and project management

import std/[os, tables, sequtils, strutils, options, times, algorithm]
import ../shared/[errors, types]
import ../domain
import ../infrastructure/filesystem/file_manager
import chronos
import ../infrastructure/external/git_client

# File service state
type FileService* = ref object # Infrastructure dependencies
  fileManager*: FileManager
  gitClient*: Option[GitClient]

  # Current workspace and project
  workspace*: Option[Workspace]
  currentProject*: Option[Project]

  # File watching
  watchedFiles*: Table[string, Time]
  fileChangeCallbacks*: Table[string, proc(filePath: string)]

  # Recent operations
  recentDirectories*: seq[string]
  maxRecentDirectories*: int

  # Settings
  showHiddenFiles*: bool
  followSymlinks*: bool
  maxFileSize*: int64 # Maximum file size to open in bytes
  autoRefreshInterval*: int # seconds

  # Event callbacks
  onProjectOpened*: proc(service: FileService, project: Project)
  onProjectClosed*: proc(service: FileService)
  onFileChanged*: proc(service: FileService, filePath: string)
  onWorkspaceChanged*: proc(service: FileService, workspace: Workspace)

# Service creation
proc newFileService*(fileManager: FileManager): FileService =
  FileService(
    fileManager: fileManager,
    gitClient: none(GitClient),
    workspace: none(Workspace),
    currentProject: none(Project),
    watchedFiles: initTable[string, Time](),
    fileChangeCallbacks: initTable[string, proc(filePath: string)](),
    recentDirectories: @[],
    maxRecentDirectories: 20,
    showHiddenFiles: false,
    followSymlinks: true,
    maxFileSize: 100 * 1024 * 1024, # 100MB
    autoRefreshInterval: 5,
    onProjectOpened: nil,
    onProjectClosed: nil,
    onFileChanged: nil,
    onWorkspaceChanged: nil,
  )

# Basic file operations
proc readFile*(service: FileService, filePath: string): Result[string, EditorError] =
  # Check file size
  try:
    let info = getFileInfo(filePath)
    if info.size > service.maxFileSize:
      return err(
        EditorError(
          msg: "File too large: " & $info.size & " bytes", code: "FILE_TOO_LARGE"
        )
      )
  except:
    return err(EditorError(msg: "Cannot access file", code: "FILE_ACCESS_ERROR"))

  service.fileManager.readFile(filePath)

proc writeFile*(
    service: FileService, filePath: string, content: string
): Result[void, EditorError] =
  let writeResult = service.fileManager.writeFile(filePath, content)

  if writeResult.isOk:
    # Update watched file timestamp
    if filePath in service.watchedFiles:
      service.watchedFiles[filePath] = getTime()

    # Trigger file change callback
    if service.onFileChanged != nil:
      service.onFileChanged(service, filePath)

  writeResult

proc createFile*(
    service: FileService, filePath: string, content: string = ""
): Result[void, EditorError] =
  if fileExists(filePath):
    return err(EditorError(msg: "File already exists", code: "FILE_EXISTS"))

  service.writeFile(filePath, content)

proc deleteFile*(service: FileService, filePath: string): Result[void, EditorError] =
  try:
    removeFile(filePath)

    # Remove from watched files
    service.watchedFiles.del(filePath)

    # Update current project if file is deleted
    if service.currentProject.isSome:
      let project = service.currentProject.get()
      discard project.removeFile(filePath)

    ok()
  except OSError as e:
    err(EditorError(msg: "Failed to delete file: " & e.msg, code: "DELETE_FAILED"))

proc moveFile*(
    service: FileService, sourcePath: string, destPath: string
): Result[void, EditorError] =
  try:
    moveFile(sourcePath, destPath)

    # Update watched files
    if sourcePath in service.watchedFiles:
      let timestamp = service.watchedFiles[sourcePath]
      service.watchedFiles.del(sourcePath)
      service.watchedFiles[destPath] = timestamp

    # Update current project
    if service.currentProject.isSome:
      let project = service.currentProject.get()
      discard project.removeFile(sourcePath)
      discard project.addFile(destPath)

    ok()
  except OSError as e:
    err(EditorError(msg: "Failed to move file: " & e.msg, code: "MOVE_FAILED"))

proc copyFile*(
    service: FileService, sourcePath: string, destPath: string
): Result[void, EditorError] =
  try:
    copyFile(sourcePath, destPath)
    ok()
  except OSError as e:
    err(EditorError(msg: "Failed to copy file: " & e.msg, code: "COPY_FAILED"))

# Directory operations
proc createDirectory*(
    service: FileService, dirPath: string
): Result[void, EditorError] =
  try:
    createDir(dirPath)
    ok()
  except OSError as e:
    err(
      EditorError(
        msg: "Failed to create directory: " & e.msg, code: "CREATE_DIR_FAILED"
      )
    )

proc deleteDirectory*(
    service: FileService, dirPath: string, recursive: bool = false
): Result[void, EditorError] =
  try:
    if recursive:
      removeDir(dirPath)
    else:
      removeDir(dirPath)

    # Remove any watched files in this directory
    var filesToRemove: seq[string] = @[]
    for watchedPath in service.watchedFiles.keys:
      if watchedPath.startsWith(dirPath):
        filesToRemove.add(watchedPath)

    for filePath in filesToRemove:
      service.watchedFiles.del(filePath)

    ok()
  except OSError as e:
    err(
      EditorError(
        msg: "Failed to delete directory: " & e.msg, code: "DELETE_DIR_FAILED"
      )
    )

proc listDirectory*(
    service: FileService, dirPath: string
): Result[seq[FileNode], EditorError] =
  if not dirExists(dirPath):
    return
      err(EditorError(msg: "Directory does not exist", code: "DIRECTORY_NOT_FOUND"))

  var files: seq[FileNode] = @[]

  try:
    for kind, path in walkDir(dirPath):
      let fileName = extractFilename(path)

      # Skip hidden files if not showing them
      if not service.showHiddenFiles and fileName.startsWith("."):
        continue

      let isDir = (kind == pcDir)
      let node = newFileNode(fileName, path, isDir)

      # Get file info
      try:
        let info = getFileInfo(path, followSymlink = service.followSymlinks)
        node.size = info.size
        node.lastModified = info.lastWriteTime
      except:
        discard # Use defaults

      files.add(node)

    # Sort: directories first, then files, both alphabetically
    files.sort(
      proc(a, b: FileNode): int =
        if a.isDirectory and not b.isDirectory:
          -1
        elif not a.isDirectory and b.isDirectory:
          1
        else:
          cmp(a.name.toLower(), b.name.toLower())
    )

    ok(files)
  except OSError as e:
    err(EditorError(msg: "Failed to list directory: " & e.msg, code: "LIST_DIR_FAILED"))

# Recent directories management
proc addRecentDirectory*(service: FileService, dirPath: string) =
  let normalizedPath = dirPath.absolutePath()

  # Remove if already exists
  let index = service.recentDirectories.find(normalizedPath)
  if index >= 0:
    service.recentDirectories.delete(index)

  # Add to front
  service.recentDirectories.insert(normalizedPath, 0)

  # Limit size
  if service.recentDirectories.len > service.maxRecentDirectories:
    service.recentDirectories.setLen(service.maxRecentDirectories)

proc getRecentDirectories*(service: FileService): seq[string] =
  service.recentDirectories.filterIt(dirExists(it))

proc clearRecentDirectories*(service: FileService) =
  service.recentDirectories.setLen(0)

# Project operations
proc openProject*(
    service: FileService, projectPath: string
): Future[Result[Project, EditorError]] {.async, gcsafe.} =
  if not dirExists(projectPath):
    return err(
      EditorError(msg: "Project directory does not exist", code: "PROJECT_NOT_FOUND")
    )

  let projectName = extractFilename(projectPath)
  let project = newProject(projectName, projectPath)

  # Scan the project directory
  let refreshResult = project.refreshFileTree()
  if refreshResult.isErr:
    return err(refreshResult.error)

  # Detect project type
  project.projectType = project.detectProjectType()

  # Load configuration
  let configResult = project.loadConfig("")
  if configResult.isErr:
    return err(configResult.error)

  # Initialize git if available
  if service.gitClient.isSome:
    let gitInfo = await service.gitClient.get().getRepositoryInfo(projectPath)
    if gitInfo.isOk:
      let repo = gitInfo.get()
      project.gitInfo = some(GitInfo(
        branch: repo.currentBranch,
        hasChanges: repo.hasChanges,
        ahead: 0, # Would need to calculate from git status
        behind: 0  # Would need to calculate from git status
      ))
    else:
      project.gitInfo = none(GitInfo)

  project.isInitialized = true
  service.currentProject = some(project)

  # Add to workspace if one exists
  if service.workspace.isSome:
    service.workspace.get().addProject(project)

  # Add to recent directories
  service.addRecentDirectory(projectPath)

  # TODO: Handle callback safely in async context
  # if service.onProjectOpened != nil:
  #   service.onProjectOpened(service, project)

  result = ok(project)

proc closeProject*(service: FileService): Result[void, EditorError] =
  if service.currentProject.isNone:
    return err(EditorError(msg: "No project currently open", code: "NO_ACTIVE_PROJECT"))

  service.currentProject = none(Project)

  # Trigger callback
  if service.onProjectClosed != nil:
    service.onProjectClosed(service)

  ok()

proc createProject*(
    service: FileService, projectPath: string, tmpl: ProjectTemplate
): Result[Project, EditorError] =
  if dirExists(projectPath):
    return err(EditorError(msg: "Directory already exists", code: "DIRECTORY_EXISTS"))

  let projectName = extractFilename(projectPath)
  return tmpl.createFromTemplate(projectPath, projectName)

proc refreshProject*(service: FileService): Result[void, EditorError] =
  if service.currentProject.isNone:
    return err(EditorError(msg: "No project currently open", code: "NO_ACTIVE_PROJECT"))

  let project = service.currentProject.get()
  return project.refreshFileTree()

proc getProjectFiles*(service: FileService, extension: string = ""): seq[FileNode] =
  if service.currentProject.isNone:
    return @[]

  let project = service.currentProject.get()
  if project.fileTree == nil:
    return @[]

  if extension.len == 0:
    getAllFiles(project.fileTree)
  else:
    getFilesByExtension(project.fileTree, extension)

# Workspace operations
proc createWorkspace*(service: FileService, name: string): Workspace =
  let workspace = newWorkspace(name)
  service.workspace = some(workspace)

  if service.onWorkspaceChanged != nil:
    service.onWorkspaceChanged(service, workspace)

  workspace

proc openWorkspace*(
    service: FileService, workspaceFile: string
): Result[Workspace, EditorError] =
  # This would load workspace from file
  # For now, create a basic workspace
  let workspace =
    newWorkspace(extractFilename(workspaceFile).replace(".folx-workspace", ""))
  workspace.workspaceFile = workspaceFile
  service.workspace = some(workspace)

  if service.onWorkspaceChanged != nil:
    service.onWorkspaceChanged(service, workspace)

  ok(workspace)

proc saveWorkspace*(service: FileService): Result[void, EditorError] =
  if service.workspace.isNone:
    return err(EditorError(msg: "No workspace to save", code: "NO_WORKSPACE"))

  # Would save workspace to file
  ok()

proc addProjectToWorkspace*(
    service: FileService, projectPath: string
): Future[Result[void, EditorError]] {.async, gcsafe.} =
  if service.workspace.isNone:
    result = err(EditorError(msg: "No workspace open", code: "NO_WORKSPACE"))
    return

  let projectResult = await service.openProject(projectPath)
  if projectResult.isErr:
    result = err(projectResult.error)
    return

  # Project is automatically added to workspace in openProject
  result = ok()

# File watching
proc watchFile*(
    service: FileService, filePath: string, callback: proc(filePath: string) = nil
) =
  service.watchedFiles[filePath] = getTime()
  if callback != nil:
    service.fileChangeCallbacks[filePath] = callback

proc unwatchFile*(service: FileService, filePath: string) =
  service.watchedFiles.del(filePath)
  service.fileChangeCallbacks.del(filePath)

proc checkFileChanges*(service: FileService): seq[string] =
  var changedFiles: seq[string] = @[]

  for filePath, lastChecked in service.watchedFiles:
    try:
      let info = getFileInfo(filePath)
      if info.lastWriteTime > lastChecked:
        changedFiles.add(filePath)
        service.watchedFiles[filePath] = getTime()

        # Call specific callback if registered
        if filePath in service.fileChangeCallbacks:
          service.fileChangeCallbacks[filePath](filePath)

        # Call global callback
        if service.onFileChanged != nil:
          service.onFileChanged(service, filePath)
    except:
      # File might have been deleted
      service.unwatchFile(filePath)

  changedFiles

# Search operations
proc searchFiles*(
    service: FileService, query: string, caseSensitive: bool = false
): seq[FileNode] =
  if service.currentProject.isNone:
    return @[]

  service.currentProject.get().searchFiles(query, caseSensitive)

proc searchInFiles*(
    service: FileService,
    query: string,
    filePattern: string = "*",
    caseSensitive: bool = false,
): seq[tuple[file: string, matches: seq[tuple[line: int, content: string]]]] =
  if service.currentProject.isNone:
    return @[]

  # This would search file contents - implementation depends on file reading
  @[]



# File utilities
proc getFileInfo*(
    service: FileService, filePath: string
): Result[tuple[size: int64, modified: Time, isDirectory: bool], EditorError] =
  try:
    let info = getFileInfo(filePath)
    ok((size: info.size, modified: info.lastWriteTime, isDirectory: info.kind == pcDir))
  except OSError as e:
    err(EditorError(msg: "Cannot get file info: " & e.msg, code: "FILE_INFO_ERROR"))

proc fileExists*(service: FileService, filePath: string): bool =
  fileExists(filePath)

proc directoryExists*(service: FileService, dirPath: string): bool =
  dirExists(dirPath)

proc isFileInProject*(service: FileService, filePath: string): bool =
  if service.currentProject.isNone:
    return false

  service.currentProject.get().isValidPath(filePath)

proc getRelativePathInProject*(service: FileService, filePath: string): string =
  if service.currentProject.isNone:
    return filePath

  let project = service.currentProject.get()
  if project.fileTree != nil:
    let node = findNode(project.fileTree, filePath)
    if node.isSome:
      return getRelativePath(node.get(), project.rootPath)

  filePath

# File type detection
proc detectFileType*(service: FileService, filePath: string): FileType =
  try:
    let info = getFileInfo(filePath)
    if info.kind == pcDir:
      # Directories are handled separately, not through file type detection
      return ftUnknown

    # Check if binary by reading first few bytes
    let file = open(filePath, fmRead)
    defer:
      file.close()

    var buffer: array[512, byte]
    let bytesRead = file.readBytes(buffer, 0, 512)

    echo "DEBUG: detectFileType - read ", bytesRead, " bytes from ", filePath

    # Simple binary detection - check for null bytes
    for i in 0 ..< bytesRead:
      if buffer[i] == 0:
        echo "DEBUG: detectFileType - found null byte at position ", i, " in ", filePath
        return ftBinary

    echo "DEBUG: detectFileType - detected as text: ", filePath
    ftText
  except Exception as e:
    echo "DEBUG: detectFileType - exception: ", e.msg, " for file: ", filePath
    ftUnknown

# Backup operations
proc createBackup*(
    service: FileService, filePath: string
): Result[string, EditorError] =
  let backupPath = filePath & ".backup." & $getTime().toUnix()
  let copyResult = service.copyFile(filePath, backupPath)
  if copyResult.isErr:
    return err(copyResult.error)

  ok(backupPath)

proc restoreBackup*(
    service: FileService, backupPath: string, originalPath: string
): Result[void, EditorError] =
  service.moveFile(backupPath, originalPath)

# Temporary file operations
proc createTempFile*(
    service: FileService, content: string = "", extension: string = ""
): Result[string, EditorError] =
  try:
    let tempDir = getTempDir()
    let tempFile = tempDir / ("folx_temp_" & $getTime().toUnix() & extension)

    let writeResult = service.writeFile(tempFile, content)
    if writeResult.isErr:
      return err(writeResult.error)

    ok(tempFile)
  except OSError as e:
    err(
      EditorError(msg: "Failed to create temp file: " & e.msg, code: "TEMP_FILE_ERROR")
    )

proc cleanupTempFiles*(service: FileService) =
  try:
    let tempDir = getTempDir()
    for kind, path in walkDir(tempDir):
      if kind == pcFile and extractFilename(path).startsWith("folx_temp_"):
        try:
          removeFile(path)
        except:
          discard # Best effort cleanup
  except:
    discard

# Settings and preferences
proc setShowHiddenFiles*(service: FileService, show: bool) =
  service.showHiddenFiles = show

proc setFollowSymlinks*(service: FileService, follow: bool) =
  service.followSymlinks = follow

proc setMaxFileSize*(service: FileService, size: int64) =
  service.maxFileSize = size

proc getShowHiddenFiles*(service: FileService): bool =
  service.showHiddenFiles

proc getFollowSymlinks*(service: FileService): bool =
  service.followSymlinks

proc getMaxFileSize*(service: FileService): int64 =
  service.maxFileSize

# Status queries
proc hasActiveProject*(service: FileService): bool =
  service.currentProject.isSome

proc hasActiveWorkspace*(service: FileService): bool =
  service.workspace.isSome

proc getActiveProject*(service: FileService): Option[Project] =
  service.currentProject

proc getActiveWorkspace*(service: FileService): Option[Workspace] =
  service.workspace

proc getProjectName*(service: FileService): string =
  if service.currentProject.isSome:
    service.currentProject.get().name
  else:
    ""

proc getProjectPath*(service: FileService): string =
  if service.currentProject.isSome:
    service.currentProject.get().rootPath
  else:
    ""

proc getWatchedFileCount*(service: FileService): int =
  service.watchedFiles.len
