## Project Domain Model
## Pure business logic for workspace and file management

import std/[os, tables, sequtils, strutils, options, times, sets, algorithm]
import results
import ../shared/[types, errors]

# Project structure types
type
  FileNode* = ref object
    name*: string
    path*: string
    isDirectory*: bool
    size*: int64
    lastModified*: Time
    isHidden*: bool
    children*: seq[FileNode]
    parent*: FileNode
    gitStatus*: GitFileStatusEnum

  ProjectConfig* = object
    name*: string
    version*: string
    description*: string
    language*: string
    buildCommand*: string
    runCommand*: string
    testCommand*: string
    excludePatterns*: seq[string]
    includePatterns*: seq[string]
    customCommands*: Table[string, string]
    dependencies*: Table[string, string]
    settings*: Table[string, string]

  ProjectType* = enum
    ptGeneric = "generic"
    ptNim = "nim"
    ptPython = "python"
    ptJavaScript = "javascript"
    ptTypeScript = "typescript"
    ptRust = "rust"
    ptGo = "go"
    ptCpp = "cpp"
    ptJava = "java"

  Project* = ref object
    name*: string
    rootPath*: string
    projectType*: ProjectType
    config*: ProjectConfig
    fileTree*: FileNode
    openFiles*: seq[string]
    recentFiles*: seq[string]
    watchedFiles*: Table[string, Time]
    gitInfo*: Option[GitInfo]
    isInitialized*: bool
    lastScanTime*: Time
    maxRecentFiles*: int

  Workspace* = ref object
    name*: string
    projects*: seq[Project]
    activeProject*: Option[Project]
    workspaceFile*: string
    settings*: Table[string, string]

# Project creation and initialization
proc newProject*(name: string, rootPath: string): Project =
  Project(
    name: name,
    rootPath: rootPath.absolutePath(),
    projectType: ptGeneric,
    config: ProjectConfig(),
    fileTree: nil,
    openFiles: @[],
    recentFiles: @[],
    watchedFiles: Table[string, Time](),
    gitInfo: none(GitInfo),
    isInitialized: false,
    lastScanTime: getTime(),
    maxRecentFiles: 20,
  )

proc newFileNode*(name: string, path: string, isDirectory: bool): FileNode =
  FileNode(
    name: name,
    path: path.absolutePath(),
    isDirectory: isDirectory,
    size: 0,
    lastModified: getTime(),
    isHidden: name.startsWith("."),
    children: @[],
    parent: nil,
    gitStatus: gfsUnmodified,
  )

proc newWorkspace*(name: string): Workspace =
  Workspace(
    name: name,
    projects: @[],
    activeProject: none(Project),
    workspaceFile: "",
    settings: Table[string, string](),
  )

# Project validation
proc exists*(project: Project): bool =
  dirExists(project.rootPath)

proc isValidPath*(project: Project, path: string): bool =
  let normalizedPath = path.absolutePath()
  normalizedPath.startsWith(project.rootPath)

proc validateProject*(project: Project): Result[void, EditorError] =
  if not project.exists():
    return err(
      EditorError(msg: "Project directory does not exist", code: "PROJECT_NOT_FOUND")
    )

  if not project.rootPath.dirExists():
    return err(
      EditorError(msg: "Root path is not a directory", code: "INVALID_PROJECT_ROOT")
    )

  ok()

# File tree operations
proc addChild*(parent: FileNode, child: FileNode) =
  child.parent = parent
  parent.children.add(child)

proc removeChild*(parent: FileNode, childName: string): bool =
  for i, child in parent.children:
    if child.name == childName:
      parent.children.delete(i)
      return true
  false

proc findChild*(parent: FileNode, name: string): Option[FileNode] =
  for child in parent.children:
    if child.name == name:
      return some(child)
  none(FileNode)

proc findNode*(root: FileNode, path: string): Option[FileNode] =
  if root.path == path:
    return some(root)

  for child in root.children:
    let found = findNode(child, path)
    if found.isSome:
      return found

  none(FileNode)

proc getRelativePath*(node: FileNode, rootPath: string): string =
  if node.path.startsWith(rootPath):
    node.path[rootPath.len + 1 ..^ 1]
  else:
    node.path

proc getAllFiles*(root: FileNode, includeDirectories: bool = false): seq[FileNode] =
  var files: seq[FileNode] = @[]

  if not root.isDirectory or includeDirectories:
    files.add(root)

  for child in root.children:
    files.add(getAllFiles(child, includeDirectories))

  files

