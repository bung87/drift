## Explorer file operations module - Production-ready file system operations
import std/[os, times, strutils, tables, options, algorithm]
import chronos except Result
import raylib as rl
import types

export FileOperationResult, ExplorerFileInfo, FileKind, ExplorerFilePermission

type
  FileWatcher* = object
    watchedDirs*: Table[string, Time]
    lastModified*: Table[string, Time]
    enabled*: bool
    checkInterval*: float32

  FileFilter* = object
    extensions*: seq[string]
    patterns*: seq[string]
    includeHidden*: bool
    includeDirectories*: bool
    includeFiles*: bool
    maxSize*: int64
    minSize*: int64

proc newFileWatcher*(): FileWatcher =
  FileWatcher(
    watchedDirs: initTable[string, Time](),
    lastModified: initTable[string, Time](),
    enabled: true,
    checkInterval: 1.0,
  )

proc newFileFilter*(): FileFilter =
  FileFilter(
    extensions: @[],
    patterns: @[],
    includeHidden: true,
    includeDirectories: true,
    includeFiles: true,
    maxSize: int64.high,
    minSize: 0,
  )

# File information utilities
proc getExplorerFileInfo*(path: string): Option[ExplorerFileInfo] =
  ## Get detailed file information
  try:
    if not fileExists(path) and not dirExists(path):
      return none(ExplorerFileInfo)

    let info = os.getFileInfo(path)
    let name = extractFilename(path)
    let ext =
      if path.splitFile().ext.len > 0:
        path.splitFile().ext[1 ..^ 1]
      else:
        ""

    let kind =
      if info.kind == pcDir:
        fkDirectory
      elif info.kind == pcLinkToDir or info.kind == pcLinkToFile:
        fkSymlink
      else:
        fkFile

    let permissions = block:
      var perms: set[ExplorerFilePermission] = {}
      when defined(posix):
        if (info.permissions * {fpUserRead, fpGroupRead, fpOthersRead}) != {}:
          perms.incl(fpRead)
        if (info.permissions * {fpUserWrite, fpGroupWrite, fpOthersWrite}) != {}:
          perms.incl(fpWrite)
        if (info.permissions * {fpUserExec, fpGroupExec, fpOthersExec}) != {}:
          perms.incl(fpExecute)
      else:
        # Windows fallback
        perms = {fpRead, fpWrite}
        if ext.toLower() in ["exe", "bat", "cmd", "com", "scr"]:
          perms.incl(fpExecute)
      perms

    result = some(
      ExplorerFileInfo(
        name: name,
        path: path,
        kind: kind,
        size: info.size,
        modTime: info.lastWriteTime,
        permissions: permissions,
        isHidden:
          name.startsWith("."),
        extension: ext,
        isExpanded: false,
        level: 0,
      )
    )
  except OSError, IOError:
    result = none(ExplorerFileInfo)

proc getDirectoryContents*(
    path: string, filter: FileFilter = newFileFilter(), recursive: bool = false
): seq[ExplorerFileInfo] =
  ## Get contents of a directory with filtering
  result = @[]

  if not dirExists(path):
    return

  try:
    for kind, filePath in walkDir(path):
      let fileInfo = getExplorerFileInfo(filePath)
      if fileInfo.isNone:
        continue

      let info = fileInfo.get()

      # Apply filters
      if not filter.includeHidden and info.isHidden:
        continue

      if not filter.includeDirectories and info.kind == fkDirectory:
        continue

      if not filter.includeFiles and info.kind == fkFile:
        continue

      if info.size < filter.minSize or info.size > filter.maxSize:
        continue

      if filter.extensions.len > 0 and info.extension notin filter.extensions:
        continue

      # Check patterns
      var matchesPattern = filter.patterns.len == 0
      for pattern in filter.patterns:
        if info.name.contains(pattern):
          matchesPattern = true
          break

      if not matchesPattern:
        continue

      result.add(info)

      # Recursive search
      if recursive and info.kind == fkDirectory:
        let subFiles = getDirectoryContents(info.path, filter, recursive = true)
        for subFile in subFiles:
          var subInfo = subFile
          subInfo.level = info.level + 1
          result.add(subInfo)
  except OSError, IOError:
    discard

