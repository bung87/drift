## Terminal Panel Component
## Uses ComponentManager for standardized service access and patterns

import std/[options, tables, strutils, times]
import raylib as rl
import results
import ../shared/[types, errors]
import ../services/component_manager
import ../services/ui_service  # For UIComponent type
import ../services/terminal_service  # For TerminalService type
import ../infrastructure/terminal/[ansi_parser, terminal_io]
import ../infrastructure/input/[drag_interaction, mouse, keyboard, input_handler]
import ../infrastructure/rendering/[theme, renderer]  # For theme color constants and renderer
import ../infrastructure/ui/cursor_manager  # For cursor priority constants

type
  TerminalPanel* = ref object of UIComponent
    # Core component manager integration
    componentManager*: ComponentManager
    
    # Terminal state
    buffer*: TerminalBuffer
    session*: Option[TerminalSession]
    scrollOffset*: int
    cursorPos*: rl.Vector2
    
    # Display properties
    lineHeight*: float32
    fontSize*: float32
    visibleLines*: int
    maxScrollOffset*: int
    
    # Terminal infrastructure
    terminalIO*: TerminalIO
    ansiParser*: AnsiParser
    terminalService*: TerminalService  # For session management
    
    # Input handling
    inputBuffer*: string
    cursorColumn*: int
    focused*: bool
    
    # Header and drag handling
    headerHeight*: float32
    dragHandler*: TerminalPanelDragHandler
    isDraggingHeader*: bool
    dragStartPos*: rl.Vector2
    lastDragY*: float32
    onResize*: proc(newHeight: float32)
    
    # Cursor blinking
    showCursor*: bool
    cursorBlinkTime*: float
    lastBlinkTime*: float
    
    # Auto-scroll
    autoScroll*: bool
    
    # Startup state
    isStartingUp*: bool
    startupMessage*: string
    startupTime*: float
    
    # Callbacks
    onInput*: proc(input: string)
    onCommand*: proc(command: string)

# Forward declarations for methods used in closures
proc scrollToTop*(panel: TerminalPanel)
proc scrollToBottom*(panel: TerminalPanel)
proc scrollUp*(panel: TerminalPanel, lines: int = 1)
proc scrollDown*(panel: TerminalPanel, lines: int = 1)
proc handleInput*(panel: TerminalPanel, event: UnifiedInputEvent): bool
proc handleKeyInput*(panel: TerminalPanel, key: int32): bool
proc handleTextInput*(panel: TerminalPanel, text: string): bool
proc handleHeaderMouseDown*(panel: TerminalPanel, mousePos: rl.Vector2): bool
proc handleHeaderMouseMove*(panel: TerminalPanel, mousePos: rl.Vector2): bool
proc handleHeaderMouseUp*(panel: TerminalPanel, mousePos: rl.Vector2): bool

# Constructor
proc newTerminalPanel*(
  id: string,
  bounds: rl.Rectangle,
  componentManager: ComponentManager,
  terminalService: TerminalService = nil,
  fontSize: float32 = 14.0,
  onResize: proc(newHeight: float32) = nil
): TerminalPanel =
  result = TerminalPanel(
    # UIComponent fields
    id: id,
    name: "Terminal Panel",
    state: csVisible,
    bounds: bounds,
    zIndex: 1,
    isVisible: true,
    isEnabled: true,
    isDirty: true,
    parent: nil,
    children: @[],
    data: initTable[string, string](),
    
    # Component manager integration
    componentManager: componentManager,
    
    # Terminal state
    buffer: newTerminalBuffer(),
    session: none(TerminalSession),
    scrollOffset: 0,
    cursorPos: rl.Vector2(x: 0, y: 0),
    
    # Display properties
    lineHeight: fontSize + 4.0,
    fontSize: fontSize,
    visibleLines: 0,
    maxScrollOffset: 0,
    
    # Terminal infrastructure
    terminalIO: nil,
    ansiParser: newAnsiParser(),
    terminalService: terminalService,  # Set from parameter
    
    # Input handling
    inputBuffer: "",
    cursorColumn: 0,
    focused: false,
    
    # Header and drag handling
    headerHeight: 20.0,
    dragHandler: nil,
    isDraggingHeader: false,
    dragStartPos: rl.Vector2(x: 0, y: 0),
    lastDragY: 0.0,
    onResize: onResize,  # Set from parameter
    
    # Cursor blinking
    showCursor: true,
    cursorBlinkTime: 0.5,
    lastBlinkTime: 0.0,
    
    # Auto-scroll
    autoScroll: true,
    
    # Startup state
    isStartingUp: false,
    startupMessage: "",
    startupTime: 0.0,
    
    # Callbacks
    onInput: nil,
    onCommand: nil
  )
  
  # Calculate visible lines
  let safeLineHeight = max(1.0, result.lineHeight)
  result.visibleLines = max(1, int((bounds.height - result.headerHeight) / safeLineHeight))
  
  # Initialize drag handler using existing infrastructure
  let statusBarBounds = rl.Rectangle(
    x: bounds.x,
    y: bounds.y + bounds.height - result.headerHeight,
    width: bounds.width,
    height: result.headerHeight
  )
  result.dragHandler = newTerminalPanelDragHandler(
    statusBarBounds,
    bounds.height - result.headerHeight
  )

