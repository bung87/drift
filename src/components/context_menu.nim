## Context Menu Component - VSCode-style right-click context menus
##
## Provides context-aware right-click menus for the file explorer with:
## - Different menu items based on context (file, folder, empty space)
## - Keyboard shortcuts display
## - Conditional menu items based on file state
## - Proper positioning and styling
## - Standardized ComponentManager integration

import std/[tables, options, strutils, hashes]
import raylib as rl
import ../shared/errors
import ../services/[ui_service, component_manager]
import ../infrastructure/input/[input_handler, keyboard, mouse]
import ../infrastructure/rendering/theme
import ../infrastructure/rendering/renderer
import results
# Context menu item types
type
  ContextMenuItemKind* = enum
    cmikAction = "action"
    cmikSeparator = "separator"
    cmikSubmenu = "submenu"

  ContextMenuItem* = object
    id*: string
    label*: string
    shortcut*: string
    kind*: ContextMenuItemKind
    enabled*: bool
    visible*: bool
    action*: proc(): void
    submenu*: seq[ContextMenuItem]
    condition*: proc(): bool # For conditional visibility

  ContextMenuContext* = enum
    cmcFile = "file"
    cmcFolder = "folder"
    cmcEmpty = "empty"

  ContextMenu* = ref object of UIComponent
    # ComponentManager integration
    componentManager*: ComponentManager
    
    # Menu data
    items*: seq[ContextMenuItem]
    context*: ContextMenuContext
    position*: rl.Vector2
    selectedIndex*: int
    actionHandler*: proc(actionId: string, targetPath: string)
    
    # Display properties
    itemHeight*: float32
    padding*: float32
    maxWidth*: float32
    
    # Navigation state
    keyboardNavigationEnabled*: bool
    lastKeyTime*: float64
    hoveredIndex*: int
    animationTime*: float32
    
    # Enhanced positioning
    preferredSide*: int # 0=right, 1=left, 2=auto
    avoidEdges*: bool
    
    # Event consumption state
    justShown*: bool
    showTime*: float64
    creationEventId*: int
    lastEventId*: int

# Constants
const
  CONTEXT_MENU_ITEM_HEIGHT = 28.0
  CONTEXT_MENU_PADDING = 8.0
  CONTEXT_MENU_MIN_WIDTH = 200.0
  CONTEXT_MENU_MAX_WIDTH = 400.0
  CONTEXT_MENU_SEPARATOR_HEIGHT = 1.0

# Forward declarations
proc handleInput*(menu: ContextMenu, event: UnifiedInputEvent): bool
proc render*(menu: ContextMenu)
proc registerInputHandlers*(menu: ContextMenu): Result[void, EditorError]
proc hide*(menu: ContextMenu)
proc selectCurrentItem*(menu: ContextMenu)
proc moveSelection*(menu: ContextMenu, direction: int)
proc handleMouseClick*(menu: ContextMenu, pos: MousePosition)
proc handleMouseMove*(menu: ContextMenu, pos: MousePosition)
proc handleMouseEvent*(menu: ContextMenu, event: MouseEvent): bool
proc handleKeyboardEvent*(menu: ContextMenu, event: InputEvent): bool
proc searchByChar*(menu: ContextMenu, char: char): bool
proc updateHoverSelection*(menu: ContextMenu, mousePos: rl.Vector2)
proc selectItemAtPosition*(menu: ContextMenu, mousePos: rl.Vector2)