proc getFilesByExtension*(root: FileNode, extension: string): seq[FileNode] =
  getAllFiles(root).filterIt(not it.isDirectory and it.name.endsWith(extension))

# Project scanning and indexing
proc shouldExclude*(project: Project, path: string): bool =
  let relativePath = path.replace(project.rootPath, "")

  for pattern in project.config.excludePatterns:
    if relativePath.contains(pattern):
      return true

  false

proc shouldInclude*(project: Project, path: string): bool =
  if project.config.includePatterns.len == 0:
    return true

  let relativePath = path.replace(project.rootPath, "")

  for pattern in project.config.includePatterns:
    if relativePath.contains(pattern):
      return true

  false

proc scanDirectory*(project: Project, dirPath: string): Result[FileNode, EditorError] =
  if not dirExists(dirPath):
    return err(
      EditorError(
        msg: "Directory does not exist: " & dirPath, code: "DIRECTORY_NOT_FOUND"
      )
    )

  let root = newFileNode(extractFilename(dirPath), dirPath, true)

  try:
    for kind, path in walkDir(dirPath):
      let fileName = extractFilename(path)

      if project.shouldExclude(path) or not project.shouldInclude(path):
        continue

      case kind
      of pcFile:
        let fileNode = newFileNode(fileName, path, false)
        let info = getFileInfo(path)
        fileNode.size = info.size
        fileNode.lastModified = info.lastWriteTime
        root.addChild(fileNode)
      of pcDir:
        if not fileName.startsWith(".") or fileName in [".git", ".vscode"]:
          let subDirResult = project.scanDirectory(path)
          if subDirResult.isOk:
            root.addChild(subDirResult.get())
      else:
        discard

    ok(root)
  except OSError as e:
    err(EditorError(msg: "Failed to scan directory: " & e.msg, code: "SCAN_ERROR"))

proc refreshFileTree*(project: Project): Result[void, EditorError] =
  let scanResult = project.scanDirectory(project.rootPath)
  if scanResult.isErr:
    return err(scanResult.error)

  project.fileTree = scanResult.get()
  project.lastScanTime = getTime()
  ok()

# Project type detection
proc detectProjectType*(project: Project): ProjectType =
  if project.fileTree == nil:
    return ptGeneric

  let files = getAllFiles(project.fileTree)

  # Check for specific project files
  for file in files:
    case file.name
    of "package.json":
      return ptJavaScript
    of "tsconfig.json":
      return ptTypeScript
    of "Cargo.toml":
      return ptRust
    of "go.mod":
      return ptGo
    of "pom.xml", "build.gradle":
      return ptJava
    of "CMakeLists.txt", "Makefile":
      return ptCpp
    of "setup.py", "requirements.txt", "pyproject.toml":
      return ptPython
    else:
      discard

  # Check by file extensions
  let extensions = files.mapIt(splitFile(it.name).ext).toHashSet()

  if ".nim" in extensions or ".nims" in extensions:
    return ptNim
  elif ".py" in extensions:
    return ptPython
  elif ".js" in extensions:
    return ptJavaScript
  elif ".ts" in extensions:
    return ptTypeScript
  elif ".rs" in extensions:
    return ptRust
  elif ".go" in extensions:
    return ptGo
  elif ".cpp" in extensions or ".c" in extensions or ".h" in extensions:
    return ptCpp
  elif ".java" in extensions:
    return ptJava

  ptGeneric

# File operations
proc addFile*(project: Project, filePath: string): Result[void, EditorError] =
  if not project.isValidPath(filePath):
    return err(EditorError(msg: "File path outside project root", code: "INVALID_PATH"))

  if filePath in project.openFiles:
    return ok() # Already open

  project.openFiles.add(filePath)

  # Add to recent files
  if filePath in project.recentFiles:
    let index = project.recentFiles.find(filePath)
    project.recentFiles.delete(index)

  project.recentFiles.insert(filePath, 0)

  # Limit recent files
  if project.recentFiles.len > project.maxRecentFiles:
    project.recentFiles.setLen(project.maxRecentFiles)

  ok()

proc removeFile*(project: Project, filePath: string): Result[void, EditorError] =
  let index = project.openFiles.find(filePath)
  if index >= 0:
    project.openFiles.delete(index)

  ok()

proc isFileOpen*(project: Project, filePath: string): bool =
  filePath in project.openFiles

