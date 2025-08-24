## Test comprehensive error handling for text measurement failures
## Tests the enhanced error handling, logging, and fallback mechanisms

import std/[unittest, unicode, strformat]
import raylib as rl
import ../src/shared/text_measurement
import ../src/shared/types
import ../src/shared/errors

# Mock font for testing
var mockFont: rl.Font

proc setupMockFont() =
  ## Setup a mock font for testing
  # Initialize raylib for font operations
  rl.initWindow(1, 1, "Test")
  rl.setTargetFPS(60)
  # Use the default font
  mockFont = rl.getFontDefault()

suite "Text Measurement Error Handling":
  setup:
    setupMockFont()
    resetMeasurementStats()

  test "measureTextSafe handles empty text":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    let result = tm.measureTextSafe("")
    check result.x == 0.0
    check result.y == 14.0

  test "measureTextSafe handles null font gracefully":
    let tm = newTextMeasurement(nil, 14.0, 1.0, 8.0)
    let result = tm.measureTextSafe("Hello")
    # Should fallback to character counting
    check result.x == 5.0 * 8.0  # 5 characters * 8.0 fallback width
    check result.y == 14.0

  test "measureTextSafe handles invalid UTF-8 sequences":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    # Create text with invalid UTF-8 byte sequence
    let invalidUtf8 = "Hello\xFF\xFEWorld"
    let result = tm.measureTextSafe(invalidUtf8)
    # Should not crash and should return a reasonable result
    check result.x > 0.0
    check result.y == 14.0

  test "measureTextToPosition handles edge cases":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    
    # Empty text
    check tm.measureTextToPosition("", 5) == 0.0
    
    # Negative position
    check tm.measureTextToPosition("Hello", -1) == 0.0
    
    # Position beyond text length
    let text = "Hello"
    let fullWidth = tm.measureTextSafe(text).x
    check tm.measureTextToPosition(text, 10) == fullWidth

  test "findPositionFromWidth handles edge cases":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    
    # Empty text
    check tm.findPositionFromWidth("", 50.0) == 0
    
    # Zero width
    check tm.findPositionFromWidth("Hello", 0.0) == 0
    
    # Negative width
    check tm.findPositionFromWidth("Hello", -10.0) == 0

  test "getCharacterBounds handles edge cases":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    
    # Empty text
    let emptyBounds = tm.getCharacterBounds("", 0)
    check emptyBounds.x == 0.0
    check emptyBounds.width == 0.0
    
    # Negative position
    let negBounds = tm.getCharacterBounds("Hello", -1)
    check negBounds.x == 0.0
    check negBounds.width == 0.0
    
    # Position beyond text
    let beyondBounds = tm.getCharacterBounds("Hi", 5)
    check beyondBounds.width == 0.0

  test "safeValidateUtf8 handles invalid sequences":
    # Valid UTF-8
    check safeValidateUtf8("Hello World") == true
    check safeValidateUtf8("こんにちは") == true
    
    # Invalid UTF-8 should not crash
    let invalidUtf8 = "Hello\xFF\xFEWorld"
    let result = safeValidateUtf8(invalidUtf8)
    # Should return false for invalid UTF-8
    check result == false

  test "safeToRunes handles invalid UTF-8":
    # Valid UTF-8
    let validRunes = safeToRunes("Hello")
    check validRunes.len == 5
    
    # Invalid UTF-8 should not crash and should return something
    let invalidUtf8 = "Hello\xFF\xFEWorld"
    let invalidRunes = safeToRunes(invalidUtf8)
    check invalidRunes.len > 0  # Should return some runes, even if fallback

  test "safeRuneLen handles invalid UTF-8":
    # Valid UTF-8
    check safeRuneLen("Hello") == 5
    check safeRuneLen("こんにちは") == 5
    
    # Invalid UTF-8 should not crash
    let invalidUtf8 = "Hello\xFF\xFEWorld"
    let length = safeRuneLen(invalidUtf8)
    check length > 0  # Should return some length

  test "measurement statistics are tracked":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    
    # Reset stats
    resetMeasurementStats()
    let initialStats = getMeasurementStats()
    check initialStats.totalMeasurements == 0
    
    # Perform some measurements
    discard tm.measureTextSafe("Hello")
    discard tm.measureTextToPosition("World", 3)
    discard tm.findPositionFromWidth("Test", 50.0)
    
    let finalStats = getMeasurementStats()
    check finalStats.totalMeasurements > initialStats.totalMeasurements

  test "withMeasurementFallback works correctly":
    let result = withMeasurementFallback(
      proc(): int = 
        raise newException(ValueError, "Test error"),
      42,  # fallback value
      "test text",
      "test_operation"
    )
    check result == 42

  test "error logging doesn't crash":
    # These should not crash the program
    logMeasurementFailure(mfrNullFont, "test", "test_op", "test details")
    logMeasurementFallback("test", "test_op", "test reason")
    
    # Statistics logging should work
    if shouldLogMeasurementStats():
      logMeasurementStats()

  test "failure rates are calculated correctly":
    resetMeasurementStats()
    
    # Simulate some measurements and failures
    globalMeasurementStats.totalMeasurements = 100
    globalMeasurementStats.failedMeasurements = 5
    globalMeasurementStats.fallbacksUsed = 10
    
    check getMeasurementFailureRate() == 5.0
    check getFallbackUsageRate() == 10.0

  test "Unicode text measurement doesn't crash":
    let tm = newTextMeasurement(addr mockFont, 14.0, 1.0, 8.0)
    
    # Various Unicode texts
    let unicodeTexts = @[
      "Hello 世界",
      "🚀 Rocket",
      "Café naïve résumé",
      "Здравствуй мир",
      "مرحبا بالعالم",
      "🎉🎊🎈"
    ]
    
    for text in unicodeTexts:
      # These should not crash
      let size = tm.measureTextSafe(text)
      check size.x >= 0.0
      check size.y > 0.0
      
      let pos = tm.findPositionFromWidth(text, size.x / 2.0)
      check pos >= 0
      
      if text.len > 0:
        let bounds = tm.getCharacterBounds(text, 0)
        check bounds.x >= 0.0

when isMainModule:
  # Run the tests
  echo "Running text measurement error handling tests..."
  # Cleanup
  rl.closeWindow()