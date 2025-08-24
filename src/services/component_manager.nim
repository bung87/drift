## Component Manager Service
## Coordinates all infrastructure services for standardized component architecture

import std/[tables, options, sequtils]
import raylib as rl
import results
import ../shared/errors
import ../infrastructure/input/[input_handler, keyboard, mouse]
import ../infrastructure/rendering/[renderer, theme]
import ../infrastructure/ui/cursor_manager
import ../infrastructure/filesystem/file_manager
import ui_service

# Component Manager types
type
  ComponentManager* = ref object
    # Core services
    uiService*: UIService
    inputHandler*: InputHandler
    renderer*: Renderer
    themeManager*: ThemeManager
    cursorManager*: CursorManager
    fileManager*: FileManager
    
    # Component registry
    registeredComponents*: Table[string, UIComponent]
    componentInputHandlers*: Table[string, proc(event: UnifiedInputEvent): bool]
    componentRenderHandlers*: Table[string, proc(bounds: rl.Rectangle)]
    
    # State management
    initialized*: bool
    enabled*: bool

# Constructor
proc newComponentManager*(
  uiService: UIService,
  inputHandler: InputHandler,
  renderer: Renderer,
  themeManager: ThemeManager,
  cursorManager: CursorManager,
  fileManager: FileManager
): ComponentManager =
  ComponentManager(
    uiService: uiService,
    inputHandler: inputHandler,
    renderer: renderer,
    themeManager: themeManager,
    cursorManager: cursorManager,
    fileManager: fileManager,
    registeredComponents: initTable[string, UIComponent](),
    componentInputHandlers: initTable[string, proc(event: UnifiedInputEvent): bool](),
    componentRenderHandlers: initTable[string, proc(bounds: Rectangle)](),
    initialized: false,
    enabled: true
  )

# Initialization
proc initialize*(manager: ComponentManager): Result[void, EditorError] =
  ## Initialize the component manager and all infrastructure services
  if manager.initialized:
    return ok()
  
  try:
    # Initialize all services if needed
    # Most services should already be initialized, but we can add checks here
    
    manager.initialized = true
    return ok()
  except:
    return err(EditorError(
      msg: "Failed to initialize ComponentManager",
      code: "COMPONENT_MANAGER_INIT_ERROR"
    ))

# Component registration
proc registerComponent*(
  manager: ComponentManager,
  componentId: string,
  component: UIComponent,
  inputHandler: proc(event: UnifiedInputEvent): bool = nil,
  renderHandler: proc(bounds: rl.Rectangle) = nil
): Result[void, EditorError] =
  ## Register a component with the manager
  if not manager.enabled:
    return err(EditorError(
      msg: "ComponentManager is disabled",
      code: "COMPONENT_MANAGER_DISABLED"
    ))
  
  if componentId in manager.registeredComponents:
    return err(EditorError(
      msg: "Component already registered: " & componentId,
      code: "COMPONENT_ALREADY_REGISTERED"
    ))
  
  # Register with UI service
  manager.uiService.components[componentId] = component
  
  # Store in local registry
  manager.registeredComponents[componentId] = component
  
  # Register handlers if provided
  if inputHandler != nil:
    manager.componentInputHandlers[componentId] = inputHandler
  
  if renderHandler != nil:
    manager.componentRenderHandlers[componentId] = renderHandler
  
  return ok()

proc unregisterComponent*(
  manager: ComponentManager,
  componentId: string
): Result[void, EditorError] =
  ## Unregister a component from the manager
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not found: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  # Remove from UI service
  discard manager.uiService.removeComponent(componentId)
  
  # Remove from local registry
  manager.registeredComponents.del(componentId)
  manager.componentInputHandlers.del(componentId)
  manager.componentRenderHandlers.del(componentId)
  
  return ok()

# Input handling coordination
proc registerInputHandlers*(
  manager: ComponentManager,
  componentId: string,
  keyHandlers: Table[KeyCombination, proc()],
  mouseHandlers: Table[mouse.MouseButton, proc(pos: MousePosition)]
): Result[void, EditorError] =
  ## Register input handlers for a component using existing infrastructure
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not registered: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  # Register keyboard shortcuts using InputHandler command system
  for keyCombination, handler in keyHandlers:
    let commandName = componentId & "_" & $keyCombination.key
    let commandHandler: CommandHandler = proc(command: InputCommand, event: UnifiedInputEvent): bool =
      handler()
      return true
    
    let registerResult = manager.inputHandler.registerCommand(
      commandName,
      "Component command for " & componentId,
      keyCombination,
      {icNormal},
      ipNormal,
      commandHandler
    )
    
    if registerResult.isErr:
      return err(EditorError(
        msg: "Failed to register key handler: " & registerResult.error.msg,
        code: "INPUT_HANDLER_REGISTRATION_ERROR"
      ))
  
  # Register mouse handlers
  for mouseButton, mouseHandler in mouseHandlers:
    let mouseGesture = MouseGesture(
      button: mouseButton,
      clickType: ctSingle,
      modifiers: {},
      requiresHover: false,
      hoverElement: ""
    )
    
    let commandName = componentId & "_mouse_" & $mouseButton
    let commandHandler: CommandHandler = proc(command: InputCommand, event: UnifiedInputEvent): bool =
      if event.kind == uiekMouse:
        mouseHandler(event.mouseEvent.position)
      return true
    
    let registerResult = manager.inputHandler.registerMouseCommand(
      commandName,
      "Mouse command for " & componentId,
      mouseGesture,
      {icNormal},
      ipNormal,
      commandHandler
    )
    
    if registerResult.isErr:
      return err(EditorError(
        msg: "Failed to register mouse handler: " & registerResult.error.msg,
        code: "INPUT_HANDLER_REGISTRATION_ERROR"
      ))
  
  return ok()