# Constructor
proc newContextMenu*(
    componentManager: ComponentManager,
    id: string, 
    context: ContextMenuContext,
    position: rl.Vector2
): ContextMenu =
  ## Create new context menu using ComponentManager
  
  echo "DEBUG: Creating new context menu with id: ", id
  
  let menu = ContextMenu(
    componentManager: componentManager,
    items: @[],
    context: context,
    position: position,
    selectedIndex: -1,
    actionHandler: nil,
    itemHeight: CONTEXT_MENU_ITEM_HEIGHT,
    padding: CONTEXT_MENU_PADDING,
    maxWidth: CONTEXT_MENU_MAX_WIDTH,
    keyboardNavigationEnabled: true,
    lastKeyTime: 0.0,
    hoveredIndex: -1,
    animationTime: 0.0,
    preferredSide: 2, # auto
    avoidEdges: true
  )
  
  # Initialize UIComponent base
  menu.id = id
  menu.name = "ContextMenu"
  menu.state = csHidden
  menu.bounds = rl.Rectangle(x: 0, y: 0, width: 0, height: 0)
  menu.zIndex = 1000 # High z-index for overlay
  menu.isVisible = false
  menu.isEnabled = true
  menu.isDirty = true
  menu.justShown = false
  menu.showTime = 0.0
  menu.creationEventId = 0
  menu.lastEventId = 0
  menu.data = initTable[string, string]()
  
  echo "DEBUG: ContextMenu UIComponent initialized"
  
  # Register with ComponentManager
  let registerResult = componentManager.registerComponent(
    id, 
    menu,
    proc(event: UnifiedInputEvent): bool = menu.handleInput(event),
    proc(bounds: rl.Rectangle) = 
      echo "DEBUG: ContextMenu render handler called for: ", id
      menu.bounds = bounds
      menu.render()
  )
  
  if registerResult.isErr:
    echo "ERROR: Failed to register context menu component: ", registerResult.error.msg
    raise newException(EditorError, "Failed to register context menu component: " & registerResult.error.msg)
  
  echo "DEBUG: ContextMenu registered with ComponentManager successfully"
  
  # Register input handlers
  let inputResult = menu.registerInputHandlers()
  if inputResult.isErr:
    echo "ERROR: Failed to register context menu input handlers: ", inputResult.error.msg
    raise newException(EditorError, "Failed to register context menu input handlers: " & inputResult.error.msg)
  
  echo "DEBUG: ContextMenu input handlers registered successfully"
  return menu

# Input handling registration
proc registerInputHandlers*(menu: ContextMenu): Result[void, EditorError] =
  ## Register standardized input handlers using ComponentManager
  
  # Register keyboard shortcuts
  var keyHandlers = initTable[KeyCombination, proc()]()
  
  # Escape to close
  keyHandlers[KeyCombination(key: ekEscape, modifiers: {})] = proc() =
    menu.hide()
  
  # Enter to select
  keyHandlers[KeyCombination(key: ekEnter, modifiers: {})] = proc() =
    menu.selectCurrentItem()
  
  # Arrow navigation
  keyHandlers[KeyCombination(key: ekUp, modifiers: {})] = proc() =
    menu.moveSelection(-1)
  
  keyHandlers[KeyCombination(key: ekDown, modifiers: {})] = proc() =
    menu.moveSelection(1)
  
  let keyResult = menu.componentManager.registerInputHandlers(
    menu.id,
    keyHandlers,
    initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  )
  
  if keyResult.isErr:
    return err(keyResult.error)
  
  # Register mouse handlers using drag system for hover/click
  let dragResult = menu.componentManager.registerDragHandlers(
    menu.id,
    proc(pos: MousePosition) = menu.handleMouseClick(pos),
    proc(pos: MousePosition) = menu.handleMouseMove(pos),
    proc(pos: MousePosition) = discard
  )
  
  return dragResult

