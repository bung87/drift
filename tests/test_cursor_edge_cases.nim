## Test cursor position validation with edge cases from requirements

import unittest
import std/unicode
import ../src/shared/text_measurement
import ../src/shared/types
import ../src/domain/document

suite "Cursor Position Validation Edge Cases":
  
  test "empty document edge case":
    # Requirement 5.3: When the document is empty THEN the cursor SHALL be positioned at line 0, column 0
    let doc = newDocument("")
    
    # Test various invalid positions with empty document
    check validateCursorPosition(CursorPos(line: -1, col: -1), doc) == CursorPos(line: 0, col: 0)
    check validateCursorPosition(CursorPos(line: 10, col: 5), doc) == CursorPos(line: 0, col: 0)
    check validateCursorPosition(CursorPos(line: 0, col: 10), doc) == CursorPos(line: 0, col: 0)
    check validateCursorPosition(CursorPos(line: 0, col: 0), doc) == CursorPos(line: 0, col: 0)
  
  test "clicking beyond document bounds":
    # Requirement 5.2: When clicking beyond the document bounds THEN the cursor SHALL be positioned at the nearest valid location
    let doc = newDocument("Line 1\nLine 2\nLine 3")
    
    # Beyond last line
    let beyondDoc = validateCursorPosition(CursorPos(line: 10, col: 5), doc)
    check beyondDoc.line == 2  # Last line (0-based)
    check beyondDoc.col == 5   # Should be clamped to line length
    
    # Beyond line length
    let beyondLine = validateCursorPosition(CursorPos(line: 0, col: 20), doc)
    check beyondLine.line == 0
    check beyondLine.col == 6  # Length of "Line 1"
  
  test "empty lines handling":
    # Requirement 5.1: When clicking on an empty line THEN the cursor SHALL be positioned at column 0 of that line
    let doc = newDocument("First\n\nThird")
    
    # Position on empty line (line 1)
    let emptyLinePos = validateCursorPosition(CursorPos(line: 1, col: 5), doc)
    check emptyLinePos.line == 1
    check emptyLinePos.col == 0  # Empty line can only have cursor at col 0
    
    # Valid position on empty line
    let validEmptyPos = validateCursorPosition(CursorPos(line: 1, col: 0), doc)
    check validEmptyPos.line == 1
    check validEmptyPos.col == 0
  
  test "whitespace-only lines":
    # Requirement 5.4: When text contains only whitespace characters THEN cursor positioning SHALL work correctly
    let doc = newDocument("Normal\n   \nAnother")
    
    # Position within whitespace line
    let whitespacePos = validateCursorPosition(CursorPos(line: 1, col: 2), doc)
    check whitespacePos.line == 1
    check whitespacePos.col == 2  # Should be valid within whitespace
    
    # Position beyond whitespace line
    let beyondWhitespace = validateCursorPosition(CursorPos(line: 1, col: 10), doc)
    check beyondWhitespace.line == 1
    check beyondWhitespace.col == 3  # Length of "   "
    
    # Position at end of whitespace line
    let endWhitespace = validateCursorPosition(CursorPos(line: 1, col: 3), doc)
    check endWhitespace.line == 1
    check endWhitespace.col == 3
  
  test "negative positions handling":
    let doc = newDocument("Hello\nWorld\nTest")
    
    # Negative line
    let negLine = validateCursorPosition(CursorPos(line: -5, col: 2), doc)
    check negLine.line == 0
    check negLine.col == 2
    
    # Negative column
    let negCol = validateCursorPosition(CursorPos(line: 1, col: -3), doc)
    check negCol.line == 1
    check negCol.col == 0
    
    # Both negative
    let bothNeg = validateCursorPosition(CursorPos(line: -2, col: -1), doc)
    check bothNeg.line == 0
    check bothNeg.col == 0
  
  test "cursor at line end positions":
    let doc = newDocument("Short\nLonger line\nEnd")
    
    # Cursor at exact end of line (should be valid)
    let lineEnd = validateCursorPosition(CursorPos(line: 1, col: 11), doc)  # "Longer line".len = 11
    check lineEnd.line == 1
    check lineEnd.col == 11
    
    # Cursor beyond line end
    let beyondEnd = validateCursorPosition(CursorPos(line: 0, col: 10), doc)  # "Short".len = 5
    check beyondEnd.line == 0
    check beyondEnd.col == 5
  
  test "unicode text handling":
    # Test with Unicode characters to ensure rune-based positioning works
    let doc = newDocument("Hello 🌍\nUnicode 测试\nEmoji 🎉🎊")
    
    # Position within unicode text
    let unicodePos = validateCursorPosition(CursorPos(line: 1, col: 8), doc)
    check unicodePos.line == 1
    check unicodePos.col <= "Unicode 测试".toRunes().len  # Should be within rune length
    
    # Position beyond unicode line
    let beyondUnicode = validateCursorPosition(CursorPos(line: 2, col: 20), doc)
    check beyondUnicode.line == 2
    check beyondUnicode.col == "Emoji 🎉🎊".toRunes().len
  
  test "isValidCursorPosition comprehensive":
    let doc = newDocument("Line1\n\nLine3")
    
    # Valid positions
    check isValidCursorPosition(CursorPos(line: 0, col: 0), doc) == true
    check isValidCursorPosition(CursorPos(line: 0, col: 5), doc) == true  # End of line
    check isValidCursorPosition(CursorPos(line: 1, col: 0), doc) == true  # Empty line
    check isValidCursorPosition(CursorPos(line: 2, col: 5), doc) == true  # End of last line
    
    # Invalid positions
    check isValidCursorPosition(CursorPos(line: -1, col: 0), doc) == false
    check isValidCursorPosition(CursorPos(line: 0, col: -1), doc) == false
    check isValidCursorPosition(CursorPos(line: 3, col: 0), doc) == false  # Beyond document
    check isValidCursorPosition(CursorPos(line: 0, col: 6), doc) == false  # Beyond line
    check isValidCursorPosition(CursorPos(line: 1, col: 1), doc) == false  # Beyond empty line
  
  test "clampCursorToDocument edge cases":
    let doc = newDocument("A\n\nC")
    
    # Extreme negative values
    let extremeNeg = clampCursorToDocument(CursorPos(line: -1000, col: -1000), doc)
    check extremeNeg.line == 0
    check extremeNeg.col == 0
    
    # Extreme positive values
    let extremePos = clampCursorToDocument(CursorPos(line: 1000, col: 1000), doc)
    check extremePos.line == 2  # Last line
    check extremePos.col == 1   # Length of "C"
    
    # Mixed extreme values
    let mixed = clampCursorToDocument(CursorPos(line: -5, col: 1000), doc)
    check mixed.line == 0
    check mixed.col == 1  # Length of "A"