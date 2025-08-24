## InputDialog - Reusable modal input dialog for Drift
## Refactored to use ComponentManager architecture

import std/[options, tables]
import raylib as rl
import results
import ../services/ui_service
import ../services/component_manager
import ../infrastructure/input/input_handler
import ../infrastructure/input/keyboard
import ../infrastructure/input/mouse
import ../infrastructure/rendering/theme
import ../infrastructure/ui/cursor_manager
import ../shared/errors

# Callback type for dialog result
type InputDialogCallback* = proc(value: Option[string]) {.closure.}

# InputDialog component
type InputDialog* = ref object of UIComponent
  # ComponentManager integration
  componentManager*: ComponentManager
  
  # Dialog state
  prompt*: string
  value*: string
  placeholder*: string
  callback*: Option[InputDialogCallback]
  okLabel*: string
  cancelLabel*: string
  errorMessage*: string
  
  # UI state
  dialogBounds*: rl.Rectangle
  inputBounds*: rl.Rectangle
  okButtonBounds*: rl.Rectangle
  cancelButtonBounds*: rl.Rectangle
  isOkHovered*: bool
  isCancelHovered*: bool
  showCursor*: bool
  cursorBlinkTime*: float32

# Constants
const
  DIALOG_WIDTH = 400.0
  DIALOG_HEIGHT = 180.0
  INPUT_HEIGHT = 36.0
  BUTTON_WIDTH = 90.0
  BUTTON_HEIGHT = 32.0
  PADDING = 24.0

# Forward declarations
proc handleInput*(dialog: InputDialog, event: UnifiedInputEvent): bool
proc handleMouseEvent*(dialog: InputDialog, event: MouseEvent): bool
proc handleKeyboardEvent*(dialog: InputDialog, event: InputEvent): bool
proc updateLayout*(dialog: InputDialog)
proc executeOk*(dialog: InputDialog)
proc executeCancel*(dialog: InputDialog)
proc updateButtonHover*(dialog: InputDialog, mousePos: rl.Vector2)
proc hide*(dialog: InputDialog)