# Input event handling
proc handleInput*(menu: ContextMenu, event: UnifiedInputEvent): bool =
  ## Handle unified input events
  if not menu.isVisible:
    return false
  
  echo "DEBUG: ContextMenu.handleInput() called - event kind: ", event.kind, " - justShown: ", menu.justShown
  
  # Auto-clear justShown flag after grace period
  let currentTime = rl.getTime()
  let gracePeriod = 0.1 # 100ms grace period
  if menu.justShown and (currentTime - menu.showTime) >= gracePeriod:
    menu.justShown = false
    echo "DEBUG: Grace period expired - clearing justShown flag - elapsed: ", (currentTime - menu.showTime)
  
  case event.kind:
  of uiekMouse:
    return menu.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return menu.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc handleMouseEvent*(menu: ContextMenu, event: MouseEvent): bool =
  ## Handle mouse events with bounds checking
  if not menu.isVisible:
    return false
  
  # Generate event ID for tracking
  let eventId = hash((event.position.x, event.position.y, event.eventType, rl.getTime()))
  menu.lastEventId = eventId
  
  echo "DEBUG: ContextMenu.handleMouseEvent() - event: ", event.eventType, " button: ", event.button, " - justShown: ", menu.justShown
  
  let mousePos = rl.Vector2(x: event.position.x, y: event.position.y)
  let currentTime = rl.getTime()
  
  # Check if mouse is over menu
  let mouseOverMenu = rl.checkCollisionPointRec(mousePos, menu.bounds)
  
  # Enhanced grace period with event tracking to prevent immediate hiding
  let gracePeriod = 0.15 # 150ms grace period (increased for robustness)
  let timeInGracePeriod = menu.justShown and (currentTime - menu.showTime) < gracePeriod
  let sameCreationEvent = eventId == menu.creationEventId
  let inGracePeriod = timeInGracePeriod or sameCreationEvent
  
  if not mouseOverMenu:
    menu.hoveredIndex = -1
    # Only close menu on left click outside, not right click (to prevent interference with explorer right-click)
    if event.eventType == metButtonPressed and event.button == mbLeft:
      echo "CONTEXT_MENU_HIDE: Left click outside menu - hiding"
      menu.hide()
      return true
    # During grace period, consume all right-click events to prevent the creating right-click from hiding the menu
    if event.eventType == metButtonPressed and event.button == mbRight:
      if inGracePeriod:
        if sameCreationEvent:
          echo "CONTEXT_MENU_GRACE: Right-click consumed - same creation event"
        else:
          echo "CONTEXT_MENU_GRACE: Right-click consumed - within grace period"
        return true # Consume the event during grace period
      else:
        echo "CONTEXT_MENU_GRACE: Right-click NOT consumed - grace period expired"
        return false # Allow normal right-click processing after grace period
    return false
  
  # Mouse is over the menu - consume all events to prevent them from reaching components underneath
  case event.eventType:
  of metMoved:
    menu.updateHoverSelection(mousePos)
    return true  # Consume mouse move events when over menu
  of metButtonPressed:
    if event.button == mbLeft:
      # Clear justShown flag on any interaction
      menu.justShown = false
      menu.selectItemAtPosition(mousePos)
      return true
    elif event.button == mbRight:
      # Clear justShown flag and close menu on right click
      echo "CONTEXT_MENU_HIDE: Right-click on menu itself - hiding"
      menu.justShown = false
      menu.hide()
      return true
  of metButtonReleased:
    # Consume button release events when over menu
    return true
  of metScrolled:
    # Consume scroll events when over menu
    return true
  else:
    # Consume any other mouse events when over menu
    return true
  
  return false

proc handleKeyboardEvent*(menu: ContextMenu, event: InputEvent): bool =
  ## Handle keyboard events for navigation
  if not menu.isVisible:
    return false
  
  # Character search
  if event.eventType == ietCharInput and event.character.int32 >= 32 and event.character.int32 <= 126:
    let char = char(event.character.int32).toLowerAscii()
    return menu.searchByChar(char)
  
  return false

proc handleMouseClick*(menu: ContextMenu, pos: MousePosition) =
  ## Handle mouse click events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  menu.selectItemAtPosition(mousePos)

proc handleMouseMove*(menu: ContextMenu, pos: MousePosition) =
  ## Handle mouse move events for hover
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  menu.updateHoverSelection(mousePos)

# Menu item creation helpers
proc createMenuItem*(
    id: string,
    label: string,
    shortcut: string = "",
    action: proc(): void = nil,
    enabled: bool = true,
    condition: proc(): bool = nil
): ContextMenuItem =
  ContextMenuItem(
    id: id,
    label: label,
    shortcut: shortcut,
    kind: cmikAction,
    enabled: enabled,
    visible: true,
    action: action,
    submenu: @[],
    condition: condition
  )

proc createSeparator*(): ContextMenuItem =
  ContextMenuItem(
    id: "separator",
    label: "",
    shortcut: "",
    kind: cmikSeparator,
    enabled: false,
    visible: true,
    action: nil,
    submenu: @[],
    condition: nil
  )

