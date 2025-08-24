## UI Service
## Coordinates user interface operations and state management

import std/[options, tables, sequtils, times, algorithm]
import raylib as rl
import results
import ../shared/errors
import ../infrastructure/rendering/[theme, renderer]
import ../infrastructure/input/input_handler

# UI component types
type
  ComponentState* = enum
    csHidden = "hidden"
    csVisible = "visible"
    csActive = "active"
    csFocused = "focused"
    csDisabled = "disabled"

  UIComponent* = ref object of RootObj
    id*: string
    name*: string
    state*: ComponentState
    bounds*: rl.Rectangle
    zIndex*: int
    isVisible*: bool
    isEnabled*: bool
    isDirty*: bool
    parent*: UIComponent
    children*: seq[UIComponent]
    data*: Table[string, string]

  Layout* = object
    componentId*: string
    x*: float32
    y*: float32
    width*: float32
    height*: float32
    constraints*: LayoutConstraints

  LayoutConstraints* = object
    minWidth*: float32
    minHeight*: float32
    maxWidth*: float32
    maxHeight*: float32
    flexible*: bool

  # Using raylib.Rectangle instead of custom Rectangle type
  ViewportInfo* = object
    width*: float32
    height*: float32
    dpi*: float32
    scale*: float32

  UIEvent* = object
    eventType*: UIEventType
    componentId*: string
    data*: Table[string, string]
    timestamp*: Time
    handled*: bool

  UIEventType* = enum
    uetClick = "click"
    uetHover = "hover"
    uetFocus = "focus"
    uetBlur = "blur"
    uetKeyPress = "keypress"
    uetTextInput = "textinput"
    uetResize = "resize"
    uetScroll = "scroll"
    uetDrag = "drag"
    uetDrop = "drop"

  UIService* = ref object # Core state
    components*: Table[string, UIComponent]
    layouts*: Table[string, Layout]
    activeComponent*: Option[UIComponent]
    focusedComponent*: Option[UIComponent]
    hoveredComponent*: Option[UIComponent]

    # Viewport and rendering
    viewport*: ViewportInfo
    theme*: Theme
    renderer*: Renderer
    inputHandler*: InputHandler

    # Event handling
    eventQueue*: seq[UIEvent]
    eventHandlers*: Table[string, proc(event: UIEvent)]
    globalEventHandlers*: Table[UIEventType, seq[proc(event: UIEvent)]]

    # Layout management
    layoutDirty*: bool
    needsRedraw*: bool
    nextZIndex*: int

    # Status and feedback
    statusMessage*: string
    statusTimeout*: Option[Time]

    # UI state
    sidebarWidth*: float32
    statusBarHeight*: float32
    toolbarHeight*: float32
    showSidebar*: bool
    showStatusBar*: bool
    showToolbar*: bool
    showLineNumbers*: bool
    showMinimap*: bool

    # Settings
    animationsEnabled*: bool
    tooltipDelay*: int    # milliseconds
    doubleClickTime*: int # milliseconds

    # Event callbacks
    onComponentAdded*: proc(service: UIService, component: UIComponent)
    onComponentRemoved*: proc(service: UIService, componentId: string)
    onLayoutChanged*: proc(service: UIService)
    onThemeChanged*: proc(service: UIService, theme: Theme)

# Forward declarations
proc queueEvent*(service: UIService, event: UIEvent)

# Service creation
proc newUIService*(
    theme: Theme, renderer: Renderer, inputHandler: InputHandler
): UIService =
  UIService(
    components: Table[string, UIComponent](),
    layouts: Table[string, Layout](),
    activeComponent: none(UIComponent),
    focusedComponent: none(UIComponent),
    hoveredComponent: none(UIComponent),
    viewport: ViewportInfo(width: 1200, height: 800, dpi: 96.0, scale: 1.0),
    theme: theme,
    renderer: renderer,
    inputHandler: inputHandler,
    eventQueue: @[],
    eventHandlers: Table[string, proc(event: UIEvent)](),
    globalEventHandlers: Table[UIEventType, seq[proc(event: UIEvent)]](),
    layoutDirty: true,
    needsRedraw: true,
    nextZIndex: 1,
    statusMessage: "",
    statusTimeout: none(Time),
    sidebarWidth: 250.0,
    statusBarHeight: 24.0,
    toolbarHeight: 40.0,
    showSidebar: true,
    showStatusBar: true,
    showToolbar: true,
    showLineNumbers: true,
    showMinimap: false,
    animationsEnabled: true,
    tooltipDelay: 500,
    doubleClickTime: 300,
    onComponentAdded: nil,
    onComponentRemoved: nil,
    onLayoutChanged: nil,
    onThemeChanged: nil,
  )

