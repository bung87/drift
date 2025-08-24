## File Manager Infrastructure
## Provides reliable file system operations with proper error handling

import std/[os, times, options, tables]
import results
import ../../shared/constants
import ../../shared/errors

# File operation types
type
  FileOperationType* = enum
    fotRead = "read"
    fotWrite = "write"
    fotDelete = "delete"
    fotMove = "move"
    fotCopy = "copy"
    fotCreate = "create"

  FileOperationResult* = object
    operation*: FileOperationType
    filePath*: string
    success*: bool
    bytesProcessed*: int64
    duration*: float64
    error*: Option[string]

  FileManagerConfig* = object
    maxFileSize*: int64
    enableCache*: bool
    cacheTimeoutSeconds*: int
    enableBackups*: bool
    backupDirectory*: string
    enableLogging*: bool
    followSymlinks*: bool
    createDirectories*: bool

  CachedFile* = object
    content*: string
    lastModified*: Time
    cacheTime*: Time
    size*: int64

  FileManager* = ref object
    config*: FileManagerConfig
    cache*: Table[string, CachedFile]
    operationHistory*: seq[FileOperationResult]
    tempDirectory*: string

# Default configuration
proc defaultFileManagerConfig*(): FileManagerConfig =
  FileManagerConfig(
    maxFileSize: 100 * 1024 * 1024, # 100MB
    enableCache: true,
    cacheTimeoutSeconds: 300, # 5 minutes
    enableBackups: false,
    backupDirectory: "",
    enableLogging: true,
    followSymlinks: true,
    createDirectories: true,
  )

# Constructor
proc newFileManager*(
    config: FileManagerConfig = defaultFileManagerConfig()
): FileManager =
  result = FileManager(
    config: config,
    cache: initTable[string, CachedFile](),
    operationHistory: @[],
    tempDirectory: getTempDir(),
  )

# Logging helper
proc logOperation(manager: FileManager, operation: FileOperationResult) =
  if manager.config.enableLogging:
    manager.operationHistory.add(operation)
    # Keep only last 1000 operations to prevent memory bloat
    if manager.operationHistory.len > 1000:
      manager.operationHistory = manager.operationHistory[^1000 ..^ 1]

# Cache management
proc isCacheValid(manager: FileManager, path: string): bool =
  if not manager.config.enableCache or path notin manager.cache:
    return false

  let cached = manager.cache[path]
  let currentTime = getTime()
  let cacheAge = (currentTime - cached.cacheTime).inSeconds

  if cacheAge > manager.config.cacheTimeoutSeconds:
    return false

  # Check if file has been modified since caching
  try:
    let fileInfo = getFileInfo(path, followSymlink = manager.config.followSymlinks)
    return cached.lastModified == fileInfo.lastWriteTime
  except:
    return false

proc invalidateCache(manager: FileManager, path: string) =
  if path in manager.cache:
    manager.cache.del(path)

proc addToCache(
    manager: FileManager, path: string, content: string, fileInfo: FileInfo
) =
  if manager.config.enableCache:
    manager.cache[path] = CachedFile(
      content: content,
      lastModified: fileInfo.lastWriteTime,
      cacheTime: getTime(),
      size: fileInfo.size,
    )

# File validation
proc validateFilePath(path: string): Result[void, EditorError] =
  if path.len == 0:
    return err(EditorError(msg: "File path cannot be empty", code: "EMPTY_PATH"))

  if path.len > MAX_PATH_LENGTH:
    return err(EditorError(msg: "File path too long", code: "PATH_TOO_LONG"))

  # Check for invalid characters
  for c in path:
    if c in INVALID_PATH_CHARS:
      return err(
        EditorError(msg: "Invalid character in path: " & $c, code: "INVALID_PATH_CHAR")
      )

  return ok()

proc validateFileSize(manager: FileManager, size: int64): Result[void, EditorError] =
  if size > manager.config.maxFileSize:
    return err(
      EditorError(
        msg:
          "File too large: " & $size & " bytes (max: " & $manager.config.maxFileSize &
          ")",
        code: "FILE_TOO_LARGE",
      )
    )

  return ok()

