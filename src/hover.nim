## Hover and LSP functionality module
import raylib as rl
import std/[strutils, algorithm, options, tables]
import shared/types

import enhanced_syntax, shared/utils
# import infrastructure/rendering/theme  # Unused import
import shared/constants

# Cache for parsed hover content to avoid repetitive parsing
var hoverContentCache: Table[string, tuple[signature: string, description: string, codeBlocks: seq[string]]] = initTable[string, tuple[signature: string, description: string, codeBlocks: seq[string]]]()

# Cache for hover rendering to prevent excessive rendering
# var lastRenderedHover: tuple[content: string, mousePos: rl.Vector2, windowWidth: int32, windowHeight: int32] = ("", rl.Vector2(), 0, 0)

# Hover content parsing with caching
proc parseHoverContent*(
    content: string
): tuple[signature: string, description: string, codeBlocks: seq[string]] =
  if content.len == 0:
    return ("", "", @[])
  
  # Check cache first
  if content in hoverContentCache:
    return hoverContentCache[content]
    
  let lines = content.splitLines()
  var signature = ""
  var description = ""
  var codeBlocks: seq[string] = @[]
  var inCodeBlock = false
  var currentCodeBlock = ""
  var foundSignature = false

  for lineIndex, line in lines:
    let trimmedLine = strutils.strip(line)
    let isEmptyLine = trimmedLine.len == 0

    # Handle code block delimiters
    if trimmedLine.startsWith("```"):
      if inCodeBlock:
        # End of code block - preserve formatting
        if currentCodeBlock.len > 0:
          var cleanCodeBlock = currentCodeBlock
          while cleanCodeBlock.endsWith("\n"):
            cleanCodeBlock = cleanCodeBlock[0..^2]
          if cleanCodeBlock.len > 0:
            codeBlocks.add(cleanCodeBlock)
          currentCodeBlock = ""
        inCodeBlock = false
      else:
        # Start of code block
        inCodeBlock = true
        currentCodeBlock = ""
    elif inCodeBlock:
      # Inside code block - preserve original line formatting
      if currentCodeBlock.len > 0:
        currentCodeBlock.add("\n")
      currentCodeBlock.add(line)
    else:
      # Outside code block - handle regular content
      if not isEmptyLine:
        if not foundSignature:
          signature = trimmedLine
          foundSignature = true
        else:
          if description.len > 0 and not description.endsWith("\n"):
            description.add("\n")
          description.add(line)
      elif description.len > 0 and foundSignature:
        # Empty line in description - preserve paragraph breaks
        if not description.endsWith("\n\n"):
          description.add("\n")

  # Add any remaining code block
  if currentCodeBlock.len > 0:
    var cleanCodeBlock = currentCodeBlock
    while cleanCodeBlock.endsWith("\n"):
      cleanCodeBlock = cleanCodeBlock[0..^2]
    if cleanCodeBlock.len > 0:
      codeBlocks.add(cleanCodeBlock)

  # Clean up trailing whitespace from description
  if description.len > 0:
    while description.endsWith("\n"):
      description = description[0..^2]

  # Cache the result
  let hoverResult = (signature, description, codeBlocks)
  hoverContentCache[content] = hoverResult

  # Debug output to help diagnose parsing issues
  if signature.len > 0 or description.len > 0 or codeBlocks.len > 0:
    echo "DEBUG parseHoverContent:"
    echo "  Signature: '", signature, "'"
    echo "  Description: '", description.replace("\n", "\\n"), "'"
    echo "  Code blocks: ", codeBlocks.len
    for i, codeBlock in codeBlocks:
      echo "    Block ", i, ": '", codeBlock.replace("\n", "\\n"), "'"

  return hoverResult

# Clear hover content cache
proc clearHoverContentCache*() =
  ## Clear the hover content cache to free memory
  hoverContentCache.clear()

