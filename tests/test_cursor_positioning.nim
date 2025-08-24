## Test cursor positioning accuracy with the new text measurement system

import std/[unittest, strutils, unicode]
import raylib as rl
import ../src/shared/text_measurement
import ../src/shared/types

# Initialize raylib for testing
proc initTestEnvironment() =
  rl.initWindow(1, 1, "Test")
  rl.setTargetFPS(60)

proc cleanupTestEnvironment() =
  rl.closeWindow()

suite "Cursor Positioning Tests":
  setup:
    initTestEnvironment()
    
  teardown:
    cleanupTestEnvironment()

  test "cursor positioning with ASCII text":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
    let text = "Hello World"
    
    # Test positioning at different character positions
    let pos0 = tm.measureTextToPosition(text, 0)
    let pos5 = tm.measureTextToPosition(text, 5)
    let pos11 = tm.measureTextToPosition(text, 11)
    
    check pos0 == 0.0
    check pos5 > 0.0
    check pos11 > pos5
    check pos11 == tm.measureTextSafe(text).x

  test "cursor positioning with Unicode text":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
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

  test "cursor positioning at character boundaries":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
    let text = "ABCD"
    
    # Test that cursor positions are at exact character boundaries
    for i in 0..text.runeLen():
      let pos = tm.measureTextToPosition(text, i)
      check pos >= 0.0
      
      # Verify that position increases monotonically
      if i > 0:
        let prevPos = tm.measureTextToPosition(text, i - 1)
        check pos >= prevPos

  test "cursor positioning with empty text":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
    let text = ""
    
    let pos = tm.measureTextToPosition(text, 0)
    check pos == 0.0

  test "cursor positioning beyond text length":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
    let text = "Test"
    
    let normalPos = tm.measureTextToPosition(text, text.runeLen())
    let beyondPos = tm.measureTextToPosition(text, text.runeLen() + 5)
    
    # Position beyond text length should equal text width
    check normalPos == beyondPos
    check beyondPos == tm.measureTextSafe(text).x

  test "cursor positioning consistency":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
    let text = "Consistent Test"
    
    # Measure full text width
    let fullWidth = tm.measureTextSafe(text).x
    let posAtEnd = tm.measureTextToPosition(text, text.runeLen())
    
    # These should be equal
    check abs(fullWidth - posAtEnd) < 0.1  # Allow small floating point differences

  test "cursor positioning with tabs and spaces":
    let font = rl.getFontDefault()
    let tm = newTextMeasurement(font.addr, 14.0, 1.0, 8.0)
    let text = "A\tB C"  # Tab and space characters
    
    let pos0 = tm.measureTextToPosition(text, 0)  # Before 'A'
    let pos1 = tm.measureTextToPosition(text, 1)  # Before tab
    let pos2 = tm.measureTextToPosition(text, 2)  # Before 'B'
    let pos3 = tm.measureTextToPosition(text, 3)  # Before space
    let pos4 = tm.measureTextToPosition(text, 4)  # Before 'C'
    
    check pos0 == 0.0
    check pos1 > pos0
    check pos2 > pos1
    check pos3 > pos2
    check pos4 > pos3