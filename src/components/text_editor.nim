## Text Editor Component - UIComponent-based text editor
## Integrates with editor_service.nim for state management and operations
##
## Hover System:
## - Validates LSP content matches the requested symbol (word boundary check)
## - Tracks pending hover requests with symbol name and position
## - Only shows hover if LSP response matches current cursor position
## - Clears hover state when cursor moves to different symbol
## - No fallback hover - if LSP doesn't respond or content doesn't match, shows nothing
## - Prevents stale hover info from previous symbols

import std/[strutils, options, tables, unicode, times, os]
import raylib as rl
import chronos except Result
import results
import ../services/ui_service
import ../services/editor_service
import ../services/language_service
import ../services/component_manager

import ../services/terminal_integration
import ../infrastructure/clipboard
import ../shared/types
import ../shared/text_measurement
import ../shared/constants
import ../infrastructure/rendering/renderer
import ../infrastructure/input/[mouse, input_handler]
from ../infrastructure/input/keyboard import KeyCombination, EditorKey, ModifierKey, InputEventType, ietKeyPressed, ietKeyReleased, ietCharInput, ekEscape, ekLeft, ekRight, ekUp, ekDown, ekBackspace, ekDelete, ekEnter, ekTab, ekA, ekZ, ekY, ekS, mkCtrl, mkSuper
from ../infrastructure/input/keyboard_manager import FocusableComponent, fcTerminal
import ../enhanced_syntax
import ../markdown_code_blocks
import ../domain/document
import ../hover
import text_editor_types
import text_editor_input

import ../shared/constants
import ../infrastructure/ui/cursor_manager
from ../infrastructure/external/lsp_client_async import Location
import ../os_files/dialog
import ./text_editor_types
import ./text_editor_input

# Forward declarations
# updateScrolling moved to text_editor_input.nim
# renderLineNumbers moved to text_editor_input.nim
# renderTextContent moved to text_editor_input.nim
# renderCursor moved to text_editor_input.nim
# renderScrollbar moved to text_editor_input.nim
proc handleInput*(editor: TextEditor, event: UnifiedInputEvent): bool
proc handleMouseInput*(editor: TextEditor, mousePos: rl.Vector2, mouseButton: rl.MouseButton, currentTime: float, modifiers: set[ModifierKey])
proc handleScrollInput*(editor: TextEditor)
# handleTextInput moved to text_editor_input.nim
proc updateSyntaxHighlighting*(editor: TextEditor)
proc getTokensForLine*(editor: TextEditor, lineIndex: int): seq[enhanced_syntax.Token]
proc updateHover*(editor: TextEditor, mousePos: rl.Vector2)
proc renderHover*(editor: TextEditor)
proc syncComponentState*(editor: TextEditor)
proc requestFocus*(editor: TextEditor)
proc handleMouseMovement*(editor: TextEditor, mousePos: rl.Vector2)
# Constructor function for TextEditor
proc newTextEditor*(
  uiService: UIService,
  componentManager: ComponentManager,
  editorService: EditorService,
  languageService: LanguageService,
  clipboardService: ClipboardService,
  terminalIntegration: Option[TerminalIntegration] = none(TerminalIntegration)
): TextEditor =
  ## Create a new TextEditor instance with the given services
  result = TextEditor(
    uiService: uiService,
    componentManager: componentManager,
    editorService: editorService,
    languageService: languageService,
    clipboardService: clipboardService,
    terminalIntegration: terminalIntegration,
    config: defaultTextEditorConfig(),
    editorState: TextEditorState(),
    syntaxHighlighter: newSyntaxHighlighter(enhanced_syntax.langPlainText),
    allTokens: @[],
    tokensValid: false,
    lastTokenizedVersion: 0,
    currentLanguage: enhanced_syntax.langPlainText,
    markdownParser: none(MarkdownCodeBlockRenderer),
    lastUpdateTime: epochTime(),
    cursorBlinkTime: epochTime(),
    cursorVisible: true,
    isMultiCursorMode: false,
    multiCursors: @[],
    clickCount: 0,
    lastClickTime: 0.0,
    lastClickPos: CursorPos(line: 0, col: 0),
    lastSelectedWord: "",
    ctrlDSelections: @[],
    isCtrlHovering: false,
    ctrlHoverSymbol: "",
    ctrlHoverPosition: CursorPos(line: 0, col: 0),
    hoverStartTime: 0.0,
    lastHoverRequestTime: 0.0,
    lastMousePos: rl.Vector2(x: 0, y: 0),
    lastMouseMoveTime: 0.0
  )
  

  
  # Initialize unique ID for the component
  result.id = "textEditor_" & $(cast[int](result))
  
  # Register with component manager
  let registrationResult = componentManager.registerComponent(result.id, result)
  if registrationResult.isErr:
    echo "Warning: Failed to register text editor component: ", registrationResult.error
  


# Token types that should not trigger hover functionality
const InvalidHoverTokenTypes* = {
  enhanced_syntax.ttComment,
  enhanced_syntax.ttTodoComment,
  enhanced_syntax.ttOperator,
  enhanced_syntax.ttText,
  enhanced_syntax.ttLineNumber,
  enhanced_syntax.ttExportMark,
  enhanced_syntax.ttStringLit,
  enhanced_syntax.ttNumberLit,
  enhanced_syntax.ttKeyword,
  enhanced_syntax.ttType # Type names often don't have useful hover info
}

# Hover timing constants
# HOVER_REQUEST_DEBOUNCE_MS moved to shared/constants.nim to avoid duplication

# Symbol detection utility
proc detectSymbol*(line: string, charIndex: int): tuple[symbol: string, start: int, `end`: int] =
  ## Detects the symbol at the given character index in a line
  ## Returns the symbol text and its start/end positions
  
  if line.len == 0 or charIndex < 0 or charIndex >= line.len:
    return ("", 0, 0)
    
  # Find symbol start - alphanumeric characters and underscores
  var startPos = charIndex
  while startPos > 0 and ((line[startPos-1] in {'a'..'z', 'A'..'Z', '0'..'9'}) or line[startPos-1] == '_'):
    dec startPos
    
  # Find symbol end
  var endPos = charIndex
  while endPos < line.len and ((line[endPos] in {'a'..'z', 'A'..'Z', '0'..'9'}) or line[endPos] == '_'):
    inc endPos
    
  # Handle case where we're at a non-symbol character
  if startPos == endPos:
    return ("", 0, 0)
    
  let symbolText = line[startPos ..< endPos]
  return (symbolText, startPos, endPos)

# Helper function for terminal bounds checking
proc isMouseOverTerminal*(editor: TextEditor, mousePos: rl.Vector2): bool =
  ## Check if mouse is over terminal area, considering actual terminal state
  if not editor.terminalIntegration.isSome:
    return false
  
  let terminalIntegration = editor.terminalIntegration.get()
  
  # Check if mouse is within terminal bounds
  let mouseInTerminal = mousePos.x >= terminalIntegration.bounds.x and 
                       mousePos.x <= terminalIntegration.bounds.x + terminalIntegration.bounds.width and
                       mousePos.y >= terminalIntegration.bounds.y and 
                       mousePos.y <= terminalIntegration.bounds.y + terminalIntegration.bounds.height
  
  # Only consider terminal "open" if it's actually visible
  return mouseInTerminal and terminalIntegration.isActuallyVisible()