# Constructor
proc newInputDialog*(
  componentManager: ComponentManager,
  id: string
): InputDialog =
  ## Create new input dialog using ComponentManager
  
  let dialog = InputDialog(
    componentManager: componentManager,
    prompt: "",
    value: "",
    placeholder: "",
    callback: none(InputDialogCallback),
    okLabel: "OK",
    cancelLabel: "Cancel",
    errorMessage: "",
    dialogBounds: rl.Rectangle(),
    inputBounds: rl.Rectangle(),
    okButtonBounds: rl.Rectangle(),
    cancelButtonBounds: rl.Rectangle(),
    isOkHovered: false,
    isCancelHovered: false,
    showCursor: true,
    cursorBlinkTime: 0.0
  )
  
  # Initialize UIComponent base
  dialog.id = id
  dialog.name = "InputDialog"
  dialog.state = csHidden
  dialog.bounds = rl.Rectangle(x: 0, y: 0, width: DIALOG_WIDTH, height: DIALOG_HEIGHT)
  dialog.zIndex = 2000 # Very high z-index for modal
  dialog.isVisible = false
  dialog.isEnabled = true
  dialog.isDirty = true
  dialog.data = initTable[string, string]()
  
  # Register with ComponentManager
  let registerResult = componentManager.registerComponent(
    id,
    dialog,
    proc(event: UnifiedInputEvent): bool =
      if not dialog.isVisible:
        return false
      
      case event.kind:
      of uiekMouse:
        return dialog.handleMouseEvent(event.mouseEvent)
      of uiekKeyboard:
        return dialog.handleKeyboardEvent(event.keyEvent)
      else:
        return false,
    proc(bounds: rl.Rectangle) = 
      dialog.bounds = bounds
      let screenWidth = rl.getScreenWidth().float32
      let screenHeight = rl.getScreenHeight().float32
      
      # Draw overlay
      let overlayColor = rl.Color(r: 0, g: 0, b: 0, a: 128)
      rl.drawRectangle(0, 0, screenWidth.int32, screenHeight.int32, overlayColor)
      
      # Draw dialog background
      let bgColor = dialog.componentManager.getUIColor(uiPopup)
      rl.drawRectangleRounded(dialog.dialogBounds, 0.08, 12, bgColor)
      
      # Draw dialog border
      let borderColor = dialog.componentManager.getUIColor(uiBorder)
      rl.drawRectangleRoundedLines(dialog.dialogBounds, 0.08, 12, 2.0, borderColor)
      
      # Draw prompt text
      let textColor = dialog.componentManager.getUIColor(uiText)
      rl.drawText(
        dialog.prompt,
        (dialog.dialogBounds.x + PADDING).int32,
        (dialog.dialogBounds.y + 18).int32,
        14,
        textColor
      )
      
      # Draw input field
      let inputBgColor = dialog.componentManager.getUIColor(uiBackground)
      rl.drawRectangleRounded(dialog.inputBounds, 0.12, 8, inputBgColor)
      rl.drawRectangleRoundedLines(dialog.inputBounds, 0.12, 8, 2.0, borderColor)
      
      # Draw input text or placeholder
      let textToShow = if dialog.value.len > 0: dialog.value else: dialog.placeholder
      let inputTextColor = if dialog.value.len > 0:
        dialog.componentManager.getUIColor(uiText)
      else:
        dialog.componentManager.getUIColor(uiTextMuted)
      
      if textToShow.len > 0:
        rl.drawText(
          textToShow,
          (dialog.inputBounds.x + 8).int32,
          (dialog.inputBounds.y + 8).int32,
          14,
          inputTextColor
        )
      
      # Draw buttons
      let buttonColor = dialog.componentManager.getUIColor(uiButton)
      let buttonHoverColor = dialog.componentManager.getUIColor(uiButtonHover)
      
      # OK button
      let okColor = if dialog.isOkHovered: buttonHoverColor else: buttonColor
      rl.drawRectangleRounded(dialog.okButtonBounds, 0.18, 8, okColor)
      rl.drawText(
        dialog.okLabel,
        (dialog.okButtonBounds.x + 18).int32,
        (dialog.okButtonBounds.y + 8).int32,
        14,
        textColor
      )
      
      # Cancel button
      let cancelColor = if dialog.isCancelHovered: buttonHoverColor else: buttonColor
      rl.drawRectangleRounded(dialog.cancelButtonBounds, 0.18, 8, cancelColor)
      rl.drawText(
        dialog.cancelLabel,
        (dialog.cancelButtonBounds.x + 8).int32,
        (dialog.cancelButtonBounds.y + 8).int32,
        14,
        textColor
      )
      
      dialog.isDirty = false
  )
  
  if registerResult.isErr:
    raise newException(EditorError, "Failed to register input dialog component: " & registerResult.error.msg)
  
  # Update layout
  dialog.updateLayout()
  
  # Register input handlers
  var keyHandlers = initTable[KeyCombination, proc()]()
  keyHandlers[KeyCombination(key: ekEnter, modifiers: {})] = proc() = dialog.executeOk()
  keyHandlers[KeyCombination(key: ekEscape, modifiers: {})] = proc() = dialog.executeCancel()
  
  let inputResult = componentManager.registerInputHandlers(
    id,
    keyHandlers,
    initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  )
  if inputResult.isErr:
    raise newException(EditorError, "Failed to register input handlers: " & inputResult.error.msg)
  
  return dialog

# Input event handling
proc handleInput*(dialog: InputDialog, event: UnifiedInputEvent): bool =
  ## Handle unified input events
  if not dialog.isVisible:
    return false
  
  case event.kind:
  of uiekMouse:
    return dialog.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return dialog.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc handleKeyboardEvent*(dialog: InputDialog, event: InputEvent): bool =
  ## Handle keyboard events for text input
  if not dialog.isVisible:
    return false
  
  # Handle character input
  if event.eventType == ietCharInput:
    let char = char(event.character.int32)
    if char.ord >= 32 and char.ord <= 126:  # Printable ASCII
      dialog.value.add(char)
      dialog.errorMessage = ""  # Clear error on input
      dialog.componentManager.markComponentDirty(dialog.id)
      return true
  
  # Handle backspace
  if event.eventType == ietKeyPressed and event.key == ekBackspace:
    if dialog.value.len > 0:
      dialog.value = dialog.value[0..^2]
      dialog.componentManager.markComponentDirty(dialog.id)
      return true
  
  return false