proc sortFiles*(
    files: var seq[ExplorerFileInfo],
    sortBy: SortBy,
    order: ExplorerSortOrder,
    directoriesFirst: bool = true,
) =
  ## Sort files according to specified criteria
  sort(
    files,
    proc(a, b: ExplorerFileInfo): int =
      # Directories first if requested
      if directoriesFirst:
        if a.kind == fkDirectory and b.kind != fkDirectory:
          return -1
        elif a.kind != fkDirectory and b.kind == fkDirectory:
          return 1

      # Sort by specified criteria
      let sortResult =
        case sortBy
        of sbName:
          cmp(a.name.toLower(), b.name.toLower())
        of sbSize:
          cmp(a.size, b.size)
        of sbModified:
          cmp(a.modTime, b.modTime)
        of sbType:
          cmp(a.extension.toLower(), b.extension.toLower())

      if order == soDescending:
        return -sortResult
      else:
        return sortResult,
  )

# File operations
proc createFile*(path: string, content: string = ""): FileOperationResult =
  ## Create a new file
  try:
    let dir = path.parentDir()
    if not dirExists(dir):
      createDir(dir)

    writeFile(path, content)
    result = FileOperationResult(success: true, error: "", affectedFiles: @[path])
  except CatchableError as e:
    result = FileOperationResult(
      success: false, error: "Failed to create file: " & e.msg, affectedFiles: @[]
    )

proc createDirectory*(path: string): FileOperationResult =
  ## Create a new directory
  try:
    createDir(path)
    result = FileOperationResult(success: true, error: "", affectedFiles: @[path])
  except CatchableError as e:
    result = FileOperationResult(
      success: false, error: "Failed to create directory: " & e.msg, affectedFiles: @[]
    )

proc deleteFile*(path: string): FileOperationResult =
  ## Delete a file
  try:
    if fileExists(path):
      removeFile(path)
    elif dirExists(path):
      removeDir(path)
    else:
      return FileOperationResult(
        success: false, error: "File or directory does not exist", affectedFiles: @[]
      )

    result = FileOperationResult(success: true, error: "", affectedFiles: @[path])
  except CatchableError as e:
    result = FileOperationResult(
      success: false, error: "Failed to delete: " & e.msg, affectedFiles: @[]
    )

proc deleteDirectory*(path: string, recursive: bool = false): FileOperationResult =
  ## Delete a directory
  var affectedFiles: seq[string] = @[]

  try:
    if not dirExists(path):
      return FileOperationResult(
        success: false, error: "Directory does not exist", affectedFiles: @[]
      )

    if recursive:
      # Collect all files that will be deleted
      for filePath in walkDirRec(path):
        affectedFiles.add(filePath)

      removeDir(path)
    else:
      # Check if directory is empty
      var isEmpty = true
      for kind, filePath in walkDir(path):
        isEmpty = false
        break

      if not isEmpty:
        return FileOperationResult(
          success: false,
          error: "Directory is not empty. Use recursive delete.",
          affectedFiles: @[],
        )

      removeDir(path)

    affectedFiles.add(path)
    result = FileOperationResult(success: true, error: "", affectedFiles: affectedFiles)
  except CatchableError as e:
    result = FileOperationResult(
      success: false, error: "Failed to delete directory: " & e.msg, affectedFiles: @[]
    )

proc copyFile*(
    srcPath: string, destPath: string, overwrite: bool = false
): FileOperationResult =
  ## Copy a file
  try:
    if fileExists(destPath) and not overwrite:
      return FileOperationResult(
        success: false, error: "Destination file already exists", affectedFiles: @[]
      )

    let destDir = destPath.parentDir()
    if not dirExists(destDir):
      createDir(destDir)

    os.copyFile(srcPath, destPath)
    result =
      FileOperationResult(success: true, error: "", affectedFiles: @[srcPath, destPath])
  except CatchableError as e:
    result = FileOperationResult(
      success: false, error: "Failed to copy file: " & e.msg, affectedFiles: @[]
    )