# Menu building for different contexts
proc buildFileMenu*(menu: ContextMenu, filePath: string, isGitRepo: bool = false) =
  ## Build context menu for file items
  menu.items = @[]
  
  # Open actions
  menu.items.add(createMenuItem("open", "Open", "Cmd+O", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("open", filePath)
  ))
  menu.items.add(createMenuItem("open_to_side", "Open to the Side", "Cmd+\\", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("open_to_side", filePath)
  ))
  menu.items.add(createSeparator())
  
  # Reveal and copy actions
  menu.items.add(createMenuItem("reveal", "Reveal in Finder", "Shift+Cmd+R", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("reveal", filePath)
  ))
  menu.items.add(createMenuItem("copy_path", "Copy Path", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("copy_path", filePath)
  ))
  menu.items.add(createMenuItem("copy_relative_path", "Copy Relative Path", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("copy_relative_path", filePath)
  ))
  menu.items.add(createSeparator())
  
  # File operations
  menu.items.add(createMenuItem("rename", "Rename", "F2", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("rename", filePath)
  ))
  menu.items.add(createMenuItem("delete", "Delete", "Cmd+Delete", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("delete", filePath)
  ))
  menu.items.add(createSeparator())
  
  # Selection operations
  menu.items.add(createMenuItem("compare", "Compare with Selected", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("compare", filePath)
  ))
  menu.items.add(createMenuItem("copy", "Copy", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("copy", filePath)
  ))
  menu.items.add(createMenuItem("cut", "Cut", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("cut", filePath)
  ))
  menu.items.add(createMenuItem("paste", "Paste", "Cmd+V", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("paste", filePath)
  ))
  menu.items.add(createSeparator())
  
  # Git operations (conditional)
  if isGitRepo:
    menu.items.add(createMenuItem("git_stage", "Git: Stage", "", proc() =
      if menu.actionHandler != nil:
        menu.actionHandler("git_stage", filePath)
    ))
    menu.items.add(createMenuItem("git_discard", "Git: Discard Changes", "", proc() =
      if menu.actionHandler != nil:
        menu.actionHandler("git_discard", filePath)
    ))
    menu.items.add(createSeparator())
  
  # Development actions (conditional)
  menu.items.add(createMenuItem("run", "Run", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("run", filePath)
  ))
  menu.items.add(createMenuItem("debug", "Debug", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("debug", filePath)
  ))
  menu.items.add(createMenuItem("format", "Format File", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("format", filePath)
  ))

proc buildFolderMenu*(menu: ContextMenu, folderPath: string, isGitRepo: bool = false) =
  ## Build context menu for folder items
  menu.items = @[]
  
  # Create actions
  menu.items.add(createMenuItem("new_file", "New File", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("new_file", folderPath)
  ))
  menu.items.add(createMenuItem("new_folder", "New Folder", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("new_folder", folderPath)
  ))
  menu.items.add(createSeparator())
  
  # Reveal and copy actions
  menu.items.add(createMenuItem("reveal", "Reveal in Finder", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("reveal", folderPath)
  ))
  menu.items.add(createMenuItem("copy_path", "Copy Path", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("copy_path", folderPath)
  ))
  menu.items.add(createMenuItem("copy_relative_path", "Copy Relative Path", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("copy_relative_path", folderPath)
  ))
  menu.items.add(createSeparator())
  
  # Folder operations
  menu.items.add(createMenuItem("rename", "Rename", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("rename", folderPath)
  ))
  menu.items.add(createMenuItem("delete", "Delete", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("delete", folderPath)
  ))
  menu.items.add(createSeparator())
  
  # Selection operations
  menu.items.add(createMenuItem("copy", "Copy", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("copy", folderPath)
  ))
  menu.items.add(createMenuItem("cut", "Cut", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("cut", folderPath)
  ))
  menu.items.add(createMenuItem("paste", "Paste", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("paste", folderPath)
  ))
  menu.items.add(createSeparator())
  
  # Git operations (conditional)
  if isGitRepo:
    menu.items.add(createMenuItem("git_stage_all", "Git: Stage All", "", proc() =
      if menu.actionHandler != nil:
        menu.actionHandler("git_stage_all", folderPath)
    ))
  
  # Development actions (conditional)
  menu.items.add(createMenuItem("format_all", "Format All Files", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("format_all", folderPath)
  ))

proc buildEmptyMenu*(menu: ContextMenu) =
  ## Build context menu for empty space
  menu.items = @[]
  
  # Create actions
  menu.items.add(createMenuItem("new_file", "New File", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("new_file", "")
  ))
  menu.items.add(createMenuItem("new_folder", "New Folder", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("new_folder", "")
  ))
  menu.items.add(createSeparator())
  
  # View actions
  menu.items.add(createMenuItem("refresh", "Refresh", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("refresh", "")
  ))
  menu.items.add(createMenuItem("collapse_all", "Collapse All", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("collapse_all", "")
  ))
  menu.items.add(createMenuItem("paste", "Paste", "", proc() =
    if menu.actionHandler != nil:
      menu.actionHandler("paste", "")
  ))

