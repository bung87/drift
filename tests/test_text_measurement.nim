## Unit tests for the unified text measurement system

import std/[unittest, unicode, strutils]
import raylib as rl
import ../src/shared/text_measurement

# Mock font for testing
var mockFont: rl.Font

proc setupMockFont() =
  ## Setup a mock font for testing
  # Initialize raylib for font operations
  rl.initWindow(1, 1, "Test")
  rl.setTargetFPS(60)
  mockFont = rl.getFontDefault()

proc teardownMockFont() =
  ## Cleanup mock font
  rl.closeWindow()

suite "Text Measurement System Tests":
  setup:
    setupMockFont()
  
  teardown:
    teardownMockFont()

  test "TextMeasurement constructor":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    check tm.font == addr mockFont
    check tm.fontSize == 14.0
    check tm.spacing == 1.0
    check tm.fallbackCharWidth == 8.0

  test "measureTextSafe with empty string":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let result = tm.measureTextSafe("")
    check result.x == 0.0
    check result.y == 0.0

  test "measureTextSafe with simple ASCII text":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let result = tm.measureTextSafe("hello")
    check result.x > 0.0
    check result.y > 0.0

  test "measureTextSafe with Unicode text":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let result = tm.measureTextSafe("héllo 世界")
    check result.x > 0.0
    check result.y > 0.0

  test "measureTextToPosition with empty string":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let result = tm.measureTextToPosition("", 5)
    check result == 0.0

  test "measureTextToPosition with zero position":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let result = tm.measureTextToPosition("hello", 0)
    check result == 0.0

  test "measureTextToPosition with valid position":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let fullWidth = tm.measureTextSafe("hello").x
    let partialWidth = tm.measureTextToPosition("hello", 3)
    check partialWidth > 0.0
    check partialWidth < fullWidth

  test "measureTextToPosition beyond text length":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let fullWidth = tm.measureTextSafe("hello").x
    let beyondWidth = tm.measureTextToPosition("hello", 10)
    check beyondWidth == fullWidth

  test "findPositionFromWidth with zero width":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let result = tm.findPositionFromWidth("hello", 0.0)
    check result == 0

  test "findPositionFromWidth with valid width":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "hello"
    let midWidth = tm.measureTextToPosition(text, 3)
    let foundPos = tm.findPositionFromWidth(text, midWidth)
    check foundPos >= 2 and foundPos <= 4  # Should be close to position 3

  test "findPositionFromWidth with excessive width":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "hello"
    let excessiveWidth = tm.measureTextSafe(text).x * 2
    let foundPos = tm.findPositionFromWidth(text, excessiveWidth)
    check foundPos == text.runeLen

  test "findPositionFromWidth snaps to character edges":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "ABCD"
    
    # Test that clicking between characters snaps to the nearest edge
    for i in 0..text.runeLen:
      let targetWidth = tm.measureTextToPosition(text, i)
      
      # Test clicking slightly before the character boundary
      let beforeBoundary = targetWidth - 2.0
      let beforePos = tm.findPositionFromWidth(text, beforeBoundary)
      check beforePos == i
      
      # Test clicking slightly after the character boundary
      let afterBoundary = targetWidth + 2.0
      let afterPos = tm.findPositionFromWidth(text, afterBoundary)
      if i < text.runeLen:
        check afterPos == i + 1
      else:
        check afterPos == i

  test "findPositionFromWidth with Unicode text":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "Hello 世界"  # Mixed ASCII and Unicode
    
    # Test positioning at different character positions
    let pos0 = tm.measureTextToPosition(text, 0)
    let pos6 = tm.measureTextToPosition(text, 6)  # Before Unicode chars
    let pos7 = tm.measureTextToPosition(text, 7)  # First Unicode char
    let pos8 = tm.measureTextToPosition(text, 8)  # Second Unicode char
    
    check pos0 == 0.0
    check pos6 > 0.0
    check pos7 > pos6
    check pos8 > pos7

  test "getCharacterBounds with empty string":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let bounds = tm.getCharacterBounds("", 0)
    check bounds.x == 0.0
    check bounds.width == 0.0

  test "getCharacterBounds with valid position":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let bounds = tm.getCharacterBounds("hello", 2)
    check bounds.x > 0.0
    check bounds.width > 0.0

  test "getCharacterBounds beyond text length":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "hello"
    let totalWidth = tm.measureTextSafe(text).x
    let bounds = tm.getCharacterBounds(text, 10)
    check bounds.x == totalWidth
    check bounds.width == 0.0

  test "validatePosition with empty string":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    check tm.validatePosition("", -1) == 0
    check tm.validatePosition("", 0) == 0
    check tm.validatePosition("", 5) == 0

  test "validatePosition with valid text":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "hello"
    check tm.validatePosition(text, -1) == 0
    check tm.validatePosition(text, 3) == 3
    check tm.validatePosition(text, 10) == text.runeLen

  test "isValidPosition checks":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "hello"
    check tm.isValidPosition(text, -1) == false
    check tm.isValidPosition(text, 0) == true
    check tm.isValidPosition(text, 3) == true
    check tm.isValidPosition(text, text.runeLen) == true
    check tm.isValidPosition(text, text.runeLen + 1) == false

  test "runeColumnToByte conversion":
    let text = "héllo"  # Contains accented character
    check runeColumnToByte(text, 0) == 0
    check runeColumnToByte(text, 1) >= 1  # Should account for multi-byte character
    check runeColumnToByte(text, -1) == 0

  test "byteColumnToRune conversion":
    let text = "héllo"  # Contains accented character
    check byteColumnToRune(text, 0) == 0
    check byteColumnToRune(text, 1) <= 1  # Should handle multi-byte character
    check byteColumnToRune(text, -1) == 0

  test "safeSubstring operations":
    let text = "héllo"
    check safeSubstring(text, 0, 3) == "hél"
    check safeSubstring(text, 2, 5) == "llo"
    check safeSubstring(text, 5, 3) == ""  # Invalid range
    check safeSubstring(text, -1, 3) == "hél"  # Negative start

  test "safeSubstringFromStart":
    let text = "héllo"
    check safeSubstringFromStart(text, 3) == "hél"
    check safeSubstringFromStart(text, 0) == ""
    check safeSubstringFromStart(text, 10) == text

  test "estimateTextWidth":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    let text = "hello"
    let estimate = tm.estimateTextWidth(text)
    check estimate == text.runeLen.float32 * 8.0

  test "needsAccurateMeasurement detection":
    check needsAccurateMeasurement("hello") == false  # Simple ASCII
    check needsAccurateMeasurement("héllo") == true   # Unicode
    check needsAccurateMeasurement("hello\tworld") == true  # Tab character
    check needsAccurateMeasurement("") == false       # Empty string

  test "fallback handling with nil font":
    let tm = newTextMeasurement(nil, 14.0, 1.0, 8.0)
    let result = tm.measureTextSafe("hello")
    check result.x == 5.0 * 8.0  # Should use fallback
    check result.y == 14.0

  test "Unicode text measurement consistency":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let unicodeText = "Hello 世界 🌍"
    
    # Test that measurement functions are consistent
    let fullWidth = tm.measureTextSafe(unicodeText).x
    let positionWidth = tm.measureTextToPosition(unicodeText, unicodeText.runeLen)
    check abs(fullWidth - positionWidth) < 1.0  # Should be very close
    
    # Test round-trip position finding
    let midWidth = tm.measureTextToPosition(unicodeText, 5)
    let foundPos = tm.findPositionFromWidth(unicodeText, midWidth)
    check abs(foundPos - 5) <= 1  # Should be close to original position

  test "Binary search accuracy in findPositionFromWidth":
    let tm = newTextMeasurement(addr mockFont, 14.0)
    let text = "The quick brown fox jumps"
    
    # Test multiple positions
    for i in 0..text.runeLen:
      let targetWidth = tm.measureTextToPosition(text, i)
      let foundPos = tm.findPositionFromWidth(text, targetWidth)
      check abs(foundPos - i) <= 1  # Should be very close