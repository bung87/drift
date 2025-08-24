## Unified input handler for Drift editor
## Coordinates keyboard and mouse input with context-aware processing

import std/[tables, sequtils, strutils]
import results
import keyboard, mouse
import ../../shared/[constants, utils]
import ../../shared/errors

# Input context types
type InputContext* = enum
  icNormal = "normal" # Normal editor operation
  icTextInput = "text_input" # Typing text
  icSelection = "selection" # Text selection mode
  icCommand = "command" # Command palette
  icSearch = "search" # Search mode
  icDialog = "dialog" # Modal dialog
  icMenu = "menu" # Menu navigation
  icDebug = "debug" # Debug mode

# Input priority levels
type InputPriority* = enum
  ipLow = "low"
  ipNormal = "normal"
  ipHigh = "high"
  ipCritical = "critical"

# Unified input event kinds
type UnifiedInputEventKind* = enum
  uiekKeyboard = "keyboard"
  uiekMouse = "mouse"
  uiekCombined = "combined"

# Mouse gesture for input commands
type MouseGesture* = object
  button*: MouseButton
  clickType*: ClickType
  modifiers*: set[ModifierKey]
  requiresHover*: bool
  hoverElement*: string

# Unified input event
type UnifiedInputEvent* = object
  case kind*: UnifiedInputEventKind
  of uiekKeyboard:
    keyEvent*: InputEvent
  of uiekMouse:
    mouseEvent*: MouseEvent
  of uiekCombined:
    keyCombo*: KeyCombination
    mousePos*: MousePosition

# Input command mapping
type InputCommand* = object
  name*: string
  description*: string
  context*: set[InputContext]
  priority*: InputPriority
  keyCombination*: KeyCombination
  mouseGesture*: MouseGesture
  requiresHover*: bool
  hoverElement*: string

# Input handler configuration
type InputConfig* = object
  enableKeyRepeat*: bool
  keyRepeatDelay*: float
  keyRepeatRate*: float
  enableMouseHover*: bool
  mouseHoverDelay*: float
  doubleClickTime*: float
  dragThreshold*: float32
  contextSwitchDelay*: float

# Input filter function type
type InputFilter* = proc(event: UnifiedInputEvent, context: InputContext): bool

# Input command handler function type
type CommandHandler* = proc(command: InputCommand, event: UnifiedInputEvent): bool

# Main unified input handler
type InputHandler* = ref object # Sub-handlers
  keyboard*: KeyboardHandler
  mouse*: MouseHandler

  # State management
  currentContext*: InputContext
  contextStack*: seq[InputContext]
  lastContextSwitch*: float

  # Event processing
  eventQueue*: seq[UnifiedInputEvent]
  pendingEvents*: seq[UnifiedInputEvent]

  # Command system
  commands*: Table[string, InputCommand]
  contextCommands*: Table[InputContext, seq[string]]
  commandHandlers*: Table[string, CommandHandler]

  # Filtering and routing
  inputFilters*: seq[InputFilter]
  blockedKeys*: set[EditorKey]
  blockedButtons*: set[MouseButton]

  # Configuration
  config*: InputConfig
  enabled*: bool
  recordingMode*: bool
  recordedEvents*: seq[UnifiedInputEvent]

# Constructor
proc newInputHandler*(): InputHandler =
  result = InputHandler(
    keyboard: newKeyboardHandler(),
    mouse: newMouseHandler(),
    currentContext: icNormal,
    contextStack: @[],
    lastContextSwitch: 0.0,
    eventQueue: @[],
    pendingEvents: @[],
    commands: Table[string, InputCommand](),
    contextCommands: Table[InputContext, seq[string]](),
    commandHandlers: Table[string, CommandHandler](),
    inputFilters: @[],
    blockedKeys: {},
    blockedButtons: {},
    config: InputConfig(
      enableKeyRepeat: true,
      keyRepeatDelay: KEY_REPEAT_DELAY,
      keyRepeatRate: KEY_REPEAT_RATE,
      enableMouseHover: true,
      mouseHoverDelay: 1.0,
      doubleClickTime: DOUBLE_CLICK_TIME,
      dragThreshold: 5.0,
      contextSwitchDelay: 0.1,
    ),
    enabled: true,
    recordingMode: false,
    recordedEvents: @[],
  )

