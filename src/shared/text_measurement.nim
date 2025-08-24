## Unified Text Measurement System
## Provides consistent, accurate text measurement for all editor operations
## Replaces fixed charWidth usage with Unicode-safe text measurement

import std/[unicode, strformat, times]
import raylib as rl
import types
import ../domain/document
import errors
import results

type
  TextMeasurement* = object
    ## Configuration for text measurement operations
    font*: ptr rl.Font
    fontSize*: float32
    spacing*: float32
    fallbackCharWidth*: float32 # Used only when measurement fails

  TextMeasurementError* = object of EditorError
    ## Error type for text measurement failures
    text*: string
    operation*: string
    fallbackUsed*: bool

  MeasurementFailureReason* = enum
    ## Reasons why text measurement might fail
    mfrNullFont = "null_font"
    mfrInvalidUtf8 = "invalid_utf8"
    mfrRaylibError = "raylib_error"
    mfrEmptyText = "empty_text"
    mfrUnknownError = "unknown_error"

  MeasurementStats* = object
    ## Statistics for monitoring measurement performance and failures
    totalMeasurements*: int
    failedMeasurements*: int
    fallbacksUsed*: int
    lastFailureTime*: float64
    lastFailureReason*: MeasurementFailureReason

# Global measurement statistics for monitoring
var globalMeasurementStats* = MeasurementStats()

# Logging utilities for text measurement failures
proc logMeasurementFailure*(
    failureType: MeasurementFailureReason, text: string, context: string,
        details: string = ""
) =
  ## Log measurement failures for debugging and optimization
  globalMeasurementStats.failedMeasurements.inc
  globalMeasurementStats.lastFailureReason = failureType
  globalMeasurementStats.lastFailureTime = now().toTime().toUnixFloat()

proc logMeasurementFallback*(text: string, operation: string, reason: string) =
  ## Log when fallback measurement is used
  globalMeasurementStats.fallbacksUsed.inc

# Constructor
proc newTextMeasurement*(
  font: ptr rl.Font,
  fontSize: float32,
  spacing: float32 = 1.0,
  fallbackCharWidth: float32 = 8.0
): TextMeasurement =
  ## Create a new TextMeasurement configuration
  TextMeasurement(
    font: font,
    fontSize: fontSize,
    spacing: spacing,
    fallbackCharWidth: fallbackCharWidth
  )

# Error handling utilities
proc newTextMeasurementError*(
  code: string,
  message: string,
  text: string,
  operation: string,
  fallbackUsed: bool = false
): TextMeasurementError =
  ## Create a new text measurement error
  result = TextMeasurementError(
    text: text,
    operation: operation,
    fallbackUsed: fallbackUsed
  )
  result.code = code
  result.msg = message

proc handleMeasurementError*(
  text: string,
  operation: string,
  reason: MeasurementFailureReason,
  details: string = ""
): TextMeasurementError =
  ## Handle and log measurement errors consistently
  logMeasurementFailure(reason, text, operation, details)

  let errorMessage = case reason
    of mfrNullFont: "Font is null - cannot measure text"
    of mfrInvalidUtf8: "Invalid UTF-8 sequence in text"
    of mfrRaylibError: "Raylib measurement function failed"
    of mfrEmptyText: "Empty text provided for measurement"
    of mfrUnknownError: "Unknown error during text measurement"

  let reasonStr = case reason
    of mfrNullFont: "null_font"
    of mfrInvalidUtf8: "invalid_utf8"
    of mfrRaylibError: "raylib_error"
    of mfrEmptyText: "empty_text"
    of mfrUnknownError: "unknown_error"

  return newTextMeasurementError(
    reasonStr,
    fmt"{errorMessage}: {details}",
    text,
    operation,
    false
  )

