## Welcome Screen Component for Drift Editor
## Refactored to use ComponentManager architecture

import raylib as rl
import std/[tables, os]
import ../shared/errors
import ../services/[ui_service, component_manager]
import ../infrastructure/input/[input_handler, keyboard, mouse]
import ../infrastructure/rendering/theme
import ../infrastructure/ui/cursor_manager
# import ../application/types
import results

# proc getAppInstance(): EditorApp {.importc.}
# proc setApplicationState(editorApp: EditorApp, newState: ApplicationState) {.importc.}
# proc updateExplorer(app: EditorApp) {.importc.}
# proc createNewEmptyFile(app: EditorApp) {.importc.}
# proc openFileInApp(app: EditorApp, filePath: string): bool {.importc.}

type
  WelcomeAction* = enum
    waNewFile = "new_file"
    waOpenFile = "open_file"
    waOpenFolder = "open_folder"
    waCloneRepo = "clone_repo"
    waShowCommands = "show_commands"
    waDocumentation = "documentation"
    waOpenRecent = "open_recent"
    waNone = "none"

  WelcomeItem* = object
    label*: string
    hotkey*: string
    icon*: string
    action*: WelcomeAction
    actionData*: string
    bounds*: rl.Rectangle
    isHovered*: bool

  WelcomeSection* = object
    title*: string
    items*: seq[WelcomeItem]
    bounds*: rl.Rectangle

  WelcomeScreenComponent* = ref object of UIComponent
    # ComponentManager integration
    componentManager*: ComponentManager
    
    # Welcome screen data
    title*: string
    subtitle*: string
    sections*: seq[WelcomeSection]
    recentFiles*: seq[string]
    
    # Action handlers as closure properties
    onNewFile*: proc()
    onOpenFile*: proc()
    onOpenFolder*: proc()
    onCloneRepo*: proc()
    onOpenRecent*: proc(filePath: string)
    onShowCommands*: proc()
    onDocumentation*: proc()
    
    # Layout properties
    titleFontSize*: float32
    subtitleFontSize*: float32
    sectionFontSize*: float32
    itemFontSize*: float32
    columnWidth*: float32
    leftMargin*: float32
    topMargin*: float32
    sectionSpacing*: float32
    itemSpacing*: float32

# Forward declarations
proc handleInput*(component: WelcomeScreenComponent, event: UnifiedInputEvent): bool
proc render*(component: WelcomeScreenComponent)
proc registerInputHandlers*(component: WelcomeScreenComponent): Result[void, EditorError]
proc updateLayout*(component: WelcomeScreenComponent)
proc handleMouseClick*(component: WelcomeScreenComponent, pos: MousePosition)
proc handleMouseMove*(component: WelcomeScreenComponent, pos: MousePosition)
proc handleMouseEvent*(component: WelcomeScreenComponent, event: MouseEvent): bool
proc handleKeyboardEvent*(component: WelcomeScreenComponent, event: InputEvent): bool
proc triggerAction*(component: WelcomeScreenComponent, action: WelcomeAction, data: string)
proc initializeSections*(component: WelcomeScreenComponent)
proc updateHoverStates*(component: WelcomeScreenComponent, mousePos: rl.Vector2)
proc handleItemClick*(component: WelcomeScreenComponent, mousePos: rl.Vector2)
proc hide*(component: WelcomeScreenComponent)

