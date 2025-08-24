## Enhanced Button Group Module for Drift Editor
## Professional button group system with sophisticated input handling and theme integration
## Now inherits from UIComponent for direct ComponentManager integration

import std/[tables]
import raylib as rl
import shared/[errors, constants]
import infrastructure/input/[input_handler, keyboard, mouse]
import infrastructure/rendering/[theme, renderer]
import services/[ui_service, component_manager]
import icons
import results
# Button state
type ButtonState* = enum
  bsNormal = "normal"
  bsHovered = "hovered"
  bsActive = "active"
  bsDisabled = "disabled"

# Button definition
type Button* = object
  label*: string
  bounds*: rl.Rectangle
  isHovered*: bool
  isActive*: bool
  state*: ButtonState
  icon*: proc(x, y: float32, color: rl.Color) {.closure.}

# Button group - now inherits from UIComponent for ComponentManager integration
type ButtonGroup* = ref object of UIComponent
  buttons*: seq[Button]
  activeIndex*: int
  cols*: int
  rows*: int
  onButtonClick*: proc(buttonIndex: int) {.closure.}
  componentManager*: ComponentManager

# Forward declarations
proc handleInput*(buttonGroup: ButtonGroup, event: UnifiedInputEvent): bool
proc handleMouseEvent*(buttonGroup: ButtonGroup, event: MouseEvent): bool
proc handleKeyboardEvent*(buttonGroup: ButtonGroup, event: InputEvent): bool
proc registerInputHandlers*(buttonGroup: ButtonGroup): Result[void, EditorError]
proc registerWithComponentManager*(buttonGroup: ButtonGroup, componentManager: ComponentManager)
proc renderButtonGroup*(buttonGroup: ButtonGroup, themeManager: ThemeManager, renderer: Renderer)

proc newButtonGroup*(bounds: rl.Rectangle, cols: int = 4): ButtonGroup =
  ## Create a new button group that fills the given bounds
  result = ButtonGroup(
    buttons: @[], 
    bounds: bounds, 
    activeIndex: 0, 
    cols: cols, 
    rows: 1, 
    onButtonClick: nil,
    componentManager: nil
  )
  
  # Initialize UIComponent fields
  result.id = "button_group"
  result.name = "Button Group"
  result.state = csVisible
  result.zIndex = 0
  result.isVisible = true
  result.isEnabled = true
  result.isDirty = true
  result.parent = nil
  result.children = @[]
  result.data = initTable[string, string]()

proc updateButtonLayout*(buttonGroup: var ButtonGroup) =
  ## Update the layout of buttons to fill the bounds completely
  if buttonGroup.buttons.len == 0:
    return

  # Calculate rows needed
  buttonGroup.rows =
    (buttonGroup.buttons.len + buttonGroup.cols - 1) div buttonGroup.cols

  # Calculate button dimensions to fill the area completely
  let buttonWidth = buttonGroup.bounds.width / buttonGroup.cols.float32
  let buttonHeight = buttonGroup.bounds.height / buttonGroup.rows.float32

  # Position each button in the grid
  for i in 0 ..< buttonGroup.buttons.len:
    let row = i div buttonGroup.cols
    let col = i mod buttonGroup.cols

    buttonGroup.buttons[i].bounds = rl.Rectangle(
      x: buttonGroup.bounds.x + col.float32 * buttonWidth,
      y: buttonGroup.bounds.y + row.float32 * buttonHeight,
      width: buttonWidth,
      height: buttonHeight,
    )

proc addButton*(
    buttonGroup: var ButtonGroup,
    label: string,
    icon: proc(x, y: float32, color: rl.Color),
) =
  ## Add a button to the group and update layout
  let newButton = Button(
    label: label,
    bounds: rl.Rectangle(x: 0, y: 0, width: 0, height: 0), # Will be set by updateLayout
    icon: icon,
    isHovered: false,
    isActive: buttonGroup.buttons.len == buttonGroup.activeIndex,
    state: bsNormal,
  )
  buttonGroup.buttons.add(newButton)
  buttonGroup.updateButtonLayout()