# Layout and positioning using UIService
proc calculateMenuBounds*(menu: ContextMenu): rl.Rectangle =
  ## Calculate menu bounds using UIService layout system
  var maxItemWidth = 0.0
  var totalHeight = 0.0
  var visibleItemCount = 0
  
  let fontSize = 14.0 # Default font size
  
  for item in menu.items:
    if not item.visible:
      continue
      
    if item.kind == cmikSeparator:
      totalHeight += CONTEXT_MENU_SEPARATOR_HEIGHT
    else:
      # Calculate item width including shortcut and icon space
      # Get font from ComponentManager for consistent measurement
      let defaultFont = rl.getFontDefault()
      let menuItemFont = if menu.componentManager != nil:
        let uiFont = menu.componentManager.renderer.getFont("ui")
        if uiFont != nil: uiFont else: addr(defaultFont)
      else:
        addr(defaultFont)
      
      var itemWidth = rl.measureText(menuItemFont[], item.label, fontSize, 1.0).x
      if item.shortcut.len > 0:
        itemWidth += 30.0 + rl.measureText(menuItemFont[], item.shortcut, fontSize, 1.0).x
      itemWidth += menu.padding * 2 + 20.0 # Extra space for icons and margins
      
      maxItemWidth = max(maxItemWidth, itemWidth)
      totalHeight += menu.itemHeight
      visibleItemCount += 1
  
  # Add padding and ensure minimum dimensions
  totalHeight += menu.padding * 2
  maxItemWidth = max(maxItemWidth + menu.padding * 2, CONTEXT_MENU_MIN_WIDTH)
  maxItemWidth = min(maxItemWidth, menu.maxWidth)
  
  # Enhanced positioning logic using UIService
  var x = menu.position.x
  var y = menu.position.y
  let screenWidth = rl.getScreenWidth().float32
  let screenHeight = rl.getScreenHeight().float32
  let margin = 10.0
  
  # Smart horizontal positioning
  if menu.avoidEdges:
    case menu.preferredSide:
    of 0: # Prefer right
      if x + maxItemWidth + margin > screenWidth:
        x = max(margin, x - maxItemWidth) # Try left side
    of 1: # Prefer left  
      x = max(margin, x - maxItemWidth)
      if x < margin:
        x = min(screenWidth - maxItemWidth - margin, menu.position.x) # Fallback to right
    else: # Auto
      if x + maxItemWidth + margin > screenWidth:
        x = max(margin, x - maxItemWidth)
      if x < margin:
        x = margin
  
  # Smart vertical positioning
  if menu.avoidEdges:
    if y + totalHeight + margin > screenHeight:
      # Try positioning above the click point
      let newY = y - totalHeight
      if newY >= margin:
        y = newY
      else:
        # Position at bottom with scrolling if needed
        y = max(margin, screenHeight - totalHeight - margin)
  
  # Ensure minimum margins and handle negative coordinates
  x = max(margin, min(x, screenWidth - maxItemWidth - margin))
  # Clamp Y to ensure menu is always visible, even when mouse is at negative coordinates
  y = max(margin, min(y, screenHeight - totalHeight - margin))
  
  # Additional safety check for negative coordinates
  if y < margin:
    y = margin
  
  # Ensure bounds are valid (non-zero dimensions)
  let finalBounds = rl.Rectangle(x: x, y: y, width: maxItemWidth, height: totalHeight)
  if finalBounds.width <= 0 or finalBounds.height <= 0:
    echo "ERROR: Invalid context menu bounds calculated"
    return rl.Rectangle(x: menu.position.x, y: menu.position.y, width: CONTEXT_MENU_MIN_WIDTH, height: max(totalHeight, 50.0))
  
  result = rl.Rectangle(x: x, y: y, width: maxItemWidth, height: totalHeight)
  
  # Update bounds using ComponentManager
  discard menu.componentManager.updateComponentBounds(menu.id, result)
  menu.bounds = result