proc handleMouseEvent*(dialog: InputDialog, event: MouseEvent): bool =
  ## Handle mouse events
  if not dialog.isVisible:
    return false
  
  let mousePos = rl.Vector2(x: event.position.x, y: event.position.y)
  
  case event.eventType:
  of metMoved:
    dialog.updateButtonHover(mousePos)
    # Only consume mouse move events if we're actually doing something with them
    # This allows hover effects to work in other components
    return false
  of metButtonPressed:
    if event.button == mbLeft:
      # Check button clicks
      if rl.checkCollisionPointRec(mousePos, dialog.okButtonBounds):
        dialog.executeOk()
        return true
      elif rl.checkCollisionPointRec(mousePos, dialog.cancelButtonBounds):
        dialog.executeCancel()
        return true
      elif rl.checkCollisionPointRec(mousePos, dialog.dialogBounds):
        # Click inside dialog but not on buttons - keep focus
        return true
      else:
        # Click outside dialog - cancel
        dialog.executeCancel()
        return true
  else:
    discard
  
  return false

# Input handling registration
proc registerInputHandlers*(dialog: InputDialog): Result[void, EditorError] =
  ## Register standardized input handlers using ComponentManager
  
  var keyHandlers = initTable[KeyCombination, proc()]()
  
  # Enter to confirm
  keyHandlers[KeyCombination(key: ekEnter, modifiers: {})] = proc() =
    dialog.executeOk()
  
  # Escape to cancel
  keyHandlers[KeyCombination(key: ekEscape, modifiers: {})] = proc() =
    dialog.executeCancel()
  
  let keyResult = dialog.componentManager.registerInputHandlers(
    dialog.id,
    keyHandlers,
    initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  )
  
  if keyResult.isErr:
    return err(keyResult.error)
  
  # Register mouse handlers
  let dragResult = dialog.componentManager.registerDragHandlers(
    dialog.id,
    proc(pos: MousePosition) =
      let mousePos = rl.Vector2(x: pos.x, y: pos.y)
      if rl.checkCollisionPointRec(mousePos, dialog.okButtonBounds):
        dialog.executeOk()
      elif rl.checkCollisionPointRec(mousePos, dialog.cancelButtonBounds):
        dialog.executeCancel()
      elif not rl.checkCollisionPointRec(mousePos, dialog.dialogBounds):
        # Click outside dialog
        dialog.executeCancel(),
    proc(pos: MousePosition) =
      let mousePos = rl.Vector2(x: pos.x, y: pos.y)
      dialog.updateButtonHover(mousePos),
    proc(pos: MousePosition) = discard
  )
  
  return dragResult



proc handleMouseClick*(dialog: InputDialog, pos: MousePosition) =
  ## Handle mouse click events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  
  if rl.checkCollisionPointRec(mousePos, dialog.okButtonBounds):
    dialog.executeOk()
  elif rl.checkCollisionPointRec(mousePos, dialog.cancelButtonBounds):
    dialog.executeCancel()
  elif not rl.checkCollisionPointRec(mousePos, dialog.dialogBounds):
    # Click outside dialog
    dialog.executeCancel()

proc handleMouseMove*(dialog: InputDialog, pos: MousePosition) =
  ## Handle mouse move events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  dialog.updateButtonHover(mousePos)

proc updateButtonHover*(dialog: InputDialog, mousePos: rl.Vector2) =
  ## Update button hover states
  let wasOkHovered = dialog.isOkHovered
  let wasCancelHovered = dialog.isCancelHovered
  
  dialog.isOkHovered = rl.checkCollisionPointRec(mousePos, dialog.okButtonBounds)
  dialog.isCancelHovered = rl.checkCollisionPointRec(mousePos, dialog.cancelButtonBounds)
  
  if wasOkHovered != dialog.isOkHovered or wasCancelHovered != dialog.isCancelHovered:
    dialog.componentManager.markComponentDirty(dialog.id)
    
    # Set cursor
    if dialog.isOkHovered or dialog.isCancelHovered:
      dialog.componentManager.setCursor(dialog.id, rl.MouseCursor.PointingHand, cpUI)
    else:
      dialog.componentManager.clearCursor(dialog.id)