proc moveFile*(
    srcPath: string, destPath: string, overwrite: bool = false
): FileOperationResult =
  ## Move/rename a file
  try:
    if fileExists(destPath) and not overwrite:
      return FileOperationResult(
        success: false, error: "Destination file already exists", affectedFiles: @[]
      )

    let destDir = destPath.parentDir()
    if not dirExists(destDir):
      createDir(destDir)

    os.moveFile(srcPath, destPath)
    result =
      FileOperationResult(success: true, error: "", affectedFiles: @[srcPath, destPath])
  except CatchableError as e:
    result = FileOperationResult(
      success: false, error: "Failed to move file: " & e.msg, affectedFiles: @[]
    )

proc renameFile*(path: string, newName: string): FileOperationResult =
  ## Rename a file or directory
  let newPath = path.parentDir() / newName
  return moveFile(path, newPath, false)

proc copyDirectory*(
    srcPath: string, destPath: string, overwrite: bool = false
): FileOperationResult =
  ## Copy a directory recursively
  var affectedFiles: seq[string] = @[]

  try:
    if dirExists(destPath) and not overwrite:
      return FileOperationResult(
        success: false,
        error: "Destination directory already exists",
        affectedFiles: @[],
      )

    # Create destination directory
    if not dirExists(destPath):
      createDir(destPath)

    affectedFiles.add(destPath)

    # Copy all contents
    for filePath in walkDirRec(srcPath):
      let relativePath = filePath.replace(srcPath, "")
      let destFile = destPath / relativePath

      let destDir = destFile.parentDir()
      if not dirExists(destDir):
        createDir(destDir)

      if fileExists(filePath):
        os.copyFile(filePath, destFile)
        affectedFiles.add(destFile)

    result = FileOperationResult(success: true, error: "", affectedFiles: affectedFiles)
  except CatchableError as e:
    result = FileOperationResult(
      success: false,
      error: "Failed to copy directory: " & e.msg,
      affectedFiles: affectedFiles,
    )

# File watching
proc addWatchDirectory*(watcher: var FileWatcher, path: string) =
  ## Add a directory to watch for changes
  if dirExists(path):
    watcher.watchedDirs[path] = times.getTime()

    # Initialize file modification times
    for kind, filePath in walkDir(path):
      let info = getExplorerFileInfo(filePath)
      if info.isSome:
        watcher.lastModified[filePath] = info.get().modTime

proc removeWatchDirectory*(watcher: var FileWatcher, path: string) =
  ## Remove a directory from watching
  watcher.watchedDirs.del(path)

  # Clean up file modification times
  var toRemove: seq[string] = @[]
  for watchedPath in watcher.lastModified.keys:
    if watchedPath.startsWith(path):
      toRemove.add(watchedPath)

  for watchedPath in toRemove:
    watcher.lastModified.del(watchedPath)

proc checkForChanges*(watcher: var FileWatcher): seq[string] =
  ## Check for file changes and return list of changed files
  result = @[]

  if not watcher.enabled:
    return

  for watchPath in watcher.watchedDirs.keys:
    if not dirExists(watchPath):
      continue

    try:
      for kind, filePath in walkDir(watchPath):
        try:
          let osInfo = os.getFileInfo(filePath)
          let currentModTime = osInfo.lastWriteTime

          if filePath in watcher.lastModified:
            if watcher.lastModified[filePath] != currentModTime:
              result.add(filePath)
              watcher.lastModified[filePath] = currentModTime
          else:
            # New file
            watcher.lastModified[filePath] = currentModTime
            result.add(filePath)
        except CatchableError:
          continue
    except CatchableError:
      continue