# Rendering using ComponentManager services
proc render*(menu: ContextMenu) =
  ## Render using ComponentManager's renderer and theme
  if not menu.isVisible:
    return
  
  # Auto-clear justShown flag after grace period during render
  let currentTime = rl.getTime()
  let gracePeriod = 0.1 # 100ms grace period
  if menu.justShown and (currentTime - menu.showTime) >= gracePeriod:
    menu.justShown = false
  
  let bounds = menu.bounds
  
  # Additional bounds validation during render
  if bounds.width <= 0 or bounds.height <= 0:
    echo "ERROR: Invalid bounds during render - recalculating"
    menu.bounds = menu.calculateMenuBounds()
  
  # Set up rendering context (using direct raylib calls)
  
  # Draw shadow
  let shadowOffset = rl.Vector2(x: 2.0, y: 2.0)
  let shadowColor = rl.Color(r: 0, g: 0, b: 0, a: 50)
  let shadowBounds = rl.Rectangle(
    x: bounds.x + shadowOffset.x,
    y: bounds.y + shadowOffset.y,
    width: bounds.width,
    height: bounds.height
  )
  rl.drawRectangle(shadowBounds.x.int32, shadowBounds.y.int32, shadowBounds.width.int32, shadowBounds.height.int32, shadowColor)
  
  # Draw background
  let bgColor = menu.componentManager.getUIColor(uiBackground)
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, bgColor)
  
  # Draw border
  let borderColor = menu.componentManager.getUIColor(uiBorder)
  rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
  
  # Render menu items
  var y = bounds.y + menu.padding
  var itemIndex = 0
  
  # Get custom font from ComponentManager, fallback to default
  let defaultFont = rl.getFontDefault()
  let menuItemFont = if menu.componentManager != nil: 
    let uiFont = menu.componentManager.renderer.getFont("ui")
    if uiFont != nil: uiFont else: addr(defaultFont)
  else:
    addr(defaultFont)
  
  for item in menu.items:
    if not item.visible:
      continue
      
    if item.kind == cmikSeparator:
      # Draw separator
      let separatorY = y + CONTEXT_MENU_SEPARATOR_HEIGHT / 2
      let leftMargin = bounds.x + 20.0
      let rightMargin = bounds.x + bounds.width - 20.0
      let separatorColor = menu.componentManager.getUIColor(uiBorder)
      
      rl.drawLine(
        leftMargin.int32, separatorY.int32,
        rightMargin.int32, separatorY.int32,
        separatorColor
      )
      y += CONTEXT_MENU_SEPARATOR_HEIGHT
    else:
      # Draw menu item
      let itemBounds = rl.Rectangle(
        x: bounds.x,
        y: y,
        width: bounds.width,
        height: menu.itemHeight
      )
      
      # Background color based on state
      var bgColor: rl.Color
      if itemIndex == menu.selectedIndex or itemIndex == menu.hoveredIndex:
        if item.enabled:
          bgColor = menu.componentManager.getUIColor(uiSelection)
        else:
          bgColor = rl.Color(r: 240, g: 240, b: 240, a: 100)
      else:
        bgColor = rl.Color(r: 0, g: 0, b: 0, a: 0) # Transparent
      
      if bgColor.a > 0:
        rl.drawRectangle(itemBounds.x.int32, itemBounds.y.int32, itemBounds.width.int32, itemBounds.height.int32, bgColor)
      
      # Text color based on enabled state
      let textColor = if item.enabled:
        menu.componentManager.getUIColor(uiText)
      else:
        menu.componentManager.getUIColor(uiTextDisabled)
      
      # Draw text
      let textX = bounds.x + menu.padding + 20.0 # Space for icon
      let textY = y + (menu.itemHeight - 14.0) / 2 # Center vertically
      
      menu.componentManager.renderer.drawText(
        menuItemFont[],
        item.label,
        rl.Vector2(x: textX, y: textY),
        14.0, 1.0, textColor
      )
      
      # Draw shortcut if present
      if item.shortcut.len > 0:
        let shortcutColor = menu.componentManager.getUIColor(uiTextMuted)
        # Use the same font as the menu items for consistency
        let shortcutWidth = rl.measureText(menuItemFont[], item.shortcut, 12.0, 1.0).x
        let shortcutX = bounds.x + bounds.width - shortcutWidth - menu.padding
        let shortcutY = y + (menu.itemHeight - 12.0) / 2
        
        # Draw shortcut background
        let shortcutBg = rl.Rectangle(
          x: shortcutX - 4.0,
          y: shortcutY - 2.0,
          width: shortcutWidth + 8.0,
          height: 16.0
        )
        let shortcutBgColor = menu.componentManager.getUIColor(uiPanel)
        rl.drawRectangle(shortcutBg.x.int32, shortcutBg.y.int32, shortcutBg.width.int32, shortcutBg.height.int32, shortcutBgColor)
        
        menu.componentManager.renderer.drawText(
          menuItemFont[],
          item.shortcut,
          rl.Vector2(x: shortcutX, y: shortcutY),
          12.0, 1.0, shortcutColor
        )
      
      y += menu.itemHeight
      itemIndex += 1
  
  # Draw overlay for animation effects
  if menu.animationTime < 0.15:
    let overlayColor = rl.Color(r: 255, g: 255, b: 255, a: uint8(100 * (1.0 - menu.animationTime / 0.15)))
    rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, overlayColor)
  
  menu.isDirty = false