# Constructor
proc newWelcomeScreenComponent*(
    componentManager: ComponentManager,
    id: string,
    bounds: rl.Rectangle
): WelcomeScreenComponent =
  ## Create new welcome screen component using ComponentManager
  
  let component = WelcomeScreenComponent(
    componentManager: componentManager,
    title: "Welcome to Drift Editor",
    subtitle: "Enhanced with sophisticated UI components",
    sections: @[],
    recentFiles: @[],
    onNewFile: proc() = discard,
    onOpenFile: proc() = discard,
    onOpenFolder: proc() = discard,
    onCloneRepo: proc() = discard,
    onOpenRecent: proc(filePath: string) = discard,
    onShowCommands: proc() = discard,
    onDocumentation: proc() = discard,
    titleFontSize: 32.0,
    subtitleFontSize: 16.0,
    sectionFontSize: 18.0,
    itemFontSize: 14.0,
    columnWidth: 300.0,
    leftMargin: 60.0,
    topMargin: 120.0,
    sectionSpacing: 60.0,
    itemSpacing: 8.0
  )
  
  # Initialize UIComponent base
  component.id = id
  component.name = "WelcomeScreen"
  component.state = csVisible
  component.bounds = bounds
  component.zIndex = 1000 # High z-index to appear on top
  component.isVisible = true
  component.isEnabled = true
  component.isDirty = true
  component.data = initTable[string, string]()
  
  # Register with ComponentManager
  let registerResult = componentManager.registerComponent(
    id,
    component,
    proc(event: UnifiedInputEvent): bool = component.handleInput(event),
    proc(bounds: rl.Rectangle) = 
      component.bounds = bounds
      component.render()
  )
  
  if registerResult.isErr:
    raise newException(EditorError, "Failed to register welcome screen component: " & registerResult.error.msg)
  
  # Initialize sections and layout
  component.initializeSections()
  component.updateLayout()
  
  # Register input handlers
  let inputResult = component.registerInputHandlers()
  if inputResult.isErr:
    raise newException(EditorError, "Failed to register input handlers: " & inputResult.error.msg)
  
  return component

# Input handling registration
proc registerInputHandlers*(component: WelcomeScreenComponent): Result[void, EditorError] =
  ## Register standardized input handlers using ComponentManager
  
  var keyHandlers = initTable[KeyCombination, proc()]()
  
  # Escape to hide welcome screen
  keyHandlers[KeyCombination(key: ekEscape, modifiers: {})] = proc() =
    component.hide()
  
  # Common shortcuts
  keyHandlers[KeyCombination(key: ekN, modifiers: {mkCtrl})] = proc() =
    component.triggerAction(waNewFile, "")
  
  # Removed global Ctrl+O registration - file opening should be handled by explorer
  # keyHandlers[KeyCombination(key: ekO, modifiers: {mkCtrl})] = proc() =
  #   component.triggerAction(waOpenFile, "")
  
  keyHandlers[KeyCombination(key: ekP, modifiers: {mkCtrl, mkShift})] = proc() =
    component.triggerAction(waShowCommands, "")
  
  let keyResult = component.componentManager.registerInputHandlers(
    component.id,
    keyHandlers,
    initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  )
  
  if keyResult.isErr:
    return err(keyResult.error)
  
  # Register mouse handlers
  let dragResult = component.componentManager.registerDragHandlers(
    component.id,
    proc(pos: MousePosition) = component.handleMouseClick(pos),
    proc(pos: MousePosition) = component.handleMouseMove(pos),
    proc(pos: MousePosition) = discard
  )
  
  return dragResult

# Input event handling
proc handleInput*(component: WelcomeScreenComponent, event: UnifiedInputEvent): bool =
  ## Handle unified input events
  if not component.isVisible:
    return false
  
  case event.kind:
  of uiekMouse:
    return component.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return component.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc handleMouseEvent*(component: WelcomeScreenComponent, event: MouseEvent): bool =
  ## Handle mouse events
  if not component.isVisible:
    return false
  
  let mousePos = rl.Vector2(x: event.position.x, y: event.position.y)
  
  case event.eventType:
  of metMoved:
    component.updateHoverStates(mousePos)
    # Only consume mouse move events if we're actually doing something with them
    # This allows hover effects to work in other components
    return false
  of metButtonPressed:
    echo "WelcomeScreen: Mouse button pressed at: ", mousePos.x, ", ", mousePos.y
    if event.button == mbLeft:
      component.handleItemClick(mousePos)
      return true
  else:
    discard
  
  return false

