## Shared utilities for the Drift editor
## Pure utility functions without external dependencies

import std/[sequtils, times, os, unicode, math]
import std/strutils as strutils
import raylib as rl
import types

# String manipulation utilities
proc isEmpty*(s: string): bool =
  ## Check if string is empty or only whitespace
  strutils.strip(s).len == 0

proc isNotEmpty*(s: string): bool =
  ## Check if string has non-whitespace content
  not s.isEmpty()

proc truncate*(s: string, maxLen: int, suffix: string = "..."): string =
  ## Truncate string to maximum length with optional suffix
  if s.len <= maxLen:
    return s

  if maxLen <= suffix.len:
    return suffix[0 ..< maxLen]

  return s[0 ..< (maxLen - suffix.len)] & suffix

proc capitalize*(s: string): string =
  ## Capitalize first letter of string
  if s.len == 0:
    return s

  result = s
  result[0] = s[0].toUpperAscii()

proc camelToSnake*(s: string): string =
  ## Convert camelCase to snake_case
  result = ""
  for i, c in s:
    if c.isUpperAscii() and i > 0:
      result.add('_')
    result.add(c.toLowerAscii())

proc snakeToCamel*(s: string): string =
  ## Convert snake_case to camelCase
  let parts = s.split('_')
  result = parts[0].toLowerAscii()
  for i in 1 ..< parts.len:
    result.add(parts[i].capitalize())

proc removePrefix*(s: string, prefix: string): string =
  ## Remove prefix from string if present
  if s.startsWith(prefix):
    return s[prefix.len ..^ 1]
  return s

proc removeSuffix*(s: string, suffix: string): string =
  ## Remove suffix from string if present
  if s.endsWith(suffix):
    return s[0 ..< (s.len - suffix.len)]
  return s

proc countLines*(s: string): int =
  ## Count number of lines in string
  if s.len == 0:
    return 0
  return s.count('\n') + 1

proc getLineAt*(s: string, lineIndex: int): string =
  ## Get line at specific index (0-based)
  let lines = s.split('\n')
  if lineIndex >= 0 and lineIndex < lines.len:
    return lines[lineIndex]
  return ""

proc insertAt*(s: var string, pos: int, text: string) =
  ## Insert text at specific position
  if pos <= 0:
    s = text & s
  elif pos >= s.len:
    s = s & text
  else:
    s = s[0 ..< pos] & text & s[pos ..^ 1]

proc deleteRange*(s: var string, start: int, length: int) =
  ## Delete characters in range
  if start < 0 or start >= s.len or length <= 0:
    return

  let endPos = min(start + length, s.len)
  s = s[0 ..< start] & s[endPos ..^ 1]

# File path utilities
proc getFileExtension*(filepath: string): string =
  ## Get file extension including the dot
  let (_, _, ext) = filepath.splitFile()
  return ext

proc getFileNameWithoutExt*(filepath: string): string =
  ## Get filename without extension
  let (_, name, _) = filepath.splitFile()
  return name

proc getFileName*(filepath: string): string =
  ## Get filename with extension
  let (_, name, ext) = filepath.splitFile()
  return name & ext

proc getDirectory*(filepath: string): string =
  ## Get directory portion of path
  let (dir, _, _) = filepath.splitFile()
  return dir

proc isAbsolutePath*(path: string): bool =
  ## Check if path is absolute
  when defined(windows):
    path.len >= 2 and path[1] == ':' and path[0].isAlphaAscii()
  else:
    path.startsWith('/')

proc joinPaths*(paths: varargs[string]): string =
  ## Join multiple path components
  result = ""
  for i, path in paths:
    if i == 0:
      result = path
    else:
      result = result / path

proc normalizePath*(path: string): string =
  ## Normalize path separators and resolve relative components
  result = path.replace('\\', '/')

  # Remove trailing slashes except for root
  while result.len > 1 and result.endsWith('/'):
    result = result[0 ..^ 2]

proc getRelativePath*(fromPath: string, toPath: string): string =
  ## Get relative path from one path to another
  let fromNorm = fromPath.normalizePath()
  let toNorm = toPath.normalizePath()

  if fromNorm == toNorm:
    return "."

  # Simple implementation - could be enhanced
  if toNorm.startsWith(fromNorm):
    return toNorm[fromNorm.len ..^ 1].removePrefix("/")

  return toNorm

# Math and geometry utilities
proc clamp*[T](value: T, minVal: T, maxVal: T): T =
  ## Clamp value between min and max
  if value < minVal:
    return minVal
  elif value > maxVal:
    return maxVal
  else:
    return value

proc lerp*(a: float, b: float, t: float): float =
  ## Linear interpolation between a and b by factor t
  a + (b - a) * t

proc smoothstep*(edge0: float, edge1: float, x: float): float =
  ## Smooth interpolation with easing
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
  return t * t * (3.0 - 2.0 * t)