# Smart text wrapping that aggressively prevents horizontal overflow
proc smartWrapText*(
    text: string, maxWidth: float32, fontSize: float32, font: rl.Font
): seq[string] =
  if text.len == 0:
    return @[]

  # Use stricter width limit to ensure no overflow
  let safeMaxWidth = maxWidth * 0.95 # 5% margin for safety

  var wrappedLines: seq[string] = @[]
  let words = text.split(' ')
  var currentLine = ""

  for word in words:
    let testLine =
      if currentLine.len == 0:
        word
      else:
        currentLine & " " & word
    let testWidth = measureTextWidth(testLine, fontSize, font)

    if testWidth <= safeMaxWidth:
      currentLine = testLine
    else:
      # Current word doesn't fit, start new line
      if currentLine.len > 0:
        wrappedLines.add(currentLine)

        # Check if single word is still too long
        let wordWidth = measureTextWidth(word, fontSize, font)
        if wordWidth > safeMaxWidth:
          # Force break long words character by character with proper handling
          var chars = ""
          for c in word:
            let testChars = chars & c
            let charWidth = measureTextWidth(testChars, fontSize, font)
            if charWidth > safeMaxWidth and chars.len > 0:
              wrappedLines.add(chars)
              chars = $c
            else:
              chars = testChars
          currentLine = chars
        else:
          currentLine = word
      else:
        # Single word is too long, force break it intelligently
        var chars = ""
        var lastBreakPoint = ""
        for i, c in word:
          let testChars = chars & c
          let charWidth = measureTextWidth(testChars, fontSize, font)
          if charWidth > safeMaxWidth and chars.len > 0:
            wrappedLines.add(chars)
            chars = $c
            lastBreakPoint = ""
          else:
            chars = testChars
            # Look for natural break points
            if c in {'.', ':', ':', '_', '-'}:
              lastBreakPoint = chars
        currentLine = chars

  if currentLine.len > 0:
    wrappedLines.add(currentLine)

  return wrappedLines

# Syntax highlighted text drawing for hover
proc drawSyntaxHighlightedText*(
    text: string,
    x: float32,
    y: float32,
    fontSize: float32,
    font: rl.Font,
    highlighter: var SyntaxHighlighter,
): float32 =
  if text.len == 0:
    return 0.0

  # Use the provided highlighter to tokenize the text
  let tokens = highlighter.tokenize(text)

  var currentX = x
  var lastProcessedIndex = 0

  # Sort tokens by position to ensure correct rendering order
  var sortedTokens = tokens
  sortedTokens.sort(
    proc(a, b: enhanced_syntax.Token): int =
      cmp(a.start, b.start)
  )

  for token in sortedTokens:
    let tokenStart = token.start
    let tokenEnd = token.start + token.length

    if tokenStart >= lastProcessedIndex and tokenStart < text.len:
      # Draw text before this token
      if tokenStart > lastProcessedIndex:
        let beforeText = text[lastProcessedIndex ..< tokenStart]
        let beforeWidth = measureTextWidth(beforeText, fontSize, font)
        rl.drawText(
          font,
          beforeText,
          rl.Vector2(x: currentX, y: y),
          fontSize,
          1.0,
          rl.Color(r: 230, g: 230, b: 230, a: 255),
        )
        currentX += beforeWidth

      # Draw the token with syntax highlighting
      if tokenEnd <= text.len:
        let tokenText = text[tokenStart ..< tokenEnd]
        let tokenColor = getTokenColor(token.tokenType)
        let tokenWidth = measureTextWidth(tokenText, fontSize, font)
        rl.drawText(
          font, tokenText, rl.Vector2(x: currentX, y: y), fontSize, 1.0, tokenColor
        )
        currentX += tokenWidth

        lastProcessedIndex = tokenEnd

  # Draw any remaining text
  if lastProcessedIndex < text.len:
    let remainingText = text[lastProcessedIndex ..< text.len]
    let remainingWidth = measureTextWidth(remainingText, fontSize, font)
    rl.drawText(
      font,
      remainingText,
      rl.Vector2(x: currentX, y: y),
      fontSize,
      1.0,
      rl.Color(r: 230, g: 230, b: 230, a: 255),
    )
    currentX += remainingWidth

  return currentX - x