# Search operations
proc searchFiles*(
    rootPath: string, query: string, caseSensitive: bool = false, useRegex: bool = false
): seq[ExplorerFileInfo] =
  ## Search for files matching a query
  result = @[]

  if not dirExists(rootPath):
    return

  let searchQuery =
    if caseSensitive:
      query
    else:
      query.toLower()

  try:
    for filePath in walkDirRec(rootPath):
      let info = getExplorerFileInfo(filePath)
      if info.isNone:
        continue

      let fileInfo = info.get()
      let searchName =
        if caseSensitive:
          fileInfo.name
        else:
          fileInfo.name.toLower()

      var matches = false
      if useRegex:
        # TODO: Add regex support when needed
        matches = searchName.contains(searchQuery)
      else:
        matches = searchName.contains(searchQuery)

      if matches:
        result.add(fileInfo)
  except CatchableError:
    discard

proc searchInFiles*(
    rootPath: string, query: string, fileExtensions: seq[string] = @[]
): seq[tuple[file: string, line: int, content: string]] =
  ## Search for text content within files
  result = @[]

  if not dirExists(rootPath):
    return

  try:
    for filePath in walkDirRec(rootPath):
      if not fileExists(filePath):
        continue

      let ext = filePath.splitFile().ext
      if fileExtensions.len > 0 and ext notin fileExtensions:
        continue

      try:
        let content = readFile(filePath)
        let lines = content.splitLines()

        for i, line in lines:
          if query in line:
            result.add((file: filePath, line: i + 1, content: line))
      except CatchableError:
        continue
  except CatchableError:
    discard

# Utility functions
proc getFileSize*(path: string): int64 =
  ## Get file size in bytes
  try:
    let info = os.getFileInfo(path)
    result = info.size
  except CatchableError:
    result = 0

proc getFileModificationTime*(path: string): Time =
  ## Get file modification time
  try:
    let info = os.getFileInfo(path)
    result = info.lastWriteTime
  except CatchableError:
    result = fromUnix(0)

proc isFileNewer*(path1: string, path2: string): bool =
  ## Check if first file is newer than second
  let time1 = getFileModificationTime(path1)
  let time2 = getFileModificationTime(path2)
  result = time1 > time2

proc getUniqueFileName*(basePath: string): string =
  ## Generate a unique filename by appending numbers if needed
  result = basePath
  var counter = 1

  while fileExists(result) or dirExists(result):
    let (dir, name, ext) = result.splitFile()
    result = dir / (name & "_" & $counter & ext)
    counter += 1

proc getRelativePath*(fromPath: string, toPath: string): string =
  ## Get relative path from one location to another
  try:
    result = relativePath(toPath, fromPath)
  except CatchableError:
    result = toPath

proc isValidFileName*(name: string): bool =
  ## Check if a filename is valid for the current platform
  if name.len == 0:
    return false

  when defined(windows):
    const invalidChars = ['<', '>', ':', '"', '|', '?', '*', '\\', '/']
    const invalidNames = [
      "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6",
      "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7",
      "LPT8", "LPT9",
    ]

    for char in invalidChars:
      if char in name:
        return false

    if name.toUpper() in invalidNames:
      return false

    if name.endsWith(".") or name.endsWith(" "):
      return false
  else:
    # Unix-like systems
    if name.contains('/') or name.contains('\0'):
      return false

  return true

proc sanitizeFileName*(name: string): string =
  ## Sanitize a filename for the current platform
  result = name

  when defined(windows):
    const invalidChars = ['<', '>', ':', '"', '|', '?', '*', '\\', '/']
    for char in invalidChars:
      result = result.replace($char, "_")

    result = result.strip(chars = {'.', ' '})
  else:
    result = result.replace("/", "_").replace("\0", "_")

  if result.len == 0:
    result = "unnamed"

# Async operations using chronos
proc asyncCopyFile*(
    srcPath: string, destPath: string
): Future[FileOperationResult] {.async.} =
  ## Asynchronously copy a file
  return copyFile(srcPath, destPath, false)

proc asyncDeleteFile*(path: string): Future[FileOperationResult] {.async.} =
  ## Asynchronously delete a file
  return deleteFile(path)

proc asyncGetDirectoryContents*(
    path: string, filter: FileFilter = newFileFilter()
): Future[seq[ExplorerFileInfo]] {.async.} =
  ## Asynchronously get directory contents
  return getDirectoryContents(path, filter)