proc executeOk*(dialog: InputDialog) =
  ## Execute OK action
  if dialog.value.len == 0:
    dialog.errorMessage = "Value required"
    dialog.componentManager.markComponentDirty(dialog.id)
    return
  
  if dialog.callback.isSome:
    dialog.callback.get()(some(dialog.value))
  
  dialog.hide()

proc executeCancel*(dialog: InputDialog) =
  ## Execute Cancel action
  if dialog.callback.isSome:
    dialog.callback.get()(none(string))
  
  dialog.hide()

# Layout management
proc updateLayout*(dialog: InputDialog) =
  ## Update layout using window dimensions
  let screenWidth = rl.getScreenWidth().float32
  let screenHeight = rl.getScreenHeight().float32
  
  let dialogWidth = min(DIALOG_WIDTH, screenWidth * 0.8)
  let dialogHeight = DIALOG_HEIGHT
  let dialogX = (screenWidth - dialogWidth) / 2
  let dialogY = (screenHeight - dialogHeight) / 2
  
  dialog.dialogBounds = rl.Rectangle(
    x: dialogX,
    y: dialogY,
    width: dialogWidth,
    height: dialogHeight
  )
  
  # Input bounds
  dialog.inputBounds = rl.Rectangle(
    x: dialogX + PADDING,
    y: dialogY + 54,
    width: dialogWidth - PADDING * 2,
    height: INPUT_HEIGHT
  )
  
  # Button bounds
  let buttonY = dialogY + dialogHeight - BUTTON_HEIGHT - PADDING
  dialog.cancelButtonBounds = rl.Rectangle(
    x: dialogX + dialogWidth - BUTTON_WIDTH - PADDING,
    y: buttonY,
    width: BUTTON_WIDTH,
    height: BUTTON_HEIGHT
  )
  
  dialog.okButtonBounds = rl.Rectangle(
    x: dialog.cancelButtonBounds.x - BUTTON_WIDTH - 12,
    y: buttonY,
    width: BUTTON_WIDTH,
    height: BUTTON_HEIGHT
  )
  
  # Update component bounds
  dialog.bounds = dialog.dialogBounds
  discard dialog.componentManager.updateComponentBounds(dialog.id, dialog.bounds)

# Rendering using ComponentManager services
proc render*(dialog: InputDialog) =
  ## Render using ComponentManager's renderer and theme
  if not dialog.isVisible:
    return
  
  let screenWidth = rl.getScreenWidth().float32
  let screenHeight = rl.getScreenHeight().float32
  
  # Draw overlay
  let overlayColor = rl.Color(r: 0, g: 0, b: 0, a: 128)
  rl.drawRectangle(0, 0, screenWidth.int32, screenHeight.int32, overlayColor)
  
  # Draw dialog background
  let bgColor = dialog.componentManager.getUIColor(uiPopup)
  rl.drawRectangleRounded(dialog.dialogBounds, 0.08, 12, bgColor)
  
  # Draw dialog border
  let borderColor = dialog.componentManager.getUIColor(uiBorder)
  rl.drawRectangleRoundedLines(dialog.dialogBounds, 0.08, 12, 2.0, borderColor)
  
  # Draw prompt text
  let textColor = dialog.componentManager.getUIColor(uiText)
  rl.drawText(
    dialog.prompt,
    (dialog.dialogBounds.x + PADDING).int32,
    (dialog.dialogBounds.y + 18).int32,
    14,
    textColor
  )
  
  # Draw input field
  let inputBgColor = dialog.componentManager.getUIColor(uiBackground)
  rl.drawRectangleRounded(dialog.inputBounds, 0.12, 8, inputBgColor)
  rl.drawRectangleRoundedLines(dialog.inputBounds, 0.12, 8, 2.0, borderColor)
  
  # Draw input text or placeholder
  let textToShow = if dialog.value.len > 0: dialog.value else: dialog.placeholder
  let inputTextColor = if dialog.value.len > 0:
    dialog.componentManager.getUIColor(uiText)
  else:
    dialog.componentManager.getUIColor(uiTextMuted)
  
  if textToShow.len > 0:
    rl.drawText(
      textToShow,
      (dialog.inputBounds.x + 8).int32,
      (dialog.inputBounds.y + 8).int32,
      14,
      inputTextColor
    )
  
  # Draw cursor
  if dialog.value.len > 0 and dialog.showCursor:
    let textWidth = rl.measureText(dialog.value, 14)
    let cursorX = dialog.inputBounds.x + 8 + textWidth.float32
    let cursorY = dialog.inputBounds.y + 6
    rl.drawLine(
      cursorX.int32, cursorY.int32,
      cursorX.int32, (cursorY + 20).int32,
      textColor
    )
  
  # Draw error message
  if dialog.errorMessage.len > 0:
    let errorColor = dialog.componentManager.getUIColor(uiError)
    rl.drawText(
      dialog.errorMessage,
      (dialog.inputBounds.x).int32,
      (dialog.inputBounds.y + dialog.inputBounds.height + 8).int32,
      12,
      errorColor
    )
  
  # Draw buttons
  let buttonColor = dialog.componentManager.getUIColor(uiButton)
  let buttonHoverColor = dialog.componentManager.getUIColor(uiButtonHover)
  
  # OK button
  let okColor = if dialog.isOkHovered: buttonHoverColor else: buttonColor
  rl.drawRectangleRounded(dialog.okButtonBounds, 0.18, 8, okColor)
  rl.drawText(
    dialog.okLabel,
    (dialog.okButtonBounds.x + 18).int32,
    (dialog.okButtonBounds.y + 8).int32,
    14,
    textColor
  )
  
  # Cancel button
  let cancelColor = if dialog.isCancelHovered: buttonHoverColor else: buttonColor
  rl.drawRectangleRounded(dialog.cancelButtonBounds, 0.18, 8, cancelColor)
  rl.drawText(
    dialog.cancelLabel,
    (dialog.cancelButtonBounds.x + 8).int32,
    (dialog.cancelButtonBounds.y + 8).int32,
    14,
    textColor
  )
  
  dialog.isDirty = false