proc handleKeyboardEvent*(component: WelcomeScreenComponent, event: InputEvent): bool =
  ## Handle keyboard events
  if not component.isVisible:
    return false
  
  # Additional keyboard handling if needed
  return false

proc handleMouseClick*(component: WelcomeScreenComponent, pos: MousePosition) =
  ## Handle mouse click events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  component.handleItemClick(mousePos)

proc handleMouseMove*(component: WelcomeScreenComponent, pos: MousePosition) =
  ## Handle mouse move events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  component.updateHoverStates(mousePos)

proc updateHoverStates*(component: WelcomeScreenComponent, mousePos: rl.Vector2) =
  ## Update hover states for all items
  var needsUpdate = false
  
  for sectionIndex in 0..<component.sections.len:
    for itemIndex in 0..<component.sections[sectionIndex].items.len:
      let item = component.sections[sectionIndex].items[itemIndex]
      let wasHovered = item.isHovered
      let newHovered = rl.checkCollisionPointRec(mousePos, item.bounds)
      
      if wasHovered != newHovered:
        component.sections[sectionIndex].items[itemIndex].isHovered = newHovered
        needsUpdate = true
        
        # Set cursor
        if newHovered:
          component.componentManager.setCursor(component.id, rl.MouseCursor.PointingHand, cpUI)
        else:
          component.componentManager.clearCursor(component.id)
  
  if needsUpdate:
    component.componentManager.markComponentDirty(component.id)

proc handleItemClick*(component: WelcomeScreenComponent, mousePos: rl.Vector2) =
  ## Handle clicks on welcome items
  echo "WelcomeScreen: handleItemClick called at position: ", mousePos.x, ", ", mousePos.y
  for section in component.sections:
    for item in section.items:
      echo "Checking item: ", item.label, " bounds: ", item.bounds.x, ", ", item.bounds.y, " ", item.bounds.width, "x", item.bounds.height
      if rl.checkCollisionPointRec(mousePos, item.bounds):
        echo "Click detected on: ", item.label, " action: ", $item.action
        component.triggerAction(item.action, item.actionData)
        break



proc triggerAction*(component: WelcomeScreenComponent, action: WelcomeAction, data: string) =
  ## Trigger a welcome action using closure properties
  case action:
  of waNewFile:
    component.onNewFile()
    component.hide()
  of waOpenFile:
    component.onOpenFile()
    component.hide()
  of waOpenFolder:
    component.onOpenFolder()
    component.hide()
  of waCloneRepo:
    component.onCloneRepo()
    component.hide()
  of waOpenRecent:
    component.onOpenRecent(data)
    component.hide()
  of waShowCommands:
    component.onShowCommands()
    component.hide()
  of waDocumentation:
    component.onDocumentation()
    # Don't hide for documentation action
  else:
    discard

# Initialization and layout
proc initializeSections*(component: WelcomeScreenComponent) =
  ## Initialize default sections
  component.sections = @[]
  
  # Start section
  var startSection = WelcomeSection(title: "Start", items: @[])
  startSection.items.add(WelcomeItem(
    label: "New File",
    hotkey: "Ctrl+N",
    icon: "file",
    action: waNewFile,
    actionData: ""
  ))
  startSection.items.add(WelcomeItem(
    label: "Open File...",
    hotkey: "Ctrl+O",
    icon: "folder",
    action: waOpenFile,
    actionData: ""
  ))
  startSection.items.add(WelcomeItem(
    label: "Open Folder...",
    hotkey: "Ctrl+K Ctrl+O",
    icon: "folder",
    action: waOpenFolder,
    actionData: ""
  ))
  startSection.items.add(WelcomeItem(
    label: "Clone Git Repository...",
    hotkey: "",
    icon: "git",
    action: waCloneRepo,
    actionData: ""
  ))
  component.sections.add(startSection)
  
  # Recent section (initially empty)
  var recentSection = WelcomeSection(title: "Recent", items: @[])
  component.sections.add(recentSection)
  
  # Help section
  var helpSection = WelcomeSection(title: "Help", items: @[])
  helpSection.items.add(WelcomeItem(
    label: "Show All Commands",
    hotkey: "Ctrl+Shift+P",
    icon: "menu",
    action: waShowCommands,
    actionData: ""
  ))
  helpSection.items.add(WelcomeItem(
    label: "Documentation",
    hotkey: "",
    icon: "file",
    action: waDocumentation,
    actionData: ""
  ))
  component.sections.add(helpSection)