proc getOpenFiles*(project: Project): seq[string] =
  project.openFiles

proc getRecentFiles*(project: Project): seq[string] =
  project.recentFiles

# File watching
proc addWatchedFile*(project: Project, filePath: string) =
  project.watchedFiles[filePath] = getTime()

proc removeWatchedFile*(project: Project, filePath: string) =
  project.watchedFiles.del(filePath)

proc getWatchedFiles*(project: Project): seq[string] =
  toSeq(project.watchedFiles.keys)

proc hasFileChanged*(project: Project, filePath: string): bool =
  if filePath notin project.watchedFiles:
    return false

  try:
    let info = getFileInfo(filePath)
    let lastWatched = project.watchedFiles[filePath]
    info.lastWriteTime > lastWatched
  except:
    false

proc updateWatchedFile*(project: Project, filePath: string) =
  if filePath in project.watchedFiles:
    project.watchedFiles[filePath] = getTime()

# Project configuration
proc loadConfig*(project: Project, configPath: string): Result[void, EditorError] =
  # This would typically load from a file like .folx/project.toml
  # For now, we'll set some defaults based on project type
  project.config.name = project.name
  project.config.language = $project.projectType

  case project.projectType
  of ptNim:
    project.config.buildCommand = "nim c"
    project.config.runCommand = "nim r"
    project.config.testCommand = "nim test"
    project.config.excludePatterns = @["nimcache", "*.exe", "*.out"]
  of ptPython:
    project.config.buildCommand = ""
    project.config.runCommand = "python"
    project.config.testCommand = "pytest"
    project.config.excludePatterns = @["__pycache__", "*.pyc", ".pytest_cache"]
  of ptJavaScript:
    project.config.buildCommand = "npm run build"
    project.config.runCommand = "npm start"
    project.config.testCommand = "npm test"
    project.config.excludePatterns = @["node_modules", "dist", "build"]
  of ptTypeScript:
    project.config.buildCommand = "tsc"
    project.config.runCommand = "npm start"
    project.config.testCommand = "npm test"
    project.config.excludePatterns = @["node_modules", "dist", "build"]
  else:
    project.config.excludePatterns = @[".git", ".vscode", ".idea"]

  ok()

proc saveConfig*(project: Project, configPath: string): Result[void, EditorError] =
  # Would save configuration to file
  # Implementation depends on serialization format
  ok()

# Search functionality
proc searchFiles*(
    project: Project, query: string, caseSensitive: bool = false
): seq[FileNode] =
  if project.fileTree == nil:
    return @[]

  let files = getAllFiles(project.fileTree)
  let searchQuery =
    if caseSensitive:
      query
    else:
      query.toLower()

  files.filterIt(
    (if caseSensitive: it.name else: it.name.toLower()).contains(searchQuery)
  )

type
  SearchMatch* = tuple[line: int, content: string]
  SearchResult* = tuple[file: string, matches: seq[SearchMatch]]

proc searchInFiles*(
    project: Project,
    query: string,
    filePattern: string = "*",
    caseSensitive: bool = false,
): seq[SearchResult] =
  # This would search file contents
  # Implementation would require file reading capabilities
  @[]

# Project templates
type ProjectTemplate* = object
  name*: string
  description*: string
  projectType*: ProjectType
  files*: Table[string, string] # path -> content
  directories*: seq[string]

proc newProjectTemplate*(name: string, projectType: ProjectType): ProjectTemplate =
  ProjectTemplate(
    name: name,
    description: "",
    projectType: projectType,
    files: Table[string, string](),
    directories: @[],
  )

proc addTemplateFile*(tmpl: var ProjectTemplate, path: string, content: string) =
  tmpl.files[path] = content

proc addTemplateDirectory*(tmpl: var ProjectTemplate, path: string) =
  tmpl.directories.add(path)

proc createFromTemplate*(
    tmpl: ProjectTemplate, projectPath: string, projectName: string
): Result[Project, EditorError] =
  try:
    # Create project directory
    createDir(projectPath)

    # Create subdirectories
    for dir in tmpl.directories:
      let fullPath = joinPath(projectPath, dir)
      createDir(fullPath)

    # Create files
    for filePath, content in tmpl.files:
      let fullPath = joinPath(projectPath, filePath)
      let processedContent = content.replace("{{PROJECT_NAME}}", projectName)
      writeFile(fullPath, processedContent)

    let project = newProject(projectName, projectPath)
    project.projectType = tmpl.projectType

    let refreshResult = project.refreshFileTree()
    if refreshResult.isErr:
      return err(refreshResult.error)

    project.projectType = project.detectProjectType()
    let configResult = project.loadConfig("")
    if configResult.isErr:
      return err(configResult.error)

    project.isInitialized = true
    ok(project)
  except OSError as e:
    err(
      EditorError(
        msg: "Failed to create project: " & e.msg, code: "PROJECT_CREATION_FAILED"
      )
    )

