## ConfirmationDialog - Three-button confirmation dialog for save operations
## Based on InputDialog but simplified for Save/Don't Save/Cancel workflow

import raylib as rl
import ../services/[ui_service, component_manager]
import ../infrastructure/input/[input_handler, keyboard, mouse]
import ../infrastructure/rendering/theme

# Callback type for confirmation result
type ConfirmationResult* = enum
  crSave, crDontSave, crCancel

type ConfirmationCallback* = proc(result: ConfirmationResult) {.closure.}

# ConfirmationDialog component
type ConfirmationDialog* = ref object of UIComponent
  # ComponentManager integration
  componentManager*: ComponentManager
  
  # Dialog state
  message*: string
  callback*: ConfirmationCallback
  
  # Layout
  dialogBounds*: rl.Rectangle
  saveButtonBounds*: rl.Rectangle
  dontSaveButtonBounds*: rl.Rectangle
  cancelButtonBounds*: rl.Rectangle
  
  # Button states
  isSaveHovered*: bool
  isDontSaveHovered*: bool
  isCancelHovered*: bool
  
  # Button labels
  saveLabel*: string
  dontSaveLabel*: string
  cancelLabel*: string

# Forward declarations
proc executeSave*(dialog: ConfirmationDialog)
proc executeDontSave*(dialog: ConfirmationDialog)
proc executeCancel*(dialog: ConfirmationDialog)
proc hide*(dialog: ConfirmationDialog)
proc updateButtonHover*(dialog: ConfirmationDialog, mousePos: rl.Vector2)

# Constructor
proc newConfirmationDialog*(
  componentManager: ComponentManager,
  id: string
): ConfirmationDialog =
  ## Create new confirmation dialog using ComponentManager
  
  let dialog = ConfirmationDialog(
    componentManager: componentManager,
    message: "",
    callback: nil,
    isSaveHovered: false,
    isDontSaveHovered: false,
    isCancelHovered: false,
    saveLabel: "Save",
    dontSaveLabel: "Don't Save",
    cancelLabel: "Cancel"
  )
  
  # Set up UIComponent fields
  dialog.id = id
  dialog.isVisible = false
  dialog.isDirty = false
  dialog.bounds = rl.Rectangle(x: 0, y: 0, width: 400, height: 150)
  
  return dialog

proc updateLayout*(dialog: ConfirmationDialog) =
  ## Update dialog layout based on current bounds
  let screenWidth = rl.getScreenWidth().float32
  let screenHeight = rl.getScreenHeight().float32
  
  # Center dialog on screen
  let dialogWidth = 400.0
  let dialogHeight = 150.0
  dialog.dialogBounds = rl.Rectangle(
    x: (screenWidth - dialogWidth) / 2,
    y: (screenHeight - dialogHeight) / 2,
    width: dialogWidth,
    height: dialogHeight
  )
  
  # Button layout - three buttons side by side
  let buttonWidth = 80.0
  let buttonHeight = 30.0
  let buttonSpacing = 10.0
  let totalButtonWidth = (buttonWidth * 3) + (buttonSpacing * 2)
  let buttonStartX = dialog.dialogBounds.x + (dialog.dialogBounds.width - totalButtonWidth) / 2
  let buttonY = dialog.dialogBounds.y + dialog.dialogBounds.height - buttonHeight - 15
  
  dialog.saveButtonBounds = rl.Rectangle(
    x: buttonStartX,
    y: buttonY,
    width: buttonWidth,
    height: buttonHeight
  )
  
  dialog.dontSaveButtonBounds = rl.Rectangle(
    x: buttonStartX + buttonWidth + buttonSpacing,
    y: buttonY,
    width: buttonWidth,
    height: buttonHeight
  )
  
  dialog.cancelButtonBounds = rl.Rectangle(
    x: buttonStartX + (buttonWidth + buttonSpacing) * 2,
    y: buttonY,
    width: buttonWidth,
    height: buttonHeight
  )

proc executeSave*(dialog: ConfirmationDialog) =
  ## Execute save action
  if dialog.callback != nil:
    dialog.callback(crSave)
  dialog.hide()

proc executeDontSave*(dialog: ConfirmationDialog) =
  ## Execute don't save action
  if dialog.callback != nil:
    dialog.callback(crDontSave)
  dialog.hide()

proc executeCancel*(dialog: ConfirmationDialog) =
  ## Execute cancel action
  if dialog.callback != nil:
    dialog.callback(crCancel)
  dialog.hide()

proc hide*(dialog: ConfirmationDialog) =
  ## Hide the dialog
  dialog.isVisible = false
  dialog.componentManager.markComponentDirty(dialog.id)

proc updateButtonHover*(dialog: ConfirmationDialog, mousePos: rl.Vector2) =
  ## Update button hover states
  let wasSaveHovered = dialog.isSaveHovered
  let wasDontSaveHovered = dialog.isDontSaveHovered
  let wasCancelHovered = dialog.isCancelHovered
  
  dialog.isSaveHovered = rl.checkCollisionPointRec(mousePos, dialog.saveButtonBounds)
  dialog.isDontSaveHovered = rl.checkCollisionPointRec(mousePos, dialog.dontSaveButtonBounds)
  dialog.isCancelHovered = rl.checkCollisionPointRec(mousePos, dialog.cancelButtonBounds)
  
  # Mark dirty if hover state changed
  if wasSaveHovered != dialog.isSaveHovered or 
     wasDontSaveHovered != dialog.isDontSaveHovered or
     wasCancelHovered != dialog.isCancelHovered:
    dialog.componentManager.markComponentDirty(dialog.id)