proc updateLayout*(component: WelcomeScreenComponent) =
  ## Update layout using ComponentManager
  if not component.isVisible:
    return
  
  var currentX = component.leftMargin
  var currentY = component.topMargin
  let sectionsPerColumn = 2
  
  for sectionIndex in 0..<component.sections.len:
    var section = component.sections[sectionIndex]
    
    # Set section bounds
    section.bounds = rl.Rectangle(
      x: currentX,
      y: currentY,
      width: component.columnWidth,
      height: 30.0 + (section.items.len.float32 * (32.0 + component.itemSpacing))
    )
    
    # Update item positions within section
    var itemY = currentY + 30.0
    
    for itemIndex in 0..<section.items.len:
      var item = section.items[itemIndex]
      
      item.bounds = rl.Rectangle(
        x: currentX + 20.0,
        y: itemY,
        width: component.columnWidth - 40.0,
        height: 32.0
      )
      
      section.items[itemIndex] = item
      itemY += 32.0 + component.itemSpacing
    
    component.sections[sectionIndex] = section
    
    # Move to next column or row
    if (sectionIndex + 1) mod sectionsPerColumn == 0:
      currentX += component.columnWidth + 50.0
      currentY = component.topMargin
    else:
      currentY = itemY + component.sectionSpacing
  
  # Update bounds using ComponentManager
  discard component.componentManager.updateComponentBounds(component.id, component.bounds)
  
  # Debug: Print item bounds
  echo "WelcomeScreen: Layout updated"
  for section in component.sections:
    echo "Section: ", section.title
    for item in section.items:
      echo "  Item: ", item.label, " bounds: ", item.bounds.x, ", ", item.bounds.y, " ", item.bounds.width, "x", item.bounds.height

