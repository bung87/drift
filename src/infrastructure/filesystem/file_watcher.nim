## File system abstraction with async operations and file watching for Drift editor
## Provides clean interface for file operations without direct OS dependencies

import std/[asyncdispatch, os, times, tables, strutils]
import std/algorithm
import ../../shared/[types, constants, errors, utils]

# File event types
type FileEventType* = enum
  fetCreated = "created"
  fetModified = "modified"
  fetDeleted = "deleted"
  fetRenamed = "renamed"
  fetMoved = "moved"
  fetAttributesChanged = "attributes_changed"

# File event
type FileEvent* = object
  eventType*: FileEventType
  path*: string
  oldPath*: string # For rename/move events
  timestamp*: float
  size*: int64
  isDirectory*: bool

# File metadata
# Define permission types first
type DriftFilePermission* = enum
  fpRead = "read"
  fpWrite = "write"
  fpExecute = "execute"

type FileMetadata* = object
  path*: string
  size*: int64
  createdTime*: float
  modifiedTime*: float
  accessedTime*: float
  isDirectory*: bool
  isReadonly*: bool
  isHidden*: bool
  permissions*: set[DriftFilePermission]

# Directory entry
type DirectoryEntry* = object
  name*: string
  path*: string
  metadata*: FileMetadata
  fileType*: FileType

# File operation types
type FileOperation* = enum
  foRead = "read"
  foWrite = "write"
  foCreate = "create"
  foDelete = "delete"
  foCopy = "copy"
  foMove = "move"
  foWatch = "watch"

# File watcher configuration
type WatcherConfig* = object
  recursive*: bool
  debounceTime*: float # Minimum time between events for same file
  batchEvents*: bool # Batch multiple events together
  maxBatchSize*: int
  excludePatterns*: seq[string] # Glob patterns to exclude
  includePatterns*: seq[string] # Glob patterns to include (if specified)

# File watcher state
type WatchedPath* = object
  path*: string
  config*: WatcherConfig
  lastEvent*: float
  eventCount*: int
  isActive*: bool

# Event handler callback
type FileEventHandler* = proc(event: FileEvent): Future[void] {.async.}

# File watcher implementation
type FileWatcher* = ref object
  watchedPaths*: Table[string, WatchedPath]
  eventHandlers*: seq[FileEventHandler]
  eventQueue*: seq[FileEvent]
  batchedEvents*: Table[string, seq[FileEvent]]
  isRunning*: bool
  pollInterval*: float
  lastPollTime*: float
  fileStates*: Table[string, FileMetadata] # For polling-based watching

# File system abstraction
type FileSystem* = ref object
  watcher*: FileWatcher
  operationCache*: Table[string, FileMetadata]
  cacheTimeout*: float
  maxCacheSize*: int
  readOnlyMode*: bool
  tempDirectory*: string

# Constructor
proc newFileWatcher*(): FileWatcher =
  result = FileWatcher(
    watchedPaths: initTable[string, WatchedPath](),
    eventHandlers: @[],
    eventQueue: @[],
    batchedEvents: initTable[string, seq[FileEvent]](),
    isRunning: false,
    pollInterval: 0.5, # 500ms polling interval
    lastPollTime: 0.0,
    fileStates: initTable[string, FileMetadata](),
  )

proc newFileSystem*(): FileSystem =
  result = FileSystem(
    watcher: newFileWatcher(),
    operationCache: initTable[string, FileMetadata](),
    cacheTimeout: 30.0, # 30 second cache timeout
    maxCacheSize: 1000,
    readOnlyMode: false,
    tempDirectory: getTempDir(),
  )

# File metadata operations
proc getFileMetadata*(fs: FileSystem, path: string): Result[FileMetadata, FileError] =
  ## Get file metadata with caching
  let normalizedPath = path.normalizePath()

  # Check cache first
  if normalizedPath in fs.operationCache:
    let cached = fs.operationCache[normalizedPath]
    let age = getCurrentTimestamp() - cached.modifiedTime
    if age < fs.cacheTimeout:
      return ok(cached)

  try:
    if not fileExists(normalizedPath) and not dirExists(normalizedPath):
      return err(fileNotFound(normalizedPath))

    let info = getFileInfo(normalizedPath)
    let metadata = FileMetadata(
      path: normalizedPath,
      size: info.size,
      createdTime: info.creationTime.toUnixFloat(),
      modifiedTime: info.lastWriteTime.toUnixFloat(),
      accessedTime: info.lastAccessTime.toUnixFloat(),
      isDirectory: info.kind == pcDir,
      isReadonly: false, # Simplified: implement proper check later
      isHidden: false, # Would need platform-specific implementation
      permissions: {}, # Would need conversion from DriftFilePermission
    )

    # Cache the result
    if fs.operationCache.len < fs.maxCacheSize:
      fs.operationCache[normalizedPath] = metadata

    return ok(metadata)
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to get file metadata: " & e.msg,
        normalizedPath,
        "metadata",
      )
    )