# ComponentManager integration
proc registerWithManager*(panel: TerminalPanel): Result[void, EditorError] =
  ## Register the component with ComponentManager
  
  # Register the component itself
  let registerResult = panel.componentManager.registerComponent(
    panel.id,
    panel,
    nil, # Input handler will be registered separately
    nil  # Render handler will be registered separately
  )
  
  if registerResult.isErr:
    return registerResult
  
  # Register keyboard shortcuts for scrolling
  var keyHandlers: Table[keyboard.KeyCombination, proc()] = initTable[keyboard.KeyCombination, proc()]()
  var mouseHandlers: Table[mouse.MouseButton, proc(pos: MousePosition)] = initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  
  # Scroll shortcuts
  keyHandlers[keyboard.KeyCombination(key: ekHome, modifiers: {mkCtrl})] = proc() =
    panel.scrollToTop()
  
  keyHandlers[keyboard.KeyCombination(key: ekEnd, modifiers: {mkCtrl})] = proc() =
    panel.scrollToBottom()
  
  keyHandlers[keyboard.KeyCombination(key: ekPageUp, modifiers: {mkCtrl})] = proc() =
    panel.scrollUp(panel.visibleLines)
  
  keyHandlers[keyboard.KeyCombination(key: ekPageDown, modifiers: {mkCtrl})] = proc() =
    panel.scrollDown(panel.visibleLines)
  
  # Register input handlers
  let inputResult = panel.componentManager.registerInputHandlers(
    panel.id,
    keyHandlers,
    mouseHandlers
  )
  
  if inputResult.isErr:
    return inputResult
  
  # Register drag handlers using existing drag_interaction.nim
  let dragResult = panel.componentManager.registerDragHandlers(
    panel.id,
    proc(pos: MousePosition) = # onDragStart
      discard panel.handleHeaderMouseDown(rl.Vector2(x: pos.x, y: pos.y)),
    proc(pos: MousePosition) = # onDragMove
      discard panel.handleHeaderMouseMove(rl.Vector2(x: pos.x, y: pos.y)),
    proc(pos: MousePosition) = # onDragEnd
      discard panel.handleHeaderMouseUp(rl.Vector2(x: pos.x, y: pos.y))
  )
  
  return dragResult

# Output handling
proc handleOutputReceived*(panel: TerminalPanel, output: string) =
  # Terminal is now ready if we're receiving output
  if panel.isStartingUp:
    panel.isStartingUp = false
    panel.startupMessage = ""
  
  # Parse output with ANSI codes and add to buffer
  let lines = output.splitLines(keepEol = false)
  for line in lines:
    if line.len > 0:
      let terminalLine = panel.ansiParser.parseToTerminalLine(line)
      panel.buffer.addLine(terminalLine)
  
  # Auto-scroll to bottom if enabled
  if panel.autoScroll:
    panel.scrollOffset = max(0, panel.buffer.lines.len - panel.visibleLines)
  
  panel.componentManager.markComponentDirty(panel.id)

proc handleProcessTerminated*(panel: TerminalPanel) =
  # Add notification that process terminated
  let line = newTerminalLine("[Process terminated]", @[newTerminalTextStyle(0, 19, rl.RED)])
  panel.buffer.addLine(line)
  panel.componentManager.markComponentDirty(panel.id)

