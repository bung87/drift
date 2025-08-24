## Text Editor Input Handling
## Extracted from text_editor.nim

import std/[strutils, options, tables, algorithm, strformat, times]
import raylib as rl
import chronos except Result
import ../services/ui_service
import ../services/editor_service
import ../services/language_service


import ../shared/types
import ../shared/text_measurement
import ../infrastructure/rendering/[theme, renderer]
import ../infrastructure/input/keyboard
import ../enhanced_syntax

import ../domain/document






import ../os_files/dialog
import ../infrastructure/clipboard
import text_editor_types

proc measureTextSafe*(font: ptr rl.Font, text: string, fontSize: float32,
    spacing: float32): rl.Vector2 =
  ## Unicode-safe text measurement - wrapper for the enhanced text measurement system
  let tm = newTextMeasurement(font, fontSize, spacing, 8.0)
  return tm.measureTextSafe(text)

proc validateCurrentCursor*(editor: TextEditor) =
  ## Validate and correct the current cursor position
  if editor.editorService.document != nil:
    editor.editorState.cursor = validateCursorPosition(editor.editorState.cursor, editor.editorService.document)
  else:
    editor.editorState.cursor = CursorPos(line: 0, col: 0)

proc tokenizeFullDocument*(editor: TextEditor) =
  ## Tokenize the entire document for syntax highlighting
  if not editor.config.syntaxHighlighting:
    return

  if editor.editorService.document != nil:
    let doc = editor.editorService.document
    let totalLines = doc.lineCount()
    
    # Tokenize each line
    # Note: The actual tokenization is handled by tokenizeFullDocument which uses allTokens
    # This is a simplified line-by-line tokenization for compatibility
    
    editor.tokensValid = true
    editor.lastTokenizedVersion = 0  # Reset tokenization version

proc invalidateTokens*(editor: TextEditor) =
  ## Mark tokens as invalid so they will be regenerated
  editor.tokensValid = false
  editor.lastTokenizedVersion = -1 # Force retokenization on next update

  # Trigger immediate tokenization if syntax highlighting is enabled
  if editor.config.syntaxHighlighting:
    editor.tokenizeFullDocument()

proc notifyLSPTextChange*(editor: TextEditor) =
  ## Notify the language server about text changes
  if editor.languageService != nil and editor.editorService.document != nil:
    let doc = editor.editorService.document
    let content = doc.getFullText()
    let filePath = editor.editorService.currentFile.get("")
    discard editor.languageService.updateDocument(filePath, content)

proc updateScrolling*(editor: TextEditor) =
  ## Update scrolling bounds and clamp scroll offsets
  if editor.editorService.document == nil:
    return
  
  let totalLines = editor.editorService.document.lineCount()
  let viewportHeight = editor.bounds.height - (editor.config.padding * 2)
  editor.editorState.visibleLines = int(viewportHeight /
      editor.config.lineHeight)
  editor.editorState.maxScrollOffset =
    max(0, totalLines - editor.editorState.visibleLines)
  
  # Calculate horizontal scrolling bounds
  let viewportWidth = editor.bounds.width - (editor.config.padding * 2) -
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0) -
    (if editor.config.showScrollbar: editor.config.scrollbarWidth else: 0.0)
  
  # Find the maximum line width for horizontal scrolling
  var maxLineWidth = 0.0
  if editor.font != nil:
    for i in 0 ..< min(totalLines, 1000): # Limit check to first 1000 lines for performance
      let lineResult = editor.editorService.document.getLine(i)
      if lineResult.isOk:
        let lineText = lineResult.get()
        let lineWidth = measureTextSafe(editor.font, lineText, editor.config.fontSize, 1.0)
        maxLineWidth = max(maxLineWidth, lineWidth.x)
  
  # Calculate maximum horizontal scroll and clamp current scroll offsets
  let maxScrollX = max(0.0, maxLineWidth - viewportWidth)
  editor.editorState.scrollOffset = min(editor.editorState.scrollOffset, 
                                       editor.editorState.maxScrollOffset)
  editor.editorState.scrollX = min(editor.editorState.scrollX, maxScrollX)
  editor.editorState.scrollX = max(0.0, editor.editorState.scrollX)
  editor.editorState.scrollOffset = max(0, min(editor.editorState.scrollOffset,
      editor.editorState.maxScrollOffset))