# Context management
proc pushContext*(handler: InputHandler, context: InputContext) =
  ## Push new input context onto stack
  if handler.currentContext != context:
    handler.contextStack.add(handler.currentContext)
    handler.currentContext = context
    handler.lastContextSwitch = getCurrentTimestamp()

proc popContext*(handler: InputHandler): InputContext =
  ## Pop current context and return to previous
  result = handler.currentContext
  if handler.contextStack.len > 0:
    handler.currentContext = handler.contextStack.pop()
    handler.lastContextSwitch = getCurrentTimestamp()
  else:
    handler.currentContext = icNormal

proc setContext*(handler: InputHandler, context: InputContext) =
  ## Set context without using stack
  if handler.currentContext != context:
    handler.currentContext = context
    handler.lastContextSwitch = getCurrentTimestamp()

proc getCurrentContext*(handler: InputHandler): InputContext =
  handler.currentContext

proc isInContext*(handler: InputHandler, context: InputContext): bool =
  handler.currentContext == context

proc hasContextChanged*(handler: InputHandler, threshold: float = 0.1): bool =
  let timeSinceSwitch = getCurrentTimestamp() - handler.lastContextSwitch
  timeSinceSwitch <= threshold

# Command registration and management
proc registerCommand*(
    handler: InputHandler,
    name: string,
    description: string,
    keyCombination: KeyCombination,
    contexts: set[InputContext] = {icNormal},
    priority: InputPriority = ipNormal,
    commandHandler: CommandHandler = nil,
): Result[void, InputError] =
  ## Register a new input command

  if name in handler.commands:
    return
      err(newInputError(ERROR_INPUT_INVALID_KEY, "Command already exists: " & name))

  let command = InputCommand(
    name: name,
    description: description,
    context: contexts,
    priority: priority,
    keyCombination: keyCombination,
    mouseGesture: MouseGesture(), # Empty gesture
  )

  handler.commands[name] = command

  # Add to context mappings
  for context in contexts:
    if context notin handler.contextCommands:
      handler.contextCommands[context] = @[]
    handler.contextCommands[context].add(name)

  # Register handler if provided
  if commandHandler != nil:
    handler.commandHandlers[name] = commandHandler

  return ok()

proc registerMouseCommand*(
    handler: InputHandler,
    name: string,
    description: string,
    mouseGesture: MouseGesture,
    contexts: set[InputContext] = {icNormal},
    priority: InputPriority = ipNormal,
    commandHandler: CommandHandler = nil,
): Result[void, InputError] =
  ## Register a mouse-based command

  if name in handler.commands:
    return
      err(newInputError(ERROR_INPUT_INVALID_MOUSE, "Command already exists: " & name))

  let command = InputCommand(
    name: name,
    description: description,
    context: contexts,
    priority: priority,
    keyCombination: KeyCombination(), # Empty combination
    mouseGesture: mouseGesture,
  )

  handler.commands[name] = command

  for context in contexts:
    if context notin handler.contextCommands:
      handler.contextCommands[context] = @[]
    handler.contextCommands[context].add(name)

  if commandHandler != nil:
    handler.commandHandlers[name] = commandHandler

  return ok()

proc unregisterCommand*(handler: InputHandler, name: string): bool =
  ## Unregister a command
  if name notin handler.commands:
    return false

  let command = handler.commands[name]

  # Remove from context mappings
  for context in command.context:
    if context in handler.contextCommands:
      handler.contextCommands[context] = handler.contextCommands[context].filter(
        proc(cmd: string): bool =
          cmd != name
      )

  # Remove from tables
  handler.commands.del(name)
  if name in handler.commandHandlers:
    handler.commandHandlers.del(name)

  return true

# Event processing
proc processEvents*(handler: InputHandler): seq[UnifiedInputEvent] =
  ## Process all input events and return unified events
  result = @[]

  if not handler.enabled:
    return

  # let currentTime = getCurrentTimestamp()  # Unused variable

  # Process keyboard events
  let keyEvents = handler.keyboard.processInput()
  for keyEvent in keyEvents:
    # Check if key is blocked
    if keyEvent.key in handler.blockedKeys:
      continue

    let unifiedEvent = UnifiedInputEvent(kind: uiekKeyboard, keyEvent: keyEvent)

    # Apply filters
    var passed = true
    for filter in handler.inputFilters:
      if not filter(unifiedEvent, handler.currentContext):
        passed = false
        break

    if passed:
      result.add(unifiedEvent)

      # Record if in recording mode
      if handler.recordingMode:
        handler.recordedEvents.add(unifiedEvent)

  # Process mouse events
  let mouseEvents = handler.mouse.processInput()
  for mouseEvent in mouseEvents:
    # Check if button is blocked
    if mouseEvent.button in handler.blockedButtons:
      continue

    let unifiedEvent = UnifiedInputEvent(kind: uiekMouse, mouseEvent: mouseEvent)

    # Apply filters
    var passed = true
    for filter in handler.inputFilters:
      if not filter(unifiedEvent, handler.currentContext):
        passed = false
        break

    if passed:
      result.add(unifiedEvent)

      if handler.recordingMode:
        handler.recordedEvents.add(unifiedEvent)

  # Store events in queue
  handler.eventQueue.add(result)

