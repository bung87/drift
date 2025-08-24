## Unit tests for ANSI escape sequence parser

import std/[unittest, strutils, strformat]
import raylib as rl
import ../../src/infrastructure/terminal/ansi_parser
import ../../src/shared/types

suite "ANSI Parser Tests":
  
  setup:
    let parser = newAnsiParser()
  
  teardown:
    parser.reset()

  test "Parse plain text without ANSI codes":
    let input = "Hello, World!"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Hello, World!"
    check result[0].style.color == AnsiWhite
    check result[0].style.backgroundColor == AnsiBlack
    check result[0].style.bold == false
    check result[0].style.italic == false
    check result[0].style.underline == false

  test "Parse basic foreground colors":
    let testCases = [
      ("\x1b[30mBlack", AnsiBlack),
      ("\x1b[31mRed", AnsiRed),
      ("\x1b[32mGreen", AnsiGreen),
      ("\x1b[33mYellow", AnsiYellow),
      ("\x1b[34mBlue", AnsiBlue),
      ("\x1b[35mMagenta", AnsiMagenta),
      ("\x1b[36mCyan", AnsiCyan),
      ("\x1b[37mWhite", AnsiWhite)
    ]
    
    for (input, expectedColor) in testCases:
      parser.reset()
      let result = parser.parseText(input)
      check result.len == 1
      check result[0].style.color == expectedColor

  test "Parse bright foreground colors":
    let testCases = [
      ("\x1b[90mBrightBlack", AnsiBrightBlack),
      ("\x1b[91mBrightRed", AnsiBrightRed),
      ("\x1b[92mBrightGreen", AnsiBrightGreen),
      ("\x1b[93mBrightYellow", AnsiBrightYellow),
      ("\x1b[94mBrightBlue", AnsiBrightBlue),
      ("\x1b[95mBrightMagenta", AnsiBrightMagenta),
      ("\x1b[96mBrightCyan", AnsiBrightCyan),
      ("\x1b[97mBrightWhite", AnsiBrightWhite)
    ]
    
    for (input, expectedColor) in testCases:
      parser.reset()
      let result = parser.parseText(input)
      check result.len == 1
      check result[0].style.color == expectedColor

  test "Parse background colors":
    let input = "\x1b[41mRed Background"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Red Background"
    check result[0].style.backgroundColor == AnsiRed

  test "Parse text formatting":
    # Bold text
    parser.reset()
    var result = parser.parseText("\x1b[1mBold Text")
    check result.len == 1
    check result[0].style.bold == true
    
    # Italic text
    parser.reset()
    result = parser.parseText("\x1b[3mItalic Text")
    check result.len == 1
    check result[0].style.italic == true
    
    # Underline text
    parser.reset()
    result = parser.parseText("\x1b[4mUnderline Text")
    check result.len == 1
    check result[0].style.underline == true

  test "Parse reset sequences":
    # Test that reset clears all formatting
    let input = "\x1b[1;31;42mFormatted\x1b[0mReset"
    let result = parser.parseText(input)
    
    check result.len == 2
    check result[0].text == "Formatted"
    check result[0].style.bold == true
    check result[0].style.color == AnsiRed
    check result[0].style.backgroundColor == AnsiGreen
    
    check result[1].text == "Reset"
    check result[1].style.bold == false
    check result[1].style.color == AnsiWhite
    check result[1].style.backgroundColor == AnsiBlack

  test "Parse combined formatting":
    let input = "\x1b[1;3;4;31mBold Italic Underline Red"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].style.bold == true
    check result[0].style.italic == true
    check result[0].style.underline == true
    check result[0].style.color == AnsiRed

  test "Parse 256-color mode":
    # Test 256-color foreground
    let input = "\x1b[38;5;196mBright Red 256"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Bright Red 256"
    # Color 196 should be a bright red
    check result[0].style.color.r > 200

  test "Parse RGB color mode":
    # Test RGB foreground color
    let input = "\x1b[38;2;255;128;0mOrange RGB"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Orange RGB"
    check result[0].style.color.r == 255
    check result[0].style.color.g == 128
    check result[0].style.color.b == 0

  test "Parse multiple color changes in one line":
    let input = "\x1b[31mRed\x1b[32mGreen\x1b[34mBlue"
    let result = parser.parseText(input)
    
    check result.len == 3
    check result[0].text == "Red"
    check result[0].style.color == AnsiRed
    check result[1].text == "Green"
    check result[1].style.color == AnsiGreen
    check result[2].text == "Blue"
    check result[2].style.color == AnsiBlue

  test "Handle malformed escape sequences":
    # Test that malformed sequences are treated as regular text
    let input = "\x1b[999mInvalid\x1bIncomplete"
    let result = parser.parseText(input)
    
    # Should still parse something reasonable
    check result.len >= 1

  test "Parse mixed text and escape sequences":
    let input = "Normal \x1b[31mRed Text\x1b[0m More Normal"
    let result = parser.parseText(input)
    
    check result.len == 3
    check result[0].text == "Normal "
    check result[0].style.color == AnsiWhite
    check result[1].text == "Red Text"
    check result[1].style.color == AnsiRed
    check result[2].text == " More Normal"
    check result[2].style.color == AnsiWhite

  test "Parse empty escape sequence":
    let input = "\x1b[mDefault"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Default"

  test "Parse sequence with multiple parameters":
    let input = "\x1b[1;31;42mComplex"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Complex"
    check result[0].style.bold == true
    check result[0].style.color == AnsiRed
    check result[0].style.backgroundColor == AnsiGreen

  test "Parse terminal line with ANSI codes":
    let input = "\x1b[1;32mSuccess:\x1b[0m Operation completed"
    let terminalLine = parser.parseToTerminalLine(input)
    
    check terminalLine.text == "Success: Operation completed"
    check terminalLine.styles.len == 2
    check terminalLine.styles[0].startPos == 0
    check terminalLine.styles[0].endPos == 8  # "Success:"
    check terminalLine.styles[0].bold == true
    check terminalLine.styles[0].color == AnsiGreen

  test "Parse cursor movement sequences (should be ignored)":
    let input = "\x1b[2J\x1b[H\x1b[1;1HText"
    let result = parser.parseText(input)
    
    check result.len == 1
    check result[0].text == "Text"

  test "Test parser state persistence":
    # First parse should set state
    var result = parser.parseText("\x1b[1;31m")
    check parser.bold == true
    check parser.currentFgColor == AnsiRed
    
    # Second parse should use existing state
    result = parser.parseText("Bold Red Text")
    check result.len == 1
    check result[0].style.bold == true
    check result[0].style.color == AnsiRed

  test "Test parser reset functionality":
    # Set some state
    discard parser.parseText("\x1b[1;3;4;31;42m")
    check parser.bold == true
    check parser.italic == true
    check parser.underline == true
    
    # Reset parser
    parser.reset()
    check parser.bold == false
    check parser.italic == false
    check parser.underline == false
    check parser.currentFgColor == AnsiWhite
    check parser.currentBgColor == AnsiBlack

  test "Parse complex real-world example":
    let input = "\x1b[32muser@host\x1b[0m:\x1b[34m~/projects\x1b[0m$ \x1b[1mls -la\x1b[0m"
    let result = parser.parseText(input)
    
    # Should have multiple styled segments
    check result.len >= 4
    
    # Check that we have green, blue, and bold segments
    var hasGreen = false
    var hasBlue = false
    var hasBold = false
    
    for segment in result:
      if segment.style.color == AnsiGreen:
        hasGreen = true
      if segment.style.color == AnsiBlue:
        hasBlue = true
      if segment.style.bold:
        hasBold = true
    
    check hasGreen
    check hasBlue
    check hasBold

  test "Parse long text with many color changes":
    var input = ""
    for i in 0..<100:
      let colorCode = 30 + (i mod 8)  # Cycle through basic colors
      input.add(&"\x1b[{colorCode}mText{i} ")
    
    let result = parser.parseText(input)
    check result.len == 100  # Should have one segment per color change

  test "Test color conversion functions":
    # Test standard color lookup
    let red = get256Color(1)
    check red == AnsiRed
    
    let brightRed = get256Color(9)
    check brightRed == AnsiBrightRed
    
    # Test 216-color cube
    let colorCube = get256Color(16)  # First color in 6x6x6 cube
    check colorCube.r == 0
    check colorCube.g == 0
    check colorCube.b == 0
    
    # Test grayscale
    let gray = get256Color(232)  # First grayscale color
    check gray.r == gray.g
    check gray.g == gray.b

  test "Handle edge cases":
    # Empty string
    var result = parser.parseText("")
    check result.len == 0
    
    # Only escape sequences, no text
    result = parser.parseText("\x1b[31m\x1b[0m")
    check result.len == 0
    
    # Escape at end of string
    result = parser.parseText("Text\x1b")
    check result.len == 2
    check result[0].text == "Text"
    check result[1].text == "\x1b"

  test "Performance with large input":
    # Test with a large input string
    var largeInput = ""
    for i in 0..<1000:
      largeInput.add("Some text ")
    largeInput.add("\x1b[31mRed\x1b[0m")
    
    let result = parser.parseText(largeInput)
    check result.len <= 3  # Should be efficiently parsed