proc renderTextContent*(editor: TextEditor, startLine, endLine: int) =
  ## Render the text content with syntax highlighting and hover background
  if editor.editorService.document == nil or editor.font == nil:
    return
  
  let textStartX = editor.bounds.x + editor.config.padding +
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0) -
    editor.editorState.scrollX
  let textStartY = editor.bounds.y + editor.config.padding
  let doc = editor.editorService.document
  let font = editor.font
  let fontSize = editor.config.fontSize
  let lineHeight = editor.config.lineHeight
  
  let totalLines = doc.lineCount()
  for i in startLine .. endLine:
    if i >= totalLines:
      break
    let lineResult = doc.getLine(i)
    if lineResult.isErr:
      continue
    let line = lineResult.get()
    let y = textStartY + (i - startLine).float32 * lineHeight

    # Draw hover background highlight if hovering over this line
    if editor.editorState.showHover and editor.editorState.hoverPosition.line == i:
      let hoverCol = editor.editorState.hoverPosition.col

      # Find token boundaries for highlighting using existing tokenization
      if hoverCol < line.len:
        var symbolStartX = textStartX
        var symbolWidth = 0.0
        var foundToken = false

        # Try to use line tokenization for hover detection
        if editor.config.syntaxHighlighting:
          var tokenStartX = textStartX
          var tokenStartCol = 0

          let lineTokens = editor.syntaxHighlighter.tokenize(line)

          for token in lineTokens:
            let tokenEndCol = tokenStartCol + token.text.len
            if hoverCol >= tokenStartCol and hoverCol < tokenEndCol:
              # Found the token containing the hover position
              symbolStartX = tokenStartX
              symbolWidth = measureTextSafe(font, token.text, fontSize, 1.0).x
              foundToken = true
              break

            tokenStartX += measureTextSafe(font, token.text, fontSize, 1.0).x
            tokenStartCol = tokenEndCol

        # Fallback to manual detection if no tokens found
        if not foundToken:
          var symStart = hoverCol
          var symEnd = hoverCol

          # Find symbol start
          while symStart > 0 and
              (
                line[symStart - 1].isAlphaNumeric() or
                line[symStart - 1] in ['_', '.', ':']
              )
          :
            symStart.dec

          # Find symbol end
          while symEnd < line.len and
              (line[symEnd].isAlphaNumeric() or line[symEnd] in ['_', '.', ':']):
            symEnd.inc

          if symEnd > symStart:
            # Calculate highlight position and size
            let beforeSymbol = safeSubstringFromStart(line, byteColumnToRune(
                line, symStart))
            let symbol = safeSubstring(line, byteColumnToRune(line, symStart),
                byteColumnToRune(line, symEnd))
            symbolStartX = textStartX + measureTextSafe(font, beforeSymbol,
                fontSize, 1.0).x
            symbolWidth = measureTextSafe(font, symbol, fontSize, 1.0).x
            foundToken = true

        # Draw hover background if we found something to highlight
        if foundToken and symbolWidth > 0:
          let hoverBgColor = rl.Color(r: 64, g: 64, b: 128, a: 80)
            # Semi-transparent blue
          editor.uiService.renderer.drawRectangle(
            rl.Rectangle(
              x: symbolStartX - 2,
              y: y - 2,
              width: symbolWidth + 4,
              height: lineHeight
            ),
            hoverBgColor,
          )

    # Draw Ctrl+D selections background first
    for selection in editor.ctrlDSelections:
      if selection.active:
        let selStart = selection.start
        let selEnd = selection.finish
        let normalizedStart = if selStart < selEnd: selStart else: selEnd
        let normalizedEnd = if selStart < selEnd: selEnd else: selStart

        # Check if current line intersects with selection
        if i >= normalizedStart.line and i <= normalizedEnd.line:
          var selectionStartX = textStartX
          var selectionEndX = textStartX + measureTextSafe(font, line, fontSize, 1.0).x

          # Calculate selection start position on this line
          if i == normalizedStart.line:
            let runeCol = byteColumnToRune(line, normalizedStart.col)
            let beforeSelection = safeSubstringFromStart(line, runeCol)
            selectionStartX = textStartX + measureTextSafe(font,
                beforeSelection, fontSize, 1.0).x

          # Calculate selection end position on this line
          if i == normalizedEnd.line:
            let runeCol = byteColumnToRune(line, normalizedEnd.col)
            let selectionText = safeSubstringFromStart(line, runeCol)
            selectionEndX = textStartX + measureTextSafe(font, selectionText,
                fontSize, 1.0).x

          # Draw selection background with slightly different color for multiple selections
          let selectionBgColor = editor.uiService.theme.uiColors[uiSelection]
          editor.uiService.renderer.drawRectangle(
            rl.Rectangle(
              x: selectionStartX,
              y: y,
              width: selectionEndX - selectionStartX,
              height: lineHeight
            ),
            selectionBgColor,
          )

    # Draw main selection background if active and not part of Ctrl+D selections
    if editor.editorState.selection.active and editor.ctrlDSelections.len == 0:
      let selStart = editor.editorState.selection.start
      let selEnd = editor.editorState.selection.finish
      let normalizedStart = if selStart < selEnd: selStart else: selEnd
      let normalizedEnd = if selStart < selEnd: selEnd else: selStart

      # Check if current line intersects with selection
      if i >= normalizedStart.line and i <= normalizedEnd.line:
        var selectionStartX = textStartX
        var selectionEndX = textStartX + measureTextSafe(font, line, fontSize, 1.0).x

        # Calculate selection start position on this line
        if i == normalizedStart.line:
          let runeCol = byteColumnToRune(line, normalizedStart.col)
          let beforeSelection = safeSubstringFromStart(line, runeCol)
          selectionStartX = textStartX + measureTextSafe(font, beforeSelection,
              fontSize, 1.0).x

        # Calculate selection end position on this line
        if i == normalizedEnd.line:
          let runeCol = byteColumnToRune(line, normalizedEnd.col)
          let selectionText = safeSubstringFromStart(line, runeCol)
          selectionEndX = textStartX + measureTextSafe(font, selectionText,
              fontSize, 1.0).x

        # Draw selection background
        let selectionBgColor = editor.uiService.theme.uiColors[uiSelection]
        editor.uiService.renderer.drawRectangle(
          rl.Rectangle(
            x: selectionStartX,
            y: y,
            width: selectionEndX - selectionStartX,
            height: lineHeight
          ),
          selectionBgColor,
        )

    # Draw multi-cursor selection backgrounds if in multi-cursor mode
    if editor.isMultiCursorMode:
      for cursor in editor.multiCursors:
        # For now, just highlight the cursor position (future: add selection support)
        if i == cursor.line:
          let cursorCol = min(cursor.col, line.len)
          let runeCol = byteColumnToRune(line, cursorCol)
          let beforeCursor = safeSubstringFromStart(line, runeCol)
          let cursorX = textStartX + measureTextSafe(font, beforeCursor,
              fontSize, 1.0).x

          # Draw a small selection indicator around the cursor
          let multiCursorBgColor = editor.uiService.theme.uiColors[uiSelectionInactive]
          editor.uiService.renderer.drawRectangle(
            rl.Rectangle(
              x: cursorX - 1,
              y: y,
              width: 3,
              height: lineHeight
            ),
            multiCursorBgColor,
          )

    var currentX = textStartX
    if editor.config.syntaxHighlighting:
      # Use cached tokens that include markdown code block highlighting
      let tokens = editor.editorService.getTokensForLine(i)
      for token in tokens:
        let tokenText = token.text
        let tokenColor = enhanced_syntax.getTokenColor(token.tokenType)
        let tokenWidth = measureTextSafe(font, tokenText, fontSize, 1.0).x
        editor.uiService.renderer.drawText(
          font[], tokenText, rl.Vector2(x: currentX, y: y), fontSize, 1.0, tokenColor
        )
        
        # Draw underline for Ctrl+hover Go to Definition
        if editor.isCtrlHovering and editor.ctrlHoverPosition.line == i and 
           editor.ctrlHoverSymbol.len > 0 and tokenText.contains(editor.ctrlHoverSymbol):
          let underlineY = y + fontSize + 1.0
          let underlineColor = rl.Color(r: 100, g: 150, b: 255, a: 200)
          editor.uiService.renderer.drawRectangle(
            rl.Rectangle(x: currentX, y: underlineY, width: tokenWidth, height: 1.0),
            underlineColor
          )
        
        currentX += tokenWidth
    else:
      # Simple text rendering
      editor.uiService.renderer.drawText(
        font[],
        line,
        rl.Vector2(x: textStartX, y: y),
        fontSize,
        1.0,
        editor.uiService.theme.uiColors[uiText],
      )