proc registerKeyboardShortcuts*(
  manager: ComponentManager,
  componentId: string,
  shortcuts: Table[KeyCombination, string]
): Result[void, EditorError] =
  ## Register keyboard shortcuts that map to command names
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not registered: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  for keyCombination, commandName in shortcuts:
    let fullCommandName = componentId & "_" & commandName
    let commandHandler: CommandHandler = proc(command: InputCommand, event: UnifiedInputEvent): bool =
      # Execute the named command for this component
      # This would typically call a method on the component
      return true
    
    let registerResult = manager.inputHandler.registerCommand(
      fullCommandName,
      "Keyboard shortcut for " & componentId & ": " & commandName,
      keyCombination,
      {icNormal},
      ipNormal,
      commandHandler
    )
    
    if registerResult.isErr:
      return err(EditorError(
        msg: "Failed to register keyboard shortcut: " & registerResult.error.msg,
        code: "INPUT_HANDLER_REGISTRATION_ERROR"
      ))
  
  return ok()

proc registerDragHandlers*(
  manager: ComponentManager,
  componentId: string,
  onDragStart: proc(pos: MousePosition),
  onDragMove: proc(pos: MousePosition),
  onDragEnd: proc(pos: MousePosition)
): Result[void, EditorError] =
  ## Register drag handlers using existing drag_interaction.nim infrastructure
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not registered: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  # Create a unified drag handler that uses the existing infrastructure
  let dragHandler: CommandHandler = proc(command: InputCommand, event: UnifiedInputEvent): bool =
    if event.kind == uiekMouse:
      let mouseEvent = event.mouseEvent
      case mouseEvent.eventType
      of metButtonPressed:
        if onDragStart != nil:
          onDragStart(mouseEvent.position)
      of metMoved:
        if manager.inputHandler.isDragging() and onDragMove != nil:
          onDragMove(mouseEvent.position)
      of metButtonReleased:
        if onDragEnd != nil:
          onDragEnd(mouseEvent.position)
      else:
        discard
    return true
  
  # Register as a mouse command
  let mouseGesture = MouseGesture(
    button: mbLeft,
    clickType: ctSingle,
    modifiers: {},
    requiresHover: true,
    hoverElement: componentId
  )
  
  let dragResult = manager.inputHandler.registerMouseCommand(
    componentId & "_drag",
    "Drag handler for " & componentId,
    mouseGesture,
    {icNormal},
    ipNormal,
    dragHandler
  )
  
  if dragResult.isErr:
    return err(EditorError(
      msg: "Failed to register drag handler: " & dragResult.error.msg,
      code: "INPUT_HANDLER_REGISTRATION_ERROR"
    ))
  
  return ok()

# Layout management coordination
proc createLayoutHelpers*(
  manager: ComponentManager,
  componentId: string
): Result[void, EditorError] =
  ## Create layout helper functions that use UIService layout system
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not registered: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  # Layout helpers are provided through the UIService
  # Components can use manager.uiService.setLayout(), etc.
  return ok()

proc updateComponentBounds*(
  manager: ComponentManager,
  componentId: string,
  bounds: rl.Rectangle
): Result[void, EditorError] =
  ## Update component bounds using UIService.setComponentBounds
  return manager.uiService.setComponentBounds(componentId, bounds)

proc getComponentAt*(
  manager: ComponentManager,
  x, y: float32
): Option[UIComponent] =
  ## Get component at position using UIService.getComponentAt
  return manager.uiService.getComponentAt(x, y)

# State management coordination
proc updateComponentState*(
  manager: ComponentManager,
  componentId: string,
  state: ComponentState
): Result[void, EditorError] =
  ## Update component state using UIService methods
  return manager.uiService.setComponentState(componentId, state)

proc setComponentVisibility*(
  manager: ComponentManager,
  componentId: string,
  visible: bool
): Result[void, EditorError] =
  ## Set component visibility using UIService.setComponentVisibility
  return manager.uiService.setComponentVisibility(componentId, visible)