# Navigation and interaction methods
proc getVisibleItemIndex(menu: ContextMenu, logicalIndex: int): int {.used.} =
  ## Convert logical index to visible item index
  var visibleIndex = 0
  var logicalCount = 0
  
  for item in menu.items:
    if not item.visible:
      continue
    if item.kind != cmikSeparator:
      if logicalCount == logicalIndex:
        return visibleIndex
      logicalCount += 1
    visibleIndex += 1
  
  return -1

proc getLogicalItemIndex(menu: ContextMenu, visibleIndex: int): int {.used.} =
  ## Convert visible index to logical item index
  var logicalIndex = 0
  var visibleCount = 0
  
  for item in menu.items:
    if not item.visible:
      continue
    if visibleCount == visibleIndex and item.kind != cmikSeparator:
      return logicalIndex
    if item.kind != cmikSeparator:
      logicalIndex += 1
    visibleCount += 1
  
  return -1

proc moveSelection*(menu: ContextMenu, direction: int) =
  ## Move selection up or down
  if not menu.isVisible:
    return
  
  # Count visible enabled items
  var visibleItems: seq[int] = @[]
  for i, item in menu.items:
    if item.visible and item.enabled and item.kind != cmikSeparator:
      visibleItems.add(i)
  
  if visibleItems.len == 0:
    return
  
  # Find current position in visible items
  var currentPos = -1
  for i, itemIndex in visibleItems:
    if itemIndex == menu.selectedIndex:
      currentPos = i
      break
  
  # Move to next/previous item
  if currentPos == -1:
    menu.selectedIndex = if direction > 0: visibleItems[0] else: visibleItems[^1]
  else:
    let newPos = (currentPos + direction + visibleItems.len) mod visibleItems.len
    menu.selectedIndex = visibleItems[newPos]
  
  menu.componentManager.markComponentDirty(menu.id)

proc selectCurrentItem*(menu: ContextMenu) =
  ## Select the currently highlighted item
  if menu.selectedIndex >= 0 and menu.selectedIndex < menu.items.len:
    let selectedItem = menu.items[menu.selectedIndex]
    if selectedItem.enabled and selectedItem.action != nil:
      selectedItem.action()
      menu.hide()

proc searchByChar*(menu: ContextMenu, char: char): bool =
  ## Search for item by first character
  let currentTime = rl.getTime()
  
  # Reset search if too much time has passed
  if currentTime - menu.lastKeyTime > 1.0:
    menu.selectedIndex = -1
  
  # Find next item starting with the character
  let startIndex = if menu.selectedIndex >= 0: menu.selectedIndex + 1 else: 0
  
  for i in 0..<menu.items.len:
    let index = (startIndex + i) mod menu.items.len
    let item = menu.items[index]
    
    if item.visible and item.enabled and item.kind != cmikSeparator:
      if item.label.len > 0 and item.label[0].toLowerAscii() == char:
        menu.selectedIndex = index
        menu.lastKeyTime = currentTime
        menu.componentManager.markComponentDirty(menu.id)
        return true
  
  return false