# Core file operations
proc readFile*(manager: FileManager, filePath: string): Result[string, EditorError] =
  let startTime = cpuTime()
  var opResult = FileOperationResult(
    operation: fotRead,
    filePath: filePath,
    success: false,
    bytesProcessed: 0,
    duration: 0.0,
  )

  # Validate path
  let pathValidation = validateFilePath(filePath)
  if pathValidation.isErr:
    opResult.error = some(pathValidation.error.msg)
    manager.logOperation(opResult)
    return err(pathValidation.error)

  # Check cache first
  if manager.isCacheValid(filePath):
    let cached = manager.cache[filePath]
    opResult.success = true
    opResult.bytesProcessed = cached.size
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return ok(cached.content)

  try:
    # Check if file exists
    if not fileExists(filePath):
      opResult.error = some("File does not exist")
      manager.logOperation(opResult)
      return err(
        EditorError(msg: "File does not exist: " & filePath, code: "FILE_NOT_FOUND")
      )

    # Get file info
    let fileInfo = getFileInfo(filePath, followSymlink = manager.config.followSymlinks)

    # Validate file size
    let sizeValidation = manager.validateFileSize(fileInfo.size)
    if sizeValidation.isErr:
      opResult.error = some(sizeValidation.error.msg)
      manager.logOperation(opResult)
      return err(sizeValidation.error)

    # Read file content
    let content = readFile(filePath)

    # Add to cache
    manager.addToCache(filePath, content, fileInfo)

    opResult.success = true
    opResult.bytesProcessed = fileInfo.size
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)

    return ok(content)
  except IOError as e:
    opResult.error = some("IO Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to read file: " & e.msg, code: "IO_ERROR"))
  except OSError as e:
    opResult.error = some("OS Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to read file: " & e.msg, code: "OS_ERROR"))
  except Exception as e:
    opResult.error = some("Unexpected error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(
      EditorError(
        msg: "Unexpected error reading file: " & e.msg, code: "UNEXPECTED_ERROR"
      )
    )

proc writeFile*(
    manager: FileManager, filePath: string, content: string
): Result[void, EditorError] =
  let startTime = cpuTime()
  var opResult = FileOperationResult(
    operation: fotWrite,
    filePath: filePath,
    success: false,
    bytesProcessed: 0,
    duration: 0.0,
  )

  # Validate path
  let pathValidation = validateFilePath(filePath)
  if pathValidation.isErr:
    opResult.error = some(pathValidation.error.msg)
    manager.logOperation(opResult)
    return err(pathValidation.error)

  # Validate content size
  let sizeValidation = manager.validateFileSize(content.len.int64)
  if sizeValidation.isErr:
    opResult.error = some(sizeValidation.error.msg)
    manager.logOperation(opResult)
    return err(sizeValidation.error)

  try:
    # Create parent directories if needed
    if manager.config.createDirectories:
      let parentDir = parentDir(filePath)
      if parentDir.len > 0 and not dirExists(parentDir):
        createDir(parentDir)

    # Create backup if enabled
    if manager.config.enableBackups and fileExists(filePath):
      let backupPath =
        if manager.config.backupDirectory.len > 0:
          manager.config.backupDirectory / extractFilename(filePath) & ".bak"
        else:
          filePath & ".bak"
      copyFile(filePath, backupPath)

    # Write file
    writeFile(filePath, content)

    # Invalidate cache
    manager.invalidateCache(filePath)

    # Update cache with new content
    if manager.config.enableCache:
      let fileInfo =
        getFileInfo(filePath, followSymlink = manager.config.followSymlinks)
      manager.addToCache(filePath, content, fileInfo)

    opResult.success = true
    opResult.bytesProcessed = content.len.int64
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)

    return ok()
  except IOError as e:
    opResult.error = some("IO Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to write file: " & e.msg, code: "IO_ERROR"))
  except OSError as e:
    opResult.error = some("OS Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to write file: " & e.msg, code: "OS_ERROR"))
  except Exception as e:
    opResult.error = some("Unexpected error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(
      EditorError(
        msg: "Unexpected error writing file: " & e.msg, code: "UNEXPECTED_ERROR"
      )
    )

# Additional file operations
proc deleteFile*(manager: FileManager, filePath: string): Result[void, EditorError] =
  let startTime = cpuTime()
  var opResult = FileOperationResult(
    operation: fotDelete,
    filePath: filePath,
    success: false,
    bytesProcessed: 0,
    duration: 0.0,
  )

  let pathValidation = validateFilePath(filePath)
  if pathValidation.isErr:
    opResult.error = some(pathValidation.error.msg)
    manager.logOperation(opResult)
    return err(pathValidation.error)

  try:
    if not fileExists(filePath):
      opResult.error = some("File does not exist")
      manager.logOperation(opResult)
      return err(
        EditorError(msg: "File does not exist: " & filePath, code: "FILE_NOT_FOUND")
      )

    # Create backup if enabled
    if manager.config.enableBackups:
      let backupPath =
        if manager.config.backupDirectory.len > 0:
          manager.config.backupDirectory / extractFilename(filePath) & ".deleted"
        else:
          filePath & ".deleted"
      copyFile(filePath, backupPath)

    removeFile(filePath)
    manager.invalidateCache(filePath)

    opResult.success = true
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)

    return ok()
  except OSError as e:
    opResult.error = some("OS Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to delete file: " & e.msg, code: "OS_ERROR"))