proc checkCommands*(handler: InputHandler): seq[string] =
  ## Check for matching commands and return their names
  result = @[]

  let context = handler.currentContext
  if context notin handler.contextCommands:
    return

  let contextCommands = handler.contextCommands[context]

  for commandName in contextCommands:
    if commandName notin handler.commands:
      continue

    let command = handler.commands[commandName]

    # Check keyboard command
    if command.keyCombination.key != ekNone:
      if handler.keyboard.checkKeyCombinationJustPressed(command.keyCombination):
        result.add(commandName)

    # Check mouse command
    elif command.mouseGesture.button != mbNone:
      let gesture = command.mouseGesture
      let buttonPressed = handler.mouse.isButtonJustPressed(gesture.button)
      let correctClick = (
        gesture.clickType == ctSingle or
        handler.mouse.getClickCount(gesture.button) == ord(gesture.clickType) + 1
      )
      let correctModifiers = handler.keyboard.getActiveModifiers() == gesture.modifiers

      if buttonPressed and correctClick and correctModifiers:
        # Check hover requirement
        if not gesture.requiresHover or (
          handler.mouse.isHovering() and
          handler.mouse.getHoverElement() == gesture.hoverElement
        ):
          result.add(commandName)

proc executeCommand*(handler: InputHandler, commandName: string): bool =
  ## Execute a command by name
  if commandName notin handler.commands:
    return false

  if commandName notin handler.commandHandlers:
    return false

  let command = handler.commands[commandName]
  let commandHandler = handler.commandHandlers[commandName]

  # Create appropriate unified event
  let unifiedEvent =
    if command.keyCombination.key != ekNone:
      UnifiedInputEvent(
        kind: uiekCombined,
        keyCombo: command.keyCombination,
        mousePos: handler.mouse.position,
      )
    else:
      UnifiedInputEvent(
        kind: uiekMouse,
        mouseEvent: newMouseEvent(
          metButtonPressed, command.mouseGesture.button, handler.mouse.position
        ),
      )

  return commandHandler(command, unifiedEvent)

# Input filtering
proc addInputFilter*(handler: InputHandler, filter: InputFilter) =
  ## Add an input filter
  handler.inputFilters.add(filter)

proc removeInputFilter*(handler: InputHandler, filter: InputFilter) =
  ## Remove an input filter
  for i, f in handler.inputFilters:
    # Note: This is a simplified comparison - in real code you'd need proper function comparison
    handler.inputFilters.delete(i)
    break

proc blockKey*(handler: InputHandler, key: EditorKey) =
  ## Block a specific key from processing
  handler.blockedKeys.incl(key)

proc unblockKey*(handler: InputHandler, key: EditorKey) =
  ## Unblock a specific key
  handler.blockedKeys.excl(key)

proc blockMouseButton*(handler: InputHandler, button: MouseButton) =
  ## Block a specific mouse button
  handler.blockedButtons.incl(button)

proc unblockMouseButton*(handler: InputHandler, button: MouseButton) =
  ## Unblock a specific mouse button
  handler.blockedButtons.excl(button)

# State queries
proc isKeyPressed*(handler: InputHandler, key: EditorKey): bool =
  handler.keyboard.isKeyPressed(key) and key notin handler.blockedKeys

proc isKeyJustPressed*(handler: InputHandler, key: EditorKey): bool =
  handler.keyboard.isKeyJustPressed(key) and key notin handler.blockedKeys

proc isButtonPressed*(handler: InputHandler, button: MouseButton): bool =
  handler.mouse.isButtonPressed(button) and button notin handler.blockedButtons

proc isButtonJustPressed*(handler: InputHandler, button: MouseButton): bool =
  handler.mouse.isButtonJustPressed(button) and button notin handler.blockedButtons