# Core measurement functions with comprehensive error handling
proc measureTextSafe*(tm: TextMeasurement, text: string): rl.Vector2 =
  ## Unicode-safe text measurement with robust fallback handling and comprehensive error logging
  globalMeasurementStats.totalMeasurements.inc

  # Handle empty text case
  if text.len == 0:
    return rl.Vector2(x: 0, y: tm.fontSize)

  # Handle null font case with logging
  if tm.font == nil:
    logMeasurementFallback(text, "measureTextSafe", "null font")
    return rl.Vector2(
      x: text.runeLen.float32 * tm.fallbackCharWidth,
      y: tm.fontSize
    )

  try:
    # Validate UTF-8 first
    let utf8ValidationResult = validateUtf8(text)
    if utf8ValidationResult == -1:
      # Valid UTF-8, proceed with normal measurement
      try:
        return rl.measureText(tm.font[], text, tm.fontSize, tm.spacing)
      except Exception as e:
        # Raylib measurement failed
        discard handleMeasurementError(text, "measureTextSafe", mfrRaylibError, e.msg)
        logMeasurementFallback(text, "measureTextSafe", "raylib exception: " & e.msg)
        return rl.Vector2(
          x: text.runeLen.float32 * tm.fallbackCharWidth,
          y: tm.fontSize
        )
    else:
      # Invalid UTF-8 sequences detected, sanitize text
      logMeasurementFallback(text, "measureTextSafe",
          fmt"invalid UTF-8 at position {utf8ValidationResult}")

      var safeText = ""
      var runeCount = 0
      try:
        for rune in text.runes():
          try:
            safeText.add($rune)
            runeCount.inc
          except Exception:
            safeText.add("?")
            runeCount.inc

        # Try measuring the sanitized text
        try:
          return rl.measureText(tm.font[], safeText, tm.fontSize, tm.spacing)
        except Exception as e:
          # Even sanitized text failed
          discard handleMeasurementError(safeText, "measureTextSafe",
              mfrRaylibError, e.msg)
          logMeasurementFallback(text, "measureTextSafe",
              "raylib failed on sanitized text: " & e.msg)
          return rl.Vector2(
            x: runeCount.float32 * tm.fallbackCharWidth,
            y: tm.fontSize
          )
      except Exception as e:
        # Rune iteration failed
        discard handleMeasurementError(text, "measureTextSafe", mfrInvalidUtf8, e.msg)
        logMeasurementFallback(text, "measureTextSafe",
            "rune iteration failed: " & e.msg)
        # Use byte length as approximation
        return rl.Vector2(
          x: text.len.float32 * tm.fallbackCharWidth * 0.8, # Assume average character is smaller than fallback
          y: tm.fontSize
        )
  except Exception as e:
    # Catch-all for any other errors
    discard handleMeasurementError(text, "measureTextSafe", mfrUnknownError, e.msg)
    logMeasurementFallback(text, "measureTextSafe", "unknown exception: " & e.msg)
    return rl.Vector2(
      x: text.len.float32 * tm.fallbackCharWidth * 0.8,
      y: tm.fontSize
    )

proc measureTextToPosition*(tm: TextMeasurement, text: string,
    targetPosition: int): float32 =
  ## Measure text width up to a specific character position (rune-based) with comprehensive error handling
  globalMeasurementStats.totalMeasurements.inc

  # Handle edge cases
  if text.len == 0:
    return 0.0

  if targetPosition <= 0:
    return 0.0

  try:
    # Get runes safely
    let runes = text.toRunes()

    if targetPosition >= runes.len:
      # Position is beyond text end, measure entire text
      return tm.measureTextSafe(text).x

    let safePosition = min(targetPosition, runes.len)
    if safePosition <= 0:
      return 0.0

    # Extract substring safely
    try:
      let substring = $(runes[0 ..< safePosition])
      return tm.measureTextSafe(substring).x
    except Exception as e:
      # Substring extraction failed
      discard handleMeasurementError(text, "measureTextToPosition",
        mfrInvalidUtf8,
        fmt"substring extraction failed at position {targetPosition}: {e.msg}")
      logMeasurementFallback(text, "measureTextToPosition",
          "substring extraction failed: " & e.msg)

      # Fallback: estimate based on position ratio
      let totalWidth = tm.measureTextSafe(text).x
      let positionRatio = targetPosition.float32 / runes.len.float32
      return totalWidth * positionRatio

  except Exception as e:
    # Rune conversion failed
    discard handleMeasurementError(text, "measureTextToPosition",
      mfrInvalidUtf8,
      fmt"rune conversion failed: {e.msg}")
    logMeasurementFallback(text, "measureTextToPosition",
        "rune conversion failed: " & e.msg)

    # Ultimate fallback: use byte-based estimation
    if targetPosition >= text.len:
      return text.len.float32 * tm.fallbackCharWidth
    else:
      return targetPosition.float32 * tm.fallbackCharWidth