# Component management
proc createComponent*(service: UIService, id: string,
    name: string): UIComponent =
  let component = UIComponent(
    id: id,
    name: name,
    state: csVisible,
    bounds: Rectangle(x: 0, y: 0, width: 100, height: 100),
    zIndex: service.nextZIndex,
    isVisible: true,
    isEnabled: true,
    isDirty: true,
    parent: nil,
    children: @[],
    data: Table[string, string](),
  )

  service.components[id] = component
  inc service.nextZIndex
  service.layoutDirty = true
  service.needsRedraw = true

  if service.onComponentAdded != nil:
    service.onComponentAdded(service, component)

  component

proc removeComponent*(
    service: UIService, componentId: string
): Result[void, EditorError] =
  if componentId notin service.components:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  let component = service.components[componentId]

  # Remove from parent
  if component.parent != nil:
    let index = component.parent.children.find(component)
    if index >= 0:
      component.parent.children.delete(index)

  # Remove children
  for child in component.children:
    discard service.removeComponent(child.id)

  # Update focus/hover if this component was active
  if service.focusedComponent.isSome and service.focusedComponent.get().id == componentId:
    service.focusedComponent = none(UIComponent)

  if service.hoveredComponent.isSome and service.hoveredComponent.get().id == componentId:
    service.hoveredComponent = none(UIComponent)

  if service.activeComponent.isSome and service.activeComponent.get().id == componentId:
    service.activeComponent = none(UIComponent)

  service.components.del(componentId)
  service.layouts.del(componentId)
  service.eventHandlers.del(componentId)
  service.layoutDirty = true
  service.needsRedraw = true

  if service.onComponentRemoved != nil:
    service.onComponentRemoved(service, componentId)

  ok()

proc getComponent*(service: UIService, componentId: string): Option[UIComponent] =
  if componentId in service.components:
    some(service.components[componentId])
  else:
    none(UIComponent)

proc addChildComponent*(
    service: UIService, parentId: string, childId: string
): Result[void, EditorError] =
  let parent = service.getComponent(parentId)
  let child = service.getComponent(childId)

  if parent.isNone:
    return
      err(EditorError(msg: "Parent component not found",
          code: "COMPONENT_NOT_FOUND"))

  if child.isNone:
    return
      err(EditorError(msg: "Child component not found",
          code: "COMPONENT_NOT_FOUND"))

  let parentComp = parent.get()
  let childComp = child.get()

  # Remove from current parent if any
  if childComp.parent != nil:
    let index = childComp.parent.children.find(childComp)
    if index >= 0:
      childComp.parent.children.delete(index)

  parentComp.children.add(childComp)
  childComp.parent = parentComp
  service.layoutDirty = true
  service.needsRedraw = true

  ok()

# Component state management
proc setComponentState*(
    service: UIService, componentId: string, state: ComponentState
): Result[void, EditorError] =
  let component = service.getComponent(componentId)
  if component.isNone:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  let comp = component.get()
  if comp.state != state:
    comp.state = state
    comp.isDirty = true
    service.needsRedraw = true

  ok()

proc setComponentVisibility*(
    service: UIService, componentId: string, visible: bool
): Result[void, EditorError] =
  let component = service.getComponent(componentId)
  if component.isNone:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  let comp = component.get()
  if comp.isVisible != visible:
    comp.isVisible = visible
    comp.isDirty = true
    service.layoutDirty = true
    service.needsRedraw = true

  ok()

proc setComponentEnabled*(
    service: UIService, componentId: string, enabled: bool
): Result[void, EditorError] =
  let component = service.getComponent(componentId)
  if component.isNone:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  let comp = component.get()
  if comp.isEnabled != enabled:
    comp.isEnabled = enabled
    comp.isDirty = true
    service.needsRedraw = true

  ok()