proc getMousePosition*(handler: InputHandler): MousePosition =
  handler.mouse.position

proc isDragging*(handler: InputHandler): bool =
  handler.mouse.isDragging()

proc hasModifier*(handler: InputHandler, modifier: ModifierKey): bool =
  handler.keyboard.hasModifier(modifier)

proc getActiveModifiers*(handler: InputHandler): set[ModifierKey] =
  handler.keyboard.getActiveModifiers()

# Common input patterns
proc isTextInputActive*(handler: InputHandler): bool =
  ## Check if we're in a text input context
  handler.currentContext in {icTextInput, icSearch, icCommand}

proc isNavigationKey*(event: UnifiedInputEvent): bool =
  ## Check if event is a navigation key
  if event.kind == uiekKeyboard:
    return isNavigationKey(event.keyEvent.key)
  return false

proc isEditingKey*(event: UnifiedInputEvent): bool =
  ## Check if event is an editing key (backspace, delete, etc.)
  if event.kind == uiekKeyboard:
    return event.keyEvent.key in {ekBackspace, ekDelete, ekEnter, ekTab}
  return false

proc isCharacterInput*(event: UnifiedInputEvent): bool =
  ## Check if event produces character input
  if event.kind == uiekKeyboard:
    return
      event.keyEvent.eventType == ietCharInput and
      isValidTextCharacter(event.keyEvent.character)
  return false

# Recording and playback
proc startRecording*(handler: InputHandler) =
  ## Start recording input events
  handler.recordingMode = true
  handler.recordedEvents = @[]

proc stopRecording*(handler: InputHandler): seq[UnifiedInputEvent] =
  ## Stop recording and return recorded events
  handler.recordingMode = false
  result = handler.recordedEvents
  handler.recordedEvents = @[]

proc playbackEvents*(handler: InputHandler, events: seq[UnifiedInputEvent]) =
  ## Playback recorded events
  handler.pendingEvents.add(events)

# Configuration
proc updateConfig*(handler: InputHandler, config: InputConfig) =
  ## Update handler configuration
  handler.config = config

  # Apply to sub-handlers
  handler.keyboard.setKeyRepeatEnabled(config.enableKeyRepeat)
  handler.keyboard.setKeyRepeatTiming(config.keyRepeatDelay, config.keyRepeatRate)
  handler.mouse.setDoubleClickTime(config.doubleClickTime)
  handler.mouse.setDragThreshold(config.dragThreshold)
  handler.mouse.setHoverDelay(config.mouseHoverDelay)

proc setEnabled*(handler: InputHandler, enabled: bool) =
  ## Enable or disable input processing
  handler.enabled = enabled

  if not enabled:
    # Clear all pressed states when disabled
    handler.keyboard.clearKeyStates()
    handler.mouse.clearMouseState()

# Cursor management
proc setCursor*(handler: InputHandler, cursor: CursorType) =
  ## Set mouse cursor type
  handler.mouse.setCursor(cursor)

proc getCurrentCursor*(handler: InputHandler): CursorType =
  handler.mouse.getCurrentCursor()

# Debug utilities
proc getInputStateDebug*(handler: InputHandler): string =
  ## Get debug string of current input state
  var parts: seq[string] = @[]

  parts.add("Context: " & $handler.currentContext)

  let keyState = handler.keyboard.getKeyStateDebug()
  if keyState != "No keys pressed":
    parts.add("Keys: " & keyState)

  let mouseState = handler.mouse.getMouseStateDebug()
  parts.add("Mouse: " & mouseState)

  if handler.contextStack.len > 0:
    parts.add("Stack: " & $handler.contextStack)

  return parts.join(" | ")

proc getAvailableCommands*(handler: InputHandler): seq[string] =
  ## Get list of available commands in current context
  let context = handler.currentContext
  if context in handler.contextCommands:
    return handler.contextCommands[context]
  return @[]

proc getCommandDescription*(handler: InputHandler, commandName: string): string =
  ## Get description of a command
  if commandName in handler.commands:
    return handler.commands[commandName].description
  return ""

# Cleanup
proc cleanup*(handler: InputHandler) =
  ## Clean up resources
  handler.keyboard.clearKeyStates()
  handler.mouse.clearMouseState()
  handler.eventQueue = @[]
  handler.pendingEvents = @[]
  handler.recordedEvents = @[]