proc scrollToTop*(panel: TerminalPanel) =
  panel.scrollOffset = 0
  panel.componentManager.markComponentDirty(panel.id)

proc scrollToBottom*(panel: TerminalPanel) =
  panel.scrollOffset = max(0, panel.buffer.lines.len - panel.visibleLines)
  panel.componentManager.markComponentDirty(panel.id)

proc scrollUp*(panel: TerminalPanel, lines: int = 1) =
  panel.scrollOffset = max(0, panel.scrollOffset - lines)
  panel.componentManager.markComponentDirty(panel.id)

proc scrollDown*(panel: TerminalPanel, lines: int = 1) =
  panel.scrollOffset = min(max(0, panel.buffer.lines.len - panel.visibleLines), panel.scrollOffset + lines)
  panel.componentManager.markComponentDirty(panel.id)

# Session management using existing terminal infrastructure
proc setSession*(panel: TerminalPanel, session: TerminalSession) =
  panel.session = some(session)
  panel.buffer = session.buffer
  
  # Set up terminal I/O using existing infrastructure
  if session.id > 0:
    # Create terminal I/O handler
    panel.terminalIO = initTerminalIO(
      session.id,
      nil, # Shell process will be provided by TerminalService
      panel.ansiParser,
      proc(event: IOEvent) =
        case event.eventType:
        of ietOutputReceived:
          if event.data.len > 0:
            panel.handleOutputReceived(event.data)
        of ietProcessTerminated:
          panel.handleProcessTerminated()
        of ietError:
          panel.isStartingUp = false
          panel.startupMessage = "Terminal error"
        else:
          discard
    )
    
    # Start I/O processing
    if panel.terminalIO != nil:
      panel.terminalIO.start()
  
  panel.componentManager.markComponentDirty(panel.id)

proc clearSession*(panel: TerminalPanel) =
  # Clean up terminal I/O
  if panel.terminalIO != nil:
    panel.terminalIO.cleanup()
    panel.terminalIO = nil
  
  panel.session = none(TerminalSession)
  panel.buffer = newTerminalBuffer()
  panel.scrollOffset = 0
  panel.inputBuffer = ""
  panel.cursorColumn = 0
  panel.ansiParser.reset()
  panel.componentManager.markComponentDirty(panel.id)

# Rendering methods
proc updateCursor*(panel: TerminalPanel) =
  let currentTime = times.getTime().toUnixFloat()
  if currentTime - panel.lastBlinkTime >= panel.cursorBlinkTime:
    panel.showCursor = not panel.showCursor
    panel.lastBlinkTime = currentTime
    panel.componentManager.markComponentDirty(panel.id)

proc calculateMaxScrollOffset*(panel: TerminalPanel) =
  # Optimized calculation for smooth scrolling
  if panel.buffer.lines.len <= panel.visibleLines:
    panel.maxScrollOffset = 0
  else:
    panel.maxScrollOffset = panel.buffer.lines.len - panel.visibleLines