# Unified input handling for ComponentManager integration
proc handleInput*(editor: TextEditor, event: UnifiedInputEvent): bool =
  ## Handle unified input events for the text editor
  if editor == nil or editor.editorState == nil:
    return false
    
  if not editor.editorState.isFocused:
    return false
    
  # Update state from unified input system
  case event.kind:
  of uiekMouse:
    let mouseEvent = event.mouseEvent
    editor.lastMousePos = rl.Vector2(x: mouseEvent.position.x, y: mouseEvent.position.y)
    editor.lastModifierState = (mkCtrl in mouseEvent.modifiers) or (mkSuper in mouseEvent.modifiers)
  of uiekKeyboard:
    let keyEvent = event.keyEvent
    editor.lastModifierState = (mkCtrl in keyEvent.modifiers) or (mkSuper in keyEvent.modifiers)
  of uiekCombined:
    let keyCombo = event.keyCombo
    editor.lastModifierState = (mkCtrl in keyCombo.modifiers) or (mkSuper in keyCombo.modifiers)
  else:
    discard
  
  # Check if terminal is visible and covering the text editor area
  if editor.terminalIntegration.isSome:
    let terminalIntegration = editor.terminalIntegration.get()
    if terminalIntegration.isActuallyVisible():
      # Check if the event is in the terminal area
      case event.kind:
      of uiekMouse:
        let mouseEvent = event.mouseEvent
        let mousePos = rl.Vector2(x: mouseEvent.position.x, y: mouseEvent.position.y)
        
        # Check if mouse is over terminal area
        let mouseInTerminal = mousePos.x >= terminalIntegration.bounds.x and 
                             mousePos.x <= terminalIntegration.bounds.x + terminalIntegration.bounds.width and
                             mousePos.y >= terminalIntegration.bounds.y and 
                             mousePos.y <= terminalIntegration.bounds.y + terminalIntegration.bounds.height
        
        if mouseInTerminal:
          # Don't handle input if mouse is over terminal area
          return false
      of uiekKeyboard:
        # For keyboard events, check if terminal has focus
        if terminalIntegration.getCurrentFocus() == fcTerminal:
          # Don't handle keyboard input if terminal has focus
          return false
      else:
        discard
  
  case event.kind:
  of uiekMouse:
    let mouseEvent = event.mouseEvent
    let mousePos = editor.lastMousePos
    
    case mouseEvent.eventType:
    of metMoved:
      # Handle mouse movement for hover and cursor updates
      # Check if mouse is over terminal area before updating hover
      if editor.terminalIntegration.isSome:
        if editor.isMouseOverTerminal(mousePos):
          # Don't update hover if mouse is over terminal area
          return false
      
      # Check if modifier keys are pressed before calling updateHover
      let isDefinitionModifierPressed = editor.lastModifierState
      
      # Always update hover on mouse movement regardless of modifiers
      # This ensures hover works for regular text as well
      editor.updateHover(mousePos)
      
      # Handle mouse movement for cursor updates
      let mouseInEditor = mousePos.x >= editor.bounds.x and 
                         mousePos.x <= editor.bounds.x + editor.bounds.width and
                         mousePos.y >= editor.bounds.y and 
                         mousePos.y <= editor.bounds.y + editor.bounds.height
      
      if mouseInEditor:
        editor.handleMouseMovement(mousePos)
      
      # Return false to allow other components to also process mouse movement
      return false
    of metButtonPressed:
      let currentTime = rl.getTime()
      if mouseEvent.button == mbLeft:
        editor.handleMouseInput(mousePos, rl.MouseButton.Left, currentTime, mouseEvent.modifiers)
        return true
      elif mouseEvent.button == mbRight:
        editor.handleMouseInput(mousePos, rl.MouseButton.Right, currentTime, mouseEvent.modifiers)
        return true
    of metButtonReleased:
      # Handle button release if needed
      return true
    of metScrolled:
      # Handle scroll wheel input
      const SCROLL_SPEED = 3.0  # Scroll speed in lines
      let scrollLines = mouseEvent.scrollDelta.y * SCROLL_SPEED
      editor.editorState.scrollOffset = max(0, int(editor.editorState.scrollOffset.float32 - scrollLines))
      editor.updateScrolling()
      # Force immediate scroll bounds validation
      editor.editorState.scrollOffset = max(0, min(editor.editorState.scrollOffset, editor.editorState.maxScrollOffset))
      return true
    else:
      return false
  of uiekKeyboard:
    let keyEvent = event.keyEvent
    
    case keyEvent.eventType:
    of ietCharInput:
      # Handle character input
      if keyEvent.character.int32 > 0:
        let charStr = $char(keyEvent.character.int32)
        editor.handleTextInput(charStr)
        return true
    of ietKeyPressed:
      # Handle key presses for all keyboard shortcuts
      let modifiers = keyEvent.modifiers
      
      # Sync state before operation
      editor.editorService.cursor = editor.editorState.cursor
      editor.editorService.selection = editor.editorState.selection
      
      # Handle keyboard shortcuts
      case keyEvent.key:
      of ekEscape:
        if editor.editorState.selection.active:
          editor.editorState.selection.active = false
          editor.isDirty = true
        else:
          editor.editorState.showHover = false
        return true
        
      of ekLeft:
        discard editor.editorService.moveCursorLeft()
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.isDirty = true
        return true
        
      of ekRight:
        discard editor.editorService.moveCursorRight()
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.isDirty = true
        return true
        
      of ekUp:
        discard editor.editorService.moveCursorUp()
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.isDirty = true
        return true
        
      of ekDown:
        discard editor.editorService.moveCursorDown()
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.isDirty = true
        return true
        
      of ekBackspace:
        if editor.editorState.selection.active:
          discard editor.editorService.deleteSelection()
        else:
          discard editor.editorService.deleteChar(forward = false)
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.invalidateTokens()
        editor.notifyLSPTextChange()
        editor.isDirty = true
        editor.editorState.isModified = true
        editor.editorService.isModified = true
        return true
        
      of ekDelete:
        if editor.editorState.selection.active:
          discard editor.editorService.deleteSelection()
        else:
          discard editor.editorService.deleteChar(forward = true)
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.invalidateTokens()
        editor.notifyLSPTextChange()
        editor.isDirty = true
        editor.editorState.isModified = true
        editor.editorService.isModified = true
        return true
        
      of ekEnter:
        discard editor.editorService.insertText("\n")
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.invalidateTokens()
        editor.notifyLSPTextChange()
        editor.isDirty = true
        editor.editorState.isModified = true
        editor.editorService.isModified = true
        return true
        
      of ekTab:
        discard editor.editorService.insertText("  ")  # Insert 2 spaces for tab
        editor.editorState.cursor = editor.editorService.cursor
        editor.editorState.selection = editor.editorService.selection
        editor.invalidateTokens()
        editor.notifyLSPTextChange()
        editor.isDirty = true
        editor.editorState.isModified = true
        editor.editorService.isModified = true
        return true
        
      of ekA:
        if mkCtrl in modifiers:
          # Ctrl+A to select all
          if editor.editorService.document != nil:
            let lineCount = editor.editorService.document.lineCount()
            if lineCount > 0:
              let lastLineResult = editor.editorService.document.getLine(lineCount - 1)
              if lastLineResult.isOk:
                let lastLineLen = lastLineResult.get().len
                editor.editorState.selection.start = CursorPos(line: 0, col: 0)
                editor.editorState.selection.finish = CursorPos(line: lineCount - 1, col: lastLineLen)
                editor.editorState.selection.active = true
                editor.editorService.selection = editor.editorState.selection
                editor.isDirty = true
          return true
          
      of ekZ:
        if mkCtrl in modifiers:
          # Ctrl+Z to undo
          discard editor.editorService.undo()
          editor.editorState.cursor = editor.editorService.cursor
          editor.editorState.selection = editor.editorService.selection
          editor.invalidateTokens()
          editor.notifyLSPTextChange()
          editor.isDirty = true
          editor.editorState.isModified = true
          editor.editorService.isModified = true
          return true
          
      of ekY:
        if mkCtrl in modifiers:
          # Ctrl+Y to redo
          discard editor.editorService.redo()
          editor.editorState.cursor = editor.editorService.cursor
          editor.editorState.selection = editor.editorService.selection
          editor.invalidateTokens()
          editor.notifyLSPTextChange()
          editor.isDirty = true
          editor.editorState.isModified = true
          editor.editorService.isModified = true
          return true
          
      of ekS:
        if mkCtrl in modifiers:
          # Ctrl+S to save
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
                  editor.isDirty = true
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
              let filePath = editor.editorService.currentFile.get()
              let saveResult = editor.editorService.saveFile(filePath)
              if saveResult.isOk:
                editor.editorState.isModified = false
                editor.editorService.isModified = false
                editor.isDirty = true
                # Notify FileTabBar to update modified indicator via UI event
                let saveEvent = UIEvent(
                  eventType: uetClick,
                  componentId: editor.id,
                  data: {"action": "document_saved"}.toTable(),
                  timestamp: times.getTime(),
                  handled: false
                )
                editor.uiService.queueEvent(saveEvent)
              else:
                echo "Failed to save file: ", saveResult.error
          return true
          
      else:
        return false
    else:
      return false
  of uiekCombined:
    # Combined events don't handle scroll - scroll is handled by mouse events
    return false
  
  return false



