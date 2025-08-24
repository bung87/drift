## ANSI Escape Sequence Parser
## Parses ANSI escape sequences and converts them to styled text segments

import std/[strutils, strformat]
import raylib as rl
import ../../shared/types
import ../../terminal/core/terminal_errors

type
  ParserState* = enum
    psNormal,        # Normal text parsing
    psEscape,        # After ESC character
    psCSI,           # After ESC[ (Control Sequence Introducer)
    psParameter      # Parsing parameters

  AnsiParser* = ref object
    state*: ParserState
    currentFgColor*: rl.Color
    currentBgColor*: rl.Color
    bold*: bool
    italic*: bool
    underline*: bool
    parameters*: seq[int]
    paramBuffer*: string

  StyledText* = object
    text*: string
    style*: TerminalTextStyle

# ANSI color constants
const
  AnsiBlack* = rl.Color(r: 0, g: 0, b: 0, a: 255)
  AnsiRed* = rl.Color(r: 197, g: 15, b: 31, a: 255)
  AnsiGreen* = rl.Color(r: 19, g: 161, b: 14, a: 255)
  AnsiYellow* = rl.Color(r: 193, g: 156, b: 0, a: 255)
  AnsiBlue* = rl.Color(r: 0, g: 55, b: 218, a: 255)
  AnsiMagenta* = rl.Color(r: 136, g: 23, b: 152, a: 255)
  AnsiCyan* = rl.Color(r: 58, g: 150, b: 221, a: 255)
  AnsiWhite* = rl.Color(r: 204, g: 204, b: 204, a: 255)
  AnsiBrightBlack* = rl.Color(r: 118, g: 118, b: 118, a: 255)
  AnsiBrightRed* = rl.Color(r: 231, g: 72, b: 86, a: 255)
  AnsiBrightGreen* = rl.Color(r: 22, g: 198, b: 12, a: 255)
  AnsiBrightYellow* = rl.Color(r: 249, g: 241, b: 165, a: 255)
  AnsiBrightBlue* = rl.Color(r: 59, g: 120, b: 255, a: 255)
  AnsiBrightMagenta* = rl.Color(r: 180, g: 0, b: 158, a: 255)
  AnsiBrightCyan* = rl.Color(r: 97, g: 214, b: 214, a: 255)
  AnsiBrightWhite* = rl.Color(r: 242, g: 242, b: 242, a: 255)

# Color lookup table for standard 8/16 colors
const StandardColors = [
  AnsiBlack, AnsiRed, AnsiGreen, AnsiYellow,
  AnsiBlue, AnsiMagenta, AnsiCyan, AnsiWhite
]

const BrightColors = [
  AnsiBrightBlack, AnsiBrightRed, AnsiBrightGreen, AnsiBrightYellow,
  AnsiBrightBlue, AnsiBrightMagenta, AnsiBrightCyan, AnsiBrightWhite
]

proc newAnsiParser*(): AnsiParser =
  ## Create a new ANSI parser with default state
  AnsiParser(
    state: psNormal,
    currentFgColor: AnsiWhite,
    currentBgColor: AnsiBlack,
    bold: false,
    italic: false,
    underline: false,
    parameters: @[],
    paramBuffer: ""
  )

proc reset*(parser: AnsiParser) =
  ## Reset parser to default state
  parser.state = psNormal
  parser.currentFgColor = AnsiWhite
  parser.currentBgColor = AnsiBlack
  parser.bold = false
  parser.italic = false
  parser.underline = false
  parser.parameters.setLen(0)
  parser.paramBuffer = ""

proc parseParameters(parser: AnsiParser, paramStr: string) =
  ## Parse semicolon-separated parameters
  parser.parameters.setLen(0)
  if paramStr.len == 0:
    parser.parameters.add(0)
    return
    
  for param in paramStr.split(';'):
    if param.len > 0:
      try:
        parser.parameters.add(parseInt(param))
      except ValueError as e:
        let error = newTerminalError(tecAnsiParse, "Invalid ANSI parameter: " & param & " - " & e.msg, "ansi_parser.parseParameters")
        logTerminalError(error)
        parser.parameters.add(0)  # Use default value
    else:
      parser.parameters.add(0)

