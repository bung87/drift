## Mouse input abstraction for Drift editor
## Provides clean interface for mouse handling without Raylib dependencies

import raylib as rl
import std/[tables, strutils, math]
import ../../shared/[constants, utils]
import keyboard

# Mouse button enumeration
type MouseButton* = enum
  mbNone = "none"
  mbLeft = "left"
  mbRight = "right"
  mbMiddle = "middle"
  mbX1 = "x1" # Additional mouse buttons
  mbX2 = "x2"

# Mouse event types
type MouseEventType* = enum
  metButtonPressed = "button_pressed"
  metButtonReleased = "button_released"
  metMoved = "moved"
  metScrolled = "scrolled"
  metEntered = "entered" # Mouse entered window
  metLeft = "left" # Mouse left window
  metHover = "hover" # Hovering over element
  metDragStart = "drag_start"
  metDragMove = "drag_move"
  metDragEnd = "drag_end"

# Click types
type ClickType* = enum
  ctSingle = "single"
  ctDouble = "double"
  ctTriple = "triple"

# Mouse cursor types
type CursorType* = enum
  curDefault = "default"
  curText = "text"
  curHand = "hand"
  curResize = "resize"
  curResizeH = "resize_h" # Horizontal resize
  curResizeV = "resize_v" # Vertical resize
  curResizeNE = "resize_ne" # Diagonal resize
  curResizeNW = "resize_nw"
  curMove = "move"
  curNotAllowed = "not_allowed"
  curWait = "wait"
  curCrosshair = "crosshair"

# Mouse position
type MousePosition* = object
  x*: float32
  y*: float32

# Mouse event
type MouseEvent* = object
  eventType*: MouseEventType
  button*: MouseButton
  position*: MousePosition
  previousPosition*: MousePosition
  scrollDelta*: MousePosition # For scroll events
  clickType*: ClickType
  clickCount*: int
  modifiers*: set[ModifierKey] # From keyboard module
  timestamp*: float
  deltaTime*: float

# Button state tracking
type ButtonState* = object
  isPressed*: bool
  pressTime*: float
  pressPosition*: MousePosition
  clickCount*: int
  lastClickTime*: float

# Drag state
type DragState* = object
  isDragging*: bool
  button*: MouseButton
  startPosition*: MousePosition
  currentPosition*: MousePosition
  startTime*: float
  threshold*: float32 # Minimum distance to start drag

# Hover state
type HoverState* = object
  isHovering*: bool
  startTime*: float
  position*: MousePosition
  element*: string # ID of hovered element

# Mouse handler
type MouseHandler* = ref object
  position*: MousePosition
  previousPosition*: MousePosition
  buttonStates*: Table[MouseButton, ButtonState]
  pressedButtons*: set[MouseButton]
  eventQueue*: seq[MouseEvent]
  dragState*: DragState
  hoverState*: HoverState
  lastMoveTime*: float
  isInWindow*: bool
  currentCursor*: CursorType

  # Configuration
  doubleClickTime*: float
  tripleClickTime*: float
  dragThreshold*: float32
  hoverDelay*: float

# Raylib to MouseButton mapping
const RaylibButtonMap = {
  rl.MouseButton.Left: mbLeft,
  rl.MouseButton.Right: mbRight,
  rl.MouseButton.Middle: mbMiddle,
}.toTable

# Constructor
proc newMouseHandler*(): MouseHandler =
  result = MouseHandler(
    position: MousePosition(x: 0, y: 0),
    previousPosition: MousePosition(x: 0, y: 0),
    buttonStates: initTable[MouseButton, ButtonState](),
    pressedButtons: {},
    eventQueue: @[],
    dragState: DragState(threshold: 5.0),
    hoverState: HoverState(),
    lastMoveTime: 0.0,
    isInWindow: true,
    currentCursor: curDefault,
    doubleClickTime: DOUBLE_CLICK_TIME,
    tripleClickTime: TRIPLE_CLICK_TIME,
    dragThreshold: 5.0,
    hoverDelay: 1.0,
  )

# Position utilities
proc newMousePosition*(x, y: float32): MousePosition =
  MousePosition(x: x, y: y)

proc `+`*(a, b: MousePosition): MousePosition =
  MousePosition(x: a.x + b.x, y: a.y + b.y)

proc `-`*(a, b: MousePosition): MousePosition =
  MousePosition(x: a.x - b.x, y: a.y - b.y)

proc distance*(a, b: MousePosition): float32 =
  let dx = a.x - b.x
  let dy = a.y - b.y
  sqrt(dx * dx + dy * dy)