# Cursor validation helper functions
proc setCursorPosition*(editor: TextEditor, cursor: CursorPos) =
  ## Set cursor position with validation to ensure it's within document bounds
  if editor.editorService.document != nil:
    let validated = validateCursorPosition(cursor, editor.editorService.document)
    editor.editorState.cursor = validated
    # Also sync with editor service
    editor.editorService.cursor = validated
  else:
    editor.editorState.cursor = CursorPos(line: 0, col: 0)
    editor.editorService.cursor = CursorPos(line: 0, col: 0)

proc setCursorPositionUnsafe*(editor: TextEditor, cursor: CursorPos) =
  ## Set cursor position without validation (for internal use when position is already known to be valid)
  editor.editorState.cursor = cursor

# validateCurrentCursor moved to text_editor_input.nim

proc getClickCount*(editor: TextEditor, currentTime: float64): int =
  ## Get the current click count for multi-click detection
  const DOUBLE_CLICK_TIME = 0.5 # 500ms for double click
  if currentTime - editor.lastClickTime < DOUBLE_CLICK_TIME:
    editor.clickCount += 1
  else:
    editor.clickCount = 1
  editor.lastClickTime = currentTime
  return editor.clickCount

# Core functionality
proc initialize*(editor: TextEditor) =
  ## Initialize the text editor
  editor.updateScrolling()
  editor.syncComponentState()
  discard editor.uiService.setComponentState(editor.id, csVisible)

# Unicode-safe helper functions for text measurement and positioning
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

# measureTextSafe moved to text_editor_input.nim

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

# updateScrolling moved to text_editor_input.nim

# renderLineNumbers moved to text_editor_input.nim

# renderTextContent moved to text_editor_input.nim

# renderCursor moved to text_editor_input.nim

# renderScrollbar moved to text_editor_input.nim

# Input handling
proc handleMouseMovement*(editor: TextEditor, mousePos: rl.Vector2) =
  ## Handle mouse movement for cursor shape changes
  let textStartX = editor.bounds.x + editor.config.padding +
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0) -
    editor.editorState.scrollX
  let textStartY = editor.bounds.y + editor.config.padding
  
  # Check if mouse is in text area and set cursor shape
  let inTextArea = mousePos.x >= textStartX and
    mousePos.x <= editor.bounds.x + editor.bounds.width -
    (if editor.config.showScrollbar: editor.config.scrollbarWidth else: 0.0) and
    mousePos.y >= textStartY and
    mousePos.y <= editor.bounds.y + editor.bounds.height - editor.config.padding
  
  if inTextArea:
    requestTextCursor("text_editor_text_area") # Change mouse cursor to I-beam when over text
  else:
    clearCursorRequest("text_editor_text_area") # Reset mouse cursor when not over text

# Forward declaration for Go to Definition
proc handleGoToDefinition*(editor: TextEditor, cursorPos: CursorPos)

proc handleMouseInput*(editor: TextEditor, mousePos: rl.Vector2, mouseButton: rl.MouseButton, currentTime: float, modifiers: set[ModifierKey]) =
  ## Handle mouse input for the text editor with enhanced selection
  # Check if mouse is within editor bounds
  if not (mousePos.x >= editor.bounds.x and mousePos.x <= editor.bounds.x + editor.bounds.width and
          mousePos.y >= editor.bounds.y and mousePos.y <= editor.bounds.y + editor.bounds.height):
    return
  
  let textStartX = editor.bounds.x + editor.config.padding +
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0) -
    editor.editorState.scrollX
  let relativeX = mousePos.x - textStartX
  let line = int((mousePos.y - editor.bounds.y - editor.config.padding) /
    editor.config.lineHeight) + editor.editorState.scrollOffset


  # Calculate column position using unified accurate text measurement with comprehensive error handling
  var col = 0

  # Get the actual line text for accurate measurement
  if editor.editorService.document != nil and line >= 0 and line < editor.editorService.document.lineCount():
    let lineResult = editor.editorService.document.getLine(line)
    if lineResult.isOk:
      let lineText = lineResult.get()
      let textMeasurement = newTextMeasurement(editor.font, editor.config.fontSize, 1.0, editor.config.charWidth)
      col = textMeasurement.findPositionFromWidth(lineText, relativeX)
    else:
      # Invalid line number - use fallback
      col = max(0, int(relativeX / editor.config.charWidth))
  else:
    # Invalid line number - use fallback
    col = max(0, int(relativeX / editor.config.charWidth))

  let newCursor = CursorPos(line: line, col: col)

  # Validate cursor position before using it
  let validatedCursor = if editor.editorService.document != nil:
    validateCursorPosition(newCursor, editor.editorService.document)
  else:
    CursorPos(line: 0, col: 0)

  if mouseButton == rl.MouseButton.Left:
    let isAltPressed = mkAlt in modifiers
    let isCtrlPressed = mkCtrl in modifiers
    let isCmdPressed = mkSuper in modifiers
    let isDefinitionModifierPressed = isCtrlPressed or isCmdPressed

    # Request focus when text editor is clicked
    editor.requestFocus()

    # Always handle mouse press (unified input system handles press detection)
    # Reset cursor blinking on interaction
    editor.cursorBlinkTime = currentTime
    editor.cursorVisible = true

    # Handle click count for different actions
    let clickCount = editor.getClickCount(currentTime)
    case clickCount
    of 1: # Single click
      # Handle Ctrl+Click (or Cmd+Click) for Go to Definition
      if isDefinitionModifierPressed:
        # Check if mouse is over terminal panel before handling Go to Definition
        if editor.terminalIntegration.isSome and editor.isMouseOverTerminal(mousePos):
          return
        editor.handleGoToDefinition(validatedCursor)
      else:
        # Clear multi-cursor mode if not using Alt
        if not isAltPressed:
          editor.isMultiCursorMode = false
          editor.multiCursors = @[]

        editor.setCursorPosition(validatedCursor)
        editor.editorState.selection.active = false
        editor.editorState.isDragging = false
        editor.editorState.dragStartPos = newCursor
        # Clear Ctrl+D state on single click
        editor.lastSelectedWord = ""
        editor.ctrlDSelections = @[]
    of 2: # Double click - select word
      # Clear multi-cursor mode for double-click
      editor.isMultiCursorMode = false
      editor.multiCursors = @[]

      editor.editorService.cursor = validatedCursor
      discard editor.editorService.selectWord()
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
    of 3: # Triple click - select line
      # Clear multi-cursor mode for triple-click
      editor.isMultiCursorMode = false
      editor.multiCursors = @[]

      editor.editorService.cursor = validatedCursor
      discard editor.editorService.selectLine()
      editor.editorState.selection = editor.editorService.selection
      editor.editorState.cursor = editor.editorService.cursor
    else:
      # Single click behavior for higher click counts
      editor.setCursorPosition(validatedCursor)
      editor.editorState.selection.active = false
      editor.editorState.isDragging = false
      editor.editorState.dragStartPos = newCursor

    editor.isDirty = true