proc updateHoverSelection*(menu: ContextMenu, mousePos: rl.Vector2) =
  ## Update hover selection based on mouse position
  var itemIndex = 0
  var y = menu.bounds.y + menu.padding
  var foundHover = false
  
  for item in menu.items:
    if not item.visible:
      continue
      
    if item.kind == cmikSeparator:
      y += CONTEXT_MENU_SEPARATOR_HEIGHT
    else:
      let itemBounds = rl.Rectangle(
        x: menu.bounds.x,
        y: y,
        width: menu.bounds.width,
        height: menu.itemHeight
      )
      
      if rl.checkCollisionPointRec(mousePos, itemBounds):
        if item.enabled:
          menu.selectedIndex = itemIndex
          menu.hoveredIndex = itemIndex
          foundHover = true
          menu.componentManager.markComponentDirty(menu.id)
        break
      
      y += menu.itemHeight
      itemIndex += 1
  
  if not foundHover and menu.hoveredIndex != -1:
    menu.hoveredIndex = -1
    menu.componentManager.markComponentDirty(menu.id)

proc selectItemAtPosition*(menu: ContextMenu, mousePos: rl.Vector2) =
  ## Select item at mouse position
  var itemIndex = 0
  var y = menu.bounds.y + menu.padding
  
  for item in menu.items:
    if not item.visible:
      continue
      
    if item.kind == cmikSeparator:
      y += CONTEXT_MENU_SEPARATOR_HEIGHT
    else:
      let itemBounds = rl.Rectangle(
        x: menu.bounds.x,
        y: y,
        width: menu.bounds.width,
        height: menu.itemHeight
      )
      
      if rl.checkCollisionPointRec(mousePos, itemBounds):
        if item.enabled:
          menu.selectedIndex = itemIndex
          menu.selectCurrentItem()
        break
      
      y += menu.itemHeight
      itemIndex += 1

# Menu visibility and state management
proc show*(menu: ContextMenu, position: rl.Vector2) =
  ## Show the context menu at the specified position
  echo "CONTEXT_MENU_SHOW: Starting show() at position ", position.x, ", ", position.y
  menu.position = position
  menu.selectedIndex = -1
  menu.hoveredIndex = -1
  menu.animationTime = 0.0
  menu.lastKeyTime = rl.getTime()
  
  # Generate unique creation event ID for this show operation
  menu.creationEventId = hash((position.x, position.y, rl.getTime()))
  
  # Calculate bounds first to ensure proper positioning
  let boundsResult = menu.calculateMenuBounds()
  menu.bounds = boundsResult
  
  # Validate bounds before showing
  if boundsResult.width <= 0 or boundsResult.height <= 0:
    echo "ERROR: Invalid context menu bounds - cannot show menu"
    return
  
  # Set visibility after bounds are calculated and validated
  menu.isVisible = true
  menu.justShown = true
  menu.showTime = rl.getTime()
  echo "CONTEXT_MENU_SHOW: Menu is now visible and justShown=true - creationEventId: ", menu.creationEventId
  
  # Update state using ComponentManager
  if menu.componentManager != nil:
    discard menu.componentManager.setComponentVisibility(menu.id, true)
    menu.componentManager.markComponentDirty(menu.id)
    
    # Force immediate render to ensure menu appears
    menu.render()
  else:
    echo "ERROR: ContextMenu componentManager is nil in show()"

proc hide*(menu: ContextMenu) =
  ## Hide the context menu using ComponentManager
  echo "CONTEXT_MENU_HIDE: Hiding menu - was visible: ", menu.isVisible
  menu.isVisible = false
  menu.selectedIndex = -1
  menu.hoveredIndex = -1
  menu.animationTime = 0.0
  menu.justShown = false
  menu.showTime = 0.0
  menu.creationEventId = 0
  menu.lastEventId = 0
  
  # Update state using ComponentManager
  discard menu.componentManager.setComponentVisibility(menu.id, false)
  menu.componentManager.markComponentDirty(menu.id)

proc update*(menu: ContextMenu, deltaTime: float32) =
  ## Update menu animations and state
  if menu.isVisible:
    menu.animationTime += deltaTime
    
    # Mark as dirty if animating
    if menu.animationTime < 0.15:
      menu.componentManager.markComponentDirty(menu.id)

# Menu state accessors
proc isVisible*(menu: ContextMenu): bool =
  ## Check if menu is visible
  menu.isVisible

proc getSelectedItem*(menu: ContextMenu): Option[ContextMenuItem] =
  ## Get the currently selected menu item
  if menu.selectedIndex >= 0 and menu.selectedIndex < menu.items.len:
    some(menu.items[menu.selectedIndex])
  else:
    none(ContextMenuItem)