proc `==`*(a, b: MousePosition): bool =
  abs(a.x - b.x) < 0.001 and abs(a.y - b.y) < 0.001

# Mouse button utilities
proc toMouseButton*(raylibButton: rl.MouseButton): MouseButton =
  if raylibButton in RaylibButtonMap:
    return RaylibButtonMap[raylibButton]
  return mbNone

# Event creation
proc newMouseEvent*(
    eventType: MouseEventType,
    button: MouseButton = mbNone,
    position: MousePosition = MousePosition(x: 0, y: 0),
    previousPosition: MousePosition = MousePosition(x: 0, y: 0),
    scrollDelta: MousePosition = MousePosition(x: 0, y: 0),
    clickType: ClickType = ctSingle,
    clickCount: int = 0,
    modifiers: set[ModifierKey] = {},
): MouseEvent =
  MouseEvent(
    eventType: eventType,
    button: button,
    position: position,
    previousPosition: previousPosition,
    scrollDelta: scrollDelta,
    clickType: clickType,
    clickCount: clickCount,
    modifiers: modifiers,
    timestamp: getCurrentTimestamp(),
    deltaTime: 0.0,
  )

# Button state management
proc updateButtonState*(
    handler: MouseHandler,
    button: MouseButton,
    isPressed: bool,
    position: MousePosition,
    currentTime: float,
) =
  if button notin handler.buttonStates:
    handler.buttonStates[button] = ButtonState()

  var state = handler.buttonStates[button]
  let wasPressed = state.isPressed

  state.isPressed = isPressed

  if isPressed and not wasPressed:
    # Button just pressed
    let timeSinceLastClick = currentTime - state.lastClickTime

    if timeSinceLastClick <= handler.doubleClickTime:
      state.clickCount += 1
    else:
      state.clickCount = 1

    state.pressTime = currentTime
    state.pressPosition = position
    state.lastClickTime = currentTime
    handler.pressedButtons.incl(button)
  elif not isPressed and wasPressed:
    # Button just released
    handler.pressedButtons.excl(button)

  handler.buttonStates[button] = state

# Drag handling
proc updateDragState*(handler: MouseHandler, currentTime: float) =
  # Check if we should start dragging
  if not handler.dragState.isDragging:
    for button in handler.pressedButtons:
      if button in handler.buttonStates:
        let state = handler.buttonStates[button]
        let dragDistance = distance(handler.position, state.pressPosition)

        if dragDistance >= handler.dragThreshold:
          handler.dragState.isDragging = true
          handler.dragState.button = button
          handler.dragState.startPosition = state.pressPosition
          handler.dragState.currentPosition = handler.position
          handler.dragState.startTime = currentTime
          break

  # Update current drag position
  if handler.dragState.isDragging:
    handler.dragState.currentPosition = handler.position

# Hover handling
proc updateHoverState*(handler: MouseHandler, elementId: string, currentTime: float) =
  if elementId != "":
    if not handler.hoverState.isHovering:
      handler.hoverState.isHovering = true
      handler.hoverState.startTime = currentTime
      handler.hoverState.position = handler.position
      handler.hoverState.element = elementId
  else:
    handler.hoverState.isHovering = false
    handler.hoverState.element = ""

