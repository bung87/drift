## Test cursor position validation functionality

import unittest
import ../src/shared/text_measurement
import ../src/shared/types
import ../src/domain/document

suite "Cursor Position Validation":
  
  test "validateCursorPosition with empty document":
    let doc = newDocument("")
    let cursor = CursorPos(line: 5, col: 10)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 0
    check validated.col == 0
  
  test "validateCursorPosition with nil document":
    let cursor = CursorPos(line: 5, col: 10)
    let validated = validateCursorPosition(cursor, nil)
    
    check validated.line == 0
    check validated.col == 0
  
  test "validateCursorPosition with valid position":
    let doc = newDocument("Hello\nWorld\nTest")
    let cursor = CursorPos(line: 1, col: 3)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 1
    check validated.col == 3
  
  test "validateCursorPosition with negative line":
    let doc = newDocument("Hello\nWorld")
    let cursor = CursorPos(line: -5, col: 2)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 0
    check validated.col == 2
  
  test "validateCursorPosition with negative column":
    let doc = newDocument("Hello\nWorld")
    let cursor = CursorPos(line: 1, col: -3)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 1
    check validated.col == 0
  
  test "validateCursorPosition with line beyond document":
    let doc = newDocument("Hello\nWorld")
    let cursor = CursorPos(line: 10, col: 2)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 1  # Last line (0-based)
    check validated.col == 2
  
  test "validateCursorPosition with column beyond line end":
    let doc = newDocument("Hello\nWorld")
    let cursor = CursorPos(line: 0, col: 20)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 0
    check validated.col == 5  # Length of "Hello"
  
  test "validateCursorPosition with empty line":
    let doc = newDocument("Hello\n\nWorld")
    let cursor = CursorPos(line: 1, col: 5)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 1
    check validated.col == 0  # Empty line can only have cursor at col 0
  
  test "validateCursorPosition with whitespace-only line":
    let doc = newDocument("Hello\n   \nWorld")
    let cursor = CursorPos(line: 1, col: 5)
    let validated = validateCursorPosition(cursor, doc)
    
    check validated.line == 1
    check validated.col == 3  # Length of "   "
  
  test "isValidCursorPosition with valid positions":
    let doc = newDocument("Hello\nWorld\nTest")
    
    check isValidCursorPosition(CursorPos(line: 0, col: 0), doc) == true
    check isValidCursorPosition(CursorPos(line: 0, col: 5), doc) == true  # End of line
    check isValidCursorPosition(CursorPos(line: 1, col: 3), doc) == true
    check isValidCursorPosition(CursorPos(line: 2, col: 4), doc) == true  # End of last line
  
  test "isValidCursorPosition with invalid positions":
    let doc = newDocument("Hello\nWorld")
    
    check isValidCursorPosition(CursorPos(line: -1, col: 0), doc) == false
    check isValidCursorPosition(CursorPos(line: 0, col: -1), doc) == false
    check isValidCursorPosition(CursorPos(line: 5, col: 0), doc) == false
    check isValidCursorPosition(CursorPos(line: 0, col: 10), doc) == false
  
  test "isValidCursorPosition with empty document":
    let doc = newDocument("")
    
    check isValidCursorPosition(CursorPos(line: 0, col: 0), doc) == true
    check isValidCursorPosition(CursorPos(line: 0, col: 1), doc) == false
    check isValidCursorPosition(CursorPos(line: 1, col: 0), doc) == false
  
  test "clampCursorToDocument functionality":
    let doc = newDocument("Hello\nWorld")
    
    let clamped1 = clampCursorToDocument(CursorPos(line: -5, col: -3), doc)
    check clamped1.line == 0
    check clamped1.col == 0
    
    let clamped2 = clampCursorToDocument(CursorPos(line: 10, col: 20), doc)
    check clamped2.line == 1
    check clamped2.col == 5  # Length of "World"
  
  test "ensureCursorInBounds modifies cursor in place":
    let doc = newDocument("Hello\nWorld")
    var cursor = CursorPos(line: 10, col: 20)
    
    ensureCursorInBounds(cursor, doc)
    
    check cursor.line == 1
    check cursor.col == 5