proc get256Color*(colorIndex: int): rl.Color =
  ## Convert 256-color index to RGB color
  if colorIndex < 16:
    # Standard 16 colors
    if colorIndex < 8:
      return StandardColors[colorIndex]
    else:
      return BrightColors[colorIndex - 8]
  elif colorIndex < 232:
    # 216 color cube (6x6x6)
    let index = colorIndex - 16
    let r = (index div 36) * 51
    let g = ((index mod 36) div 6) * 51
    let b = (index mod 6) * 51
    return rl.Color(r: uint8(r), g: uint8(g), b: uint8(b), a: 255)
  else:
    # Grayscale colors
    let gray = uint8(8 + (colorIndex - 232) * 10)
    return rl.Color(r: gray, g: gray, b: gray, a: 255)

proc processCSISequence(parser: AnsiParser, finalChar: char) =
  ## Process a complete CSI sequence
  case finalChar:
  of 'm':  # SGR (Select Graphic Rendition)
    if parser.parameters.len == 0:
      parser.parameters.add(0)
    
    var i = 0
    while i < parser.parameters.len:
      let param = parser.parameters[i]
      case param:
      of 0:  # Reset all
        parser.reset()
      of 1:  # Bold
        parser.bold = true
      of 3:  # Italic
        parser.italic = true
      of 4:  # Underline
        parser.underline = true
      of 22: # Normal intensity (not bold)
        parser.bold = false
      of 23: # Not italic
        parser.italic = false
      of 24: # Not underlined
        parser.underline = false
      of 30..37:  # Foreground colors
        parser.currentFgColor = StandardColors[param - 30]
      of 38:  # Extended foreground color
        if i + 1 < parser.parameters.len:
          inc i
          case parser.parameters[i]:
          of 5:  # 256-color mode
            if i + 1 < parser.parameters.len:
              inc i
              parser.currentFgColor = get256Color(parser.parameters[i])
          of 2:  # RGB mode
            if i + 3 < parser.parameters.len:
              let r = parser.parameters[i + 1]
              let g = parser.parameters[i + 2]
              let b = parser.parameters[i + 3]
              parser.currentFgColor = rl.Color(r: uint8(r), g: uint8(g), b: uint8(b), a: 255)
              i += 3
          else:
            discard  # Unknown extended color mode
      of 39:  # Default foreground color
        parser.currentFgColor = AnsiWhite
      of 40..47:  # Background colors
        parser.currentBgColor = StandardColors[param - 40]
      of 48:  # Extended background color
        if i + 1 < parser.parameters.len:
          inc i
          case parser.parameters[i]:
          of 5:  # 256-color mode
            if i + 1 < parser.parameters.len:
              inc i
              parser.currentBgColor = get256Color(parser.parameters[i])
          of 2:  # RGB mode
            if i + 3 < parser.parameters.len:
              let r = parser.parameters[i + 1]
              let g = parser.parameters[i + 2]
              let b = parser.parameters[i + 3]
              parser.currentBgColor = rl.Color(r: uint8(r), g: uint8(g), b: uint8(b), a: 255)
              i += 3
          else:
            discard  # Unknown extended color mode
      of 49:  # Default background color
        parser.currentBgColor = AnsiBlack
      of 90..97:  # Bright foreground colors
        parser.currentFgColor = BrightColors[param - 90]
      of 100..107:  # Bright background colors
        parser.currentBgColor = BrightColors[param - 100]
      else:
        discard  # Ignore unknown parameters
      inc i
  else:
    discard  # Ignore other CSI sequences for now

proc getCurrentStyle(parser: AnsiParser, startPos: int, endPos: int): TerminalTextStyle =
  ## Get current text style based on parser state
  TerminalTextStyle(
    startPos: startPos,
    endPos: endPos,
    color: parser.currentFgColor,
    backgroundColor: parser.currentBgColor,
    bold: parser.bold,
    italic: parser.italic,
    underline: parser.underline
  )