proc notifyLSPTextChange*(editor: TextEditor) =
  ## Notify LSP about text changes in the current document (now handled by language service)
  if editor.languageService == nil:
    return
  
  if editor.editorService.currentFile.isNone or editor.editorService.document == nil:
    return
  
  let filePath = editor.editorService.currentFile.get()
  
  # Get current document content
  var documentContent = ""
  let totalLines = editor.editorService.document.lineCount()
  for i in 0 ..< totalLines:
    let lineResult = editor.editorService.document.getLine(i)
    if lineResult.isOk:
      if documentContent.len > 0:
        documentContent.add "\n"
      documentContent.add lineResult.get()
  
  discard editor.languageService.updateDocument(filePath, documentContent)
  
  # Clear any existing hover since content changed
  editor.editorState.showHover = false
  editor.editorState.hoverInfo = none(HoverInfo)

# handleTextInput moved to text_editor_input.nim

proc tokenizeMarkdownWithCodeBlocks*(editor: TextEditor, text: string): seq[
    enhanced_syntax.Token] =
  ## Simple markdown tokenizer that highlights code blocks
  var renderer = newMarkdownCodeBlockRenderer(text)
  renderer.parseCodeBlocks()
  let tokens = renderer.renderMarkdownWithCodeBlocks()
  return tokens

proc tokenizeFullDocument*(editor: TextEditor) =
  ## Tokenize the entire document and cache the results
  if editor.editorService.document == nil:
    editor.allTokens = @[]
    editor.tokensValid = true
    editor.lastTokenizedVersion = 0
    return

  # For large files, use lazy tokenization - only tokenize visible lines
  # This dramatically improves performance for large files
  let totalLines = editor.editorService.document.lineCount()
  if totalLines > 1000: # Threshold for large files
    # Just mark as valid but don't actually tokenize - will tokenize on-demand
    editor.allTokens = @[]
    editor.tokensValid = true
    editor.lastTokenizedVersion = editor.editorService.document.version
    return

  # For smaller files, use full tokenization
  # Get full document text
  var fullText = ""
  for i in 0 ..< totalLines:
    let lineResult = editor.editorService.document.getLine(i)
    if lineResult.isOk:
      if i > 0:
        fullText.add('\n')
      fullText.add(lineResult.get())

  # Tokenize the full document
  # Check if this is a markdown file for code block highlighting
  if editor.currentLanguage == enhanced_syntax.langMarkdown:
    editor.allTokens = editor.tokenizeMarkdownWithCodeBlocks(fullText)
  else:
    editor.allTokens = editor.syntaxHighlighter.tokenize(fullText)

  editor.tokensValid = true
  editor.lastTokenizedVersion = editor.editorService.document.version

proc getTokensForLine*(editor: TextEditor, lineIndex: int): seq[
    enhanced_syntax.Token] =
  ## Get tokens that belong to a specific line from cached full-document tokens
  if not editor.tokensValid or editor.editorService.document == nil:
    return @[]

  # Check if we're using lazy tokenization (large files)
  if editor.allTokens.len == 0 and editor.editorService.document.lineCount() > 1000:
    # For large files, tokenize just this line on-demand
    let lineResult = editor.editorService.document.getLine(lineIndex)
    if lineResult.isErr:
      return @[]

    let lineContent = lineResult.get()
    return editor.syntaxHighlighter.tokenize(lineContent)

  # For smaller files, use the cached full-document tokens
  # Calculate character position of the start of this line
  var lineStartPos = 0
  for i in 0 ..< lineIndex:
    let lineResult = editor.editorService.document.getLine(i)
    if lineResult.isOk:
      lineStartPos += lineResult.get().len + 1 # +1 for newline

  # Get line length
  let lineResult = editor.editorService.document.getLine(lineIndex)
  if lineResult.isErr:
    return @[]

  let lineContent = lineResult.get()
  let lineLength = lineContent.len
  let lineEndPos = lineStartPos + lineLength

  # Find tokens that overlap with this line
  result = @[]
  for token in editor.allTokens:
    let tokenStart = token.start
    let tokenEnd = token.start + token.length

    # Check if token overlaps with current line
    if tokenStart < lineEndPos and tokenEnd > lineStartPos:
      # Calculate the portion of the token that appears on this line
      let textStart = max(0, tokenStart - lineStartPos)
      let textEnd = min(lineLength, tokenEnd - lineStartPos)

      if textStart < textEnd and textStart < lineContent.len and
          textEnd <= lineContent.len:
        # Create a token with line-relative positioning
        var lineToken = token
        lineToken.text = lineContent[textStart ..< textEnd]
        lineToken.start = textStart
        lineToken.length = textEnd - textStart
        result.add(lineToken)

# Helper function for Unicode identifier detection
proc isIdentifierRune(rune: Rune): bool =
  ## Check if a rune can be part of an identifier (Unicode-aware)
  rune.isAlpha() or ('0'.Rune <=% rune and rune <=% '9'.Rune) or
  rune == '_'.Rune or rune == '.'.Rune or rune == ':'.Rune or
  rune == '$'.Rune or rune == '@'.Rune or rune == '!'.Rune or rune == '?'.Rune

# Enhanced hover calculation function with comprehensive error handling
proc calculateHoverInfo*(
    editor: TextEditor,
    mousePos: rl.Vector2
): tuple[
  isValid: bool,
  lineIndex: int,
  charIndex: int,
  symbol: string,
  symbolStart: int,
  symbolEnd: int,
  screenX: float32,
  screenY: float32
] =
  ## Calculate hover information from mouse position
  ## Returns hover validity and symbol information

  # Check if mouse is within editor bounds
  if mousePos.x < editor.bounds.x or mousePos.x > editor.bounds.x + editor.bounds.width or
     mousePos.y < editor.bounds.y or mousePos.y > editor.bounds.y + editor.bounds.height:
    return (false, 0, 0, "", 0, 0, 0.0, 0.0)

  # Calculate line index from mouse position
  let textStartY = editor.bounds.y + editor.config.padding
  let relativeY = mousePos.y - textStartY
  let lineIndex = int(relativeY / editor.config.lineHeight) + editor.editorState.scrollOffset

  # Validate line index
  if lineIndex < 0:
    return (false, lineIndex, 0, "", 0, 0, 0.0, 0.0)

  if editor.editorService.document == nil or lineIndex >= editor.editorService.document.lineCount():
    return (false, lineIndex, 0, "", 0, 0, 0.0, 0.0)

  let lineResult = editor.editorService.document.getLine(lineIndex)
  if lineResult.isErr:
    return (false, lineIndex, 0, "", 0, 0, 0.0, 0.0)

  let line = lineResult.get()

  # Calculate character index from mouse position using proper text measurement
  let textStartX = editor.bounds.x + editor.config.padding +
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0)
  let relativeX = mousePos.x - textStartX
  
  # Use proper text measurement instead of simple division
  var charIndex = 0
  var bestDistance = 1000.0
  for i in 0 .. line.len:
    let textPart = if i > 0: line[0 ..< i] else: ""
    let textWidth = measureTextSafe(editor.font, textPart, editor.config.fontSize, 1.0).x
    let distance = abs(relativeX - textWidth)
    if distance < bestDistance:
      bestDistance = distance
      charIndex = i
  
  let safeCharIndex = max(0, charIndex)

  # Detect symbol at position
  let symbolInfo = detectSymbol(line, safeCharIndex)
  if symbolInfo.symbol.len == 0:
    return (false, lineIndex, safeCharIndex, "", 0, 0, 0.0, 0.0)

  # Calculate screen coordinates
  let symbolStartText = if symbolInfo.start > 0: line[0 ..< symbolInfo.start] else: ""
  let symbolWidth = measureTextSafe(editor.font, symbolStartText, editor.config.fontSize, 1.0).x
  let screenX = textStartX + symbolWidth
  let screenY = textStartY + (lineIndex - editor.editorState.scrollOffset).float32 * editor.config.lineHeight

  return (true, lineIndex, safeCharIndex, symbolInfo.symbol,
      symbolInfo.start, symbolInfo.`end`, screenX, screenY)