proc setBounds*(buttonGroup: var ButtonGroup, bounds: rl.Rectangle) =
  ## Update the bounds of the button group and relayout
  buttonGroup.bounds = bounds
  buttonGroup.updateButtonLayout()

proc setOnButtonClick*(buttonGroup: var ButtonGroup, callback: proc(buttonIndex: int) {.closure.}) =
  ## Set the callback for button clicks
  buttonGroup.onButtonClick = callback

# ComponentManager integration
proc registerWithComponentManager*(buttonGroup: ButtonGroup, componentManager: ComponentManager) =
  ## Register this button group with the ComponentManager for proper input handling
  buttonGroup.componentManager = componentManager
  
  # Register the component with ComponentManager
  let inputHandler = proc(event: UnifiedInputEvent): bool =
    var buttonGroupVar = buttonGroup
    buttonGroupVar.handleInput(event)
  
  let renderHandler = proc(bounds: rl.Rectangle) =
    buttonGroup.renderButtonGroup(componentManager.themeManager, componentManager.renderer)
  
  let result = componentManager.registerComponent(
    buttonGroup.id,
    buttonGroup,
    inputHandler,
    renderHandler
  )
  
  if result.isErr:
    echo "Warning: Failed to register ButtonGroup with ComponentManager: ", result.error.msg

# Input handling
proc handleInput*(buttonGroup: ButtonGroup, event: UnifiedInputEvent): bool =
  ## Handle unified input events for button group
  case event.kind:
  of uiekMouse:
    return buttonGroup.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return buttonGroup.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc handleMouseEvent*(buttonGroup: ButtonGroup, event: MouseEvent): bool =
  ## Handle mouse events for button group
  let mousePos = rl.Vector2(x: event.position.x, y: event.position.y)
  
  # Check if mouse is in button group bounds
  if not rl.checkCollisionPointRec(mousePos, buttonGroup.bounds):
    return false
  
  case event.eventType:
  of metButtonPressed:
    if event.button == mbLeft:
      # Check for button clicks, but skip disabled buttons
      for i, button in buttonGroup.buttons:
        if button.state != bsDisabled and rl.checkCollisionPointRec(mousePos, button.bounds):
          buttonGroup.activeIndex = i
          # Call the callback if set
          if buttonGroup.onButtonClick != nil:
            buttonGroup.onButtonClick(i)
          return true
  of metMoved:
    # Update hover states, but skip disabled buttons
    for i in 0 ..< buttonGroup.buttons.len:
      if buttonGroup.buttons[i].state != bsDisabled:
        buttonGroup.buttons[i].isHovered = rl.checkCollisionPointRec(mousePos, buttonGroup.buttons[i].bounds)
      else:
        buttonGroup.buttons[i].isHovered = false
    return false
  else:
    return false

proc handleKeyboardEvent*(buttonGroup: ButtonGroup, event: InputEvent): bool =
  ## Handle keyboard events for button group
  # Button group doesn't handle keyboard events directly
  return false

proc registerInputHandlers*(buttonGroup: ButtonGroup): Result[void, EditorError] =
  ## Register input handlers with ComponentManager
  # Button group doesn't need keyboard shortcuts
  return ok()