proc distance*(x1: float, y1: float, x2: float, y2: float): float =
  ## Calculate distance between two points
  sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))

proc pointInRect*(
    x: float, y: float, rectX: float, rectY: float, rectW: float, rectH: float
): bool =
  ## Check if point is inside rectangle
  x >= rectX and x < rectX + rectW and y >= rectY and y < rectY + rectH

proc rectOverlap*(
    x1: float,
    y1: float,
    w1: float,
    h1: float,
    x2: float,
    y2: float,
    w2: float,
    h2: float,
): bool =
  ## Check if two rectangles overlap
  not (x1 + w1 <= x2 or x2 + w2 <= x1 or y1 + h1 <= y2 or y2 + h2 <= y1)

# Collection utilities
proc findIndex*[T](items: seq[T], predicate: proc(item: T): bool): int =
  ## Find index of first item matching predicate
  for i, item in items:
    if predicate(item):
      return i
  return -1

proc removeFirst*[T](items: var seq[T], predicate: proc(item: T): bool): bool =
  ## Remove first item matching predicate
  let index = items.findIndex(predicate)
  if index >= 0:
    items.delete(index)
    return true
  return false

proc removeAll*[T](items: var seq[T], predicate: proc(item: T): bool): int =
  ## Remove all items matching predicate, return count removed
  var removed = 0
  var i = 0
  while i < items.len:
    if predicate(items[i]):
      items.delete(i)
      removed += 1
    else:
      i += 1
  return removed

proc partition*[T](
    items: seq[T], predicate: proc(item: T): bool
): tuple[matching: seq[T], notMatching: seq[T]] =
  ## Partition sequence into matching and non-matching items
  result.matching = @[]
  result.notMatching = @[]
  for item in items:
    if predicate(item):
      result.matching.add(item)
    else:
      result.notMatching.add(item)

proc groupBy*[T, K](
    items: seq[T], keySelector: proc(item: T): K
): seq[tuple[key: K, items: seq[T]]] =
  ## Group items by key
  var groups: seq[tuple[key: K, items: seq[T]]] = @[]

  for item in items:
    let key = keySelector(item)
    var found = false

    for i, group in groups.mpairs:
      if group.key == key:
        group.items.add(item)
        found = true
        break

    if not found:
      groups.add((key: key, items: @[item]))

  return groups

proc unique*[T](items: seq[T]): seq[T] =
  ## Return unique items preserving order
  result = @[]
  for item in items:
    if item notin result:
      result.add(item)

proc countIf*[T](items: seq[T], predicate: proc(item: T): bool): int =
  ## Count items matching predicate
  result = 0
  for item in items:
    if predicate(item):
      result += 1

# Time utilities
proc formatDuration*(seconds: float): string =
  ## Format duration in human-readable form
  if seconds < 1.0:
    return $(int(seconds * 1000)) & "ms"
  elif seconds < 60.0:
    return $(seconds.formatFloat(ffDecimal, 1)) & "s"
  elif seconds < 3600.0:
    let minutes = int(seconds / 60)
    let remainingSeconds = int(seconds mod 60)
    return $minutes & "m " & $remainingSeconds & "s"
  else:
    let hours = int(seconds / 3600)
    let remainingMinutes = int((seconds mod 3600) / 60)
    return $hours & "h " & $remainingMinutes & "m"

proc formatTimestamp*(timestamp: float): string =
  ## Format timestamp as readable time
  let time = timestamp.fromUnixFloat()
  return time.format("HH:mm:ss")

proc formatDate*(timestamp: float): string =
  ## Format timestamp as readable date
  let time = timestamp.fromUnixFloat()
  return time.format("yyyy-MM-dd")

proc formatDateTime*(timestamp: float): string =
  ## Format timestamp as readable date and time
  let time = timestamp.fromUnixFloat()
  return time.format("yyyy-MM-dd HH:mm:ss")

proc getCurrentTimestamp*(): float =
  ## Get current timestamp as float
  epochTime()

# Display utilities
proc getDPIScale*(): float32 =
  ## Get the current DPI scale factor
  ## This is needed when WindowHighdpi flag is enabled
  let dpiScaleVector = rl.getWindowScaleDPI()
  return max(dpiScaleVector.x, dpiScaleVector.y)

proc measureTextWidth*(text: string, fontSize: float32,
    font: rl.Font): float32 =
  ## Measure text width with specified font
  if text.len == 0:
    return 0.0
  # Use fontSize directly - Raylib handles DPI scaling automatically
  return rl.measureText(font, text, fontSize, 1.0).x

proc measureTextWidth*(text: string, fontSize: float32): float32 =
  ## Measure text width with default font
  let defaultFont = rl.getFontDefault()
  return measureTextWidth(text, fontSize, defaultFont)