# Draw text with inline code backticks highlighted using proper syntax highlighting
proc drawTextWithInlineCode*(
    text: string,
    x: float32,
    y: float32,
    fontSize: float32,
    textColor: rl.Color,
    font: rl.Font,
    highlighter: var SyntaxHighlighter,
    lineHeight: float32 = 0.0,
): float32 =
  if text.len == 0:
    return 0.0

  let codeBgColor = rl.Color(r: 40, g: 40, b: 40, a: 255)
  let padding = 2.0

  var currentX = x
  var i = 0

  while i < text.len:
    if text[i] == '`':
      # Look for closing backtick
      var endBacktick = i + 1
      while endBacktick < text.len and text[endBacktick] != '`':
        endBacktick += 1

      if endBacktick < text.len:
        # Found closing backtick - render as inline code with syntax highlighting
        let codeText = text[(i + 1) ..< endBacktick]

        # Draw code background with padding
        let codeWidth = measureTextWidth(codeText, fontSize, font)
        let bgHeight =
          if lineHeight > 0:
            lineHeight
          else:
            fontSize + 4
        rl.drawRectangle(
          (currentX - padding).int32,
          (y - 2).int32,
          (codeWidth + 2 * padding).int32,
          bgHeight.int32,
          codeBgColor,
        )

        # Use syntax highlighting for the code content
        let syntaxWidth =
          drawSyntaxHighlightedText(codeText, currentX, y, fontSize, font, highlighter)
        currentX += syntaxWidth

        i = endBacktick + 1
      else:
        # No closing backtick - render as normal text
        rl.drawText(
          font, $text[i], rl.Vector2(x: currentX, y: y), fontSize, 1.0, textColor
        )
        currentX += measureTextWidth($text[i], fontSize, font)
        i += 1
    else:
      # Find next backtick or end of text
      var nextBacktick = i
      while nextBacktick < text.len and text[nextBacktick] != '`':
        nextBacktick += 1

      # Draw normal text segment
      let normalText = text[i ..< nextBacktick]
      let normalWidth = measureTextWidth(normalText, fontSize, font)
      rl.drawText(
        font, normalText, rl.Vector2(x: currentX, y: y), fontSize, 1.0, textColor
      )
      currentX += normalWidth

      i = nextBacktick

  return currentX - x

# Draw multi-line text with inline code highlighting and proper line breaks
proc drawMultiLineTextWithInlineCode*(
    text: string,
    x: float32,
    y: float32,
    fontSize: float32,
    textColor: rl.Color,
    font: rl.Font,
    highlighter: var SyntaxHighlighter,
    maxWidth: float32,
    lineHeight: float32,
): float32 =
  if text.len == 0:
    return 0.0

  var currentY = y
  let lines = text.splitLines()
  
  for line in lines:
    if line.len == 0:
      # Empty line - just add line height
      currentY += lineHeight
      continue
    
    # Draw the line with inline code highlighting
    discard drawTextWithInlineCode(
      line, x, currentY, fontSize, textColor, font, highlighter, lineHeight
    )
    currentY += lineHeight

  return currentY - y