# Main input processing
proc processInput*(handler: MouseHandler): seq[MouseEvent] =
  ## Process all mouse input and return events
  result = @[]
  let currentTime = getCurrentTimestamp()

  # Get current mouse position
  let raylibPos = rl.getMousePosition()
  handler.previousPosition = handler.position
  handler.position = MousePosition(x: raylibPos.x, y: raylibPos.y)

  # Check for mouse movement
  if handler.position != handler.previousPosition:
    handler.lastMoveTime = currentTime
    result.add(
      newMouseEvent(
        metMoved,
        position = handler.position,
        previousPosition = handler.previousPosition,
      )
    )

    # Update drag state
    handler.updateDragState(currentTime)

    if handler.dragState.isDragging:
      result.add(
        newMouseEvent(
          metDragMove,
          button = handler.dragState.button,
          position = handler.position,
          previousPosition = handler.previousPosition,
        )
      )

  # Check for button presses using isMouseButtonPressed (not isMouseButtonDown)
  var anyButtonPressed = false
  
  # Debug window and mouse state
  echo "DEBUG: Window focused: ", rl.isWindowFocused()
  echo "DEBUG: Mouse position: ", handler.position.x, ", ", handler.position.y
  echo "DEBUG: Screen size: ", rl.getScreenWidth(), "x", rl.getScreenHeight()
  
  for raylibButton in rl.MouseButton.low .. rl.MouseButton.high:
    let isPressed = rl.isMouseButtonPressed(raylibButton)
    let isDown = rl.isMouseButtonDown(raylibButton)
    let isReleased = rl.isMouseButtonReleased(raylibButton)
    
    # Raw Raylib mouse state debugging
    let rawMousePos = rl.getMousePosition()
    let rawPressed = rl.isMouseButtonPressed(raylibButton)
    let rawDown = rl.isMouseButtonDown(raylibButton)
    
    echo "DEBUG: Raw Raylib - Mouse pos: ", rawMousePos.x, ", ", rawMousePos.y, " Button: ", raylibButton, " pressed: ", rawPressed, " down: ", rawDown
    echo "DEBUG: Mouse button event - raylibButton: ", raylibButton, " pressed: ", isPressed, " down: ", isDown, " released: ", isReleased
    
    if isPressed or rawPressed:
      anyButtonPressed = true
      echo "DEBUG: Mouse button converted - button: ", toMouseButton(raylibButton)
      
      if isPressed:
        let button = toMouseButton(raylibButton)
        if button != mbNone:
          handler.updateButtonState(button, true, handler.position, currentTime)

          let state = handler.buttonStates[button]
          let clickType =
            case state.clickCount
            of 1: ctSingle
            of 2: ctDouble
            else: ctTriple

          echo "DEBUG: Generating mouse button press event - button: ", button, ", clickType: ", clickType
          result.add(
            newMouseEvent(
              metButtonPressed,
              button = button,
              position = handler.position,
              clickType = clickType,
              clickCount = state.clickCount,
            )
          )
  
  if not anyButtonPressed:
    echo "DEBUG: No mouse buttons detected - checking all buttons: "
    for raylibButton in rl.MouseButton.low .. rl.MouseButton.high:
      let isPressed = rl.isMouseButtonPressed(raylibButton)
      let isDown = rl.isMouseButtonDown(raylibButton)
      let isReleased = rl.isMouseButtonReleased(raylibButton)
      echo "DEBUG: Button ", raylibButton, " pressed: ", isPressed, " down: ", isDown, " released: ", isReleased

  # Check for button releases using isMouseButtonReleased
  for raylibButton in rl.MouseButton.low .. rl.MouseButton.high:
    if rl.isMouseButtonReleased(raylibButton):
      let button = toMouseButton(raylibButton)
      if button != mbNone:
        handler.updateButtonState(button, false, handler.position, currentTime)

        result.add(
          newMouseEvent(metButtonReleased, button = button, position = handler.position)
        )

        # End drag if this button was dragging
        if handler.dragState.isDragging and handler.dragState.button == button:
          result.add(
            newMouseEvent(
              metDragEnd,
              button = button,
              position = handler.position,
              previousPosition = handler.dragState.startPosition,
            )
          )
          handler.dragState.isDragging = false

  # Check for scroll wheel
  let wheelMove = rl.getMouseWheelMove()
  echo "DEBUG: Mouse handler checking wheel - wheelMove: ", wheelMove
  if wheelMove != 0.0:
    echo "DEBUG: Mouse handler generating scroll event - wheelMove: ", wheelMove
    result.add(
      newMouseEvent(
        metScrolled,
        scrollDelta = MousePosition(x: 0, y: wheelMove * MOUSE_WHEEL_SPEED.float32),
        position = handler.position,
      )
    )

# State queries
proc isButtonPressed*(handler: MouseHandler, button: MouseButton): bool =
  button in handler.pressedButtons

proc isButtonJustPressed*(handler: MouseHandler, button: MouseButton): bool =
  if button in handler.buttonStates:
    let state = handler.buttonStates[button]
    let currentTime = getCurrentTimestamp()
    return state.isPressed and (currentTime - state.pressTime) < 0.1
  return false

proc isButtonJustReleased*(handler: MouseHandler, button: MouseButton): bool =
  if button in handler.buttonStates:
    let state = handler.buttonStates[button]
    return not state.isPressed
  return false

proc getClickCount*(handler: MouseHandler, button: MouseButton): int =
  if button in handler.buttonStates:
    return handler.buttonStates[button].clickCount
  return 0

proc isDragging*(handler: MouseHandler): bool =
  handler.dragState.isDragging

proc getDragButton*(handler: MouseHandler): MouseButton =
  if handler.dragState.isDragging:
    return handler.dragState.button
  return mbNone