proc fileExists*(fs: FileSystem, path: string): bool =
  let normalizedPath = path.normalizePath()
  return fileExists(normalizedPath) or dirExists(normalizedPath)

proc isDirectory*(fs: FileSystem, path: string): Result[bool, FileError] =
  let metadata = fs.getFileMetadata(path)
  if metadata.isOk:
    return ok(metadata.get().isReadonly)
  else:
    return err(metadata.error)

proc getFileSize*(fs: FileSystem, path: string): Result[int64, FileError] =
  let metadata = fs.getFileMetadata(path)
  if metadata.isOk:
    return ok(metadata.get().size)
  else:
    return err(metadata.error)

# Async file operations
proc readFileAsync*(
    fs: FileSystem, path: string
): Future[Result[string, FileError]] {.async.} =
  ## Asynchronously read file contents
  let normalizedPath = path.normalizePath()

  if fs.readOnlyMode and not fileExists(normalizedPath):
    return err(fileNotFound(normalizedPath))

  try:
    # Check file size first
    let metadata = fs.getFileMetadata(normalizedPath)
    if metadata.isErr:
      return err(metadata.error)

    let meta = metadata.get()
    if meta.isDirectory:
      return err(
        newFileError(
          ERROR_FILE_BINARY, "Cannot read directory as file", normalizedPath, "read"
        )
      )

    if meta.size > MAX_FILE_SIZE:
      return err(fileTooLarge(normalizedPath, meta.size.int, MAX_FILE_SIZE))

    # Read file content
    let content = readFile(normalizedPath)

    # Validate UTF-8
    if not isUtf8(content):
      return err(
        newFileError(
          ERROR_FILE_BINARY, "File contains non-UTF-8 content", normalizedPath, "read"
        )
      )

    return ok(content)
  except IOError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to read file: " & e.msg,
        normalizedPath,
        "read",
      )
    )
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "System error reading file: " & e.msg,
        normalizedPath,
        "read",
      )
    )

proc writeFileAsync*(
    fs: FileSystem, path: string, content: string
): Future[Result[void, FileError]] {.async.} =
  ## Asynchronously write file contents
  let normalizedPath = path.normalizePath()

  if fs.readOnlyMode:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED, "File system is in read-only mode", normalizedPath,
        "write",
      )
    )

  try:
    # Ensure directory exists
    let dir = normalizedPath.getDirectory()
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)

    # Write content
    writeFile(normalizedPath, content)

    # Clear cache entry
    if normalizedPath in fs.operationCache:
      fs.operationCache.del(normalizedPath)

    return ok()
  except IOError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to write file: " & e.msg,
        normalizedPath,
        "write",
      )
    )
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "System error writing file: " & e.msg,
        normalizedPath,
        "write",
      )
    )

proc deleteFileAsync*(
    fs: FileSystem, path: string
): Future[Result[void, FileError]] {.async.} =
  ## Asynchronously delete file or directory
  let normalizedPath = path.normalizePath()

  if fs.readOnlyMode:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED, "File system is in read-only mode", normalizedPath,
        "delete",
      )
    )

  try:
    if not fs.fileExists(normalizedPath):
      return err(fileNotFound(normalizedPath))

    let metadata = fs.getFileMetadata(normalizedPath)
    if metadata.isOk and metadata.get().isDirectory:
      removeDir(normalizedPath)
    else:
      removeFile(normalizedPath)

    # Clear cache entry
    if normalizedPath in fs.operationCache:
      fs.operationCache.del(normalizedPath)

    return ok()
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to delete file: " & e.msg,
        normalizedPath,
        "delete",
      )
    )