proc setComponentEnabled*(
  manager: ComponentManager,
  componentId: string,
  enabled: bool
): Result[void, EditorError] =
  ## Set component enabled state using UIService.setComponentEnabled
  return manager.uiService.setComponentEnabled(componentId, enabled)

proc markComponentDirty*(
  manager: ComponentManager,
  componentId: string
) =
  ## Mark component as dirty using UIService.markComponentDirty
  manager.uiService.markComponentDirty(componentId)

proc markAllComponentsDirty*(manager: ComponentManager) =
  ## Mark all registered components as dirty
  for componentId in manager.registeredComponents.keys:
    manager.uiService.markComponentDirty(componentId)

# Rendering coordination
proc createRenderHelpers*(
  manager: ComponentManager,
  componentId: string
): Result[void, EditorError] =
  ## Create render helper functions using existing Renderer infrastructure
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not registered: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  # Render helpers are provided through the Renderer
  # Components can use manager.renderer.drawRectangle(), etc.
  return ok()

proc renderComponent*(
  manager: ComponentManager,
  componentId: string,
  bounds: rl.Rectangle
): Result[void, EditorError] =
  ## Render a component using its registered render handler
  if componentId notin manager.registeredComponents:
    return err(EditorError(
      msg: "Component not registered: " & componentId,
      code: "COMPONENT_NOT_FOUND"
    ))
  
  if componentId in manager.componentRenderHandlers:
    let renderHandler = manager.componentRenderHandlers[componentId]
    renderHandler(bounds)
  
  return ok()

proc renderAllVisibleComponents*(manager: ComponentManager) =
  ## Render all visible components managed by this ComponentManager
  for componentId, component in manager.registeredComponents:
    if component.isVisible and componentId in manager.componentRenderHandlers:
      echo "DEBUG: Rendering visible component: ", componentId
      let renderHandler = manager.componentRenderHandlers[componentId]
      renderHandler(component.bounds)

# Cursor management integration
proc setCursor*(
  manager: ComponentManager,
  requesterId: string,
  cursor: rl.MouseCursor,
  priority: CursorPriority
) =
  ## Set cursor using existing CursorManager
  manager.cursorManager.requestCursor(requesterId, cursor, priority)

proc clearCursor*(
  manager: ComponentManager,
  requesterId: string
) =
  ## Clear cursor request using CursorManager
  manager.cursorManager.clearCursorRequest(requesterId)

# File operations integration
proc getFileManager*(manager: ComponentManager): FileManager =
  ## Get access to FileManager for file operations
  return manager.fileManager

# Theme integration
proc getTheme*(manager: ComponentManager): Theme =
  ## Get current theme from ThemeManager
  return manager.themeManager.currentTheme

proc getUIColor*(manager: ComponentManager, colorType: UIColorType): rl.Color =
  ## Get UI color from theme
  return manager.themeManager.getUIColor(colorType)

# Event processing
proc processInput*(manager: ComponentManager): seq[UnifiedInputEvent] =
  ## Process input events and route to registered components
  if not manager.enabled:
    return @[]
  
  let events = manager.inputHandler.processEvents()
  
  # Route events to component handlers
  for event in events:
    for componentId, handler in manager.componentInputHandlers:
      if handler(event):
        break # Event was handled
  
  return events

proc update*(manager: ComponentManager) =
  ## Update all managed components and services
  if not manager.enabled:
    return
  
  # Update UI service
  manager.uiService.update()
  
  # Process input events
  discard manager.processInput()
  
  # Check for command execution
  let commands = manager.inputHandler.checkCommands()
  for commandName in commands:
    discard manager.inputHandler.executeCommand(commandName)

# Utility functions
proc getRegisteredComponents*(manager: ComponentManager): seq[string] =
  ## Get list of all registered component IDs
  return toSeq(manager.registeredComponents.keys)

proc isComponentRegistered*(manager: ComponentManager, componentId: string): bool =
  ## Check if a component is registered
  return componentId in manager.registeredComponents

proc getComponent*(manager: ComponentManager, componentId: string): Option[UIComponent] =
  ## Get a registered component
  if componentId in manager.registeredComponents:
    return some(manager.registeredComponents[componentId])
  else:
    return none(UIComponent)

# Configuration
proc setEnabled*(manager: ComponentManager, enabled: bool) =
  ## Enable or disable the component manager
  manager.enabled = enabled
  manager.inputHandler.setEnabled(enabled)

proc isEnabled*(manager: ComponentManager): bool =
  ## Check if component manager is enabled
  return manager.enabled

# Cleanup
proc cleanup*(manager: ComponentManager) =
  ## Clean up all resources
  manager.registeredComponents.clear()
  manager.componentInputHandlers.clear()
  manager.componentRenderHandlers.clear()
  
  # Cleanup services
  manager.uiService.cleanup()
  manager.inputHandler.cleanup()
  manager.renderer.cleanup()
  
  manager.initialized = false