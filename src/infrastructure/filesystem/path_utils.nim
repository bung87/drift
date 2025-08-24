## Path utilities for cross-platform file path handling in Drift editor
## Provides safe, clean path operations without platform dependencies

import std/[os, strutils, sequtils, re, algorithm]
import ../../shared/[types, constants, errors, utils]

# Path component types
type PathComponent* = object
  directory*: string
  name*: string
  extension*: string

type PathType* = enum
  ptAbsolute = "absolute"
  ptRelative = "relative"
  ptInvalid = "invalid"

# Platform-specific constants
when defined(windows):
  const
    PATH_SEPARATOR* = '\\'
    ALT_PATH_SEPARATOR* = '/'
    DRIVE_SEPARATOR* = ':'
    UNC_PREFIX* = "\\\\"
    RESERVED_NAMES* = [
      "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6",
      "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7",
      "LPT8", "LPT9",
    ]
    INVALID_CHARS* = ['<', '>', ':', '"', '|', '?', '*', '\0']
    MAX_PATH_LENGTH* = 260
    MAX_COMPONENT_LENGTH* = 255
else:
  const
    PATH_SEPARATOR* = '/'
    ALT_PATH_SEPARATOR* = '\0' # No alternative on Unix
    DRIVE_SEPARATOR* = '\0' # No drives on Unix
    UNC_PREFIX* = ""
    RESERVED_NAMES*: seq[string] = @[]
    INVALID_CHARS* = ['/', '\0']
    MAX_PATH_LENGTH* = 4096
    MAX_COMPONENT_LENGTH* = 255

# Path validation
proc isValidPathChar*(c: char): bool =
  ## Check if character is valid in a path
  c notin INVALID_CHARS

proc isValidPathComponent*(component: string): bool =
  ## Check if path component (filename/directory name) is valid
  if component.len == 0 or component.len > MAX_COMPONENT_LENGTH:
    return false

  # Check for invalid characters
  for c in component:
    if not isValidPathChar(c):
      return false

  # Check for reserved names on Windows
  when defined(windows):
    let upperComponent = component.toUpperAscii()
    if upperComponent in RESERVED_NAMES:
      return false

    # Check for reserved names with extensions
    let baseName = component.split('.')[0].toUpperAscii()
    if baseName in RESERVED_NAMES:
      return false

    # Check for trailing dots or spaces (invalid on Windows)
    if component.endsWith('.') or component.endsWith(' '):
      return false

  return true

proc isValidPath*(path: string): bool =
  ## Check if entire path is valid
  if path.len == 0 or path.len > MAX_PATH_LENGTH:
    return false

  # Split into components and validate each
  let components = path.split({PATH_SEPARATOR, ALT_PATH_SEPARATOR})

  for i, component in components:
    # Skip empty components except at start (for absolute paths)
    if component.len == 0:
      if i == 0: # Absolute path
        continue
      else: # Empty component in middle
        return false

    if not isValidPathComponent(component):
      return false

  return true

# Path normalization
proc normalizePath*(path: string): string =
  ## Normalize path separators and resolve . and .. components
  if path.len == 0:
    return "."

  var components: seq[string] = @[]
  var isAbsolute = false

  # Handle different path formats
  var workingPath = path

  when defined(windows):
    # Handle UNC paths
    if workingPath.startsWith(UNC_PREFIX):
      isAbsolute = true
      workingPath = workingPath[2 ..^ 1]
      components.add("")
      components.add("")
    # Handle drive letters
    elif workingPath.len >= 2 and workingPath[1] == DRIVE_SEPARATOR:
      isAbsolute = true
      components.add(workingPath[0 .. 1])
      workingPath = workingPath[2 ..^ 1]
    # Handle absolute paths starting with separator
    elif workingPath.startsWith($PATH_SEPARATOR) or
        workingPath.startsWith($ALT_PATH_SEPARATOR):
      isAbsolute = true
      workingPath = workingPath[1 ..^ 1]
  else:
    # Unix-style absolute paths
    if workingPath.startsWith($PATH_SEPARATOR):
      isAbsolute = true
      workingPath = workingPath[1 ..^ 1]

  # Split by separators
  let rawComponents = workingPath.split({PATH_SEPARATOR, ALT_PATH_SEPARATOR})

  # Process path components
  for component in rawComponents:
    if component.len == 0 or component == ".":
      continue
    elif component == "..":
      if components.len > 0 and components[^1] != "..":
        discard components.pop()
      elif not isAbsolute:
        components.add("..")
    else:
      components.add(component)

  # Build result
  if isAbsolute:
    when defined(windows):
      if components.len >= 2 and components[0] == "" and components[1] == "":
        # UNC path
        result = UNC_PREFIX & components[2 ..^ 1].join($PATH_SEPARATOR)
      elif components.len > 0 and components[0].endsWith($DRIVE_SEPARATOR):
        # Drive letter
        result =
          components[0] & $PATH_SEPARATOR & components[1 ..^ 1].join($PATH_SEPARATOR)
      else:
        result = $PATH_SEPARATOR & components.join($PATH_SEPARATOR)
    else:
      result = $PATH_SEPARATOR & components.join($PATH_SEPARATOR)
  else:
    if components.len == 0:
      result = "."
    else:
      result = components.join($PATH_SEPARATOR)