proc copyFileAsync*(
    fs: FileSystem, sourcePath: string, destPath: string
): Future[Result[void, FileError]] {.async.} =
  ## Asynchronously copy file
  let normalizedSource = sourcePath.normalizePath()
  let normalizedDest = destPath.normalizePath()

  if fs.readOnlyMode:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED, "File system is in read-only mode", normalizedDest,
        "copy",
      )
    )

  try:
    if not fs.fileExists(normalizedSource):
      return err(fileNotFound(normalizedSource))

    # Ensure destination directory exists
    let destDir = normalizedDest.getDirectory()
    if destDir.len > 0 and not dirExists(destDir):
      createDir(destDir)

    copyFile(normalizedSource, normalizedDest)

    # Clear destination cache entry
    if normalizedDest in fs.operationCache:
      fs.operationCache.del(normalizedDest)

    return ok()
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to copy file: " & e.msg,
        normalizedSource,
        "copy",
      )
    )

proc moveFileAsync*(
    fs: FileSystem, sourcePath: string, destPath: string
): Future[Result[void, FileError]] {.async.} =
  ## Asynchronously move/rename file
  let normalizedSource = sourcePath.normalizePath()
  let normalizedDest = destPath.normalizePath()

  if fs.readOnlyMode:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED, "File system is in read-only mode", normalizedDest,
        "move",
      )
    )

  try:
    if not fs.fileExists(normalizedSource):
      return err(fileNotFound(normalizedSource))

    # Ensure destination directory exists
    let destDir = normalizedDest.getDirectory()
    if destDir.len > 0 and not dirExists(destDir):
      createDir(destDir)

    moveFile(normalizedSource, normalizedDest)

    # Update cache entries
    if normalizedSource in fs.operationCache:
      fs.operationCache.del(normalizedSource)
    if normalizedDest in fs.operationCache:
      fs.operationCache.del(normalizedDest)

    return ok()
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to move file: " & e.msg,
        normalizedSource,
        "move",
      )
    )

# Directory operations
proc listDirectoryAsync*(
    fs: FileSystem, path: string
): Future[Result[seq[DirectoryEntry], FileError]] {.async.} =
  ## Asynchronously list directory contents
  let normalizedPath = path.normalizePath()

  try:
    if not dirExists(normalizedPath):
      return err(fileNotFound(normalizedPath))

    var entries: seq[DirectoryEntry] = @[]

    for kind, filePath in walkDir(normalizedPath):
      let name = filePath.getFileName()
      let metadata = fs.getFileMetadata(filePath)

      if metadata.isOk:
        let meta = metadata.get()
        let fileType = if meta.isDirectory: ftUnknown else: ftText
        # Would need better detection
        entries.add(DirectoryEntry(name: name, path: filePath, metadata: meta, fileType: fileType))


    # Sort entries by name
    sort(entries, proc(a, b: DirectoryEntry): int {.closure.} =
      cmp(a.name.toLowerAscii(), b.name.toLowerAscii())
    )

    return ok(entries)
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to list directory: " & e.msg,
        normalizedPath,
        "list",
      )
    )

proc createDirectoryAsync*(
    fs: FileSystem, path: string
): Future[Result[void, FileError]] {.async.} =
  ## Asynchronously create directory
  let normalizedPath = path.normalizePath()

  if fs.readOnlyMode:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED, "File system is in read-only mode", normalizedPath,
        "create",
      )
    )

  try:
    createDir(normalizedPath)
    return ok()
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_ACCESS_DENIED,
        "Failed to create directory: " & e.msg,
        normalizedPath,
        "create",
      )
    )

# File watching implementation
proc addWatchPath*(
    watcher: FileWatcher, path: string, config: WatcherConfig = WatcherConfig()
): Result[void, FileError] =
  ## Add path to file watcher
  let normalizedPath = path.normalizePath()

  if not dirExists(normalizedPath) and not fileExists(normalizedPath):
    return err(fileNotFound(normalizedPath))

  watcher.watchedPaths[normalizedPath] = WatchedPath(
    path: normalizedPath,
    config: config,
    lastEvent: getCurrentTimestamp(),
    eventCount: 0,
    isActive: true,
  )

  return ok()

proc removeWatchPath*(watcher: FileWatcher, path: string): bool =
  ## Remove path from file watcher
  let normalizedPath = path.normalizePath()

  if normalizedPath in watcher.watchedPaths:
    watcher.watchedPaths.del(normalizedPath)
    return true

  return false

proc addEventHandler*(watcher: FileWatcher, handler: FileEventHandler) =
  ## Add event handler callback
  watcher.eventHandlers.add(handler)