# Arrow pointer drawing
proc drawArrowPointer*(
    x: float32, y: float32, size: float32, direction: string, color: rl.Color
) =
  let halfSize = size / 2.0

  case direction
  of "up":
    let points = [
      rl.Vector2(x: x, y: y - halfSize),
      rl.Vector2(x: x - halfSize, y: y + halfSize),
      rl.Vector2(x: x + halfSize, y: y + halfSize),
    ]
    for i in 0 ..< 3:
      let next = (i + 1) mod 3
      rl.drawLine(
        points[i].x.int32,
        points[i].y.int32,
        points[next].x.int32,
        points[next].y.int32,
        color,
      )
  of "down":
    let points = [
      rl.Vector2(x: x, y: y + halfSize),
      rl.Vector2(x: x - halfSize, y: y - halfSize),
      rl.Vector2(x: x + halfSize, y: y - halfSize),
    ]
    for i in 0 ..< 3:
      let next = (i + 1) mod 3
      rl.drawLine(
        points[i].x.int32,
        points[i].y.int32,
        points[next].x.int32,
        points[next].y.int32,
        color,
      )
  of "left":
    let points = [
      rl.Vector2(x: x - halfSize, y: y),
      rl.Vector2(x: x + halfSize, y: y - halfSize),
      rl.Vector2(x: x + halfSize, y: y + halfSize),
    ]
    for i in 0 ..< 3:
      let next = (i + 1) mod 3
      rl.drawLine(
        points[i].x.int32,
        points[i].y.int32,
        points[next].x.int32,
        points[next].y.int32,
        color,
      )
  of "right":
    let points = [
      rl.Vector2(x: x + halfSize, y: y),
      rl.Vector2(x: x - halfSize, y: y - halfSize),
      rl.Vector2(x: x - halfSize, y: y + halfSize),
    ]
    for i in 0 ..< 3:
      let next = (i + 1) mod 3
      rl.drawLine(
        points[i].x.int32,
        points[i].y.int32,
        points[next].x.int32,
        points[next].y.int32,
        color,
      )
  else:
    # Default to up arrow
    drawArrowPointer(x, y, size, "up", color)