proc render*(panel: TerminalPanel) =
  if not panel.isVisible:
    return
  
  # Update cursor blink
  panel.updateCursor()
  
  # Get renderer from ComponentManager
  let renderer = panel.componentManager.renderer
  
  # Use theme colors
  let backgroundColor = panel.componentManager.getUIColor(uiBackground)
  let textColor = panel.componentManager.getUIColor(uiText)
  let headerBg = panel.componentManager.getUIColor(uiStatusbar)
  let headerBorder = panel.componentManager.getUIColor(uiBorder)
  let focusBorder = panel.componentManager.getUIColor(uiAccent)
  
  # Calculate scroll limits
  panel.calculateMaxScrollOffset()
  panel.scrollOffset = clamp(panel.scrollOffset, 0, panel.maxScrollOffset)
  
  # Draw background
  rl.drawRectangle(panel.bounds.x.int32, panel.bounds.y.int32, panel.bounds.width.int32, panel.bounds.height.int32, backgroundColor)
  
  # Draw header
  let headerY = panel.bounds.y
  let headerHeight = panel.headerHeight
  let headerWidth = panel.bounds.width
  let headerRect = rl.Rectangle(x: panel.bounds.x, y: headerY, width: headerWidth, height: headerHeight)
  rl.drawRectangle(headerRect.x.int32, headerRect.y.int32, headerRect.width.int32, headerRect.height.int32, headerBg)
  
  # Draw header text (vertically centered)
  let textY = headerY + (headerHeight - panel.fontSize) / 2.0
  # Use proper font from ComponentManager
  let font = panel.componentManager.renderer.getFont("ui")
  if font != nil:
    drawText(
      panel.componentManager.renderer,
      font[],
      "Terminal",
      rl.Vector2(x: panel.bounds.x + 10, y: textY),
      panel.fontSize,
      1.0,
      textColor
    )
  else:
    # Fallback to default font only if UI font is not available
    let defaultFont = rl.getFontDefault()
    drawText(
      panel.componentManager.renderer,
      defaultFont,
      "Terminal",
      rl.Vector2(x: panel.bounds.x + 10, y: textY),
      panel.fontSize,
      1.0,
      textColor
    )
  
  rl.drawRectangleLines(headerRect.x.int32, headerRect.y.int32, headerRect.width.int32, headerRect.height.int32, headerBorder)
  
  # Draw terminal content area
  let terminalContentY = panel.bounds.y + headerHeight
  let terminalContentHeight = panel.bounds.height - headerHeight
  
  # Show startup message if terminal is starting
  if panel.isStartingUp and panel.startupMessage.len > 0:
    let currentTime = times.getTime().toUnixFloat()
    let elapsed = currentTime - panel.startupTime
    
    # Create animated dots for loading effect
    let dots = case (int(elapsed * 2) mod 4):
      of 0: ""
      of 1: "."
      of 2: ".."
      else: "..."
    
    let message = panel.startupMessage & dots
    let messageColor = if panel.startupMessage.contains("failed") or panel.startupMessage.contains("error"):
      rl.Color(r: 255, g: 100, b: 100, a: 255)  # Red for errors
    else:
      rl.Color(r: 150, g: 150, b: 150, a: 255)  # Gray for loading
    
    # Center the message
    # Use proper font from ComponentManager
    let font = panel.componentManager.renderer.getFont("ui")
    if font != nil:
      let textWidth = measureText(panel.componentManager.renderer, font[], message, panel.fontSize, 1.0).x
      let centerX = panel.bounds.x + (panel.bounds.width - textWidth) / 2.0
      let centerY = terminalContentY + terminalContentHeight / 2.0 - panel.lineHeight / 2.0
      drawText(
        panel.componentManager.renderer,
        font[],
        message,
        rl.Vector2(x: centerX, y: centerY),
        panel.fontSize,
        1.0,
        messageColor
      )
    else:
      # Fallback to default font only if UI font is not available
      let defaultFont = rl.getFontDefault()
      let textWidth = measureText(panel.componentManager.renderer, defaultFont, message, panel.fontSize, 1.0).x
      let centerX = panel.bounds.x + (panel.bounds.width - textWidth) / 2.0
      let centerY = terminalContentY + terminalContentHeight / 2.0 - panel.lineHeight / 2.0
      drawText(
        panel.componentManager.renderer,
        defaultFont,
        message,
        rl.Vector2(x: centerX, y: centerY),
        panel.fontSize,
        1.0,
        messageColor
      )
  else:
    # Draw terminal lines
    let startLine = panel.scrollOffset
    let endLine = min(startLine + panel.visibleLines, panel.buffer.lines.len)
    
    for i in startLine..<endLine:
      let line = panel.buffer.lines[i]
      let yPos = terminalContentY + float32(i - startLine) * panel.lineHeight
      
      # Draw line text with styles
      if line.styles.len > 0:
        var xPos = panel.bounds.x + 4.0
        # Use proper font from ComponentManager
        let font = panel.componentManager.renderer.getFont("ui")
        if font != nil:
          for style in line.styles:
            let styleText = line.text[style.startPos..<min(style.endPos, line.text.len)]
            drawText(
              panel.componentManager.renderer,
              font[],
              styleText,
              rl.Vector2(x: xPos, y: yPos),
              panel.fontSize,
              1.0,
              style.color
            )
            let textSize = measureText(panel.componentManager.renderer, font[], styleText, panel.fontSize, 1.0)
            xPos += textSize.x
        else:
          # Fallback to default font only if UI font is not available
          let defaultFont = rl.getFontDefault()
          for style in line.styles:
            let styleText = line.text[style.startPos..<min(style.endPos, line.text.len)]
            drawText(
              panel.componentManager.renderer,
              defaultFont,
              styleText,
              rl.Vector2(x: xPos, y: yPos),
              panel.fontSize,
              1.0,
              style.color
            )
            let textSize = measureText(panel.componentManager.renderer, defaultFont, styleText, panel.fontSize, 1.0)
            xPos += textSize.x
      else:
        # Render plain text
        # Use proper font from ComponentManager
        let font = panel.componentManager.renderer.getFont("ui")
        if font != nil:
          drawText(
            panel.componentManager.renderer,
            font[],
            line.text,
            rl.Vector2(x: panel.bounds.x + 4.0, y: yPos),
            panel.fontSize,
            1.0,
            textColor
          )
        else:
          # Fallback to default font only if UI font is not available
          let defaultFont = rl.getFontDefault()
          drawText(
            panel.componentManager.renderer,
            defaultFont,
            line.text,
            rl.Vector2(x: panel.bounds.x + 4.0, y: yPos),
            panel.fontSize,
            1.0,
            textColor
          )
    
    # Draw cursor if focused and visible
    if panel.focused and panel.showCursor and not panel.isStartingUp:
      let cursorX = panel.bounds.x + 4.0 + panel.cursorPos.x
      let cursorY = terminalContentY + panel.cursorPos.y
      let cursorRect = rl.Rectangle(x: cursorX, y: cursorY, width: 2.0, height: panel.lineHeight)
      rl.drawRectangle(cursorRect.x.int32, cursorRect.y.int32, cursorRect.width.int32, cursorRect.height.int32, textColor)
  
  # Draw focus border if focused
  if panel.focused:
    rl.drawRectangleLines(panel.bounds.x.int32, panel.bounds.y.int32, panel.bounds.width.int32, panel.bounds.height.int32, focusBorder)