proc moveFile*(
    manager: FileManager, sourcePath: string, destPath: string
): Result[void, EditorError] =
  let startTime = cpuTime()
  var opResult = FileOperationResult(
    operation: fotMove,
    filePath: sourcePath & " -> " & destPath,
    success: false,
    bytesProcessed: 0,
    duration: 0.0,
  )

  let sourceValidation = validateFilePath(sourcePath)
  if sourceValidation.isErr:
    opResult.error = some(sourceValidation.error.msg)
    manager.logOperation(opResult)
    return err(sourceValidation.error)

  let destValidation = validateFilePath(destPath)
  if destValidation.isErr:
    opResult.error = some(destValidation.error.msg)
    manager.logOperation(opResult)
    return err(destValidation.error)

  try:
    if not fileExists(sourcePath):
      opResult.error = some("Source file does not exist")
      manager.logOperation(opResult)
      return err(
        EditorError(
          msg: "Source file does not exist: " & sourcePath, code: "FILE_NOT_FOUND"
        )
      )

    # Create parent directories if needed
    if manager.config.createDirectories:
      let parentDir = parentDir(destPath)
      if parentDir.len > 0 and not dirExists(parentDir):
        createDir(parentDir)

    moveFile(sourcePath, destPath)
    manager.invalidateCache(sourcePath)
    manager.invalidateCache(destPath)

    opResult.success = true
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)

    return ok()
  except OSError as e:
    opResult.error = some("OS Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to move file: " & e.msg, code: "OS_ERROR"))

proc copyFile*(
    manager: FileManager, sourcePath: string, destPath: string
): Result[void, EditorError] =
  let startTime = cpuTime()
  var opResult = FileOperationResult(
    operation: fotCopy,
    filePath: sourcePath & " -> " & destPath,
    success: false,
    bytesProcessed: 0,
    duration: 0.0,
  )

  let sourceValidation = validateFilePath(sourcePath)
  if sourceValidation.isErr:
    opResult.error = some(sourceValidation.error.msg)
    manager.logOperation(opResult)
    return err(sourceValidation.error)

  let destValidation = validateFilePath(destPath)
  if destValidation.isErr:
    opResult.error = some(destValidation.error.msg)
    manager.logOperation(opResult)
    return err(destValidation.error)

  try:
    if not fileExists(sourcePath):
      opResult.error = some("Source file does not exist")
      manager.logOperation(opResult)
      return err(
        EditorError(
          msg: "Source file does not exist: " & sourcePath, code: "FILE_NOT_FOUND"
        )
      )

    # Create parent directories if needed
    if manager.config.createDirectories:
      let parentDir = parentDir(destPath)
      if parentDir.len > 0 and not dirExists(parentDir):
        createDir(parentDir)

    let fileInfo =
      getFileInfo(sourcePath, followSymlink = manager.config.followSymlinks)
    copyFile(sourcePath, destPath)
    manager.invalidateCache(destPath)

    opResult.success = true
    opResult.bytesProcessed = fileInfo.size
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)

    return ok()
  except OSError as e:
    opResult.error = some("OS Error: " & e.msg)
    opResult.duration = cpuTime() - startTime
    manager.logOperation(opResult)
    return err(EditorError(msg: "Failed to copy file: " & e.msg, code: "OS_ERROR"))

# Utility functions
proc fileExists*(manager: FileManager, filePath: string): bool =
  fileExists(filePath)

proc getFileSize*(manager: FileManager, filePath: string): Result[int64, EditorError] =
  try:
    let fileInfo = getFileInfo(filePath, followSymlink = manager.config.followSymlinks)
    return ok(fileInfo.size)
  except:
    return err(
      EditorError(msg: "Failed to get file size: " & filePath, code: "FILE_INFO_ERROR")
    )

proc getFileModifiedTime*(
    manager: FileManager, filePath: string
): Result[Time, EditorError] =
  try:
    let fileInfo = getFileInfo(filePath, followSymlink = manager.config.followSymlinks)
    return ok(fileInfo.lastWriteTime)
  except:
    return err(
      EditorError(
        msg: "Failed to get file modification time: " & filePath,
        code: "FILE_INFO_ERROR",
      )
    )

# Cache management
proc clearCache*(manager: FileManager) =
  manager.cache.clear()

proc getCacheSize*(manager: FileManager): int =
  manager.cache.len

proc getCacheInfo*(
    manager: FileManager
): seq[tuple[path: string, size: int64, cacheTime: Time]] =
  result = @[]
  for path, cached in manager.cache.pairs:
    result.add((path: path, size: cached.size, cacheTime: cached.cacheTime))

# Configuration updates
proc updateConfig*(manager: FileManager, config: FileManagerConfig) =
  manager.config = config

  # Clear cache if caching was disabled
  if not config.enableCache:
    manager.clearCache()

# Statistics and monitoring
proc getOperationStats*(
    manager: FileManager
): tuple[reads: int, writes: int, deletes: int, moves: int, copies: int] =
  var reads, writes, deletes, moves, copies = 0

  for op in manager.operationHistory:
    case op.operation
    of fotRead:
      inc reads
    of fotWrite:
      inc writes
    of fotDelete:
      inc deletes
    of fotMove:
      inc moves
    of fotCopy:
      inc copies
    else:
      discard

  return (reads: reads, writes: writes, deletes: deletes, moves: moves, copies: copies)

proc getLastError*(manager: FileManager): Option[string] =
  for i in countdown(manager.operationHistory.len - 1, 0):
    let op = manager.operationHistory[i]
    if not op.success and op.error.isSome:
      return op.error

  return none(string)

proc getTotalBytesProcessed*(manager: FileManager): int64 =
  result = 0
  for op in manager.operationHistory:
    if op.success:
      result += op.bytesProcessed