proc getCanonicalPath*(path: string): Result[string, FileError] =
  ## Get canonical (absolute) path
  try:
    let expanded = expandFilename(path)
    return ok(normalizePath(expanded))
  except OSError as e:
    return err(
      newFileError(
        ERROR_FILE_NOT_FOUND,
        "Failed to get canonical path: " & e.msg,
        path,
        "canonicalize",
      )
    )

# Path component extraction
proc splitPath*(path: string): PathComponent =
  ## Split path into directory, name, and extension
  let normalized = normalizePath(path)
  let (dir, name, ext) = splitFile(normalized)

  result =
    PathComponent(directory: if dir.len == 0: "." else: dir, name: name, extension: ext)

proc getDirectory*(path: string): string =
  ## Get directory portion of path
  splitPath(path).directory

proc getFileName*(path: string): string =
  ## Get filename with extension
  let component = splitPath(path)
  return component.name & component.extension

proc getBaseName*(path: string): string =
  ## Get filename without extension
  splitPath(path).name

proc getExtension*(path: string): string =
  ## Get file extension (including dot)
  splitPath(path).extension

proc changeExtension*(path: string, newExt: string): string =
  ## Change file extension
  let component = splitPath(path)
  let extension =
    if newExt.startsWith("."):
      newExt
    else:
      "." & newExt
  return joinPath(component.directory, component.name & extension)

proc removeExtension*(path: string): string =
  ## Remove file extension
  let component = splitPath(path)
  return joinPath(component.directory, component.name)

# Path joining and manipulation
proc joinPath*(components: varargs[string]): string =
  ## Join path components safely
  var parts: seq[string] = @[]

  for component in components:
    if component.len == 0:
      continue

    let normalized = component.replace(ALT_PATH_SEPARATOR, PATH_SEPARATOR)
    parts.add(normalized)

  if parts.len == 0:
    return ""

  result = parts[0]
  for i in 1 ..< parts.len:
    if not result.endsWith($PATH_SEPARATOR):
      result.add(PATH_SEPARATOR)
    result.add(parts[i])

  return normalizePath(result)

proc appendPath*(basePath: string, relativePath: string): string =
  ## Append relative path to base path
  if isAbsolute(relativePath):
    return normalizePath(relativePath)

  return joinPath(basePath, relativePath)

# Path type detection
proc getPathType*(path: string): PathType =
  ## Determine if path is absolute, relative, or invalid
  if not isValidPath(path):
    return ptInvalid

  if isAbsolute(path):
    return ptAbsolute
  else:
    return ptRelative

proc isAbsolute*(path: string): bool =
  ## Check if path is absolute
  if path.len == 0:
    return false

  when defined(windows):
    # UNC path
    if path.startsWith(UNC_PREFIX):
      return true
    # Drive letter
    if path.len >= 2 and path[1] == DRIVE_SEPARATOR:
      return true
    # Absolute with separator
    return path.startsWith($PATH_SEPARATOR) or path.startsWith($ALT_PATH_SEPARATOR)
  else:
    return path.startsWith($PATH_SEPARATOR)

proc isRelative*(path: string): bool =
  ## Check if path is relative
  not isAbsolute(path)