proc parseText*(parser: AnsiParser, text: string): seq[StyledText] =
  ## Parse text with ANSI escape sequences and return styled text segments
  result = @[]
  var currentText = ""
  var textStartPos = 0
  
  var i = 0
  while i < text.len:
    let ch = text[i]
    
    case parser.state:
    of psNormal:
      if ch == '\x1b':  # ESC character
        # Save current text segment if any
        if currentText.len > 0:
          let style = parser.getCurrentStyle(textStartPos, textStartPos + currentText.len)
          result.add(StyledText(text: currentText, style: style))
          currentText = ""
        parser.state = psEscape
      else:
        if currentText.len == 0:
          textStartPos = i
        currentText.add(ch)
    
    of psEscape:
      if ch == '[':
        parser.state = psCSI
        parser.paramBuffer = ""
      else:
        # Not a CSI sequence, treat as normal text
        parser.state = psNormal
        if currentText.len == 0:
          textStartPos = i - 1
        currentText.add('\x1b')
        currentText.add(ch)
    
    of psCSI:
      if ch.isDigit() or ch == ';':
        parser.paramBuffer.add(ch)
      elif ch in 'A'..'Z' or ch in 'a'..'z':
        # Final character of CSI sequence
        parser.parseParameters(parser.paramBuffer)
        parser.processCSISequence(ch)
        parser.state = psNormal
        parser.paramBuffer = ""
      else:
        # Invalid CSI sequence, treat as normal text
        parser.state = psNormal
        if currentText.len == 0:
          textStartPos = i - 2
        currentText.add('\x1b')
        currentText.add('[')
        currentText.add(parser.paramBuffer)
        currentText.add(ch)
        parser.paramBuffer = ""
    
    of psParameter:
      # Currently unused state
      discard
    
    inc i
  
  # Handle incomplete escape sequences at end of input
  if parser.state != psNormal:
    # Add incomplete escape sequence as regular text
    if currentText.len == 0:
      textStartPos = i - 1
    case parser.state:
    of psEscape:
      currentText.add('\x1b')
    of psCSI:
      currentText.add('\x1b')
      currentText.add('[')
      currentText.add(parser.paramBuffer)
    of psParameter:
      currentText.add('\x1b')
      currentText.add('[')
      currentText.add(parser.paramBuffer)
    else:
      discard
    
    # Reset parser state
    parser.state = psNormal
    parser.paramBuffer = ""
  
  # Add final text segment if any
  if currentText.len > 0:
    let style = parser.getCurrentStyle(textStartPos, textStartPos + currentText.len)
    result.add(StyledText(text: currentText, style: style))

proc parseToTerminalLine*(parser: AnsiParser, text: string): TerminalLine =
  ## Parse text and return a TerminalLine with proper styling
  let styledSegments = parser.parseText(text)
  var fullText = ""
  var styles: seq[TerminalTextStyle] = @[]
  
  for segment in styledSegments:
    let startPos = fullText.len
    fullText.add(segment.text)
    let endPos = fullText.len
    
    if segment.text.len > 0:
      var style = segment.style
      style.startPos = startPos
      style.endPos = endPos
      styles.add(style)
  
  return newTerminalLine(fullText, styles)

# Utility functions for testing and debugging
proc colorToString*(color: rl.Color): string =
  ## Convert color to string representation for debugging
  result = &"Color(r: {color.r}, g: {color.g}, b: {color.b}, a: {color.a})"

proc styleToString*(style: TerminalTextStyle): string =
  ## Convert style to string representation for debugging
  var flags: seq[string] = @[]
  if style.bold: flags.add("bold")
  if style.italic: flags.add("italic")
  if style.underline: flags.add("underline")
  
  let flagStr = if flags.len > 0: flags.join(",") else: "none"
  result = &"Style[{style.startPos}..{style.endPos}]: fg={style.color.colorToString()}, bg={style.backgroundColor.colorToString()}, flags={flagStr}"