proc pollForChanges*(watcher: FileWatcher): Future[seq[FileEvent]] {.async.} =
  ## Poll watched paths for changes (fallback when native watching not available)
  result = @[]
  let currentTime = getCurrentTimestamp()

  if currentTime - watcher.lastPollTime < watcher.pollInterval:
    return

  watcher.lastPollTime = currentTime

  for watchedPath in watcher.watchedPaths.values:
    if not watchedPath.isActive:
      continue

    try:
      # Check if path still exists
      if not fileExists(watchedPath.path) and not dirExists(watchedPath.path):
        result.add(
          FileEvent(
            eventType: fetDeleted,
            path: watchedPath.path,
            timestamp: currentTime,
            isDirectory: false,
          )
        )
        continue

      # Get current metadata
      let info = getFileInfo(watchedPath.path)
      let currentMeta = FileMetadata(
        path: watchedPath.path,
        size: info.size,
        modifiedTime: info.lastWriteTime.toUnixFloat(),
        isDirectory: info.kind == pcDir,
      )

      # Check against cached state
      if watchedPath.path in watcher.fileStates:
        let oldMeta = watcher.fileStates[watchedPath.path]

        if currentMeta.modifiedTime != oldMeta.modifiedTime or
            currentMeta.size != oldMeta.size:
          result.add(
            FileEvent(
              eventType: fetModified,
              path: watchedPath.path,
              timestamp: currentTime,
              size: currentMeta.size,
              isDirectory: currentMeta.isDirectory,
            )
          )
      else:
        # First time seeing this file
        result.add(
          FileEvent(
            eventType: fetCreated,
            path: watchedPath.path,
            timestamp: currentTime,
            size: currentMeta.size,
            isDirectory: currentMeta.isDirectory,
          )
        )

      # Update cached state
      watcher.fileStates[watchedPath.path] = currentMeta

      # If recursive, check subdirectories
      if watchedPath.config.recursive and currentMeta.isDirectory:
        for kind, subPath in walkDir(watchedPath.path):
          # Recursively check subdirectories (simplified - would need proper recursive implementation)
          discard
    except OSError:
      # Path no longer accessible
      result.add(
        FileEvent(
          eventType: fetDeleted,
          path: watchedPath.path,
          timestamp: currentTime,
          isDirectory: false,
        )
      )

proc startWatching*(watcher: FileWatcher): Future[void] {.async.} =
  ## Start the file watcher
  watcher.isRunning = true

  while watcher.isRunning:
    let events = await watcher.pollForChanges()

    for event in events:
      # Apply debouncing
      var shouldProcess = true
      var wpKeyToUpdate: string = ""
      for wpKey, watchedPath in watcher.watchedPaths.mpairs:
        if watchedPath.path == event.path:
          let timeSinceLastEvent = event.timestamp - watchedPath.lastEvent
          if timeSinceLastEvent < watchedPath.config.debounceTime:
            shouldProcess = false
            break
          wpKeyToUpdate = wpKey

      if shouldProcess:
        watcher.eventQueue.add(event)
        # Update lastEvent for debounce
        if wpKeyToUpdate.len > 0:
          watcher.watchedPaths[wpKeyToUpdate].lastEvent = event.timestamp

        # Call event handlers
        for handler in watcher.eventHandlers:
          try:
            await handler(event)
          except:
            # Log error but continue processing
            discard

    # Sleep before next poll
    await sleepAsync(int(watcher.pollInterval * 1000))

proc stopWatching*(watcher: FileWatcher) =
  ## Stop the file watcher
  watcher.isRunning = false

proc getQueuedEvents*(watcher: FileWatcher): seq[FileEvent] =
  ## Get and clear queued events
  result = watcher.eventQueue
  watcher.eventQueue = @[]

# Cache management
proc clearCache*(fs: FileSystem) =
  ## Clear metadata cache
  fs.operationCache.clear()

proc setCacheTimeout*(fs: FileSystem, timeout: float) =
  ## Set cache timeout in seconds
  fs.cacheTimeout = timeout

proc setReadOnlyMode*(fs: FileSystem, readOnly: bool) =
  ## Set read-only mode
  fs.readOnlyMode = readOnly

# Cleanup
proc cleanup*(fs: FileSystem) =
  ## Clean up file system resources
  if fs.watcher.isRunning:
    fs.watcher.stopWatching()

  fs.operationCache.clear()
  fs.watcher.watchedPaths.clear()
  fs.watcher.eventQueue.setLen(0)
  fs.watcher.fileStates.clear()