proc updateHover*(editor: TextEditor, mousePos: rl.Vector2) =
  ## Enhanced hover with comprehensive error handling and improved state management
  
  # Check if mouse is over terminal area
  if editor.terminalIntegration.isSome:
    let terminalIntegration = editor.terminalIntegration.get()
    if terminalIntegration.isActuallyVisible():
      let mouseInTerminal = mousePos.x >= terminalIntegration.bounds.x and 
                           mousePos.x <= terminalIntegration.bounds.x + terminalIntegration.bounds.width and
                           mousePos.y >= terminalIntegration.bounds.y and 
                           mousePos.y <= terminalIntegration.bounds.y + terminalIntegration.bounds.height
      if mouseInTerminal:
    
        # Don't update hover if mouse is over terminal area
        # Clear any existing hover state
        if editor.editorState.showHover:
          editor.editorState.showHover = false
          editor.editorState.hoverInfo = none(HoverInfo)
          editor.editorState.hoverActiveSymbol = ""
          editor.editorState.pendingHoverRequest = false
          if editor.languageService != nil:
            editor.languageService.clearHover()
        return
      else:
        discard
    
  else:
    discard
    
  let currentTime = rl.getTime()

  # Safe hover info calculation with error handling
  var hoverInfo: tuple[
    isValid: bool,
    lineIndex: int,
    charIndex: int,
    symbol: string,
    symbolStart: int,
    symbolEnd: int,
    screenX: float32,
    screenY: float32
  ]

  hoverInfo = editor.calculateHoverInfo(mousePos)

  # If not hovering over a valid symbol
  if not hoverInfo.isValid:
    # Clear hover immediately when not over valid symbol
    if editor.editorState.showHover:
      editor.editorState.showHover = false
      editor.editorState.hoverInfo = none(HoverInfo)
      editor.editorState.hoverActiveSymbol = ""
      # Only clear pending request if we're not waiting for a response
      # This prevents interrupting legitimate pending requests
      if not editor.editorState.pendingHoverRequest:
        if editor.languageService != nil:
          discard
    return

  # Update active symbol and timing
  let currentSymbol = hoverInfo.symbol
  let symbolChanged = editor.editorState.lastHoverSymbol != currentSymbol
  # Only consider it a position change if we move to a different line or significantly different column
  # Small movements within the same symbol shouldn't trigger position changes
  let significantPositionChange = 
    editor.editorState.hoverPosition.line != hoverInfo.lineIndex or
    abs(editor.editorState.hoverPosition.col - hoverInfo.symbolStart) > 10  # Allow 10 char tolerance
  let positionChanged = significantPositionChange and symbolChanged

  # Store screen coordinates for consistent rendering
  editor.editorState.hoverScreenPosition = rl.Vector2(x: hoverInfo.screenX,
      y: hoverInfo.screenY)

  # Always set hover position when we have valid hover info
  editor.editorState.hoverPosition = CursorPos(line: hoverInfo.lineIndex,
      col: hoverInfo.symbolStart)

  # Less aggressive state clearing - only clear if we're moving to a completely different symbol
  if symbolChanged or positionChanged:
    # Only clear hover display if we're moving to a different symbol, but keep pending requests
    if symbolChanged:
      editor.editorState.showHover = false
      editor.editorState.hoverInfo = none(HoverInfo)

    editor.editorState.lastHoverSymbol = currentSymbol
    # Don't immediately cancel pending requests - let them complete naturally
    inc editor.editorState.hoverRequestId
    editor.hoverStartTime = currentTime

  editor.editorState.hoverActiveSymbol = currentSymbol
  editor.editorState.lastHoverTime = currentTime

  # Improved debouncing logic to handle rapid mouse movements
  let timeSinceLastRequest = currentTime -
      editor.editorState.lastHoverRequestTime
  let shouldDebounce = timeSinceLastRequest < (HOVER_REQUEST_DEBOUNCE_MS / 1000.0)

  let shouldRequest = if symbolChanged or positionChanged:
    true # Always request on symbol/position change
  else:
    # For same symbol and position, respect debounce timing
    not shouldDebounce and not editor.editorState.pendingHoverRequest

  if shouldRequest and editor.languageService != nil:

    let filePath = editor.editorService.currentFile

    if filePath.isSome:
      editor.editorState.lastHoverRequestTime = currentTime
      editor.editorState.pendingHoverRequest = true

      # Update the language service's current request tracking with the actual symbol
      if editor.languageService != nil:
        editor.languageService.updateCurrentHoverRequest(currentSymbol, CursorPos(line: hoverInfo.lineIndex, col: hoverInfo.symbolStart))
      
      echo "DEBUG TextEditor: Sending hover request for symbol: '", currentSymbol, "' at line: ", hoverInfo.lineIndex, ", col: ", hoverInfo.symbolStart
      
      # 发送悬停请求，但不立即清除pending状态
      let success = editor.languageService.requestHover(
        filePath.get(),
        hoverInfo.lineIndex,
        hoverInfo.symbolStart
      )
      echo "DEBUG TextEditor: Hover request sent, success: ", success
  else:
    discard

  # 检查语言服务响应
  if editor.languageService != nil:
    # 轮询语言服务响应
    editor.languageService.performHealthCheck()
    
    let currentHover = editor.languageService.getCurrentHover()
    echo "DEBUG TextEditor: Checking hover response, has content: ", currentHover.isSome
    if currentHover.isSome:
      echo "DEBUG TextEditor: Hover content length: ", currentHover.get().content.len
    
    if currentHover.isSome and currentHover.get().content.len > 0:
      let lspContent = currentHover.get().content

      # 激活悬停显示并清除pending状态
      editor.editorState.showHover = true
      editor.editorState.hoverInfo = currentHover
      editor.editorState.pendingHoverRequest = false
      echo "DEBUG TextEditor: Hover activated with content length: ", lspContent.len
      return
    else:
      # 检查是否超时
      let currentTime = rl.getTime()
      if editor.editorState.pendingHoverRequest and 
         (currentTime - editor.editorState.lastHoverRequestTime) > 3.0:
        # 超时，清除pending状态和相关hover状态
        echo "DEBUG TextEditor: Hover request timed out after 3 seconds"
        editor.editorState.pendingHoverRequest = false
        editor.editorState.showHover = false
        editor.editorState.hoverInfo = none(HoverInfo)
        editor.editorState.hoverActiveSymbol = ""
        if editor.languageService != nil:
          editor.languageService.clearHover()
      elif editor.editorState.pendingHoverRequest:
        echo "DEBUG TextEditor: Waiting for hover response, elapsed: ", (currentTime - editor.editorState.lastHoverRequestTime), "s"

    # 清理状态
    if not editor.editorState.showHover:
      editor.editorState.hoverActiveSymbol = ""
      editor.editorState.lastHoverSymbol = ""
      editor.editorState.hoverPosition = CursorPos(line: -1, col: -1)
      editor.editorState.hoverScreenPosition = rl.Vector2(x: 0, y: 0)