proc findPositionFromWidth*(tm: TextMeasurement, text: string,
    targetWidth: float32): int =
  ## Find character position closest to a target width using binary search with comprehensive error handling
  ## Improved to snap to nearest character edge for better mouse click accuracy
  globalMeasurementStats.totalMeasurements.inc

  # Handle edge cases
  if text.len == 0 or targetWidth <= 0.0:
    return 0

  try:
    let runes = text.toRunes()
    if runes.len == 0:
      return 0

    # Binary search for the closest position with error handling
    var left = 0
    var right = runes.len
    var searchAttempts = 0
    let maxSearchAttempts = 50 # Prevent infinite loops

    while left < right and searchAttempts < maxSearchAttempts:
      searchAttempts.inc
      let mid = (left + right) div 2

      try:
        let width = tm.measureTextToPosition(text, mid)

        if width < targetWidth:
          left = mid + 1
        else:
          right = mid
      except Exception as e:
        # Measurement failed during binary search
        discard handleMeasurementError(text, "findPositionFromWidth",
          mfrUnknownError,
          fmt"binary search failed at position {mid}: {e.msg}")
        logMeasurementFallback(text, "findPositionFromWidth",
            "binary search measurement failed: " & e.msg)

        # Fallback to simple estimation
        let estimatedPosition = (targetWidth / tm.fallbackCharWidth).int
        return min(estimatedPosition, runes.len)

    if searchAttempts >= maxSearchAttempts:
      logMeasurementFallback(text, "findPositionFromWidth", "binary search exceeded max attempts")
      # Fallback to simple estimation
      let estimatedPosition = (targetWidth / tm.fallbackCharWidth).int
      return min(estimatedPosition, runes.len)

    # Improved fine-tuning: snap to nearest character edge
    if left < runes.len:
      try:
        let beforeWidth = tm.measureTextToPosition(text, left)
        let afterWidth = tm.measureTextToPosition(text, left + 1)

        # Calculate distances to both character edges (for potential future use)
        # let beforeDist = abs(targetWidth - beforeWidth)
        # let afterDist = abs(targetWidth - afterWidth)

        # Find the midpoint between the two character positions
        let midPoint = (beforeWidth + afterWidth) / 2.0

        # If target is closer to the midpoint, snap to the character edge that's closer
        if targetWidth < midPoint:
          # Click is in the first half of the character, snap to start of character
          return left
        else:
          # Click is in the second half of the character, snap to end of character
          return left + 1

      except Exception as e:
        # Fine-tuning failed, use the binary search result
        logMeasurementFallback(text, "findPositionFromWidth",
            "fine-tuning failed: " & e.msg)

    return left

  except Exception as e:
    # Rune conversion or other critical failure
    discard handleMeasurementError(text, "findPositionFromWidth",
      mfrInvalidUtf8,
      fmt"critical failure: {e.msg}")
    logMeasurementFallback(text, "findPositionFromWidth", "critical failure: " & e.msg)

    # Ultimate fallback: simple width-based estimation
    let estimatedPosition = (targetWidth / tm.fallbackCharWidth).int
    return min(estimatedPosition, text.len)