# Calculate hover position and dimensions
proc calculateHoverPosition(
    hoverPos: rl.Vector2,
    contentWidth: float32,
    contentHeight: float32,
    windowWidth: int32,
    windowHeight: int32,
    fontSize: float32,
): tuple[x: float32, y: float32, width: float32, height: float32, arrowDirection: string] =
  ## Calculate optimal hover position and dimensions
  
  let padding = 8.0'f32
  let marginSize = 10.0'f32
  let hoverOffset = 5.0'f32
  
  # Calculate base dimensions
  let minWidth = 160.0'f32
  let maxWidth = min(400.0'f32, windowWidth.float32 * 0.6)
  let hoverWidth = max(minWidth, min(contentWidth + 2 * padding, maxWidth))
  let hoverHeight = contentHeight + 2 * padding
  
  # Calculate base position
  var hoverX = hoverPos.x + hoverOffset
  var hoverY = hoverPos.y - hoverHeight - hoverOffset
  var arrowDirection = "down"
  
  # Ensure hover stays within screen bounds
  if hoverX + hoverWidth > windowWidth.float32 - marginSize:
    hoverX = windowWidth.float32 - hoverWidth - marginSize
  
  if hoverY < marginSize:
    hoverY = hoverPos.y + hoverOffset
    arrowDirection = "up"
  
  # Adjust if it goes off screen vertically
  if arrowDirection == "up" and hoverY + hoverHeight > windowHeight.float32 - marginSize:
    hoverY = windowHeight.float32 - hoverHeight - marginSize
  elif arrowDirection == "down" and hoverY < marginSize:
    hoverY = marginSize
  
  return (hoverX, hoverY, hoverWidth, hoverHeight, arrowDirection)

proc drawVSCodeHover*(
    hoverInfo: HoverInfo,
    mousePos: rl.Vector2,
    windowWidth: int32,
    windowHeight: int32,
    font: rl.Font,
    highlighter: var SyntaxHighlighter,
    fontSize: float32 = 14.0,
) =
  ## Draw VSCode-style hover tooltip with simplified logic
  if hoverInfo.content.len == 0:
    return

  # REMOVED: Overly strict rendering cache that was preventing hover from being drawn
  # The cache was causing the hover to disappear because it thought nothing had changed
  # when the mouse position changed slightly due to subpixel movements

  let hoverContent = hoverInfo.content
  let hoverPos = mousePos

  # Parse hover content
  let parsed = parseHoverContent(hoverContent)

  # Calculate font sizes
  let fontSizeRatio = 0.85
  let signatureFontSizeRatio = 0.95
  let mainFontSize = fontSize
  let fontSize = mainFontSize * fontSizeRatio
  let signatureFontSize = mainFontSize * signatureFontSizeRatio

  # Prepare text content
  let padding = 8.0
  let lineSpacing = 2.0
  let maxContentWidth = min(400.0, windowWidth.float32 * 0.6) - 2 * padding
  
  var signatureLines: seq[string] = @[]
  if parsed.signature.len > 0:
    signatureLines = smartWrapText(parsed.signature, maxContentWidth, signatureFontSize, font)

  # Calculate top padding based on whether signature is present
  let topPadding = if signatureLines.len > 0: 2.0 else: padding

  var descriptionLines: seq[string] = @[]
  if parsed.description.len > 0:
    descriptionLines = smartWrapText(parsed.description, maxContentWidth, fontSize, font)

  var allCodeLines: seq[string] = @[]
  for codeBlock in parsed.codeBlocks:
    let codeLines = smartWrapText(codeBlock, maxContentWidth, fontSize, font)
    allCodeLines.add(codeLines)

  # Calculate content dimensions
  let signatureLineHeight = signatureFontSize * 1.2 + lineSpacing
  let normalLineHeight = fontSize * 1.1 + lineSpacing
  let sectionSpacing = lineSpacing * 2
  
  var totalHeight = 2 * padding
  var maxWidth = 0.0

  # Calculate signature dimensions
  if signatureLines.len > 0:
    for line in signatureLines:
      let lineWidth = measureTextWidth(line, signatureFontSize, font)
      maxWidth = max(maxWidth, lineWidth)
      totalHeight += signatureLineHeight
    if descriptionLines.len > 0 or allCodeLines.len > 0:
      totalHeight += sectionSpacing

  # Calculate description dimensions
  if descriptionLines.len > 0:
    for line in descriptionLines:
      let lineWidth = measureTextWidth(line, fontSize, font)
      maxWidth = max(maxWidth, lineWidth)
      # Each line in descriptionLines is already wrapped, so just add one line height
      totalHeight += normalLineHeight
    if allCodeLines.len > 0:
      totalHeight += sectionSpacing

  # Calculate code block dimensions
  if allCodeLines.len > 0:
    for line in allCodeLines:
      let lineWidth = measureTextWidth(line, fontSize, font)
      maxWidth = max(maxWidth, lineWidth)
      totalHeight += normalLineHeight

  # Calculate final dimensions
  let minWidth = 160.0
  let calculatedWidth = maxWidth + 2 * padding
  let contentWidth = max(minWidth, min(calculatedWidth, maxContentWidth + 2 * padding))
  let contentHeight = totalHeight

  # Calculate position
  let (hoverX, hoverY, hoverWidth, hoverHeight, arrowDirection) = calculateHoverPosition(
    hoverPos, contentWidth, contentHeight, windowWidth, windowHeight, fontSize
  )

  # Define colors
  let hoverBgColor = rl.Color(r: 45, g: 45, b: 45, a: 255)
  let hoverBorderColor = rl.Color(r: 80, g: 80, b: 80, a: 255)
  let hoverTextColor = rl.Color(r: 220, g: 220, b: 220, a: 255)
  let codeBgColor = rl.Color(r: 35, g: 35, b: 35, a: 255)
  let signatureBgColor = rl.Color(r: 40, g: 40, b: 40, a: 255)

  # Draw hover background
  let cornerRadius = 4.0
  rl.drawRectangleRounded(
    rl.Rectangle(x: hoverX, y: hoverY, width: hoverWidth, height: hoverHeight),
    cornerRadius / min(hoverWidth, hoverHeight),
    16,
    hoverBgColor,
  )
  rl.drawRectangleRoundedLines(
    rl.Rectangle(x: hoverX, y: hoverY, width: hoverWidth, height: hoverHeight),
    cornerRadius / min(hoverWidth, hoverHeight),
    16,
    1.0,
    hoverBorderColor,
  )

  # Triangle removed for cleaner appearance

  # Draw content
  var currentY = hoverY + topPadding

  # Draw signature section
  if signatureLines.len > 0:
    # Draw signature background starting from the very top
    rl.drawRectangle(
      hoverX.int32, hoverY.int32, hoverWidth.int32, (signatureLines.len.float * signatureLineHeight).int32,
      signatureBgColor,
    )
    var sigY = currentY
    for line in signatureLines:
      let textY = sigY + (signatureLineHeight - signatureFontSize) / 2
      discard drawSyntaxHighlightedText(
        line, hoverX + padding, textY, signatureFontSize, font, highlighter
      )
      sigY += signatureLineHeight
    currentY += signatureLines.len.float * signatureLineHeight

  # Draw description section
  if descriptionLines.len > 0:
    for line in descriptionLines:
      # Split into paragraphs by empty lines
      let paragraphs = line.split("\n\n")
      for para in paragraphs:
        let wrapped = smartWrapText(para, maxContentWidth, fontSize, font)
        for wrappedLine in wrapped:
          let textY = currentY + max(lineSpacing, (normalLineHeight - fontSize) / 2)
          discard drawTextWithInlineCode(
            wrappedLine, hoverX + padding, textY, fontSize, hoverTextColor, font, highlighter, normalLineHeight
          )
          currentY += normalLineHeight
      # Remove extra paragraph spacing for now

    if allCodeLines.len > 0:
      currentY += sectionSpacing

  # Draw code blocks section
  if allCodeLines.len > 0:
    for line in allCodeLines:
      # Draw code background
      rl.drawRectangle(
        hoverX.int32, currentY.int32, hoverWidth.int32, normalLineHeight.int32,
        codeBgColor,
      )
      
      let textY = currentY + max(lineSpacing, (normalLineHeight - fontSize) / 2)
      discard drawSyntaxHighlightedText(
        line, hoverX + padding, textY, fontSize, font, highlighter
      )
      currentY += normalLineHeight

# Hover state management
proc updateHoverInfo*(
    state: TextEditorState,
    mousePos: rl.Vector2,
    windowWidth: int32,
    windowHeight: int32,
    sidebarWidth: float32,
    editorBounds: rl.Rectangle,
) =
  # Check if mouse is in text area
  let editorX = sidebarWidth
  let editorY = editorBounds.y
  let editorWidth = windowWidth.float32 - sidebarWidth
  let editorHeight = windowHeight.float32 - editorY - STATUSBAR_HEIGHT.float32
  let lineNumberWidth = 60.0

  let inTextArea =
    mousePos.x >= editorX + lineNumberWidth and mousePos.x <= editorX + editorWidth and
    mousePos.y >= editorY and mousePos.y <= editorY + editorHeight

  if not inTextArea:
    state.showHover = false
    state.hoverInfo = none(HoverInfo)
    return

  # Calculate hover position in text using state line height
  let textStartX = editorX + lineNumberWidth
  let padding = EDITOR_PADDING.float32
  let lineHeight = state.lineHeight
  let scaledFontSize = state.fontSize

  # Calculate which line we're hovering over - match text editor calculation
  let relativeY = mousePos.y - editorY - padding
  let startLine = max(0, int(state.scrollY / lineHeight))
  let hoverLine = startLine + int(relativeY / lineHeight)

  # Calculate character position with proper text measurement
  let relativeX = mousePos.x - textStartX + state.scrollX

  # Ensure hoverLine is within bounds
  if hoverLine < 0 or hoverLine >= state.text.lines.len:
    state.showHover = false
    state.hoverInfo = none(HoverInfo)
    return

  let line = state.text.lines[hoverLine]
  var hoverChar = 0
  var bestDistance = 1000.0

  # Measure character positions more accurately
  for i in 0 .. line.len:
    let textPart = line[0 ..< i] # Use proper string slicing
    let textWidth = measureTextWidth(textPart, scaledFontSize, state.font)
    let distance = abs(relativeX - textWidth)
    if distance < bestDistance:
      bestDistance = distance
      hoverChar = i

  # Update hover position
  state.hoverPosition = CursorPos(line: hoverLine, col: hoverChar)

  # Symbol detection logic - only show hover when hovering over alphanumeric symbols
  if hoverLine < state.text.lines.len and hoverChar < line.len:
    let char = line[hoverChar]
    if isAlphaNumeric(char) or char == '_':
      # Find symbol boundaries
      var symStart = hoverChar
      while symStart > 0 and (isAlphaNumeric(line[symStart - 1]) or line[symStart - 1] == '_'):
        symStart -= 1

      var symEnd = hoverChar
      while symEnd < line.len and (isAlphaNumeric(line[symEnd]) or line[symEnd] == '_'):
        symEnd += 1

      if symStart != symEnd:
        # We're hovering over a symbol - enable hover to trigger LSP requests
        let symbol = line[symStart..symEnd-1]  # Extract symbol for hover positioning
        state.showHover = true
        # Store symbol information for LSP requests
        # The actual LSP content will be populated by the main hover update loop
        return
  # No symbol found - clear hover
  state.showHover = false
  state.hoverInfo = none(HoverInfo)
  # Also clear LSP hover state if we have access to it
  # This will be handled in the main loop when showHover becomes false

proc drawHover*(
    state: TextEditorState,
    mousePos: rl.Vector2,
    windowWidth: int32,
    windowHeight: int32,
) =
  # Only log occasionally to reduce spam
  if int(mousePos.x) mod 200 == 0 and int(mousePos.y) mod 200 == 0:
    echo "DEBUG: drawHover called - showHover: ",
      state.showHover, ", hoverInfo.isSome: ", state.hoverInfo.isSome

  if not state.showHover or state.hoverInfo.isNone:
    return

  let hoverInfo = state.hoverInfo.get()
  # Only log occasionally for drawing
  if int(mousePos.x) mod 200 == 0 and int(mousePos.y) mod 200 == 0:
    echo "DEBUG: Drawing hover with content: ",
      hoverInfo.content[0 .. min(50, hoverInfo.content.len - 1)]

  # Calculate the actual screen position for the hover tooltip
  let editorX = state.sidebarWidth
  let editorY = TITLEBAR_HEIGHT.float32
  let lineNumberWidth = 60.0
  let textStartX = editorX + lineNumberWidth
  let textStartY = editorY + EDITOR_PADDING.float32

  # Convert hover position back to screen coordinates using proper text measurement
  let line = if state.hoverPosition.line < state.text.lines.len: state.text.lines[state.hoverPosition.line] else: ""
  let charPos = min(state.hoverPosition.col, line.len)
  let textBeforeCursor = if charPos > 0: line[0 ..< charPos] else: ""
  let textWidth = measureTextWidth(textBeforeCursor, state.fontSize, state.font)
  
  let hoverScreenX = textStartX + textWidth - state.scrollX
  let hoverScreenY =
    textStartY + state.hoverPosition.line.float32 * state.lineHeight - state.scrollY

  let hoverScreenPos = rl.Vector2(x: hoverScreenX, y: hoverScreenY)

  var hoverHighlighter = newSyntaxHighlighter(langNim)
  drawVSCodeHover(
    hoverInfo, hoverScreenPos, windowWidth, windowHeight, state.font, hoverHighlighter,
    state.fontSize,
  )