proc setComponentBounds*(
    service: UIService, componentId: string, bounds: rl.Rectangle
): Result[void, EditorError] =
  let component = service.getComponent(componentId)
  if component.isNone:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  let comp = component.get()
  comp.bounds = bounds
  comp.isDirty = true
  service.layoutDirty = true
  service.needsRedraw = true

  ok()

# Focus management
proc setFocus*(service: UIService, componentId: string): Result[void, EditorError] =
  let component = service.getComponent(componentId)
  if component.isNone:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  let comp = component.get()
  if not comp.isEnabled:
    return err(
      EditorError(msg: "Cannot focus disabled component",
          code: "COMPONENT_DISABLED")
    )

  # Remove focus from current component
  if service.focusedComponent.isSome:
    let currentFocused = service.focusedComponent.get()
    if currentFocused.state == csFocused:
      currentFocused.state = csVisible
      currentFocused.isDirty = true

  service.focusedComponent = some(comp)
  comp.state = csFocused
  comp.isDirty = true
  service.needsRedraw = true

  # Emit focus event
  let focusEvent = UIEvent(
    eventType: uetFocus,
    componentId: componentId,
    data: initTable[string, string](),
    timestamp: times.getTime(),
    handled: false,
  )
  service.queueEvent(focusEvent)

  ok()

proc clearFocus*(service: UIService) =
  if service.focusedComponent.isSome:
    let focused = service.focusedComponent.get()
    focused.state = csVisible
    focused.isDirty = true
    service.needsRedraw = true

    # Emit blur event
    let blurEvent = UIEvent(
      eventType: uetBlur,
      componentId: focused.id,
      data: initTable[string, string](),
      timestamp: times.getTime(),
      handled: false,
    )
    service.queueEvent(blurEvent)

  service.focusedComponent = none(UIComponent)

proc getFocusedComponent*(service: UIService): Option[UIComponent] =
  service.focusedComponent

# Layout management
proc setLayout*(
    service: UIService, componentId: string, layout: Layout
): Result[void, EditorError] =
  let component = service.getComponent(componentId)
  if component.isNone:
    return err(EditorError(msg: "Component not found",
        code: "COMPONENT_NOT_FOUND"))

  service.layouts[componentId] = layout
  service.layoutDirty = true
  service.needsRedraw = true

  if service.onLayoutChanged != nil:
    service.onLayoutChanged(service)

  ok()

proc getLayout*(service: UIService, componentId: string): Option[Layout] =
  if componentId in service.layouts:
    some(service.layouts[componentId])
  else:
    none(Layout)

proc performLayout*(service: UIService) =
  if not service.layoutDirty:
    return

  # Simple layout algorithm - this would be more sophisticated in practice
  for componentId, layout in service.layouts:
    let component = service.getComponent(componentId)
    if component.isSome and component.get().isVisible:
      let comp = component.get()
      comp.bounds = Rectangle(
        x: layout.x,
        y: layout.y,
        width: max(layout.width, layout.constraints.minWidth),
        height: max(layout.height, layout.constraints.minHeight),
      )
      comp.isDirty = true

  service.layoutDirty = false
  service.needsRedraw = true

# Event handling
proc queueEvent*(service: UIService, event: UIEvent) =
  service.eventQueue.add(event)

proc processEvents*(service: UIService) =
  for event in service.eventQueue:
    var processed = event
    processed.handled = false

    # Try component-specific handler first
    if event.componentId in service.eventHandlers:
      service.eventHandlers[event.componentId](processed)

    # If not handled, try global handlers
    if not processed.handled and event.eventType in service.globalEventHandlers:
      for handler in service.globalEventHandlers[event.eventType]:
        handler(processed)
        if processed.handled:
          break

  service.eventQueue.setLen(0)

proc registerEventHandler*(
    service: UIService, componentId: string, handler: proc(event: UIEvent)
) =
  service.eventHandlers[componentId] = handler