# Workspace operations
proc addProject*(workspace: Workspace, project: Project) =
  workspace.projects.add(project)
  if workspace.activeProject.isNone:
    workspace.activeProject = some(project)

proc removeProject*(workspace: Workspace, projectName: string): bool =
  for i, project in workspace.projects:
    if project.name == projectName:
      workspace.projects.delete(i)
      if workspace.activeProject.isSome and
          workspace.activeProject.get().name == projectName:
        workspace.activeProject =
          if workspace.projects.len > 0:
            some(workspace.projects[0])
          else:
            none(Project)
      return true
  false

proc setActiveProject*(workspace: Workspace, projectName: string): bool =
  for project in workspace.projects:
    if project.name == projectName:
      workspace.activeProject = some(project)
      return true
  false

proc getActiveProject*(workspace: Workspace): Option[Project] =
  workspace.activeProject

proc getAllProjects*(workspace: Workspace): seq[Project] =
  workspace.projects

proc findProject*(workspace: Workspace, name: string): Option[Project] =
  for project in workspace.projects:
    if project.name == name:
      return some(project)
  none(Project)

# Project statistics
type ProjectStats* = object
  totalFiles*: int
  totalDirectories*: int
  totalSize*: int64
  filesByType*: Table[string, int]
  largestFiles*: seq[tuple[path: string, size: int64]]

proc calculateStats*(project: Project): ProjectStats =
  var stats = ProjectStats(filesByType: Table[string, int](), largestFiles: @[])

  if project.fileTree == nil:
    return stats

  let allNodes = getAllFiles(project.fileTree, includeDirectories = true)

  for node in allNodes:
    if node.isDirectory:
      inc stats.totalDirectories
    else:
      inc stats.totalFiles
      stats.totalSize += node.size

      let ext = splitFile(node.name).ext
      if ext in stats.filesByType:
        inc stats.filesByType[ext]
      else:
        stats.filesByType[ext] = 1

      stats.largestFiles.add((path: node.path, size: node.size))

  # Sort largest files by size
  stats.largestFiles.sort(
    proc(a, b: tuple[path: string, size: int64]): int =
      int(b.size - a.size)
  )
  if stats.largestFiles.len > 10:
    stats.largestFiles.setLen(10)

  stats

# Project cleanup and maintenance
proc cleanupRecentFiles*(project: Project) =
  var validFiles: seq[string] = @[]

  for filePath in project.recentFiles:
    if fileExists(filePath):
      validFiles.add(filePath)

  project.recentFiles = validFiles

proc optimizeFileTree*(project: Project) =
  # Remove nodes for files that no longer exist
  if project.fileTree != nil:
    let refreshResult = project.refreshFileTree()
    discard refreshResult # Best effort cleanup

# Project import/export
proc exportProjectInfo*(project: Project): Table[string, string] =
  var projectInfo = Table[string, string]()
  projectInfo["name"] = project.name
  projectInfo["rootPath"] = project.rootPath
  projectInfo["projectType"] = $project.projectType
  projectInfo["openFiles"] = project.openFiles.join(";")
  projectInfo["recentFiles"] = project.recentFiles.join(";")
  return projectInfo

proc importProjectInfo*(data: Table[string, string]): Result[Project, EditorError] =
  if "name" notin data or "rootPath" notin data:
    return err(
      EditorError(msg: "Missing required project data", code: "INVALID_PROJECT_DATA")
    )

  let project = newProject(data["name"], data["rootPath"])

  if "projectType" in data:
    try:
      project.projectType = parseEnum[ProjectType](data["projectType"])
    except:
      project.projectType = ptGeneric

  if "openFiles" in data and data["openFiles"].len > 0:
    project.openFiles = data["openFiles"].split(";")

  if "recentFiles" in data and data["recentFiles"].len > 0:
    project.recentFiles = data["recentFiles"].split(";")

  ok(project)