# Header drag detection
proc handleHeaderMouseDown*(panel: TerminalPanel, mousePos: rl.Vector2): bool =
  ## Handle mouse down on header for drag detection
  # Make header area slightly larger for easier clicking
  let headerRect = rl.Rectangle(
    x: panel.bounds.x,
    y: panel.bounds.y,
    width: panel.bounds.width,
    height: panel.headerHeight + 5.0  # Add 5px extra height for easier clicking
  )
  
  # Simple collision check - if mouse is in header area, start dragging
  if rl.checkCollisionPointRec(mousePos, headerRect):
    panel.isDraggingHeader = true
    panel.dragStartPos = mousePos
    panel.lastDragY = mousePos.y
    # Debug output removed for cleaner output
    return true
  
  return false

proc handleHeaderMouseMove*(panel: TerminalPanel, mousePos: rl.Vector2): bool =
  ## Handle mouse move for header dragging
  if panel.isDraggingHeader and rl.isMouseButtonDown(rl.MouseButton.Left):
    let deltaY = mousePos.y - panel.lastDragY
    panel.lastDragY = mousePos.y
    # Debug output removed for cleaner output
    
    # Calculate new height based on drag direction
    # Dragging up (negative deltaY) increases height, dragging down decreases height
    let currentHeight = panel.bounds.height
    let newHeight = max(50.0, min(600.0, currentHeight - deltaY)) # Clamp between 50px and 600px
    
    # Only resize if there's a meaningful change
    if abs(newHeight - currentHeight) > 1.0:
      if panel.onResize != nil:
        panel.onResize(newHeight)
      else:
        # Fallback: resize the panel directly
        var newBounds = panel.bounds
        newBounds.height = newHeight
        newBounds.y = panel.bounds.y + panel.bounds.height - newHeight
        # Set bounds and update panel state manually
        panel.bounds = newBounds
        let safeLineHeight = max(1.0, panel.lineHeight)
        panel.visibleLines = max(1, int((newBounds.height - panel.headerHeight) / safeLineHeight))
        discard panel.componentManager.updateComponentBounds(panel.id, newBounds)
    
    return true
  
  return false

proc handleHeaderMouseUp*(panel: TerminalPanel, mousePos: rl.Vector2): bool =
  ## Handle mouse up to stop header dragging
  if panel.isDraggingHeader:
    panel.isDraggingHeader = false
    # Debug output removed for cleaner output
    return true
  
  return false