proc isRecentTimestamp*(timestamp: float, maxAgeSeconds: float = 60.0): bool =
  ## Check if timestamp is recent (within maxAge seconds)
  let now = getCurrentTimestamp()
  return (now - timestamp) <= maxAgeSeconds

# Validation utilities
proc isValidEmail*(email: string): bool =
  ## Simple email validation
  let parts = email.split('@')
  if parts.len != 2:
    return false

  let localPart = parts[0]
  let domainPart = parts[1]

  if localPart.len == 0 or domainPart.len == 0:
    return false

  if '.' notin domainPart:
    return false

  return true

proc isValidFilename*(filename: string): bool =
  ## Check if filename is valid for the current OS
  if filename.len == 0 or filename.len > 255:
    return false

  # Check for invalid characters
  when defined(windows):
    let invalidChars = ['<', '>', ':', '"', '/', '\\', '|', '?', '*']
    for char in invalidChars:
      if char in filename:
        return false

    # Check for reserved names
    let reserved = [
      "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5",
      "COM6",
      "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6",
      "LPT7",
      "LPT8", "LPT9",
    ]
    if filename.toUpperAscii() in reserved:
      return false
  else:
    if '/' in filename or '\0' in filename:
      return false

  return true

proc isValidInteger*(s: string): bool =
  ## Check if string represents a valid integer
  try:
    discard s.parseInt()
    return true
  except ValueError:
    return false

proc isValidFloat*(s: string): bool =
  ## Check if string represents a valid float
  try:
    discard s.parseFloat()
    return true
  except ValueError:
    return false

# Conversion utilities
proc toByteSize*(size: int): string =
  ## Convert byte size to human-readable format
  const units = ["B", "KB", "MB", "GB", "TB"]
  var sizeFloat = size.float
  var unitIndex = 0

  while sizeFloat >= 1024.0 and unitIndex < units.len - 1:
    sizeFloat /= 1024.0
    unitIndex += 1

  if unitIndex == 0:
    return $size & " " & units[unitIndex]
  else:
    return sizeFloat.formatFloat(ffDecimal, 1) & " " & units[unitIndex]

proc fromByteSize*(sizeStr: string): int =
  ## Convert human-readable size back to bytes
  let parts = strutils.strip(sizeStr).split(' ')
  if parts.len != 2:
    return 0

  let value =
    try:
      parts[0].parseFloat()
    except ValueError:
      return 0

  let multiplier =
    case parts[1].toUpperAscii()
    of "B":
      1
    of "KB":
      1024
    of "MB":
      1024 * 1024
    of "GB":
      1024 * 1024 * 1024
    of "TB":
      1024 * 1024 * 1024 * 1024
    else:
      1

  return int(value * multiplier.float)

proc parseKeyValue*(
    line: string, separator: char = '='
): tuple[key: string, value: string] =
  ## Parse key=value line
  let parts = line.split(separator, 1)
  if parts.len == 2:
    return (key: strutils.strip(parts[0]), value: strutils.strip(parts[1]))
  else:
    return (key: strutils.strip(line), value: "")

# Text encoding utilities
proc isUtf8*(data: string): bool =
  ## Check if string is valid UTF-8
  try:
    for rune in data.runes:
      discard rune
    return true
  except:
    return false

proc toSafeUtf8*(data: string, replacement: string = "�"): string =
  ## Convert to UTF-8, replacing invalid sequences
  result = ""
  try:
    for rune in data.runes:
      result.add(rune)
  except:
    # Fallback: replace invalid bytes with replacement
    for c in data:
      if c.ord < 128:
        result.add(c)
      else:
        result.add(replacement)

proc wrapText*(
    text: string, maxWidth: float32, fontSize: float32, font: rl.Font
): seq[string] =
  ## Wrap text to fit within maxWidth
  let words = text.split(' ')
  var lines: seq[string] = @[]
  var currentLine = ""

  for word in words:
    let testLine =
      if currentLine.len > 0:
        currentLine & " " & word
      else:
        word
    let textWidth = measureTextWidth(testLine, fontSize, font)

    if textWidth > maxWidth and currentLine.len > 0:
      lines.add(currentLine)
      currentLine = word
    else:
      currentLine = testLine

  if currentLine.len > 0:
    lines.add(currentLine)

  return lines

# Debug utilities
proc debugString*[T](value: T, maxLen: int = 100): string =
  ## Create debug representation of value
  result = $value
  if result.len > maxLen:
    result = result.truncate(maxLen, "...")

proc benchmark*(name: string, operation: proc()) =
  ## Simple benchmark utility
  let startTime = getCurrentTimestamp()
  operation()
  let endTime = getCurrentTimestamp()
  let duration = endTime - startTime
  echo "Benchmark '", name, "': ", formatDuration(duration)