proc renderHover*(editor: TextEditor) =
  ## Enhanced hover rendering with comprehensive error handling
  ## Uses calculated screen coordinates for consistent positioning

  if not editor.editorState.showHover or editor.editorState.hoverInfo.isNone:
    return

  # Validate font availability
  if editor.font == nil:
    return

  let hoverInfo = editor.editorState.hoverInfo.get()

  # Validate hover content
  if hoverInfo.content.len == 0:
    return

  # Use stored screen coordinates for consistent rendering
  let symbolScreenX = editor.editorState.hoverScreenPosition.x
  let symbolScreenY = editor.editorState.hoverScreenPosition.y

  # Calculate screen coordinates for positioning
  let lineNumberWidth = if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0
  let textStartX = editor.bounds.x + editor.config.padding + lineNumberWidth
  let textStartY = editor.bounds.y + editor.config.padding

  # Use stored hover position for calculation
  let hoverLine = editor.editorState.hoverPosition.line
  let hoverCol = editor.editorState.hoverPosition.col

  # Calculate screen coordinates for the hover symbol
  var finalScreenX = textStartX
  var finalScreenY = textStartY + (hoverLine - editor.editorState.scrollOffset).float32 * editor.config.lineHeight

  if editor.editorService.document != nil and hoverLine >= 0 and hoverLine <
      editor.editorService.document.lineCount():
    let lineResult = editor.editorService.document.getLine(hoverLine)
    if lineResult.isOk:
      let line = lineResult.get()
      let charPos = min(max(hoverCol, 0), line.len)

      if charPos > 0 and charPos <= line.len:
        let textBeforeCursor = line[0 ..< charPos]
        let textWidth = rl.measureText(editor.font[], textBeforeCursor, editor.config.fontSize, 1.0).x
        finalScreenX = textStartX + textWidth

  # Get screen bounds for positioning
  let windowWidth = rl.getScreenWidth().float32
  let windowHeight = rl.getScreenHeight().float32

  # Validate screen bounds
  if windowWidth <= 0 or windowHeight <= 0:
    return

  # Calculate hover window position with bounds checking
  let hoverOffset = 8.0
  let estimatedHoverWidth = 350.0 # Reasonable estimate
  let estimatedHoverHeight = 150.0 # Reasonable estimate
  let marginSize = 15.0

  var hoverX = finalScreenX + hoverOffset
  var hoverY = finalScreenY - 25.0 # Default: above the symbol

  # Bounds checking for tooltip placement to prevent off-screen rendering

  # Horizontal bounds checking
  if hoverX + estimatedHoverWidth > windowWidth - marginSize:
    hoverX = finalScreenX - estimatedHoverWidth - hoverOffset # Position to the left instead
    # Ensure it doesn't go off the left edge
    if hoverX < marginSize:
      hoverX = marginSize

  # Ensure minimum left margin
  if hoverX < marginSize:
    hoverX = marginSize

  # Vertical bounds checking
  if hoverY < marginSize:
    hoverY = finalScreenY + editor.config.lineHeight + hoverOffset # Below symbol instead
  
  # Ensure it doesn't go off the bottom
  if hoverY + estimatedHoverHeight > windowHeight - marginSize:
    hoverY = windowHeight - estimatedHoverHeight - marginSize
    # If still too high, position above the symbol
    if hoverY < marginSize:
      hoverY = finalScreenY - estimatedHoverHeight - hoverOffset
      # Final fallback - center vertically
      if hoverY < marginSize:
        hoverY = (windowHeight - estimatedHoverHeight) / 2.0

  # Final position for hover window
  let hoverPos = rl.Vector2(x: hoverX, y: hoverY)

  # Render hover content directly
  drawVSCodeHover(
    hoverInfo,
    hoverPos,
    windowWidth.int32,
    windowHeight.int32,
    editor.font[],
    editor.syntaxHighlighter,
    editor.config.fontSize,
  )


proc handleGoToDefinition*(editor: TextEditor, cursorPos: CursorPos) =
  ## Handle Ctrl+Click for Go to Definition functionality
  if editor.languageService.isNil:
    return
  if editor.editorService.currentFile.isNone:
    return
  let filePath = editor.editorService.currentFile.get()
  
  # Get the line content first
  if editor.editorService.document == nil:
    return
  
  let lineResult = editor.editorService.document.getLine(cursorPos.line)
  if lineResult.isErr:
    return
  
  let line = lineResult.get()
  
  # Get the symbol at the cursor position
  let symbolInfo = detectSymbol(line, cursorPos.col)
  let symbol = symbolInfo.symbol
  
  if symbol.len == 0:
    return
  # Request definition from language service
  let success = editor.languageService.requestDefinition(
    filePath, 
    cursorPos.line, 
    cursorPos.col, 
    symbol
  )
  
  if not success:
    discard


proc navigateToDefinition*(editor: TextEditor, location: Location) =
  ## Navigate to a definition location, opening the file if necessary
  
  # Parse the URI to get the file path
  var filePath = location.uri
  if filePath.startsWith("file://"):
    filePath = filePath[7..^1]  # Remove "file://" prefix
  
  # Check if we need to open a different file
  let currentFile = editor.editorService.currentFile
  let needsFileChange = currentFile.isNone or currentFile.get() != filePath
  
  if needsFileChange:
    # Check if file exists
    if not fileExists(filePath):
      return
    
    # Open the target file
    let openResult = editor.editorService.openFile(filePath)
    if openResult.isErr:
      return
    
    # Document is now opened in editor service, refresh editor state
    editor.editorState.cursor = editor.editorService.cursor
    editor.editorState.selection = editor.editorService.selection
    editor.invalidateTokens()
    editor.updateScrolling()
  
  # Navigate to the definition position
  let targetPos = CursorPos(
    line: location.range.start.line,
    col: location.range.start.character
  )
  
  # Set cursor position
  editor.setCursorPosition(targetPos)
  
  # Ensure the target position is visible by scrolling if necessary
  let lineHeight = editor.config.lineHeight
  
  # Calculate effective viewport height accounting for terminal panel
  var effectiveViewportHeight = editor.bounds.height - (2 * editor.config.padding)
  
  # Check if there's a terminal panel reducing the available height
  # The terminal panel would be positioned at the bottom, reducing the editor's effective height
  if editor.uiService != nil:
    # Get the window height to calculate available space
    let windowHeight = rl.getScreenHeight().float32
    let availableHeight = windowHeight - editor.bounds.y - (2 * editor.config.padding)
    if availableHeight < effectiveViewportHeight:
      effectiveViewportHeight = availableHeight
  
  let linesVisible = max(1, int(effectiveViewportHeight / lineHeight))
  
  # Center the target line in the viewport
  editor.editorState.scrollOffset = max(0, targetPos.line - linesVisible div 2)
  
  # Clear any selection
  editor.editorState.selection.active = false