# Unified input handling for ComponentManager integration
proc handleInput*(panel: TerminalPanel, event: UnifiedInputEvent): bool =
  ## Handle unified input events for the terminal panel
  ## Strategy: Only consume events when actively handling them to allow hover effects in other components
  if not panel.isEnabled:
    return false
  
  case event.kind:
  of uiekMouse:
    let mouseEvent = event.mouseEvent
    let mousePos = rl.Vector2(x: mouseEvent.position.x, y: mouseEvent.position.y)
    
    case mouseEvent.eventType:
    of metMoved:
      # Handle mouse movement for cursor updates and drag
      if panel.isDraggingHeader:
        discard panel.handleHeaderMouseMove(mousePos)
        return true
      # Only consume mouse move events if we're actually doing something with them
      # This allows hover effects to work in other components
      return false
    of metButtonPressed:
      if mouseEvent.button == mbLeft:
        # Debug output removed for cleaner output
        # Handle header drag
        if panel.handleHeaderMouseDown(mousePos):
                      # Debug output removed for cleaner output
          return true
        # Handle text area clicks for focus
        let textAreaBounds = rl.Rectangle(
          x: panel.bounds.x,
          y: panel.bounds.y + panel.headerHeight,
          width: panel.bounds.width,
          height: panel.bounds.height - panel.headerHeight
        )
        if rl.checkCollisionPointRec(mousePos, textAreaBounds):
          panel.focused = true
          let newState = csFocused
          discard panel.componentManager.updateComponentState(panel.id, newState)
          return true
    of metButtonReleased:
      if mouseEvent.button == mbLeft:
        discard panel.handleHeaderMouseUp(mousePos)
        return true
    else:
      return false
  of uiekKeyboard:
    let keyEvent = event.keyEvent
    
    case keyEvent.eventType:
    of ietKeyPressed:
      # Convert EditorKey to int32 for legacy handleKeyInput
      let keyInt = keyEvent.key.int32
      return panel.handleKeyInput(keyInt)
    of ietCharInput:
      # Handle character input
      if keyEvent.character.int32 > 0:
        let charStr = $char(keyEvent.character.int32)
        return panel.handleTextInput(charStr)
    else:
      return false
  of uiekCombined:
    # Handle combined events if needed
    return false
  
  return false

# Enhanced input handling
proc handleKeyInput*(panel: TerminalPanel, key: int32): bool =
  if not panel.focused or not panel.isEnabled:
    return false
  
  # Don't handle input while starting up
  if panel.isStartingUp:
    return false
  
  # Handle scrolling first
  if rl.isKeyDown(rl.KeyboardKey.LeftControl) or rl.isKeyDown(rl.KeyboardKey.RightControl):
    case key:
    of rl.KeyboardKey.Home.int32:
      panel.scrollToTop()
      return true
    of rl.KeyboardKey.End.int32:
      panel.scrollToBottom()
      return true
    of rl.KeyboardKey.PageUp.int32:
      panel.scrollUp(panel.visibleLines)
      return true
    of rl.KeyboardKey.PageDown.int32:
      panel.scrollDown(panel.visibleLines)
      return true
    else:
      discard
  
  # Send key to terminal if we have an active session
  if panel.terminalIO != nil and panel.terminalIO.isRunning():
    let modifiers = (if rl.isKeyDown(rl.KeyboardKey.LeftControl) or rl.isKeyDown(rl.KeyboardKey.RightControl): 0x02 else: 0) or
                   (if rl.isKeyDown(rl.KeyboardKey.LeftShift) or rl.isKeyDown(rl.KeyboardKey.RightShift): 0x01 else: 0) or
                   (if rl.isKeyDown(rl.KeyboardKey.LeftAlt) or rl.isKeyDown(rl.KeyboardKey.RightAlt): 0x04 else: 0)
    
    panel.terminalIO.sendKeyPress(key, modifiers.int32)
    
    # Update local input buffer for display
    case key:
    of rl.KeyboardKey.Enter.int32:
      if panel.onCommand != nil and panel.inputBuffer.len > 0:
        panel.onCommand(panel.inputBuffer)
      panel.inputBuffer = ""
      panel.cursorColumn = 0
    of rl.KeyboardKey.Backspace.int32:
      if panel.inputBuffer.len > 0 and panel.cursorColumn > 0:
        panel.inputBuffer.delete(panel.cursorColumn - 1 .. panel.cursorColumn - 1)
        dec panel.cursorColumn
    of rl.KeyboardKey.Left.int32:
      if panel.cursorColumn > 0:
        dec panel.cursorColumn
    of rl.KeyboardKey.Right.int32:
      if panel.cursorColumn < panel.inputBuffer.len:
        inc panel.cursorColumn
    of rl.KeyboardKey.Home.int32:
      panel.cursorColumn = 0
    of rl.KeyboardKey.End.int32:
      panel.cursorColumn = panel.inputBuffer.len
    else:
      discard
    
    panel.componentManager.markComponentDirty(panel.id)
    return true
  
  return false