# renderCursor moved from text_editor.nim
proc renderCursor*(editor: TextEditor) =
  ## Render the text cursor with blinking support using accurate text measurement
  if not editor.editorState.isFocused:
      return
  
  let textStartX = editor.bounds.x + editor.config.padding +
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0) -
    editor.editorState.scrollX
  let textStartY = editor.bounds.y + editor.config.padding
  
  # Check cursor visibility (blinking is handled in update method)
  if not editor.cursorVisible:
    return
  
  # Create text measurement configuration
  let textMeasurement = newTextMeasurement(
    editor.font,
    editor.config.fontSize,
    1.0,
    editor.config.charWidth
  )
  
  # Render main cursor with comprehensive error handling
  let cursorLine = editor.editorState.cursor.line - editor.editorState.scrollOffset
  if cursorLine >= 0 and cursorLine < editor.editorState.visibleLines:
    var cursorX = textStartX
    
    # Get the line text for accurate measurement
    if editor.editorService.document != nil:
      let actualLine = editor.editorState.cursor.line
      if actualLine >= 0 and actualLine < editor.editorService.document.lineCount():
        let lineResult = editor.editorService.document.getLine(actualLine)
        if lineResult.isOk:
          let lineText = lineResult.get()
          let safeRuneLen = safeRuneLen(lineText)
          let cursorCol = min(editor.editorState.cursor.col, safeRuneLen)
          cursorX = textStartX + withMeasurementFallback(
            proc(): float32 = textMeasurement.measureTextToPosition(lineText, cursorCol),
            cursorCol.float32 * editor.config.charWidth, # Fallback to fixed width
            lineText,
            "cursor_rendering_main"
          )
        else:
          # Fallback to fixed width if line cannot be retrieved
          cursorX = textStartX + (editor.editorState.cursor.col.float32 * editor.config.charWidth)
      else:
        # Cursor is beyond document bounds, position at start of line
        cursorX = textStartX
    else:
      # No document available, use fallback positioning
      cursorX = textStartX + (editor.editorState.cursor.col.float32 * editor.config.charWidth)
    
    let cursorY = textStartY + cursorLine.float32 * editor.config.lineHeight
    editor.uiService.renderer.drawRectangle(
      rl.Rectangle(
        x: cursorX,
        y: cursorY,
        width: 2,
        height: editor.config.lineHeight
      ),
      editor.uiService.theme.uiColors[uiCursor],
    )

  # Render multiple cursors with accurate positioning and error handling
  if editor.isMultiCursorMode:
    for i, cursor in editor.multiCursors:
      let mcLine = cursor.line - editor.editorState.scrollOffset
      if mcLine >= 0 and mcLine < editor.editorState.visibleLines:
        var mcX = textStartX
        
        # Get the line text for accurate measurement
        if editor.editorService.document != nil:
          let actualLine = cursor.line
          if actualLine >= 0 and actualLine < editor.editorService.document.lineCount():
            let lineResult = editor.editorService.document.getLine(actualLine)
            if lineResult.isOk:
              let lineText = lineResult.get()
              let safeRuneLen = safeRuneLen(lineText)
              let cursorCol = min(cursor.col, safeRuneLen)
              
              mcX = textStartX + withMeasurementFallback(
                proc(): float32 = textMeasurement.measureTextToPosition(lineText, cursorCol),
                cursorCol.float32 * editor.config.charWidth, # Fallback to fixed width
                lineText,
                fmt"cursor_rendering_multi_{i}"
              )
            else:
              # Fallback to fixed width if line cannot be retrieved
              mcX = textStartX + (cursor.col.float32 * editor.config.charWidth)
          else:
            # Cursor is beyond document bounds, position at start of line
            mcX = textStartX
        else:
          # No document available, use fallback positioning
          mcX = textStartX + (cursor.col.float32 * editor.config.charWidth)
        
        let mcY = textStartY + mcLine.float32 * editor.config.lineHeight

        editor.uiService.renderer.drawRectangle(
          rl.Rectangle(
            x: mcX,
            y: mcY,
            width: 2,
            height: editor.config.lineHeight
          ),
          editor.uiService.theme.uiColors[uiCursor],
        )

proc renderScrollbar*(editor: TextEditor) =
  ## Render the scrollbar if needed
  if not editor.config.showScrollbar or editor.editorState.maxScrollOffset <= 0:
    return
  
  let scrollbarX = editor.bounds.x + editor.bounds.width - editor.config.scrollbarWidth
  let scrollbarHeight = editor.bounds.height
  let scrollThumbHeight = max(
    20.0,
    (editor.editorState.visibleLines.float32 /
    (editor.editorState.maxScrollOffset + editor.editorState.visibleLines).float32) * scrollbarHeight
  )
  let scrollThumbY = editor.bounds.y +
    (editor.editorState.scrollOffset.float32 / editor.editorState.maxScrollOffset.float32) *
    (scrollbarHeight - scrollThumbHeight)
  
  # Draw scrollbar background
  editor.uiService.renderer.drawRectangle(
    rl.Rectangle(
      x: scrollbarX,
      y: editor.bounds.y,
      width: editor.config.scrollbarWidth,
      height: editor.bounds.height
    ),
    editor.uiService.theme.uiColors[uiScrollbar],
  )
  
  # Mouse position will be provided by unified input system
  # This rendering code should use the last known mouse position from handleInput
  let mousePos = editor.lastMousePos
  let thumbRect = rl.Rectangle(
    x: scrollbarX,
    y: scrollThumbY,
    width: editor.config.scrollbarWidth,
    height: scrollThumbHeight
  )
  let isHovered = rl.checkCollisionPointRec(mousePos, thumbRect)
  
  # Draw scroll thumb with hover effect
  let thumbColor = if isHovered: editor.uiService.theme.uiColors[uiScrollbar].lighten(0.3)
    else: editor.uiService.theme.uiColors[uiScrollbar].lighten(0.1)
  editor.uiService.renderer.drawRectangle(thumbRect, thumbColor)