# Relative path calculation
proc getRelativePath*(fromPath: string, toPath: string): Result[string, FileError] =
  ## Get relative path from one path to another
  let fromNorm = normalizePath(fromPath)
  let toNorm = normalizePath(toPath)

  # Both paths must be absolute or both relative
  if isAbsolute(fromNorm) != isAbsolute(toNorm):
    return err(
      newFileError(
        ERROR_VALIDATION_TYPE_MISMATCH,
        "Cannot compute relative path between absolute and relative paths", fromPath,
        "relative",
      )
    )

  # Simple case: same path
  if fromNorm == toNorm:
    return ok(".")

  # Split paths into components
  let fromParts = fromNorm.split(PATH_SEPARATOR).filterIt(it.len > 0)
  let toParts = toNorm.split(PATH_SEPARATOR).filterIt(it.len > 0)

  # Find common prefix
  var commonLen = 0
  let minLen = min(fromParts.len, toParts.len)

  for i in 0 ..< minLen:
    when defined(windows):
      if fromParts[i].toLowerAscii() == toParts[i].toLowerAscii():
        commonLen += 1
      else:
        break
    else:
      if fromParts[i] == toParts[i]:
        commonLen += 1
      else:
        break

  # Build relative path
  var relativeParts: seq[string] = @[]

  # Add .. for each remaining component in fromPath
  for i in commonLen ..< fromParts.len:
    relativeParts.add("..")

  # Add remaining components from toPath
  for i in commonLen ..< toParts.len:
    relativeParts.add(toParts[i])

  if relativeParts.len == 0:
    return ok(".")

  return ok(relativeParts.join($PATH_SEPARATOR))

# Path sanitization
proc sanitizePathComponent*(component: string): string =
  ## Sanitize a path component for safe use
  if component.len == 0:
    return "unnamed"

  result = ""
  for c in component:
    if isValidPathChar(c) and c != PATH_SEPARATOR and c != ALT_PATH_SEPARATOR:
      result.add(c)
    else:
      result.add('_')

  # Handle reserved names on Windows
  when defined(windows):
    let upperResult = result.toUpperAscii()
    if upperResult in RESERVED_NAMES:
      result = result & "_"

    # Remove trailing dots and spaces
    while result.endsWith('.') or result.endsWith(' '):
      result = result[0 ..^ 2]

  # Ensure not empty
  if result.len == 0:
    result = "unnamed"

  return result

proc sanitizePath*(path: string): string =
  ## Sanitize entire path for safe use
  let components = path.split({PATH_SEPARATOR, ALT_PATH_SEPARATOR})
  var sanitizedComponents: seq[string] = @[]

  for i, component in components:
    if i == 0 and component.len == 0:
      # Preserve leading separator for absolute paths
      sanitizedComponents.add("")
    elif component.len > 0:
      sanitizedComponents.add(sanitizePathComponent(component))

  if sanitizedComponents.len == 0:
    return "unnamed"

  return sanitizedComponents.join($PATH_SEPARATOR)

# Glob pattern matching
proc compileGlobPattern*(pattern: string): Regex =
  ## Convert glob pattern to regex
  var regexPattern = "^"
  var i = 0

  while i < pattern.len:
    case pattern[i]
    of '*':
      if i + 1 < pattern.len and pattern[i + 1] == '*':
        # ** means match any number of directories
        regexPattern.add(".*")
        i += 2
        if i < pattern.len and pattern[i] == PATH_SEPARATOR:
          i += 1
      else:
        # * means match any characters except path separator
        regexPattern.add("[^" & $PATH_SEPARATOR & "]*")
        i += 1
    of '?':
      regexPattern.add("[^" & $PATH_SEPARATOR & "]")
      i += 1
    of '[':
      # Character class
      regexPattern.add("[")
      i += 1
      while i < pattern.len and pattern[i] != ']':
        regexPattern.add(pattern[i])
        i += 1
      regexPattern.add("]")
      if i < pattern.len:
        i += 1
    of '.', '(', ')', '|', '+', '^', '$', '{', '}':
      # Escape regex special characters
      regexPattern.add("\\" & pattern[i])
      i += 1
    else:
      regexPattern.add(pattern[i])
      i += 1

  regexPattern.add("$")
  return re(regexPattern)

proc matchesGlob*(path: string, pattern: string): bool =
  ## Check if path matches glob pattern
  try:
    let regex = compileGlobPattern(pattern)
    let normalizedPath = normalizePath(path).replace('\\', '/')
    return normalizedPath.match(regex)
  except RegexError:
    return false

proc matchesAnyGlob*(path: string, patterns: seq[string]): bool =
  ## Check if path matches any of the glob patterns
  for pattern in patterns:
    if matchesGlob(path, pattern):
      return true
  return false