proc getCharacterBounds*(tm: TextMeasurement, text: string,
    position: int): tuple[x: float32, width: float32] =
  ## Get the visual bounds of a character at a specific position with comprehensive error handling
  globalMeasurementStats.totalMeasurements.inc

  # Handle edge cases
  if text.len == 0 or position < 0:
    return (x: 0.0, width: 0.0)

  try:
    let runes = text.toRunes()
    if position >= runes.len:
      let totalWidth = tm.measureTextSafe(text).x
      return (x: totalWidth, width: 0.0)

    # Calculate position of character start with error handling
    let startX = try:
      tm.measureTextToPosition(text, position)
    except Exception as e:
      discard handleMeasurementError(text, "getCharacterBounds",
          mfrUnknownError,
        fmt"start position measurement failed: {e.msg}")
      logMeasurementFallback(text, "getCharacterBounds",
          "start position measurement failed: " & e.msg)
      position.float32 * tm.fallbackCharWidth

    # Calculate character width with error handling
    let charWidth = try:
      if position + 1 < runes.len:
        # Measure to next position and subtract
        let nextX = tm.measureTextToPosition(text, position + 1)
        nextX - startX
      else:
        # For last character, measure just that character
        let charText = $runes[position]
        tm.measureTextSafe(charText).x
    except Exception as e:
      discard handleMeasurementError(text, "getCharacterBounds",
          mfrUnknownError,
        fmt"character width measurement failed: {e.msg}")
      logMeasurementFallback(text, "getCharacterBounds",
          "character width measurement failed: " & e.msg)
      tm.fallbackCharWidth

    return (x: startX, width: charWidth)

  except Exception as e:
    # Critical failure in rune conversion or other operations
    discard handleMeasurementError(text, "getCharacterBounds", mfrInvalidUtf8,
      fmt"critical failure: {e.msg}")
    logMeasurementFallback(text, "getCharacterBounds", "critical failure: " & e.msg)

    # Ultimate fallback
    return (
      x: position.float32 * tm.fallbackCharWidth,
      width: tm.fallbackCharWidth
    )

# Validation and utility functions
proc validatePosition*(tm: TextMeasurement, text: string, position: int): int =
  ## Validate and clamp position to valid range for the text
  if text.len == 0:
    return 0

  let runeCount = text.runeLen
  return max(0, min(position, runeCount))

proc isValidPosition*(tm: TextMeasurement, text: string, position: int): bool =
  ## Check if a position is valid for the given text
  if text.len == 0:
    return position == 0

  return position >= 0 and position <= text.runeLen

# Conversion utilities for compatibility with existing code
proc runeColumnToByte*(text: string, runeCol: int): int =
  ## Convert rune-based column position to byte position
  if text.len == 0 or runeCol <= 0:
    return 0

  var currentRune = 0
  var bytePos = 0

  for rune in text.runes():
    if currentRune >= runeCol:
      break
    bytePos += rune.size()
    currentRune += 1

  return min(bytePos, text.len)

proc byteColumnToRune*(text: string, byteCol: int): int =
  ## Convert byte-based column position to rune position
  if text.len == 0 or byteCol <= 0:
    return 0

  var currentByte = 0
  var runePos = 0

  for rune in text.runes():
    if currentByte >= byteCol:
      break
    currentByte += rune.size()
    runePos += 1

  return runePos

# Safe substring operations
proc safeSubstring*(text: string, startPos: int, endPos: int): string =
  ## Safely extract substring using rune positions instead of byte positions
  if text.len == 0 or startPos >= endPos:
    return ""

  let runes = text.toRunes()
  if startPos >= runes.len:
    return ""

  let safeStart = max(0, startPos)
  let safeEnd = min(runes.len, endPos)

  if safeStart >= safeEnd:
    return ""

  return $(runes[safeStart ..< safeEnd])