proc handleTextInput*(panel: TerminalPanel, text: string): bool =
  if not panel.focused or not panel.isEnabled or panel.isStartingUp:
    return false
  
  # Send text to terminal if we have an active session
  if panel.terminalIO != nil and panel.terminalIO.isRunning():
    panel.terminalIO.sendInput(text)
    
    # Update local input buffer for display
    panel.inputBuffer.insert(text, panel.cursorColumn)
    panel.cursorColumn += text.len
    
    if panel.onInput != nil:
      panel.onInput(text)
    
    panel.componentManager.markComponentDirty(panel.id)
    return true
  
  return false

# Focus management using ComponentManager
proc setFocus*(panel: TerminalPanel, focused: bool) =
  if panel.focused != focused:
    panel.focused = focused
    let newState = if focused: csFocused else: csVisible
    discard panel.componentManager.updateComponentState(panel.id, newState)
    
    # Set cursor using ComponentManager
    if focused:
      panel.componentManager.setCursor(panel.id, rl.MouseCursor.IBeam, cpTextEditor)
    else:
      panel.componentManager.clearCursor(panel.id)

# Resizing using ComponentManager
proc resize*(panel: TerminalPanel, newBounds: rl.Rectangle) =
  panel.bounds = newBounds
  let safeLineHeight = max(1.0, panel.lineHeight)
  panel.visibleLines = max(1, int((newBounds.height - panel.headerHeight) / safeLineHeight))
  panel.calculateMaxScrollOffset()
  
  # Update drag handler bounds
  if panel.dragHandler != nil:
    let statusBarBounds = rl.Rectangle(
      x: newBounds.x,
      y: newBounds.y + newBounds.height - panel.headerHeight,
      width: newBounds.width,
      height: panel.headerHeight
    )
    panel.dragHandler.setStatusBarBounds(statusBarBounds)
    panel.dragHandler.setMaxPanelHeight(newBounds.height - panel.headerHeight)
  
  discard panel.componentManager.updateComponentBounds(panel.id, newBounds)

# Content management
proc addOutput*(panel: TerminalPanel, text: string, color: rl.Color = rl.WHITE) =
  let line = TerminalLine(
    text: text,
    styles: @[TerminalTextStyle(
      startPos: 0,
      endPos: text.len,
      color: color,
      backgroundColor: rl.Color(r: 0, g: 0, b: 0, a: 0),
      bold: false,
      italic: false,
      underline: false
    )],
    timestamp: times.getTime().toUnixFloat()
  )
  
  panel.buffer.addLine(line)
  panel.calculateMaxScrollOffset()
  
  # Auto-scroll to bottom if auto-scroll is enabled
  if panel.autoScroll:
    panel.scrollToBottom()
  
  panel.componentManager.markComponentDirty(panel.id)

proc addStyledOutput*(panel: TerminalPanel, text: string, styles: seq[TerminalTextStyle]) =
  let line = TerminalLine(
    text: text,
    styles: styles,
    timestamp: times.getTime().toUnixFloat()
  )
  
  panel.buffer.addLine(line)
  panel.calculateMaxScrollOffset()
  
  # Auto-scroll to bottom if auto-scroll is enabled
  if panel.autoScroll:
    panel.scrollToBottom()
  
  panel.componentManager.markComponentDirty(panel.id)