proc updateCtrlHover*(editor: TextEditor, mousePos: rl.Vector2) =
  ## Update ctrl+hover state for Go to Definition visual feedback
  
  # Check if mouse is over terminal area using helper function
  if editor.terminalIntegration.isSome and editor.isMouseOverTerminal(mousePos):
    # Don't update ctrl hover if mouse is over terminal area
    editor.isCtrlHovering = false
    editor.ctrlHoverSymbol = ""
    editor.ctrlHoverPosition = CursorPos(line: -1, col: -1)
    return
  
  let textStartX = editor.bounds.x + editor.config.padding +
    (if editor.config.showLineNumbers: editor.config.lineNumberWidth else: 0.0) -
    editor.editorState.scrollX
  let textStartY = editor.bounds.y + editor.config.padding
  let relativeX = mousePos.x - textStartX
  let line = int((mousePos.y - textStartY) / editor.config.lineHeight) + editor.editorState.scrollOffset

  # Get column position
  var col = 0
  if editor.editorService.document != nil and line >= 0 and line < editor.editorService.document.lineCount():
    let lineResult = editor.editorService.document.getLine(line)
    if lineResult.isOk:
      let lineText = lineResult.get()
      let textMeasurement = newTextMeasurement(editor.font, editor.config.fontSize, 1.0, editor.config.charWidth)
      col = textMeasurement.findPositionFromWidth(lineText, relativeX)
      
      # Get symbol at position
      let symbolInfo = detectSymbol(lineText, col)
      if symbolInfo.symbol.len > 0:
          editor.isCtrlHovering = true
          editor.ctrlHoverSymbol = symbolInfo.symbol
          editor.ctrlHoverPosition = CursorPos(line: line, col: col)
          return

  # No valid symbol found
  editor.isCtrlHovering = false
  editor.ctrlHoverSymbol = ""
  editor.ctrlHoverPosition = CursorPos(line: -1, col: -1)

proc updateSyntaxHighlighting*(editor: TextEditor) =
  ## Update syntax highlighting if needed
  # Only update if syntax highlighting is enabled
  if not editor.config.syntaxHighlighting:
    return

  var detectedLang = enhanced_syntax.langPlainText
  var shouldUpdate = false

  # Try to detect from current file
  if editor.editorService.document != nil:
    let filePath = editor.editorService.currentFile
    if filePath.isSome and filePath.get().len > 0:
      detectedLang = enhanced_syntax.detectLanguage(filePath.get())
      # Only update if language has changed
      if editor.currentLanguage != detectedLang:
        shouldUpdate = true
    else:
      # No file path, use plain text
      if editor.currentLanguage != enhanced_syntax.langPlainText:
        shouldUpdate = true
  else:
    # No document, use plain text
    if editor.currentLanguage != enhanced_syntax.langPlainText:
      shouldUpdate = true

  # Only update if language has changed
  if shouldUpdate:
    editor.syntaxHighlighter = newSyntaxHighlighter(detectedLang)
    editor.currentLanguage = detectedLang
    editor.invalidateTokens() # Invalidate tokens when language changes

# UIComponent lifecycle methods
proc update*(editor: TextEditor, deltaTime: float32) =
  ## Update editor state with enhanced LSP integration
  let currentTime = epochTime()

  # Sync UIComponent state with TextEditor internal state
  editor.syncComponentState()

  # Update scroll limits
  editor.updateScrolling()

  # Scroll input is now handled by unified input system in handleInput

  # Update syntax highlighting if needed
  editor.updateSyntaxHighlighting()

  # Tokenization is now handled in setDocument() and setDocumentWithPath()
  # to avoid checking every frame. Only invalidate tokens when needed.
  if editor.config.syntaxHighlighting and (not editor.tokensValid or 
     (editor.editorService.document != nil and editor.lastTokenizedVersion != editor.editorService.document.version)):

    editor.tokenizeFullDocument()

  # Use last known mouse position from unified input system
  var mousePos = editor.lastMousePos
  
  # Handle cursor management based on last known mouse position and modifier state
  let isDefinitionModifierPressed = editor.lastModifierState
  
  # Check if mouse is within editor bounds
  let mouseInEditor = mousePos.x >= editor.bounds.x and 
                     mousePos.x <= editor.bounds.x + editor.bounds.width and
                     mousePos.y >= editor.bounds.y and 
                     mousePos.y <= editor.bounds.y + editor.bounds.height
  
  # Allow hover in text editor area regardless of terminal position
  var mouseInEditorForHover = mouseInEditor
  if editor.terminalIntegration.isSome:
    # Only block hover if mouse is actually over the terminal panel AND terminal is visible
    let isOverTerminal = editor.isMouseOverTerminal(mousePos)
    let terminalVisible = editor.terminalIntegration.get().isVisible()
    if isOverTerminal and terminalVisible:
  
      mouseInEditorForHover = false
      # Clear any pending hover requests when mouse is over terminal
      if editor.languageService != nil:
        editor.languageService.clearHover()
    
    else:
      discard
    
  else:
    discard
    
  if isDefinitionModifierPressed and mouseInEditorForHover:

    editor.updateCtrlHover(mousePos)
    if editor.isCtrlHovering and editor.ctrlHoverSymbol.len > 0:
      requestHandCursor("text_editor_ctrl_hover")
    else:
      clearCursorRequest("text_editor_ctrl_hover")
      # Still show text cursor in text area even when Ctrl is held but no symbol
      editor.handleMouseMovement(mousePos)
  else:
    editor.isCtrlHovering = false
    clearCursorRequest("text_editor_ctrl_hover")
    # Handle normal cursor management
    if mouseInEditorForHover:
      editor.handleMouseMovement(mousePos)

  # Check if mouse moved significantly (at least 5 pixels to reduce sensitivity)
  let mouseMovedEnough = if editor.lastMousePos.x >= 0:
    let deltaX = abs(mousePos.x - editor.lastMousePos.x)
    let deltaY = abs(mousePos.y - editor.lastMousePos.y)
    deltaX > 5.0 or deltaY > 5.0
  else:
    true # First time, always update

  # Update mouse tracking
  if mouseMovedEnough:
    editor.lastMousePos = mousePos
    editor.lastMouseMoveTime = currentTime

  # Simple hover updates - only when mouse is in editor bounds (excluding terminal panel)
  # Only call normal hover when modifier keys are NOT pressed
  if mouseMovedEnough and mouseInEditorForHover and not isDefinitionModifierPressed:
    editor.updateHover(mousePos)
    editor.editorState.lastHoverTime = currentTime

  if editor.languageService != nil and mouseInEditorForHover:
    # Check for new hover content even when mouse is still
    let currentHover = editor.languageService.getCurrentHover()
    if currentHover.isSome and currentHover.get().content.len > 0 and
        not editor.editorState.showHover:
      if editor.editorState.hoverPosition.line >= 0:
        editor.editorState.showHover = true
        editor.editorState.hoverInfo = currentHover
      editor.editorState.lastHoverTime = currentTime

  # Handle definition responses for Go to Definition
  if editor.languageService != nil:
    let definitionLocations = editor.languageService.getLastDefinitionResponse()
    if definitionLocations.len > 0:
      # Navigate to the first definition location
      let firstLocation = definitionLocations[0]
      editor.navigateToDefinition(firstLocation)
      # Clear the response after handling
      editor.languageService.clearDefinitionResponse()

  # Handle cursor blinking
  if editor.editorState.isFocused:
    if currentTime - editor.cursorBlinkTime > 0.53: # Blink every 530ms
      editor.cursorVisible = not editor.cursorVisible
      editor.cursorBlinkTime = currentTime

  # Periodically log measurement statistics if there are issues
  # Check every 30 seconds to avoid spam
  if currentTime - editor.lastUpdateTime > 30.0:
    if shouldLogMeasurementStats():
      logMeasurementStats()
      # Reset stats after logging to avoid repeated logging of the same issues
      resetMeasurementStats()

  editor.lastUpdateTime = currentTime