# Rendering using ComponentManager services
proc render*(component: WelcomeScreenComponent) =
  ## Render using ComponentManager's renderer and theme
  if not component.isVisible:
    return
  
  let bounds = component.bounds
  
  # Draw background
  let bgColor = component.componentManager.getUIColor(uiBackground)
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, bgColor)
  
  # Draw title
  let titleColor = component.componentManager.getUIColor(uiText)
  rl.drawText(
    component.title,
    50, 40,
    component.titleFontSize.int32,
    titleColor
  )
  
  # Draw subtitle
  let subtitleColor = component.componentManager.getUIColor(uiTextMuted)
  rl.drawText(
    component.subtitle,
    50, 80,
    component.subtitleFontSize.int32,
    subtitleColor
  )
  
  # Draw sections
  for section in component.sections:
    # Skip empty sections
    if section.items.len == 0:
      continue
    
    # Draw section title
    let accentColor = component.componentManager.getUIColor(uiAccent)
    rl.drawText(
      section.title,
      section.bounds.x.int32,
      section.bounds.y.int32,
      component.sectionFontSize.int32,
      accentColor
    )
    
    # Draw items
    for item in section.items:
      # Draw item background if hovered
      if item.isHovered:
        let selectionColor = component.componentManager.getUIColor(uiSelection)
        rl.drawRectangle(
          item.bounds.x.int32,
          item.bounds.y.int32,
          item.bounds.width.int32,
          item.bounds.height.int32,
          selectionColor
        )
      
      # Draw item icon (simple placeholder)
      let iconX = item.bounds.x + 8.0
      let iconY = item.bounds.y + 8.0
      let iconSize = 16.0
      let iconColor = component.componentManager.getUIColor(uiIcon)
      
      case item.icon:
      of "file":
        rl.drawRectangle(
          iconX.int32,
          iconY.int32,
          (iconSize * 0.7).int32,
          iconSize.int32,
          iconColor
        )
      of "folder":
        rl.drawRectangle(
          iconX.int32,
          iconY.int32,
          iconSize.int32,
          (iconSize * 0.8).int32,
          iconColor
        )
      of "git":
        rl.drawCircle(
          (iconX + iconSize / 2).int32,
          (iconY + iconSize / 2).int32,
          iconSize * 0.4,
          iconColor
        )
      else:
        rl.drawRectangle(
          iconX.int32,
          iconY.int32,
          iconSize.int32,
          iconSize.int32,
          iconColor
        )
      
      # Draw item text
      let textColor = if item.isHovered:
        component.componentManager.getUIColor(uiText)
      else:
        component.componentManager.getUIColor(uiTextMuted)
      
      rl.drawText(
        item.label,
        (item.bounds.x + 30.0).int32,
        (item.bounds.y + 6.0).int32,
        component.itemFontSize.int32,
        textColor
      )
      
      # Draw hotkey if available
      if item.hotkey.len > 0:
        let hotkeyColor = component.componentManager.getUIColor(uiTextMuted)
        let hotkeyX = item.bounds.x + item.bounds.width - 100.0
        rl.drawText(
          item.hotkey,
          hotkeyX.int32,
          (item.bounds.y + 6.0).int32,
          12,
          hotkeyColor
        )
  
  # Draw hint
  let hintY = bounds.y + bounds.height - 60.0
  let hintColor = component.componentManager.getUIColor(uiTextMuted)
  rl.drawText(
    "Press F1 to switch themes | Press Escape to dismiss",
    50,
    hintY.int32,
    12,
    hintColor
  )
  
  component.isDirty = false

# Public interface methods
proc addRecentFile*(component: WelcomeScreenComponent, filePath: string) =
  ## Add a recent file to the welcome screen
  if component.recentFiles.len >= 10:
    component.recentFiles.delete(component.recentFiles.len - 1)
  component.recentFiles.insert(filePath, 0)
  
  # Update Recent section (index 1)
  if component.sections.len >= 2:
    component.sections[1].items = @[]
    for i, path in component.recentFiles:
      if i >= 5:
        break # Show only 5 recent files
      let fileName = path.splitPath().tail
      component.sections[1].items.add(WelcomeItem(
        label: fileName,
        hotkey: "",
        icon: "file",
        action: waOpenRecent,
        actionData: path
      ))
  
  component.updateLayout()
  component.componentManager.markComponentDirty(component.id)

proc show*(component: WelcomeScreenComponent) =
  ## Show the welcome screen component
  component.isVisible = true
  discard component.componentManager.setComponentVisibility(component.id, true)
  component.componentManager.markComponentDirty(component.id)

proc hide*(component: WelcomeScreenComponent) =
  ## Hide the welcome screen component
  component.isVisible = false
  discard component.componentManager.setComponentVisibility(component.id, false)
  component.componentManager.clearCursor(component.id)
  component.componentManager.markComponentDirty(component.id)



proc update*(component: WelcomeScreenComponent, deltaTime: float32) =
  ## Update component state
  if component.isVisible:
    # Update layout if needed
    component.updateLayout()

# Utility functions
proc isVisible*(component: WelcomeScreenComponent): bool =
  ## Check if component is visible
  component.isVisible

# Cleanup
proc cleanup*(component: WelcomeScreenComponent) =
  ## Clean up resources
  component.hide()
  discard component.componentManager.unregisterComponent(component.id)