proc handleInput*(dialog: ConfirmationDialog, event: UnifiedInputEvent): bool =
  ## Handle unified input events
  if not dialog.isVisible:
    return false
    
  case event.kind:
  of uiekKeyboard:
    let keyEvent = event.keyEvent
    if keyEvent.eventType == ietKeyPressed:
      case keyEvent.key:
      of ekEscape:
        dialog.executeCancel()
        return true
      of ekEnter:
        dialog.executeSave()  # Default to save on Enter
        return true
      else:
        discard
  of uiekMouse:
    let mouseEvent = event.mouseEvent
    let mousePos = rl.Vector2(x: mouseEvent.position.x, y: mouseEvent.position.y)
    
    case mouseEvent.eventType:
    of metMoved:
      dialog.updateButtonHover(mousePos)
      return true
    of metButtonPressed:
      if mouseEvent.button == mbLeft:
        if rl.checkCollisionPointRec(mousePos, dialog.saveButtonBounds):
          dialog.executeSave()
          return true
        elif rl.checkCollisionPointRec(mousePos, dialog.dontSaveButtonBounds):
          dialog.executeDontSave()
          return true
        elif rl.checkCollisionPointRec(mousePos, dialog.cancelButtonBounds):
          dialog.executeCancel()
          return true
        elif not rl.checkCollisionPointRec(mousePos, dialog.dialogBounds):
          # Click outside dialog - treat as cancel
          dialog.executeCancel()
          return true
    else:
      discard
  else:
    discard
  
  return false

proc render*(dialog: ConfirmationDialog) =
  ## Render the confirmation dialog
  if not dialog.isVisible:
    return
  
  # Draw overlay background
  rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), 
                   rl.Color(r: 0, g: 0, b: 0, a: 128))
  
  # Draw dialog background
  rl.drawRectangle(dialog.dialogBounds.x.int32, dialog.dialogBounds.y.int32, 
                   dialog.dialogBounds.width.int32, dialog.dialogBounds.height.int32, 
                   rl.Color(r: 45, g: 45, b: 45, a: 255))
  rl.drawRectangleLines(dialog.dialogBounds.x.int32, dialog.dialogBounds.y.int32,
                        dialog.dialogBounds.width.int32, dialog.dialogBounds.height.int32,
                        rl.Color(r: 80, g: 80, b: 80, a: 255))
  
  # Draw message text
  let messageY = dialog.dialogBounds.y + 20
  rl.drawText(
    dialog.message,
    (dialog.dialogBounds.x + 20).int32,
    messageY.int32,
    16,
    rl.Color(r: 220, g: 220, b: 220, a: 255)
  )
  
  # Draw Save button
  let saveColor = if dialog.isSaveHovered: 
    rl.Color(r: 0, g: 120, b: 215, a: 255)  # Hover blue
  else: 
    rl.Color(r: 0, g: 100, b: 180, a: 255)  # Normal blue
  
  rl.drawRectangle(dialog.saveButtonBounds.x.int32, dialog.saveButtonBounds.y.int32,
                   dialog.saveButtonBounds.width.int32, dialog.saveButtonBounds.height.int32,
                   saveColor)
  rl.drawText(
    dialog.saveLabel,
    (dialog.saveButtonBounds.x + 20).int32,
    (dialog.saveButtonBounds.y + 8).int32,
    14,
    rl.White
  )
  
  # Draw Don't Save button
  let dontSaveColor = if dialog.isDontSaveHovered:
    rl.Color(r: 80, g: 80, b: 80, a: 255)  # Hover gray
  else:
    rl.Color(r: 60, g: 60, b: 60, a: 255)  # Normal gray
  
  rl.drawRectangle(dialog.dontSaveButtonBounds.x.int32, dialog.dontSaveButtonBounds.y.int32,
                   dialog.dontSaveButtonBounds.width.int32, dialog.dontSaveButtonBounds.height.int32,
                   dontSaveColor)
  rl.drawText(
    dialog.dontSaveLabel,
    (dialog.dontSaveButtonBounds.x + 8).int32,
    (dialog.dontSaveButtonBounds.y + 8).int32,
    14,
    rl.White
  )
  
  # Draw Cancel button
  let cancelColor = if dialog.isCancelHovered:
    rl.Color(r: 80, g: 80, b: 80, a: 255)  # Hover gray
  else:
    rl.Color(r: 60, g: 60, b: 60, a: 255)  # Normal gray
  
  rl.drawRectangle(dialog.cancelButtonBounds.x.int32, dialog.cancelButtonBounds.y.int32,
                   dialog.cancelButtonBounds.width.int32, dialog.cancelButtonBounds.height.int32,
                   cancelColor)
  rl.drawText(
    dialog.cancelLabel,
    (dialog.cancelButtonBounds.x + 18).int32,
    (dialog.cancelButtonBounds.y + 8).int32,
    14,
    rl.White
  )
  
  dialog.isDirty = false

# Dialog visibility and state management
proc show*(dialog: ConfirmationDialog, 
          message: string, 
          callback: ConfirmationCallback = nil) =
  ## Show the confirmation dialog
  dialog.message = message
  dialog.callback = callback
  dialog.isVisible = true
  dialog.updateLayout()
  dialog.componentManager.markComponentDirty(dialog.id)