# Common path operations
proc getCommonPrefix*(paths: seq[string]): string =
  ## Get common prefix of multiple paths
  if paths.len == 0:
    return ""

  if paths.len == 1:
    return getDirectory(paths[0])

  # Normalize all paths
  let normalizedPaths = paths.mapIt(normalizePath(it))

  # Split into components
  let pathComponents = normalizedPaths.mapIt(it.split(PATH_SEPARATOR))

  # Find common prefix
  var commonComponents: seq[string] = @[]
  let minLen = pathComponents.mapIt(it.len).min()

  for i in 0 ..< minLen:
    let component = pathComponents[0][i]
    var allMatch = true

    for j in 1 ..< pathComponents.len:
      when defined(windows):
        if pathComponents[j][i].toLowerAscii() != component.toLowerAscii():
          allMatch = false
          break
      else:
        if pathComponents[j][i] != component:
          allMatch = false
          break

    if allMatch:
      commonComponents.add(component)
    else:
      break

  if commonComponents.len == 0:
    return ""

  return commonComponents.join($PATH_SEPARATOR)

proc getUniqueFileName*(
    directory: string, baseName: string, extension: string = ""
): string =
  ## Generate unique filename in directory
  let ext =
    if extension.startsWith("."):
      extension
    else:
      "." & extension
  var counter = 0
  var fileName = baseName & ext

  while fileExists(joinPath(directory, fileName)):
    counter += 1
    fileName = baseName & "_" & $counter & ext

  return fileName

# Path comparison
proc pathsEqual*(path1: string, path2: string): bool =
  ## Compare paths for equality (case-insensitive on Windows)
  let norm1 = normalizePath(path1)
  let norm2 = normalizePath(path2)

  when defined(windows):
    return norm1.toLowerAscii() == norm2.toLowerAscii()
  else:
    return norm1 == norm2

proc isSubPath*(childPath: string, parentPath: string): bool =
  ## Check if childPath is under parentPath
  let childNorm = normalizePath(childPath)
  let parentNorm = normalizePath(parentPath)

  if childNorm.len <= parentNorm.len:
    return false

  when defined(windows):
    let childLower = childNorm.toLowerAscii()
    let parentLower = parentNorm.toLowerAscii()
    return childLower.startsWith(parentLower & $PATH_SEPARATOR)
  else:
    return childNorm.startsWith(parentNorm & $PATH_SEPARATOR)

# Temporary and backup path generation
proc getTempPath*(prefix: string = "drift_"): string =
  ## Generate temporary file path
  let tempDir = getTempDir()
  let timestamp = int(getCurrentTimestamp() * 1000)
  let fileName = prefix & $timestamp
  return joinPath(tempDir, fileName)

proc getBackupPath*(originalPath: string): string =
  ## Generate backup file path
  let component = splitPath(originalPath)
  let backupName = component.name & BACKUP_EXTENSION
  return joinPath(component.directory, backupName)

proc getVersionedPath*(originalPath: string, version: int): string =
  ## Generate versioned file path
  let component = splitPath(originalPath)
  let versionedName = component.name & "." & $version & component.extension
  return joinPath(component.directory, versionedName)

# Path validation with detailed errors
proc validatePath*(path: string): Result[void, ValidationError] =
  ## Validate path and return detailed error information
  if path.len == 0:
    return
      err(newValidationError(ERROR_VALIDATION_REQUIRED, "Path cannot be empty", "path"))

  if path.len > MAX_PATH_LENGTH:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE,
        "Path too long: " & $path.len & " characters (max: " & $MAX_PATH_LENGTH & ")",
        "path",
        "1-" & $MAX_PATH_LENGTH,
      )
    )

  # Check individual components
  let components = path.split({PATH_SEPARATOR, ALT_PATH_SEPARATOR})
  for i, component in components:
    if i == 0 and component.len == 0:
      continue # Allow empty first component for absolute paths

    if component.len == 0:
      return err(
        newValidationError(
          ERROR_VALIDATION_INVALID_VALUE, "Path contains empty component", "path"
        )
      )

    if not isValidPathComponent(component):
      return err(
        newValidationError(
          ERROR_VALIDATION_INVALID_VALUE, "Invalid path component: " & component, "path"
        )
      )

  return ok()

# Debug utilities
proc getPathInfo*(path: string): string =
  ## Get debug information about path
  var info: seq[string] = @[]

  info.add("Path: " & path)
  info.add("Normalized: " & normalizePath(path))
  info.add("Type: " & $getPathType(path))
  info.add("Valid: " & $isValidPath(path))

  let component = splitPath(path)
  info.add("Directory: " & component.directory)
  info.add("Name: " & component.name)
  info.add("Extension: " & component.extension)

  return info.join("\n")