# Rendering with ComponentManager integration
proc renderButtonGroup*(buttonGroup: ButtonGroup, themeManager: ThemeManager, renderer: Renderer) =
  ## Render the button group with VSCode-style icon colors
  
  # Professional button colors using theme
  let baseColor = themeManager.getUIColor(uiTitlebar)
  let hoverColor = themeManager.getUIColor(uiTitlebar).lighten(0.1)
  let activeColor = themeManager.getUIColor(uiTitlebar)
  
  # VSCode-style icon colors
  let iconColorNormal = themeManager.getUIColor(uiText).withAlpha(200)  # Brighter for inactive (0.78 * 255)
  let iconColorActive = themeManager.getUIColor(uiText)  # Full brightness for active
  let iconColorHover = themeManager.getUIColor(uiText).withAlpha(230)  # Slightly dimmed for hover (0.9 * 255)

  # Draw each button
  for i, button in buttonGroup.buttons:
    # Determine background color based on state
    var bgColor = baseColor
    if button.state == bsDisabled:
      bgColor = baseColor.darken(0.2)
    elif button.isActive:
      bgColor = activeColor
    elif button.isHovered:
      bgColor = hoverColor

    # Draw button background (no borders, fills completely)
    renderer.drawRectangle(button.bounds, bgColor)

    # Draw icon centered in button
    let iconSize = min(button.bounds.width, button.bounds.height) * 0.6

    # Center the icon
    let iconX = button.bounds.x + (button.bounds.width - iconSize) * 0.5
    let iconY = button.bounds.y + (button.bounds.height - iconSize) * 0.5

    # Determine icon color based on state
    let iconColor = if button.state == bsDisabled: iconColorNormal.withAlpha(100)
                   elif button.isActive: iconColorActive
                   elif button.isHovered: iconColorHover
                   else: iconColorNormal

    # Call the icon drawing function
    button.icon(iconX, iconY, iconColor)

# Legacy compatibility functions
proc handleMouseInput*(buttonGroup: var ButtonGroup, mousePos: rl.Vector2): int =
  ## Legacy input handling - converts to UnifiedInputEvent
  var clickedIndex = -1

  # Update hover states and check for clicks
  for i, button in buttonGroup.buttons.mpairs:
    # Check if mouse is over this button, but skip disabled ones
    if button.state != bsDisabled:
      button.isHovered = rl.checkCollisionPointRec(mousePos, button.bounds)
    else:
      button.isHovered = false

    # Check for click - use mouse position tracking instead of direct raylib calls
    if button.state != bsDisabled and button.isHovered:
      # Note: This is a simplified version since we can't detect button press directly
      # In a real implementation, this would be handled by the UnifiedInputEvent system
      clickedIndex = i
      buttonGroup.activeIndex = i

  # Update active states
  for i, button in buttonGroup.buttons.mpairs:
    button.isActive = (i == buttonGroup.activeIndex)

  return clickedIndex

proc drawButtonGroup*(buttonGroup: ButtonGroup, themeManager: ThemeManager,
    renderer: Renderer) =
  ## Legacy drawing function - now calls the new render function
  buttonGroup.renderButtonGroup(themeManager, renderer)

proc handleButtonGroupInput*(buttonGroup: var ButtonGroup, mousePos: rl.Vector2): int =
  ## Simple input handling for backward compatibility
  ## This function is deprecated - use handleMouseEvent instead
  var clickedIndex = -1

  # Update hover states and check for clicks
  for i, button in buttonGroup.buttons.mpairs:
    # Check if mouse is over this button, skip disabled ones
    if button.state != bsDisabled:
      button.isHovered = rl.checkCollisionPointRec(mousePos, button.bounds)
    else:
      button.isHovered = false

    # Check for click, but skip disabled buttons
    if button.state != bsDisabled and button.isHovered and rl.isMouseButtonPressed(rl.MouseButton.Left):
      clickedIndex = i
      buttonGroup.activeIndex = i
      
      # Call the callback if set
      if buttonGroup.onButtonClick != nil:
        buttonGroup.onButtonClick(i)

  # Update active states
  for i, button in buttonGroup.buttons.mpairs:
    button.isActive = (i == buttonGroup.activeIndex)

  return clickedIndex