proc render*(
    editor: TextEditor,
    context: RenderContext,
    x: float32,
    y: float32,
    width: float32,
    height: float32,
) =
  ## Render the text editor
  # Update bounds
  editor.bounds = rl.Rectangle(x: x, y: y, width: width, height: height)

  # Update scroll limits with new bounds
  editor.updateScrolling()

  # Calculate visible lines
  let startLine = max(0, editor.editorState.scrollOffset)
  let endLine = min(
    startLine + editor.editorState.visibleLines - 1,
    if editor.editorService.document != nil:
      editor.editorService.document.lineCount() - 1
    else:
      0,
  )

  # Render components
  editor.renderLineNumbers(startLine, endLine)
  editor.renderTextContent(startLine, endLine)
  editor.renderCursor()
  editor.renderScrollbar()

  # Render hover if active (no updates during render, only display)
  if editor.editorState.showHover:
    editor.renderHover()

  # Mark as not dirty
  editor.isDirty = false

proc syncStateToService*(editor: TextEditor) =
  ## Sync component state to editor service before operations
  editor.editorService.cursor = editor.editorState.cursor
  editor.editorService.selection = editor.editorState.selection

proc syncStateFromService*(editor: TextEditor) =
  ## Sync component state from editor service after operations
  editor.editorState.cursor = editor.editorService.cursor
  editor.editorState.selection = editor.editorService.selection
  # Validate cursor position after syncing
  editor.validateCurrentCursor()

proc syncComponentState*(editor: TextEditor) =
  ## Sync UIComponent state with TextEditor internal state
  # Ensure cursor position is always valid when syncing
  editor.validateCurrentCursor()
  
  # Sync with editor service to ensure consistency
  editor.syncStateFromService()
  
  editor.isVisible =
    editor.editorState.isFocused or editor.editorService.document != nil

  # Update component state in UI service based on internal state
  if editor.isVisible:
    if editor.isEnabled:
      discard editor.uiService.setComponentState(editor.id, csVisible)
    else:
      discard editor.uiService.setComponentState(editor.id, csDisabled)
  else:
    discard editor.uiService.setComponentState(editor.id, csHidden)

proc handleScrollInput*(editor: TextEditor) =
  ## Handle scroll input - deprecated, use unified input system instead
  ## This method is kept for backward compatibility
  discard

proc cleanup*(editor: TextEditor) =
  ## Clean up component resources and unregister from UI service
  # Close current file in language service before cleanup
  if editor.languageService != nil and editor.editorService.currentFile.isSome:
    editor.languageService.closeDocument(editor.editorService.currentFile.get())

  editor.editorState = TextEditorState()
  editor.syntaxHighlighter = newSyntaxHighlighter(enhanced_syntax.langPlainText)
  editor.allTokens = @[]
  editor.tokensValid = false
  editor.lastTokenizedVersion = 0
  editor.currentLanguage = enhanced_syntax.langPlainText
  editor.editorState.showHover = false
  editor.editorState.hoverInfo = none(HoverInfo)

  # Language service cleanup is handled by the service itself

  # Remove from UI service to prevent memory leaks
  discard editor.uiService.removeComponent(editor.id)

# Public API methods
proc setDocument*(editor: TextEditor, document: Document) =
  ## Set the document for this editor with enhanced LSP integration
  # Close previous file in language service if any
  if editor.languageService != nil and editor.editorService.currentFile.isSome:
    editor.languageService.closeDocument(editor.editorService.currentFile.get())

  editor.editorService.document = document
  editor.editorService.currentFile = none(string)
    # Clear file path since no specific file

  # Initialize cursor position to start of document
  editor.editorState.cursor = CursorPos(line: 0, col: 0)
  editor.editorService.cursor = CursorPos(line: 0, col: 0)
  
  # Request focus when document is loaded
  editor.requestFocus()

  # Do not call invalidateTokens here to avoid double tokenization
  editor.updateScrolling()
  editor.updateSyntaxHighlighting()
  # Force immediate tokenization for new document with correct language
  if editor.config.syntaxHighlighting:
    editor.tokenizeFullDocument()
  editor.isDirty = true

proc setDocumentWithPath*(
    editor: TextEditor, document: Document, filePath: string
) =
  ## Set the document for this editor with file path and enhanced LSP integration
  # Close previous file in language service if different file
  if editor.languageService != nil and editor.editorService.currentFile.isSome:
    let previousFile = editor.editorService.currentFile.get()
    if previousFile != filePath:
      editor.languageService.closeDocument(previousFile)

  editor.editorService.document = document
  editor.editorService.currentFile = some(filePath)

  # Initialize cursor position to start of document
  editor.editorState.cursor = CursorPos(line: 0, col: 0)
  editor.editorService.cursor = CursorPos(line: 0, col: 0)
  
  # Request focus when document is loaded
  editor.requestFocus()

  # Detect and set language based on file path
  if editor.config.syntaxHighlighting and filePath.len > 0:
    let detectedLang = detectLanguage(filePath)
    editor.syntaxHighlighter = newSyntaxHighlighter(detectedLang)

    # Enhanced language service integration with proper content
    if editor.languageService != nil:
      # Get document content for language service
      var documentContent = ""
      if document != nil:
        let totalLines = document.lineCount()
        for i in 0 ..< totalLines:
          let lineResult = document.getLine(i)
          if lineResult.isOk:
            if documentContent.len > 0:
              documentContent.add "\n"
            documentContent.add lineResult.get()

      discard editor.languageService.openDocument(filePath, documentContent)

  # Do not call invalidateTokens here to avoid double tokenization
  editor.updateScrolling()
  # Force immediate tokenization for new document with correct language
  if editor.config.syntaxHighlighting:
    editor.tokenizeFullDocument()
  editor.isDirty = true

proc getCursor*(editor: TextEditor): CursorPos =
  ## Get the current cursor position
  editor.editorState.cursor

proc setCursor*(editor: TextEditor, cursor: CursorPos) =
  ## Set the cursor position
  editor.editorState.cursor = cursor
  editor.isDirty = true

proc getSelection*(editor: TextEditor): Selection =
  ## Get the current selection
  editor.editorState.selection

proc setSelection*(editor: TextEditor, selection: Selection) =
  ## Set the selection
  editor.editorState.selection = selection
  editor.isDirty = true

proc isModified*(editor: TextEditor): bool =
  ## Check if the document is modified
  editor.editorState.isModified

proc setModified*(editor: TextEditor, modified: bool) =
  ## Set the modified state
  editor.editorState.isModified = modified

proc requestFocus*(editor: TextEditor) =
  ## Request focus for this component
  discard editor.uiService.setFocus(editor.id)
  editor.editorState.isFocused = true

proc clearFocus*(editor: TextEditor) =
  ## Clear focus from this component
  # Also clear focus in the UIService if this editor currently holds it
  let focused = editor.uiService.getFocusedComponent()
  if focused.isSome and focused.get().id == editor.id:
    editor.uiService.clearFocus()
  editor.editorState.isFocused = false

proc hasFocus*(editor: TextEditor): bool =
  ## Check if this component has focus
  editor.editorState.isFocused

proc setConfig*(editor: TextEditor, config: TextEditorConfig) =
  ## Set the editor configuration
  editor.config = config
  editor.isDirty = true

proc getConfig*(editor: TextEditor): TextEditorConfig =
  ## Get the editor configuration
  return editor.config

proc handleMouseClick*(editor: TextEditor, pos: MousePosition) =
  ## Handle mouse click events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  editor.handleMouseInput(mousePos, rl.MouseButton.Left, rl.getTime(), {})

proc handleMouseMove*(editor: TextEditor, pos: MousePosition) =
  ## Handle mouse move events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  # Only update hover if not dragging
  if not editor.editorState.isDragging:
    editor.updateHover(mousePos)