proc safeSubstringFromStart*(text: string, endPos: int): string =
  ## Safely extract substring from start to rune position
  return safeSubstring(text, 0, endPos)

# Error handling utilities with comprehensive logging
proc withFallback*[T](operation: proc(): T, fallback: T,
    operationName: string = "unknown"): T =
  ## Execute operation with fallback on error and logging
  try:
    return operation()
  except Exception as e:
    logMeasurementFallback("", operationName, "operation failed: " & e.msg)
    return fallback

proc withMeasurementFallback*[T](
  operation: proc(): T,
  fallback: T,
  text: string,
  operationName: string,
  reason: MeasurementFailureReason = mfrUnknownError
): T =
  ## Execute text measurement operation with comprehensive error handling and logging
  try:
    return operation()
  except Exception as e:
    discard handleMeasurementError(text, operationName, reason, e.msg)
    logMeasurementFallback(text, operationName, e.msg)
    return fallback

# Safe UTF-8 handling utilities
proc safeValidateUtf8*(text: string): bool =
  ## Safely validate UTF-8 with error handling
  try:
    return validateUtf8(text) == -1
  except Exception as e:
    logMeasurementFailure(mfrInvalidUtf8, text, "safeValidateUtf8", e.msg)
    return false

proc safeToRunes*(text: string): seq[Rune] =
  ## Safely convert text to runes with error handling
  try:
    return text.toRunes()
  except Exception as e:
    logMeasurementFailure(mfrInvalidUtf8, text, "safeToRunes", e.msg)
    # Fallback: create runes from individual bytes (not ideal but safe)
    var fallbackRunes: seq[Rune] = @[]
    for c in text:
      try:
        fallbackRunes.add(Rune(c.ord))
      except:
        fallbackRunes.add(Rune('?'.ord))
    return fallbackRunes

proc safeRuneLen*(text: string): int =
  ## Safely get rune length with error handling
  try:
    return text.runeLen
  except Exception as e:
    logMeasurementFailure(mfrInvalidUtf8, text, "safeRuneLen", e.msg)
    # Fallback to byte length (overestimate)
    return text.len

# Statistics and monitoring functions
proc getMeasurementStats*(): MeasurementStats =
  ## Get current measurement statistics
  return globalMeasurementStats

proc resetMeasurementStats*() =
  ## Reset measurement statistics
  globalMeasurementStats = MeasurementStats()

proc getMeasurementFailureRate*(): float =
  ## Get the current failure rate as a percentage
  if globalMeasurementStats.totalMeasurements == 0:
    return 0.0
  return (globalMeasurementStats.failedMeasurements.float /
      globalMeasurementStats.totalMeasurements.float) * 100.0

proc getFallbackUsageRate*(): float =
  ## Get the current fallback usage rate as a percentage
  if globalMeasurementStats.totalMeasurements == 0:
    return 0.0
  return (globalMeasurementStats.fallbacksUsed.float /
      globalMeasurementStats.totalMeasurements.float) * 100.0

proc shouldLogMeasurementStats*(): bool =
  ## Determine if measurement stats should be logged (e.g., high failure rate)
  let failureRate = getMeasurementFailureRate()
  let fallbackRate = getFallbackUsageRate()
  return failureRate > 5.0 or fallbackRate > 10.0 or
      globalMeasurementStats.totalMeasurements > 1000

proc logMeasurementStats*() =
  ## Log current measurement statistics
  let stats = getMeasurementStats()
  let failureRate = getMeasurementFailureRate()
  let fallbackRate = getFallbackUsageRate()
  # TODO: Implement actual logging output
  discard stats
  discard failureRate
  discard fallbackRate