proc drawButtonGroup*(buttonGroup: ButtonGroup) =
  ## Simple drawing for backward compatibility with VSCode-style colors
  # Simple colors
  let baseColor = rl.Color(r: 40, g: 40, b: 40, a: 255)
  let hoverColor = rl.Color(r: 60, g: 60, b: 60, a: 255)
  let activeColor = rl.Color(r: 80, g: 80, b: 80, a: 255)
  
  # VSCode-style icon colors
  let iconColorNormal = rl.Color(r: 200, g: 200, b: 200, a: 255)  # Brighter for inactive
  let iconColorActive = rl.Color(r: 220, g: 220, b: 220, a: 255)  # Full brightness for active
  let iconColorHover = rl.Color(r: 210, g: 210, b: 210, a: 255)   # Slightly dimmed for hover

  # Draw each button
  for i, button in buttonGroup.buttons:
    # Determine background color based on state
    var bgColor = baseColor
    if button.state == bsDisabled:
      bgColor = baseColor.darken(0.3)
    elif button.isActive:
      bgColor = activeColor
    elif button.isHovered:
      bgColor = hoverColor

    # Draw button background
    rl.drawRectangle(
      button.bounds.x.int32, button.bounds.y.int32, button.bounds.width.int32,
      button.bounds.height.int32, bgColor,
    )

    # Draw icon centered in button
    let iconSize = min(button.bounds.width, button.bounds.height) * 0.5

    # Center the icon
    let iconX = button.bounds.x + (button.bounds.width - iconSize) * 0.5
    let iconY = button.bounds.y + (button.bounds.height - iconSize) * 0.5

    # Determine icon color based on state
    let iconColor = if button.state == bsDisabled: rl.Color(r: 100, g: 100, b: 100, a: 255)
                   elif button.isActive: iconColorActive
                   elif button.isHovered: iconColorHover
                   else: iconColorNormal

    # Call the icon drawing function
    button.icon(iconX, iconY, iconColor)

# Utility functions
proc getButtonBounds*(buttonGroup: ButtonGroup, index: int): rl.Rectangle =
  ## Get the bounds of a specific button by index
  if index >= 0 and index < buttonGroup.buttons.len:
    return buttonGroup.buttons[index].bounds
  else:
    return rl.Rectangle(x: 0, y: 0, width: 0, height: 0)

proc getActiveButton*(buttonGroup: ButtonGroup): int =
  ## Get the index of the currently active button
  return buttonGroup.activeIndex

proc setActiveButton*(buttonGroup: var ButtonGroup, index: int) =
  ## Set the active button by index
  if index >= 0 and index < buttonGroup.buttons.len:
    buttonGroup.activeIndex = index
    for i, button in buttonGroup.buttons.mpairs:
      button.isActive = (i == index)

proc setButtonEnabled*(buttonGroup: var ButtonGroup, index: int, enabled: bool) =
  ## Enable or disable a specific button by index
  if index >= 0 and index < buttonGroup.buttons.len:
    if enabled:
      buttonGroup.buttons[index].state = bsNormal
    else:
      buttonGroup.buttons[index].state = bsDisabled

proc setButtonStates*(buttonGroup: var ButtonGroup, states: seq[bool]) =
  ## Set button states based on panel visibility
  ## states: sequence of boolean values indicating if each panel is active
  var newActiveIndex = -1
  for i, button in buttonGroup.buttons.mpairs:
    if i < states.len:
      button.isActive = states[i]
      if states[i]:
        newActiveIndex = i
    else:
      button.isActive = false
  
  # Update activeIndex to match the new states
  buttonGroup.activeIndex = newActiveIndex

# Title bar button utilities
proc createTitleBarButtonGroup*(x, y, width: float32): ButtonGroup =
  ## Create a button group specifically for title bar usage
  let buttonBounds = rl.Rectangle(x: x, y: y, width: width, height: TITLEBAR_HEIGHT.float32)
  newButtonGroup(buttonBounds, 4)

proc addIconButton*(buttonGroup: var ButtonGroup, label: string, iconFile: string, iconSize: float32 = 16.0) =
  ## Add a button with an icon from the icons system
  buttonGroup.addButton(
    label,
    proc(x, y: float32, color: rl.Color) =
      drawRasterizedIcon(iconFile, x, y, iconSize, color)
  )