proc handleTextInput*(editor: TextEditor, text: string) =
  ## Handle text input for the text editor with improved multi-cursor support and proper synchronization
  if not editor.editorState.isFocused:
    return
  
  # Reset cursor blinking on text input
  editor.cursorBlinkTime = epochTime()
  editor.cursorVisible = true
  
  # If there's a selection, delete it first
  if editor.editorState.selection.active:
    # Sync state before operation
    editor.editorService.selection = editor.editorState.selection
    editor.editorService.cursor = editor.editorState.cursor
    
    let deleteResult = editor.editorService.deleteSelection()
    if deleteResult.isErr:
      echo "Error deleting selection: ", deleteResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.selection = editor.editorService.selection
    editor.editorState.cursor = editor.editorService.cursor

  # Handle multi-cursor text input
  if editor.isMultiCursorMode:
    # Sort cursors by position (line, then column) to handle insertions correctly
    var sortedCursors = editor.multiCursors
    sortedCursors.sort(proc(a, b: CursorPos): int =
      if a.line < b.line: -1
      elif a.line > b.line: 1
      elif a.col < b.col: -1
      elif a.col > b.col: 1
      else: 0
    )

    # Calculate how the text insertion affects cursor positions
    let newlineCount = text.count('\n')
    let lastLineLength = if newlineCount > 0:
      text.split('\n')[^1].len
    else:
      text.len

    # Insert text at all cursor positions, starting from the end to avoid position shifts
    for i in countdown(sortedCursors.len - 1, 0):
      let cursor = sortedCursors[i]
      # Sync state before operation
      editor.editorState.cursor = cursor
      editor.editorService.cursor = cursor
      
      let insertResult = editor.editorService.insertText(text)
      if insertResult.isErr:
        echo "Error inserting text at multi-cursor position: ", insertResult.error.msg
        continue
      
      # Update the cursor position in our array
      sortedCursors[i] = editor.editorService.cursor
      
      # Adjust all previous cursors that are affected by this insertion
      for j in 0 ..< i:
        if sortedCursors[j].line == cursor.line and sortedCursors[j].col >= cursor.col:
          # Same line, cursor is after insertion point
          if newlineCount > 0:
            # Text contains newlines, move cursor to new line
            sortedCursors[j].line += newlineCount
            sortedCursors[j].col = sortedCursors[j].col - cursor.col + lastLineLength
          else:
            # No newlines, just shift column
            sortedCursors[j].col += text.len
        elif sortedCursors[j].line > cursor.line:
          # Cursor is on a later line
          if newlineCount > 0:
            sortedCursors[j].line += newlineCount

    # Update multi-cursor array with new positions
    editor.multiCursors = sortedCursors
    # Sync primary cursor to the last updated position
    editor.editorState.cursor = editor.editorService.cursor
  else:
    # Single cursor text input
    # Sync state before operation
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let insertResult = editor.editorService.insertText(text)
    if insertResult.isErr:
      echo "Error inserting text: ", insertResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection

  # Validate cursor position after text input
  editor.validateCurrentCursor()
  
  # Update UI state
  editor.invalidateTokens()
  editor.notifyLSPTextChange()
  editor.isDirty = true
  editor.editorState.isModified = true
  editor.editorService.isModified = true

proc renderLineNumbers*(editor: TextEditor, startLine, endLine: int) =
  ## Render line numbers in the gutter
  if not editor.config.showLineNumbers:
    return
  
  let lineNumberX = editor.bounds.x + editor.config.padding
  let lineNumberY = editor.bounds.y + editor.config.padding
  
  for i in startLine .. endLine:
    let lineNum = i + 1
    let y = lineNumberY + (i - startLine).float32 * editor.config.lineHeight
    editor.uiService.renderer.drawText(
      editor.font[],
      $(lineNum),
      rl.Vector2(x: lineNumberX, y: y),
      editor.config.fontSize,
      1.0,
      editor.uiService.theme.uiColors[uiLineNumber],
    )
  