proc registerGlobalEventHandler*(
    service: UIService, eventType: UIEventType, handler: proc(event: UIEvent)
) =
  if eventType notin service.globalEventHandlers:
    service.globalEventHandlers[eventType] = @[]
  service.globalEventHandlers[eventType].add(handler)

proc unregisterEventHandler*(service: UIService, componentId: string) =
  service.eventHandlers.del(componentId)

# Legacy notification functions removed - use NotificationService instead

# Status management
proc setStatusMessage*(
    service: UIService, message: string, timeout: Option[int] = none(int)
) =
  service.statusMessage = message
  service.statusTimeout =
    if timeout.isSome:
      some(times.getTime() + initDuration(milliseconds = timeout.get()))
    else:
      none(Time)
  service.needsRedraw = true

proc clearStatusMessage*(service: UIService) =
  service.statusMessage = ""
  service.statusTimeout = none(Time)
  service.needsRedraw = true

proc updateStatusMessage*(service: UIService) =
  if service.statusTimeout.isSome and times.getTime() >
      service.statusTimeout.get():
    service.clearStatusMessage()

# Theme management
proc setTheme*(service: UIService, theme: Theme) =
  service.theme = theme

  # Mark all components as dirty to force redraw with new theme
  for component in service.components.values:
    component.isDirty = true

  service.needsRedraw = true

  if service.onThemeChanged != nil:
    service.onThemeChanged(service, theme)

proc getTheme*(service: UIService): Theme =
  service.theme

# Viewport management
proc setViewport*(
    service: UIService,
    width: float32,
    height: float32,
    dpi: float32 = 96.0,
    scale: float32 = 1.0,
) =
  service.viewport = ViewportInfo(width: width, height: height, dpi: dpi, scale: scale)
  service.layoutDirty = true
  service.needsRedraw = true

  # Emit resize event
  let resizeEvent = UIEvent(
    eventType: uetResize,
    componentId: "",
    data: {"width": $width, "height": $height}.toTable(),
    timestamp: times.getTime(),
    handled: false,
  )
  service.queueEvent(resizeEvent)

proc getViewport*(service: UIService): ViewportInfo =
  service.viewport

# UI panel management
proc setSidebarWidth*(service: UIService, width: float32) =
  service.sidebarWidth = width
  service.layoutDirty = true
  service.needsRedraw = true

proc setSidebarVisible*(service: UIService, visible: bool) =
  service.showSidebar = visible
  service.layoutDirty = true
  service.needsRedraw = true

proc toggleSidebar*(service: UIService) =
  service.setSidebarVisible(not service.showSidebar)

proc setStatusBarVisible*(service: UIService, visible: bool) =
  service.showStatusBar = visible
  service.layoutDirty = true
  service.needsRedraw = true

proc setToolbarVisible*(service: UIService, visible: bool) =
  service.showToolbar = visible
  service.layoutDirty = true
  service.needsRedraw = true

proc setLineNumbersVisible*(service: UIService, visible: bool) =
  service.showLineNumbers = visible
  service.needsRedraw = true

proc setMinimapVisible*(service: UIService, visible: bool) =
  service.showMinimap = visible
  service.layoutDirty = true
  service.needsRedraw = true

# Hit testing
proc getComponentAt*(service: UIService, x: float32, y: float32): Option[UIComponent] =
  var foundComponent: Option[UIComponent] = none(UIComponent)
  var topZIndex = -1

  for component in service.components.values:
    if component.isVisible and component.bounds.x <= x and
        x <= component.bounds.x + component.bounds.width and
            component.bounds.y <= y and
        y <= component.bounds.y + component.bounds.height:
      if component.zIndex > topZIndex:
        topZIndex = component.zIndex
        foundComponent = some(component)

  return foundComponent

# Mouse interaction
proc handleMouseMove*(service: UIService, x: float32, y: float32) =
  let componentAtPosition = service.getComponentAt(x, y)

  # Handle hover state changes
  if service.hoveredComponent != componentAtPosition:
    # Clear old hover
    if service.hoveredComponent.isSome:
      let oldHovered = service.hoveredComponent.get()
      if oldHovered.state != csFocused:
        oldHovered.state = csVisible
      oldHovered.isDirty = true

    # Set new hover
    if componentAtPosition.isSome:
      let newHovered = componentAtPosition.get()
      if newHovered.isEnabled and newHovered.state != csFocused:
        newHovered.state = csActive
      newHovered.isDirty = true

      # Emit hover event
      let hoverEvent = UIEvent(
        eventType: uetHover,
        componentId: newHovered.id,
        data: {"x": $x, "y": $y}.toTable(),
        timestamp: times.getTime(),
        handled: false,
      )
      service.queueEvent(hoverEvent)

    service.hoveredComponent = componentAtPosition
    service.needsRedraw = true