proc clear*(panel: TerminalPanel) =
  panel.buffer.clear()
  panel.scrollOffset = 0
  panel.inputBuffer = ""
  panel.cursorColumn = 0
  panel.ansiParser.reset()
  panel.isDirty = true

# Utility methods
proc getInputBuffer*(panel: TerminalPanel): string =
  panel.inputBuffer

proc getCurrentLine*(panel: TerminalPanel): string =
  if panel.buffer.lines.len > 0:
    panel.buffer.lines[^1].text
  else:
    ""

proc getLineCount*(panel: TerminalPanel): int =
  panel.buffer.lines.len

proc isAtBottom*(panel: TerminalPanel): bool =
  panel.scrollOffset >= panel.maxScrollOffset

# Terminal-specific functionality
proc sendCommand*(panel: TerminalPanel, command: string): bool =
  if panel.terminalIO != nil and panel.terminalIO.isRunning():
    panel.terminalIO.sendCommand(command)
    panel.inputBuffer = ""
    panel.cursorColumn = 0
    return true
  return false

proc sendInput*(panel: TerminalPanel, input: string): bool =
  if panel.terminalIO != nil and panel.terminalIO.isRunning():
    panel.terminalIO.sendInput(input)
    return true
  return false

proc setAutoScroll*(panel: TerminalPanel, enabled: bool) =
  panel.autoScroll = enabled

proc isAutoScrollEnabled*(panel: TerminalPanel): bool =
  panel.autoScroll

proc hasActiveSession*(panel: TerminalPanel): bool =
  panel.session.isSome and panel.terminalIO != nil and panel.terminalIO.isRunning()

proc update*(panel: TerminalPanel) =
  # Update cursor blink (lightweight operation)
  panel.updateCursor()
  
  # Cache current time for multiple uses
  let currentTime = times.getTime().toUnixFloat()
  
  # Check startup timeout with improved error handling (non-blocking)
  if panel.isStartingUp and panel.startupTime > 0:
    if currentTime - panel.startupTime > 10.0:  # Reduced timeout for better responsiveness
      panel.isStartingUp = false
      panel.startupMessage = "Terminal startup timed out"
      panel.addOutput(panel.startupMessage, rl.Color(r: 255, g: 100, b: 100, a: 255))
  
  # Quick session state check without blocking operations
  if panel.session.isSome() and panel.terminalService != nil:
    let sessionId = panel.session.get().id
    # Use cached state check - don't perform expensive operations
    if panel.isStartingUp:
      let isActive = panel.terminalService.isSessionActive(sessionId)
      if isActive and not panel.session.get().isActive:
        panel.isStartingUp = false
        panel.startupMessage = ""
        panel.session.get().isActive = true
  
  # Minimal terminal I/O processing - defer heavy work
  if panel.terminalIO != nil and panel.terminalIO.isRunning():
    # Only check for immediately available output - no blocking calls
    if panel.terminalIO.hasOutput():
      let output = panel.terminalIO.getAndClearOutput()
      if output.len > 0:
        panel.handleOutputReceived(output)

# Handle mouse wheel scrolling (optimized for smoothness)
proc handleMouseWheel*(panel: TerminalPanel, wheelMove: float32): bool =
  if not panel.isVisible:
    return false
  
  # Quick bounds check for smooth scrolling
  let mousePos = rl.getMousePosition()
  if not rl.checkCollisionPointRec(mousePos, panel.bounds):
    return false
  
  # Smooth scroll calculation
  let scrollAmount = int(wheelMove * 2.0)  # Reduced for smoother scrolling
  
  if scrollAmount != 0:
    # Direct scroll offset manipulation for better performance
    let newOffset = panel.scrollOffset - scrollAmount
    panel.scrollOffset = clamp(newOffset, 0, max(0, panel.buffer.lines.len - panel.visibleLines))
    panel.isDirty = true
  
  return true

# Cleanup
proc cleanup*(panel: TerminalPanel) =
  # Unregister from ComponentManager
  discard panel.componentManager.unregisterComponent(panel.id)
  
  # Clean up terminal I/O
  if panel.terminalIO != nil:
    panel.terminalIO.cleanup()
    panel.terminalIO = nil
  
  # Clean up drag handler
  if panel.dragHandler != nil:
    panel.dragHandler.setEnabled(false)
    panel.dragHandler = nil