# Performance optimization helpers
proc estimateTextWidth*(tm: TextMeasurement, text: string): float32 =
  ## Quick estimation of text width using fallback character width
  ## Useful for performance-critical operations where exact measurement isn't needed
  return text.runeLen.float32 * tm.fallbackCharWidth

proc needsAccurateMeasurement*(text: string): bool =
  ## Determine if text contains characters that require accurate measurement
  ## Returns true for text with Unicode characters, tabs, or variable-width content
  for rune in text.runes():
    if rune.int32 > 127 or rune == Rune('\t'):
      return true
  return false

# Cursor Position Validation
proc validateCursorPosition*(cursor: CursorPos, document: Document): CursorPos =
  ## Validate and correct cursor position to ensure it's within document bounds
  ## Handles edge cases like empty documents and lines with only whitespace
  ## Returns a corrected cursor position that is guaranteed to be valid

  # Handle empty document case
  if document == nil or document.isEmpty():
    return CursorPos(line: 0, col: 0)

  let totalLines = document.lineCount()

  # Handle case where document has no lines (shouldn't happen but be safe)
  if totalLines == 0:
    return CursorPos(line: 0, col: 0)

  # Validate and correct line number
  var correctedLine = cursor.line
  if correctedLine < 0:
    correctedLine = 0
  elif correctedLine >= totalLines:
    correctedLine = totalLines - 1

  # Get the line to validate column position
  let lineResult = document.getLine(correctedLine)
  if lineResult.isErr:
    # If we can't get the line, position at start of document
    return CursorPos(line: 0, col: 0)

  let lineText = lineResult.get()
  let lineLength = lineText.runeLen

  # Validate and correct column position
  var correctedCol = cursor.col
  if correctedCol < 0:
    correctedCol = 0
  elif correctedCol > lineLength:
    # Allow cursor to be positioned at end of line (after last character)
    correctedCol = lineLength

  # Handle special case: lines with only whitespace
  # Cursor positioning should still work normally, but we ensure it's within bounds
  if lineText.len > 0:
    # For lines with content (including whitespace-only lines),
    # ensure column is within valid range [0, lineLength]
    correctedCol = max(0, min(correctedCol, lineLength))
  else:
    # Empty line - cursor can only be at column 0
    correctedCol = 0

  return CursorPos(line: correctedLine, col: correctedCol)

proc isValidCursorPosition*(cursor: CursorPos, document: Document): bool =
  ## Check if a cursor position is valid within the document bounds
  ## Returns true if the position is valid, false otherwise

  # Handle null document
  if document == nil:
    return cursor.line == 0 and cursor.col == 0

  # Handle empty document
  if document.isEmpty():
    return cursor.line == 0 and cursor.col == 0

  let totalLines = document.lineCount()

  # Check line bounds
  if cursor.line < 0 or cursor.line >= totalLines:
    return false

  # Get the line to check column bounds
  let lineResult = document.getLine(cursor.line)
  if lineResult.isErr:
    return false

  let lineText = lineResult.get()
  let lineLength = lineText.runeLen

  # Check column bounds - allow cursor at end of line
  if cursor.col < 0 or cursor.col > lineLength:
    return false

  return true

proc clampCursorToDocument*(cursor: CursorPos, document: Document): CursorPos =
  ## Clamp cursor position to valid document bounds without validation
  ## This is a simpler version that just ensures bounds without detailed error handling

  if document == nil or document.isEmpty():
    return CursorPos(line: 0, col: 0)

  let totalLines = document.lineCount()
  let clampedLine = max(0, min(cursor.line, totalLines - 1))

  let lineLength = document.lineLength(clampedLine)
  let clampedCol = max(0, min(cursor.col, lineLength))

  return CursorPos(line: clampedLine, col: clampedCol)

proc ensureCursorInBounds*(cursor: var CursorPos, document: Document) =
  ## In-place cursor position correction to ensure it's within document bounds
  ## Modifies the cursor position directly

  cursor = validateCursorPosition(cursor, document)