proc handleMouseClick*(service: UIService, x: float32, y: float32) =
  let componentAtPosition = service.getComponentAt(x, y)

  if componentAtPosition.isSome:
    let component = componentAtPosition.get()
    if component.isEnabled:
      # Set as active component
      service.activeComponent = some(component)

      # Set focus if focusable
      discard service.setFocus(component.id)

      # Emit click event
      let clickEvent = UIEvent(
        eventType: uetClick,
        componentId: component.id,
        data: {"x": $x, "y": $y}.toTable(),
        timestamp: times.getTime(),
        handled: false,
      )
      service.queueEvent(clickEvent)
  else:
    # Click in empty space - clear focus
    service.clearFocus()

# Rendering coordination
proc markForRedraw*(service: UIService) =
  service.needsRedraw = true

proc markComponentDirty*(service: UIService, componentId: string) =
  let component = service.getComponent(componentId)
  if component.isSome:
    component.get().isDirty = true
    service.needsRedraw = true

proc needsRedraw*(service: UIService): bool =
  service.needsRedraw

proc render*(service: UIService) =
  if not service.needsRedraw:
    return

  # Perform layout if needed
  service.performLayout()

  # Legacy notification system removed - use NotificationService instead

  # Update status message
  service.updateStatusMessage()

  # Render components in z-order
  var sortedComponents = toSeq(service.components.values)
  sortedComponents.sort(
    proc(a, b: UIComponent): int =
    a.zIndex - b.zIndex
  )

  for component in sortedComponents:
    if component.isVisible:
      # Render component using renderer
      # This would delegate to the actual rendering implementation
      component.isDirty = false

  service.needsRedraw = false

# Settings
proc setAnimationsEnabled*(service: UIService, enabled: bool) =
  service.animationsEnabled = enabled

proc setTooltipDelay*(service: UIService, delay: int) =
  service.tooltipDelay = delay

proc setDoubleClickTime*(service: UIService, time: int) =
  service.doubleClickTime = time

proc getAnimationsEnabled*(service: UIService): bool =
  service.animationsEnabled

proc getTooltipDelay*(service: UIService): int =
  service.tooltipDelay

proc getDoubleClickTime*(service: UIService): int =
  service.doubleClickTime

# Utility functions
proc getComponentCount*(service: UIService): int =
  service.components.len

proc getVisibleComponentCount*(service: UIService): int =
  service.components.values.toSeq().countIt(it.isVisible)

proc getEnabledComponentCount*(service: UIService): int =
  service.components.values.toSeq().countIt(it.isEnabled)

proc getAllComponentIds*(service: UIService): seq[string] =
  toSeq(service.components.keys)

proc getChildComponents*(service: UIService, parentId: string): seq[UIComponent] =
  let parent = service.getComponent(parentId)
  if parent.isSome:
    parent.get().children
  else:
    @[]

proc getRootComponents*(service: UIService): seq[UIComponent] =
  service.components.values.toSeq().filterIt(it.parent == nil)

# Update loop
proc update*(service: UIService) =
  # Process events
  service.processEvents()

  # Legacy notification system removed - use NotificationService instead

  # Update status message
  service.updateStatusMessage()

  # Perform layout if needed
  if service.layoutDirty:
    service.performLayout()

# Cleanup
proc cleanup*(service: UIService) =
  service.components.clear()
  service.layouts.clear()
  service.eventQueue.setLen(0)
  service.eventHandlers.clear()
  service.globalEventHandlers.clear()
  # Legacy notification system removed - use NotificationService instead
  service.activeComponent = none(UIComponent)
  service.focusedComponent = none(UIComponent)
  service.hoveredComponent = none(UIComponent)