proc getDragStartPosition*(handler: MouseHandler): MousePosition =
  handler.dragState.startPosition

proc getDragDistance*(handler: MouseHandler): float32 =
  if handler.dragState.isDragging:
    return distance(handler.position, handler.dragState.startPosition)
  return 0.0

proc getDragDelta*(handler: MouseHandler): MousePosition =
  if handler.dragState.isDragging:
    return handler.position - handler.dragState.startPosition
  return MousePosition(x: 0, y: 0)

# Region detection utilities
proc isInRectangle*(pos: MousePosition, x, y, width, height: float32): bool =
  pos.x >= x and pos.x < x + width and pos.y >= y and pos.y < y + height

proc isInCircle*(pos: MousePosition, centerX, centerY, radius: float32): bool =
  let dx = pos.x - centerX
  let dy = pos.y - centerY
  dx * dx + dy * dy <= radius * radius

# Cursor management
proc setCursor*(handler: MouseHandler, cursor: CursorType) =
  if cursor != handler.currentCursor:
    handler.currentCursor = cursor

    # Map to Raylib cursor
    case cursor
    of curDefault:
      rl.setMouseCursor(rl.MouseCursor.Default)
    of curText:
      rl.setMouseCursor(rl.MouseCursor.IBeam)
    of curHand:
      rl.setMouseCursor(rl.MouseCursor.PointingHand)
    of curResize:
      rl.setMouseCursor(rl.MouseCursor.ResizeAll)
    of curResizeH:
      rl.setMouseCursor(rl.MouseCursor.ResizeEW)
    of curResizeV:
      rl.setMouseCursor(rl.MouseCursor.ResizeNS)
    of curResizeNE:
      rl.setMouseCursor(rl.MouseCursor.ResizeNESW)
    of curResizeNW:
      rl.setMouseCursor(rl.MouseCursor.ResizeNWSE)
    of curMove:
      rl.setMouseCursor(rl.MouseCursor.ResizeAll)
    of curNotAllowed:
      rl.setMouseCursor(rl.MouseCursor.NotAllowed)
    of curWait:
      rl.setMouseCursor(rl.MouseCursor.Default) # Raylib doesn't have wait cursor
    of curCrosshair:
      rl.setMouseCursor(rl.MouseCursor.Crosshair)

proc getCurrentCursor*(handler: MouseHandler): CursorType =
  handler.currentCursor

# Hover utilities
proc startHover*(handler: MouseHandler, elementId: string) =
  let currentTime = getCurrentTimestamp()
  handler.updateHoverState(elementId, currentTime)

proc stopHover*(handler: MouseHandler) =
  handler.hoverState.isHovering = false
  handler.hoverState.element = ""

proc isHovering*(handler: MouseHandler): bool =
  handler.hoverState.isHovering

proc getHoverElement*(handler: MouseHandler): string =
  handler.hoverState.element

proc getHoverDuration*(handler: MouseHandler): float =
  if handler.hoverState.isHovering:
    return getCurrentTimestamp() - handler.hoverState.startTime
  return 0.0

proc isHoverTimeout*(handler: MouseHandler): bool =
  handler.isHovering() and handler.getHoverDuration() >= handler.hoverDelay

# Configuration
proc setDoubleClickTime*(handler: MouseHandler, time: float) =
  handler.doubleClickTime = time

proc setTripleClickTime*(handler: MouseHandler, time: float) =
  handler.tripleClickTime = time

proc setDragThreshold*(handler: MouseHandler, threshold: float32) =
  handler.dragThreshold = threshold
  handler.dragState.threshold = threshold

proc setHoverDelay*(handler: MouseHandler, delay: float) =
  handler.hoverDelay = delay

# Debug utilities
proc getMouseStateDebug*(handler: MouseHandler): string =
  var parts: seq[string] = @[]

  parts.add($"Position: ({handler.position.x:.1f}, {handler.position.y:.1f})")

  if handler.pressedButtons.len > 0:
    parts.add("Pressed: " & $handler.pressedButtons)

  if handler.isDragging():
    parts.add($"Dragging: {handler.dragState.button}")

  if handler.isHovering():
    parts.add($"Hovering: {handler.hoverState.element}")

  return parts.join(", ")

# Reset state (useful when window loses focus)
proc clearMouseState*(handler: MouseHandler) =
  handler.buttonStates.clear()
  handler.pressedButtons = {}
  handler.dragState.isDragging = false
  handler.hoverState.isHovering = false