proc handleKeyboardInput*(editor: TextEditor, key: int32, modifiers: set[ModifierKey] = {}) =
  ## Handle keyboard input with VSCode-like key bindings (deprecated - use unified input system)
  ## This method is deprecated. Use the unified input system instead.
  if not editor.editorState.isFocused:
    return

  # Reset cursor blinking on any key press
  editor.cursorBlinkTime = epochTime()
  editor.cursorVisible = true

  # Use modifier information from unified input system
  let isCtrlPressed = mkCtrl in modifiers or mkSuper in modifiers  # mkSuper handles Cmd on macOS
  let isShiftPressed = mkShift in modifiers
  let isAltPressed = mkAlt in modifiers
  
  # Log key event with modifier states (reduced logging)
  # echo "[DEBUG] Key event - key: ", key.int32, " modifiers: ", modifiers

  # Handle VSCode-like shortcuts first
  if isCtrlPressed:
    case key
    of rl.KeyboardKey.A.int32: # Ctrl+A - Select All
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let selectResult = editor.editorService.selectAll()
      if selectResult.isErr:
        echo "Error selecting all: ", selectResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
      
      # Clear Ctrl+D state when selecting all
      editor.lastSelectedWord = ""
      editor.ctrlDSelections = @[]
      editor.isDirty = true
      return
      
    of rl.KeyboardKey.C.int32: # Ctrl+C - Copy
      if editor.editorState.selection.active:
        # Sync selection state before getting text
        editor.editorService.selection = editor.editorState.selection
        let selectedText = editor.editorService.getSelectedText()
        if selectedText.len > 0:
          editor.clipboardService.setText(selectedText)
      return
      
    of rl.KeyboardKey.X.int32: # Ctrl+X - Cut
      if editor.editorState.selection.active:
        # Sync state before operation
        editor.editorService.selection = editor.editorState.selection
        editor.editorService.cursor = editor.editorState.cursor
        
        let selectedText = editor.editorService.getSelectedText()
        if selectedText.len > 0:
          editor.clipboardService.setText(selectedText)
          
          let deleteResult = editor.editorService.deleteSelection()
          if deleteResult.isErr:
            echo "Error cutting text: ", deleteResult.error.msg
            return
          
          # Sync state after operation
          editor.editorState.selection = editor.editorService.selection
          editor.editorState.cursor = editor.editorService.cursor
          
          editor.invalidateTokens()
          editor.notifyLSPTextChange()
          editor.isDirty = true
          editor.editorState.isModified = true
          editor.editorService.isModified = true
          echo "[DEBUG] Document marked as modified (cut operation)"
      return
      
    of rl.KeyboardKey.V.int32: # Ctrl+V - Paste
      try:
        let clipboardText = editor.clipboardService.getText()
        if clipboardText.len > 0:

          # Sync state before operation
          editor.editorService.cursor = editor.editorState.cursor
          editor.editorService.selection = editor.editorState.selection
          
          if editor.editorState.selection.active:
            let deleteResult = editor.editorService.deleteSelection()
            if deleteResult.isErr:
              echo "Error deleting selection before paste: ", deleteResult.error.msg
              return
          
          let insertResult = editor.editorService.insertText(clipboardText)
          if insertResult.isErr:
            echo "Error pasting text: ", insertResult.error.msg
            return
          
          # Sync state after operation
          editor.editorState.cursor = editor.editorService.cursor
          editor.editorState.selection = editor.editorService.selection
          
          editor.invalidateTokens()
          editor.notifyLSPTextChange()
          editor.isDirty = true
          editor.editorState.isModified = true
          editor.editorService.isModified = true
          echo "[DEBUG] Document marked as modified (paste operation)"
      except Exception as e:
        echo "Unexpected error in paste: ", e.msg
      return
      
    of rl.KeyboardKey.Z.int32: # Ctrl+Z - Undo
      if not isShiftPressed:
        let undoResult = editor.editorService.undo()
        if undoResult.isErr:
          echo "Error undoing: ", undoResult.error.msg
          return
      else: # Ctrl+Shift+Z - Redo
        let redoResult = editor.editorService.redo()
        if redoResult.isErr:
          echo "Error redoing: ", redoResult.error.msg
          return
      
      # Sync state after undo/redo
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      
      editor.invalidateTokens()
      editor.isDirty = true
      return
      
    of rl.KeyboardKey.Y.int32: # Ctrl+Y - Redo
      let redoResult = editor.editorService.redo()
      if redoResult.isErr:
        echo "Error redoing: ", redoResult.error.msg
        return
      
      # Sync state after redo
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      
      editor.invalidateTokens()
      editor.isDirty = true
      return
    of rl.KeyboardKey.S.int32: # Ctrl+S / Cmd+S - Save
      echo "[DEBUG] Save shortcut pressed: isModified=" & $editor.editorState.isModified & " currentFileSet=" & $editor.editorService.currentFile.isSome
      if editor.editorState.isModified:
        # Check if we have a file path - if not, show save dialog
        if not editor.editorService.currentFile.isSome:
          echo "[DEBUG] No file path set, showing save dialog"
          
          var di: DialogInfo
          di.kind = dkSaveFile
          di.title = "Save File"
          di.folder = ""  # Use current directory
          di.extension = "txt"  # Default extension
          di.filters = @[
            (name: "Text Files", ext: "*.txt"),
            (name: "All Files", ext: "*.*")
          ]
          
          let dialogResult = di.show()
          if dialogResult.len > 0:
            echo "[DEBUG] Save dialog returned path: " & dialogResult
            let saveResult = editor.editorService.saveFile(dialogResult)
            if saveResult.isErr:
              echo "Error saving file: ", saveResult.error.msg
            else:
              # Mark states as not modified
              editor.editorState.isModified = false
              editor.editorService.isModified = false
              # Notify FileTabBar (if any) to update modified indicator via UI event
              let saveEvent = UIEvent(
                eventType: uetClick,
                componentId: editor.id,
                data: {"action": "document_saved"}.toTable(),
                timestamp: times.getTime(),
                handled: false
              )
              editor.uiService.queueEvent(saveEvent)
          else:
            echo "[DEBUG] Save dialog cancelled"
        else:
          # File has a path, save directly
          let saveResult = editor.editorService.saveFile()
          if saveResult.isErr:
            echo "Error saving file: ", saveResult.error.msg
          else:
            # Mark states as not modified
            editor.editorState.isModified = false
            editor.editorService.isModified = false
            # Notify FileTabBar (if any) to update modified indicator via UI event
            let saveEvent = UIEvent(
              eventType: uetClick,
              componentId: editor.id,
              data: {"action": "document_saved"}.toTable(),
              timestamp: times.getTime(),
              handled: false
            )
            editor.uiService.queueEvent(saveEvent)
      return
    of rl.KeyboardKey.F.int32: # Ctrl+F - Find
      let findEvent = UIEvent(
        eventType: uetClick,
        componentId: editor.id,
        data: {"action": "show_search"}.toTable(),
        timestamp: times.getTime(),
        handled: false
      )
      editor.uiService.queueEvent(findEvent)
      return
    of rl.KeyboardKey.H.int32: # Ctrl+H - Replace
      let replaceEvent = UIEvent(
        eventType: uetClick,
        componentId: editor.id,
        data: {"action": "show_replace"}.toTable(),
        timestamp: times.getTime(),
        handled: false
      )
      editor.uiService.queueEvent(replaceEvent)
      return
    of rl.KeyboardKey.L.int32: # Ctrl+L - Select line
      editor.editorService.cursor = editor.editorState.cursor
      discard editor.editorService.selectLine()
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
      editor.isDirty = true
      editor.editorState.isModified = true
      editor.editorService.isModified = true
      echo "[DEBUG] Document marked as modified (line select operation)"
      return
    of rl.KeyboardKey.Slash.int32: # Ctrl+/ - Toggle line comment
      if editor.editorState.selection.active:
        # TODO: Implement line comment toggle in EditorService
        # For now, just ignore this shortcut
        discard
      else:
        # TODO: Implement line comment toggle in EditorService
        # For now, just ignore this shortcut
        discard
      return
    of rl.KeyboardKey.D.int32: # Ctrl+D - Select word/add next occurrence
      editor.editorService.cursor = editor.editorState.cursor

      # Get current word at cursor
      let currentLineResult = editor.editorService.document.getLine(
          editor.editorState.cursor.line)
      if currentLineResult.isOk:
        let line = currentLineResult.get()
        let col = min(editor.editorState.cursor.col, line.len - 1)

        if col >= 0 and col < line.len and (line[col].isAlphaNumeric() or line[
            col] == '_'):
          # Find word boundaries
          var wordStart = col
          var wordEnd = col

          # Find start of word
          while wordStart > 0 and (line[wordStart - 1].isAlphaNumeric() or line[
              wordStart - 1] == '_'):
            wordStart.dec

          # Find end of word
          while wordEnd < line.len and (line[wordEnd].isAlphaNumeric() or line[
              wordEnd] == '_'):
            wordEnd.inc

          let currentWord = line[wordStart ..< wordEnd]

          if currentWord.len > 0:
            if editor.lastSelectedWord != currentWord or
                editor.ctrlDSelections.len == 0:
              # First Ctrl+D or different word - start new selection
              editor.lastSelectedWord = currentWord
              editor.ctrlDSelections = @[]

              # Select current word
              let selection = Selection(
                start: CursorPos(line: editor.editorState.cursor.line,
                    col: wordStart),
                finish: CursorPos(line: editor.editorState.cursor.line,
                    col: wordEnd),
                active: true
              )
              editor.ctrlDSelections.add(selection)
              editor.editorState.selection = selection
              editor.editorState.cursor = selection.finish
            else:
              # Subsequent Ctrl+D - find next occurrence
              let doc = editor.editorService.document
              let totalLines = doc.lineCount()
              var found = false

              # Start search from current position
              var searchLine = editor.editorState.cursor.line
              var searchCol = editor.editorState.cursor.col

              # Search for next occurrence
              for lineIdx in searchLine ..< totalLines:
                let lineResult = doc.getLine(lineIdx)
                if lineResult.isOk:
                  let searchInLine = lineResult.get()
                  let startCol = if lineIdx == searchLine: searchCol else: 0

                  var pos = startCol
                  while pos < searchInLine.len:
                    let foundPos = searchInLine.find(currentWord, pos)
                    if foundPos >= 0:
                      # Skip if this occurrence is already selected
                      var alreadySelected = false
                      for existingSel in editor.ctrlDSelections:
                        if existingSel.start.line == lineIdx and
                            existingSel.start.col == foundPos:
                          alreadySelected = true
                          break

                      if not alreadySelected:
                        # Check if it's a whole word match
                        let isWordStart = foundPos == 0 or not (searchInLine[
                            foundPos - 1].isAlphaNumeric() or searchInLine[
                            foundPos - 1] == '_')
                        let isWordEnd = foundPos + currentWord.len >=
                            searchInLine.len or not (searchInLine[foundPos +
                            currentWord.len].isAlphaNumeric() or searchInLine[
                            foundPos + currentWord.len] == '_')

                        if isWordStart and isWordEnd:
                          # Found next occurrence
                          let newSelection = Selection(
                            start: CursorPos(line: lineIdx, col: foundPos),
                            finish: CursorPos(line: lineIdx, col: foundPos +
                                currentWord.len),
                            active: true
                          )
                          editor.ctrlDSelections.add(newSelection)
                          editor.editorState.selection = newSelection
                          editor.editorState.cursor = newSelection.finish

                          # Enable multi-cursor mode
                          editor.isMultiCursorMode = true
                          editor.multiCursors = @[]
                          for sel in editor.ctrlDSelections:
                            editor.multiCursors.add(sel.finish)

                          found = true
                          break

                      pos = foundPos + 1
                    else:
                      break

                  if found:
                    break

              # If not found, wrap around to beginning
              if not found:
                for lineIdx in 0 ..< searchLine:
                  let lineResult = doc.getLine(lineIdx)
                  if lineResult.isOk:
                    let searchInLine = lineResult.get()

                    var pos = 0
                    while pos < searchInLine.len:
                      let foundPos = searchInLine.find(currentWord, pos)
                      if foundPos >= 0:
                        # Skip if this occurrence is already selected
                        var alreadySelected = false
                        for existingSel in editor.ctrlDSelections:
                          if existingSel.start.line == lineIdx and
                              existingSel.start.col == foundPos:
                            alreadySelected = true
                            break

                        if not alreadySelected:
                          # Check if it's a whole word match
                          let isWordStart = foundPos == 0 or not (searchInLine[
                              foundPos - 1].isAlphaNumeric() or searchInLine[
                              foundPos - 1] == '_')
                          let isWordEnd = foundPos + currentWord.len >=
                              searchInLine.len or not (searchInLine[foundPos +
                              currentWord.len].isAlphaNumeric() or searchInLine[
                              foundPos + currentWord.len] == '_')

                          if isWordStart and isWordEnd:
                            # Found next occurrence
                            let newSelection = Selection(
                              start: CursorPos(line: lineIdx, col: foundPos),
                              finish: CursorPos(line: lineIdx, col: foundPos +
                                  currentWord.len),
                              active: true
                            )
                            editor.ctrlDSelections.add(newSelection)
                            editor.editorState.selection = newSelection
                            editor.editorState.cursor = newSelection.finish

                            # Enable multi-cursor mode
                            editor.isMultiCursorMode = true
                            editor.multiCursors = @[]
                            for sel in editor.ctrlDSelections:
                              editor.multiCursors.add(sel.finish)

                            found = true
                            break

                        pos = foundPos + 1
                      else:
                        break

                    if found:
                      break

      editor.isDirty = true
      return
    of rl.KeyboardKey.Home.int32: # Ctrl+Home - Document start
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let moveResult = editor.editorService.moveCursorToDocumentStart(isShiftPressed)
      if moveResult.isErr:
        echo "Error moving cursor to document start: ", moveResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      editor.isDirty = true
      return
      
    of rl.KeyboardKey.End.int32: # Ctrl+End - Document end
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let moveResult = editor.editorService.moveCursorToDocumentEnd(isShiftPressed)
      if moveResult.isErr:
        echo "Error moving cursor to document end: ", moveResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      editor.isDirty = true
      return
      
    of rl.KeyboardKey.Left.int32: # Ctrl+Left - Move by word
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let moveResult = editor.editorService.moveCursorLeftByWord(isShiftPressed)
      if moveResult.isErr:
        echo "Error moving cursor left by word: ", moveResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      editor.isDirty = true
      return
      
    of rl.KeyboardKey.Right.int32: # Ctrl+Right - Move by word
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let moveResult = editor.editorService.moveCursorRightByWord(isShiftPressed)
      if moveResult.isErr:
        echo "Error moving cursor right by word: ", moveResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      editor.isDirty = true
      return
    else:
      discard

  # Handle regular navigation with optional selection extension
  case key
  of rl.KeyboardKey.Up.int32:
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let moveResult = editor.editorService.moveCursorUp(isShiftPressed)
      if moveResult.isErr:
        echo "Error moving cursor up: ", moveResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
      editor.isDirty = true
      
  of rl.KeyboardKey.Down.int32:
    # Sync state before operation
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let moveResult = editor.editorService.moveCursorDown(isShiftPressed)
    if moveResult.isErr:
      echo "Error moving cursor down: ", moveResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    editor.isDirty = true
      
  of rl.KeyboardKey.Left.int32:
    # Sync state before operation
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let moveResult = editor.editorService.moveCursorLeft(isShiftPressed)
    if moveResult.isErr:
      echo "Error moving cursor left: ", moveResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    editor.isDirty = true
      
  of rl.KeyboardKey.Right.int32:
    # Sync state before operation
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let moveResult = editor.editorService.moveCursorRight(isShiftPressed)
    if moveResult.isErr:
      echo "Error moving cursor right: ", moveResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    editor.isDirty = true
      
  of rl.KeyboardKey.Home.int32:
    # Sync state before operation
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let moveResult = editor.editorService.moveCursorToLineStart(isShiftPressed)
    if moveResult.isErr:
      echo "Error moving cursor to line start: ", moveResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    editor.isDirty = true
      
  of rl.KeyboardKey.End.int32:
    # Sync state before operation
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let moveResult = editor.editorService.moveCursorToLineEnd(isShiftPressed)
    if moveResult.isErr:
      echo "Error moving cursor to line end: ", moveResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    editor.isDirty = true
    editor.editorState.isModified = true
    editor.editorService.isModified = true
    echo "[DEBUG] Document marked as modified (end key operation)"
  of rl.KeyboardKey.PageUp.int32:
      editor.editorState.scrollOffset =
        max(0, editor.editorState.scrollOffset - editor.editorState.visibleLines)
      editor.isDirty = true
      return
  of rl.KeyboardKey.PageDown.int32:
      editor.editorState.scrollOffset = min(
        editor.editorState.maxScrollOffset,
        editor.editorState.scrollOffset + editor.editorState.visibleLines,
      )
      editor.isDirty = true
      return
  of rl.KeyboardKey.Backspace.int32:

    if editor.editorState.selection.active:
      # Sync state before operation
      editor.editorService.selection = editor.editorState.selection
      editor.editorService.cursor = editor.editorState.cursor
      
      let deleteResult = editor.editorService.deleteSelection()
      if deleteResult.isErr:
        echo "Error deleting selection with backspace: ", deleteResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
    else:
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let deleteResult = editor.editorService.deleteChar(forward = false)
      if deleteResult.isErr:
        echo "Error deleting character with backspace: ", deleteResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
    
    editor.invalidateTokens()
    editor.notifyLSPTextChange()
    editor.isDirty = true
    editor.editorState.isModified = true
    editor.editorService.isModified = true
    echo "[DEBUG] Document marked as modified (backspace operation)"
    return
      
  of rl.KeyboardKey.Delete.int32:

    if editor.editorState.selection.active:
      # Sync state before operation
      editor.editorService.selection = editor.editorState.selection
      editor.editorService.cursor = editor.editorState.cursor
      
      let deleteResult = editor.editorService.deleteSelection()
      if deleteResult.isErr:
        echo "Error deleting selection with delete key: ", deleteResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
    else:
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      let deleteResult = editor.editorService.deleteChar(forward = true)
      if deleteResult.isErr:
        echo "Error deleting character with delete key: ", deleteResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.cursor = editor.editorService.cursor
      editor.editorState.selection = editor.editorService.selection
    
    editor.invalidateTokens()
    editor.notifyLSPTextChange()
    editor.isDirty = true
    editor.editorState.isModified = true
    editor.editorService.isModified = true
    echo "[DEBUG] Document marked as modified (delete key operation)"
      
  of rl.KeyboardKey.Enter.int32:
    # Ensure editor service is in insert mode for newline insertion

    if editor.editorState.selection.active:
      # Sync state before operation
      editor.editorService.selection = editor.editorState.selection
      editor.editorService.cursor = editor.editorState.cursor
      
      let deleteResult = editor.editorService.deleteSelection()
      if deleteResult.isErr:
        echo "Error deleting selection before newline: ", deleteResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
    
    # Sync state before newline insertion
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let insertResult = editor.editorService.insertNewline()
    if insertResult.isErr:
      echo "Error inserting newline: ", insertResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    
    editor.invalidateTokens()
    editor.notifyLSPTextChange()
    editor.isDirty = true
    editor.editorState.isModified = true
    editor.editorService.isModified = true
    echo "[DEBUG] Document marked as modified (enter key operation)"
      
  of rl.KeyboardKey.Tab.int32:
    # Ensure editor service is in insert mode for tab insertion

    if editor.editorState.selection.active:
      # Sync state before operation
      editor.editorService.selection = editor.editorState.selection
      editor.editorService.cursor = editor.editorState.cursor
      
      let deleteResult = editor.editorService.deleteSelection()
      if deleteResult.isErr:
        echo "Error deleting selection before tab: ", deleteResult.error.msg
        return
      
      # Sync state after operation
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
    
    # Sync state before tab insertion
    editor.editorService.cursor = editor.editorState.cursor
    editor.editorService.selection = editor.editorState.selection
    
    let tabText = if editor.config.useSpaces: "    " else: "\t" # Insert 4 spaces or tab
    let insertResult = editor.editorService.insertText(tabText)
    if insertResult.isErr:
      echo "Error inserting tab: ", insertResult.error.msg
      return
    
    # Sync state after operation
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    
    editor.invalidateTokens()
    editor.notifyLSPTextChange()
    editor.isDirty = true
    editor.editorState.isModified = true
    editor.editorService.isModified = true
    echo "[DEBUG] Document marked as modified (tab operation)"
  of rl.KeyboardKey.Escape.int32:
    # Clear selections and multi-cursor mode
    editor.editorState.selection.active = false
    # Clear multi-cursor mode and selections
    editor.isMultiCursorMode = false
    editor.multiCursors = @[]
    # Clear Ctrl+D state
    editor.lastSelectedWord = ""
    editor.ctrlDSelections = @[]
    editor.isDirty = true
  else:
    discard

  # Handle non-Ctrl key presses
  case key
  of rl.KeyboardKey.Tab.int32: # Tab - Indent or insert tab
    if isShiftPressed:
      # Shift+Tab - Unindent
      # TODO: Implement unindent functionality in EditorService
      # For now, just delete characters manually
      if editor.editorState.selection.active:
        # Simple unindent: remove up to tabSize spaces or one tab from start of each line
        discard
      else:
        # Simple unindent for current line
        discard
    else:
      # Tab - Indent
      if editor.editorState.selection.active:
        # TODO: Implement indent selection in EditorService
        # For now, just insert tab at cursor
        let tabText = if editor.config.useSpaces: " ".repeat(editor.config.tabSize) else: "\t"
        editor.editorService.cursor = editor.editorState.cursor
        discard editor.editorService.insertText(tabText)
        editor.editorState.cursor = editor.editorService.cursor
      else:
        let tabText = if editor.config.useSpaces: " ".repeat(editor.config.tabSize) else: "\t"
        editor.editorService.cursor = editor.editorState.cursor
        discard editor.editorService.insertText(tabText)
        editor.editorState.cursor = editor.editorService.cursor
    editor.invalidateTokens()
    editor.notifyLSPTextChange()
    editor.isDirty = true
    return
  of rl.KeyboardKey.Home.int32: # Home - Go to line start
    if isCtrlPressed:
      # Ctrl+Home - Go to document start
      editor.editorState.cursor = CursorPos(line: 0, col: 0)
      editor.editorService.cursor = CursorPos(line: 0, col: 0)
      if not isShiftPressed:
        editor.editorState.selection.active = false
    else:
      # Home - Go to line start (smart home: first non-whitespace or actual start)
      let lineResult = editor.editorService.document.getLine(editor.editorState.cursor.line)
      if lineResult.isOk:
        let line = lineResult.get()
        var firstNonWhite = 0
        while firstNonWhite < line.len and line[firstNonWhite] in {' ', '\t'}:
          firstNonWhite.inc
        
        if editor.editorState.cursor.col == firstNonWhite or firstNonWhite == line.len:
          editor.editorState.cursor.col = 0
        else:
          editor.editorState.cursor.col = firstNonWhite
      else:
        editor.editorState.cursor.col = 0
      
      if not isShiftPressed:
        editor.editorState.selection.active = false
    editor.isDirty = true
    return
  of rl.KeyboardKey.End.int32: # End - Go to line end
    if isCtrlPressed:
      # Ctrl+End - Go to document end
      if editor.editorService.document != nil:
        let lastLine = editor.editorService.document.lineCount() - 1
        let lineResult = editor.editorService.document.getLine(lastLine)
        if lineResult.isOk:
          editor.editorState.cursor = CursorPos(line: lastLine, col: lineResult.get().len)
          editor.editorService.cursor = CursorPos(line: lastLine, col: lineResult.get().len)
        else:
          editor.editorState.cursor = CursorPos(line: lastLine, col: 0)
          editor.editorService.cursor = CursorPos(line: lastLine, col: 0)
      if not isShiftPressed:
        editor.editorState.selection.active = false
    else:
      # End - Go to line end
      let lineResult = editor.editorService.document.getLine(editor.editorState.cursor.line)
      if lineResult.isOk:
        editor.editorState.cursor.col = lineResult.get().len
      if not isShiftPressed:
        editor.editorState.selection.active = false
    editor.isDirty = true
    return
  of rl.KeyboardKey.PageUp.int32: # Page Up
    let pageLinesUp = max(1, editor.editorState.visibleLines - 1)
    editor.editorState.cursor.line = max(0, editor.editorState.cursor.line - pageLinesUp)
    if not isShiftPressed:
      editor.editorState.selection.active = false
    editor.isDirty = true
    return
  of rl.KeyboardKey.PageDown.int32: # Page Down
    let pageLinesDown = max(1, editor.editorState.visibleLines - 1)
    let maxLine = if editor.editorService.document != nil: editor.editorService.document.lineCount() - 1 else: 0
    editor.editorState.cursor.line = min(maxLine, editor.editorState.cursor.line + pageLinesDown)
    if not isShiftPressed:
      editor.editorState.selection.active = false
    editor.isDirty = true
    return
  of rl.KeyboardKey.Left.int32: # Left arrow
    if isCtrlPressed:
      # Ctrl+Left - Move by word
      editor.editorService.cursor = editor.editorState.cursor
      discard editor.editorService.moveCursorLeftByWord()
      editor.editorState.cursor = editor.editorService.cursor
    else:
      # Regular left movement
      if editor.editorState.cursor.col > 0:
        editor.editorState.cursor.col.dec
      elif editor.editorState.cursor.line > 0:
        editor.editorState.cursor.line.dec
        let lineResult = editor.editorService.document.getLine(editor.editorState.cursor.line)
        if lineResult.isOk:
          editor.editorState.cursor.col = lineResult.get().len
    if not isShiftPressed:
      editor.editorState.selection.active = false
    editor.isDirty = true
    return
  of rl.KeyboardKey.Right.int32: # Right arrow
    if isCtrlPressed:
      # Ctrl+Right - Move by word
      editor.editorService.cursor = editor.editorState.cursor
      discard editor.editorService.moveCursorRightByWord()
      editor.editorState.cursor = editor.editorService.cursor
    else:
      # Regular right movement
      let lineResult = editor.editorService.document.getLine(editor.editorState.cursor.line)
      if lineResult.isOk:
        let line = lineResult.get()
        if editor.editorState.cursor.col < line.len:
          editor.editorState.cursor.col.inc
        elif editor.editorState.cursor.line < editor.editorService.document.lineCount() - 1:
          editor.editorState.cursor.line.inc
          editor.editorState.cursor.col = 0
    if not isShiftPressed:
      editor.editorState.selection.active = false
    editor.isDirty = true
    return

  of rl.KeyboardKey.Delete.int32: # Delete
    if isCtrlPressed:
      # Ctrl+Delete - Delete word to the right
      # TODO: Implement word deletion in EditorService
      # For now, just use regular character deletion
      editor.editorService.cursor = editor.editorState.cursor
      discard editor.editorService.deleteChar(forward = true)
      editor.editorState.cursor = editor.editorService.cursor
    else:
      # Regular delete
      if editor.editorState.selection.active:
        editor.editorService.selection = editor.editorState.selection
        editor.editorService.cursor = editor.editorState.cursor
        discard editor.editorService.deleteSelection()
        editor.editorState.selection = editor.editorService.selection
        editor.editorState.cursor = editor.editorService.cursor
      else:
        editor.editorService.cursor = editor.editorState.cursor
        discard editor.editorService.deleteChar(forward = true)
        editor.editorState.cursor = editor.editorService.cursor
    editor.invalidateTokens()
    editor.notifyLSPTextChange()
    editor.isDirty = true
    editor.editorState.isModified = true
    editor.editorService.isModified = true
    echo "[DEBUG] Document marked as modified (secondary delete operation)"
    return
  else:
    discard
  
  # Validate cursor position after keyboard input
  if editor.editorService.document != nil:
    let totalLines = editor.editorService.document.lineCount()
    if editor.editorState.cursor.line >= totalLines:
      editor.editorState.cursor.line = max(0, totalLines - 1)
    
    let lineLen = editor.editorService.document.lineLength(editor.editorState.cursor.line)
    if editor.editorState.cursor.col > lineLen:
      editor.editorState.cursor.col = lineLen
    
    # Sync with editor service
    editor.editorService.cursor = editor.editorState.cursor