# Dialog visibility and state management
proc show*(dialog: InputDialog, 
          prompt: string, 
          initial: string = "", 
          placeholder: string = "", 
          cb: InputDialogCallback = nil, 
          okLabel: string = "OK", 
          cancelLabel: string = "Cancel") =
  ## Show the input dialog
  dialog.prompt = prompt
  dialog.value = initial
  dialog.placeholder = placeholder
  dialog.callback = some(cb)
  dialog.okLabel = okLabel
  dialog.cancelLabel = cancelLabel
  dialog.errorMessage = ""
  dialog.showCursor = true
  dialog.cursorBlinkTime = 0.0
  
  dialog.isVisible = true
  dialog.updateLayout()
  discard dialog.componentManager.setComponentVisibility(dialog.id, true)
  dialog.componentManager.markComponentDirty(dialog.id)

proc hide*(dialog: InputDialog) =
  ## Hide the input dialog
  dialog.isVisible = false
  dialog.callback = none(InputDialogCallback)
  dialog.errorMessage = ""
  
  discard dialog.componentManager.setComponentVisibility(dialog.id, false)
  dialog.componentManager.clearCursor(dialog.id)
  dialog.componentManager.markComponentDirty(dialog.id)

proc update*(dialog: InputDialog, deltaTime: float32) =
  ## Update dialog animation state
  if dialog.isVisible:
    dialog.cursorBlinkTime += deltaTime
    if dialog.cursorBlinkTime >= 1.0:
      dialog.showCursor = not dialog.showCursor
      dialog.cursorBlinkTime = 0.0
      dialog.componentManager.markComponentDirty(dialog.id)

# Utility functions
proc isVisible*(dialog: InputDialog): bool =
  ## Check if dialog is visible
  dialog.isVisible

proc getValue*(dialog: InputDialog): string =
  ## Get current input value
  dialog.value

proc setValue*(dialog: InputDialog, value: string) =
  ## Set input value
  dialog.value = value
  dialog.componentManager.markComponentDirty(dialog.id)

proc setError*(dialog: InputDialog, message: string) =
  ## Set error message
  dialog.errorMessage = message
  dialog.componentManager.markComponentDirty(dialog.id)

proc clearError*(dialog: InputDialog) =
  ## Clear error message
  dialog.errorMessage = ""
  dialog.componentManager.markComponentDirty(dialog.id)

# Cleanup
proc cleanup*(dialog: InputDialog) =
  ## Clean up resources
  dialog.hide()
  discard dialog.componentManager.unregisterComponent(dialog.id)