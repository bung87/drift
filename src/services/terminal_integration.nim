## Terminal Integration Manager
## Coordinates all terminal components and integrates them into the main application

import std/[options, times]
import raylib as rl
import ../shared/types
import ../components/terminal_panel
import ../services/[terminal_service, ui_service, component_manager]
import ../infrastructure/terminal/shell_process
import ../infrastructure/input/[keyboard_manager, drag_interaction]
import ../infrastructure/rendering/renderer
import results
type
  TerminalVisibility* = enum
    tvHidden,
    tvVisible,
    tvFullscreen

  TerminalIntegrationConfig* = object
    defaultTerminalHeight*: float32
    minTerminalHeight*: float32
    maxTerminalHeight*: float32
    enableKeyboardShortcuts*: bool
    autoCreateFirstSession*: bool
    defaultShell*: string
    fontSize*: float32

  TerminalIntegration* = ref object
    config*: TerminalIntegrationConfig
    terminalService*: TerminalService
    keyboardManager*: KeyboardManager
    terminalPanel*: TerminalPanel
    dragHandler*: TerminalPanelDragHandler
    visibility*: TerminalVisibility
    bounds*: rl.Rectangle
    originalBounds*: rl.Rectangle
    statusBarBounds*: rl.Rectangle
    isInitialized*: bool
    uiService*: UIService
    renderer*: Renderer
    font*: ptr rl.Font
    componentManager*: ComponentManager  # Store main ComponentManager
    isDragControlled*: bool
    lastTerminalUpdate*: float
    onVisibilityChanged*: proc(visible: bool) {.closure.}
    onSessionChanged*: proc(sessionId: int) {.closure.}
    onTerminalOutput*: proc(output: string) {.closure.}

# Forward declarations
proc createNewSession*(integration: TerminalIntegration, name: string = "", workingDir: string = ""): Option[TerminalSession]
proc closeCurrentSession*(integration: TerminalIntegration): bool
proc switchToNextSession*(integration: TerminalIntegration)
proc switchToPreviousSession*(integration: TerminalIntegration)
proc getCurrentSession*(integration: TerminalIntegration): Option[TerminalSession]
proc getAllSessions*(integration: TerminalIntegration): seq[TerminalSession]
proc clearCurrentTerminal*(integration: TerminalIntegration)
proc handleDragEvent*(integration: TerminalIntegration, event: DragEvent)
proc handlePanelHeightChanged*(integration: TerminalIntegration, height: float32, progress: float32)
proc handleTerminalEvent*(integration: TerminalIntegration, event: TerminalEvent)
proc handleShortcutEvent*(integration: TerminalIntegration, event: ShortcutEvent)

proc focusEditor*(integration: TerminalIntegration) =
  if integration.keyboardManager != nil:
    integration.keyboardManager.focusManager.setFocus(fcEditor)
  if integration.terminalPanel != nil:
    integration.terminalPanel.setFocus(false)

proc focusTerminal*(integration: TerminalIntegration) =
  if integration.keyboardManager != nil:
    integration.keyboardManager.focusManager.setFocus(fcTerminal)
  if integration.terminalPanel != nil:
    integration.terminalPanel.setFocus(true)
    # Ensure panel is visible and properly initialized
    if not integration.terminalPanel.isVisible and integration.dragHandler != nil:
      integration.dragHandler.showPanel(animated = false)

proc updateTerminalState*(integration: TerminalIntegration, visibility: TerminalVisibility, panelHeight: float32) =
  ## Centralized state management for terminal visibility changes
  ## 
  ## This function ensures all terminal state variables are updated consistently
  ## when the visibility changes. It prevents state inconsistencies that can
  ## cause hover effects to trigger incorrectly.
  ##
  ## Parameters:
  ## - visibility: The new visibility state
  ## - panelHeight: The actual panel height (0.0 for hidden, actual height for visible)
  integration.visibility = visibility
  
  # Update drag handler state consistently
  if integration.dragHandler != nil:
    integration.dragHandler.currentPanelHeight = panelHeight
    
  # Update bounds to match panel height
  if panelHeight > 0.0:
    integration.bounds.height = panelHeight
    integration.bounds.y = integration.statusBarBounds.y - panelHeight
  else:
    integration.bounds.height = 0.0
    integration.bounds.y = integration.statusBarBounds.y

proc setVisibility*(integration: TerminalIntegration, visibility: TerminalVisibility) =
  if integration.visibility == visibility:
    return
  let wasVisible = integration.visibility != tvHidden
  integration.visibility = visibility
  case visibility:
  of tvHidden:
    integration.dragHandler.hidePanel(animated = true)
    integration.updateTerminalState(tvHidden, 0.0)
    integration.keyboardManager.focusManager.setFocus(fcEditor)
  of tvVisible:
    # Start animation immediately, then create session asynchronously
    integration.dragHandler.showPanel(animated = true)
    # Use actual bounds height for consistency
    let targetHeight = integration.bounds.height
    integration.updateTerminalState(tvVisible, targetHeight)
    integration.keyboardManager.focusManager.setFocus(fcTerminal)
    # Ensure terminal panel gets focus
    if integration.terminalPanel != nil:
      integration.terminalPanel.setFocus(true)
    # Create a session if none exists (this is now non-blocking)
    if integration.terminalService != nil and integration.terminalService.getSessionCount() == 0:
      discard integration.createNewSession()
  of tvFullscreen:
    # Show fullscreen immediately, then create session asynchronously
    integration.terminalPanel.isVisible = true
    integration.terminalPanel.bounds = rl.Rectangle(
      x: 0, y: 0,
      width: float32(rl.getScreenWidth()),
      height: float32(rl.getScreenHeight())
    )
    integration.updateTerminalState(tvFullscreen, float32(rl.getScreenHeight()))
    integration.keyboardManager.focusManager.setFocus(fcTerminal)
    # Create a session if none exists (this is now non-blocking)
    if integration.terminalService != nil and integration.terminalService.getSessionCount() == 0:
      discard integration.createNewSession()
  let isVisible = visibility != tvHidden
  if wasVisible != isVisible and integration.onVisibilityChanged != nil:
    integration.onVisibilityChanged(isVisible)

# Private method to ensure components are initialized
proc ensureComponentsInitialized*(integration: TerminalIntegration): bool =
  if not integration.isInitialized:
    echo "DEBUG TerminalIntegration: Not initialized"
    return false
  
  # If components are already initialized, return true
  if integration.terminalService != nil:
    return true
  
  try:
    echo "DEBUG TerminalIntegration: Initializing components"
    
    # Initialize terminal service
    integration.terminalService = newTerminalService(
      terminal_service.defaultTerminalConfig(),
      proc(event: TerminalEvent) =
        integration.handleTerminalEvent(event)
    )
    
    # Initialize keyboard manager
    integration.keyboardManager = newKeyboardManager()
    integration.keyboardManager.onShortcut = proc(event: ShortcutEvent) =
      integration.handleShortcutEvent(event)
    
    # Initialize drag handler
    integration.dragHandler = newTerminalPanelDragHandler(
      integration.statusBarBounds,
      integration.config.defaultTerminalHeight
    )
    integration.dragHandler.onDragEvent = proc(event: DragEvent) =
      integration.handleDragEvent(event)
    integration.dragHandler.onPanelHeightChanged = proc(height: float32, progress: float32) =
      integration.handlePanelHeightChanged(height, progress)
    
    # Use the main ComponentManager instead of creating a temporary one
    if integration.componentManager == nil:
      echo "DEBUG TerminalIntegration: No main ComponentManager provided"
      return false
    
    # Initialize terminal panel using main ComponentManager
    integration.terminalPanel = newTerminalPanel(
      "main_terminal",
      integration.bounds,
      integration.componentManager,  # Use main ComponentManager
      integration.terminalService,
      integration.config.fontSize,
      onResize = proc(newHeight: float32) =
        # Update integration bounds to match new height
        var newBounds = integration.bounds
        newBounds.height = newHeight
        newBounds.y = integration.statusBarBounds.y - newHeight
        integration.bounds = newBounds
        
        # Update drag handler if it exists
        if integration.dragHandler != nil:
          integration.dragHandler.currentPanelHeight = newHeight
          
        # Trigger panel height changed callback
        integration.handlePanelHeightChanged(newHeight, newHeight / integration.config.defaultTerminalHeight)
    )
    
    # Register terminal panel with component manager for input handling
    let registerWithManagerResult = integration.terminalPanel.registerWithManager()
    if registerWithManagerResult.isErr:
      echo "DEBUG TerminalIntegration: Failed to register terminal panel with component manager: ", registerWithManagerResult.error.msg
      return false
    
    # Register terminal panel with UI service
    let registerResult = ui_service.addChildComponent(integration.uiService, "root", integration.terminalPanel.id)
    if registerResult.isErr:
      echo "DEBUG TerminalIntegration: Failed to register terminal panel with UI service: ", registerResult.error.msg
      return false
    
    echo "DEBUG TerminalIntegration: Components initialized successfully"
    return true
    
  except Exception as e:
    echo "DEBUG TerminalIntegration: Failed to initialize terminal components: ", e.msg
    return false

proc toggleVisibility*(integration: TerminalIntegration) =
  echo "DEBUG: toggleVisibility called"
  # Ensure components are initialized before toggling
  if not integration.ensureComponentsInitialized():
    echo "DEBUG: Failed to initialize components"
    return
    
  echo "DEBUG: Components initialized successfully"
  if integration.dragHandler != nil:
    echo "DEBUG: Using dragHandler.togglePanel"
    
    # Check current state before toggling
    let wasOpen = integration.dragHandler.isOpen()
    integration.dragHandler.togglePanel(animated = true)
    
    # Update visibility state based on the toggle action (opposite of current state)
    if wasOpen:
      # Was open, now closing
      integration.visibility = tvHidden
      integration.focusEditor()
    else:
      # Was closed, now opening
      integration.visibility = tvVisible
      integration.focusTerminal()
  else:
    echo "DEBUG: dragHandler is nil"
    echo "DEBUG: Using fallback visibility toggle"
    case integration.visibility:
    of tvHidden:
      integration.setVisibility(tvVisible)
    of tvVisible:
      integration.setVisibility(tvHidden)
    of tvFullscreen:
      integration.setVisibility(tvHidden)

proc initHiddenBounds(bounds: rl.Rectangle, statusBarBounds: rl.Rectangle): rl.Rectangle =
  ## Initialize bounds for hidden terminal state
  var hiddenBounds = bounds
  hiddenBounds.height = 0.0
  hiddenBounds.y = statusBarBounds.y  # Position at status bar level when hidden
  return hiddenBounds

proc isVisible*(integration: TerminalIntegration): bool =
  integration.visibility != tvHidden

proc isActuallyVisible*(integration: TerminalIntegration): bool =
  ## Check if terminal is both marked as visible AND has actual height
  ## This prevents issues where visibility state doesn't match bounds
  integration.isVisible() and integration.bounds.height > 0.0

proc getEffectiveHeight*(integration: TerminalIntegration): float32 =
  ## Get the effective height for layout calculations
  ## Returns 0.0 if terminal is not actually visible
  if integration.isActuallyVisible():
    return integration.bounds.height
  return 0.0

proc handleTerminalEvent(integration: TerminalIntegration, event: TerminalEvent) =
  case event.eventType:
  of teSessionCreated:
    if integration.onSessionChanged != nil:
      integration.onSessionChanged(event.sessionId)
  
  of teSessionClosed:
    if integration.onSessionChanged != nil:
      integration.onSessionChanged(-1)
  
  of teSessionActivated:
    if integration.onSessionChanged != nil:
      integration.onSessionChanged(event.sessionId)
    
    # Update terminal panel with new session
    let session = integration.terminalService.getSession(event.sessionId)
    if session.isSome:
      integration.terminalPanel.setSession(session.get())
  
  of teOutputReceived:
    if integration.onTerminalOutput != nil:
      integration.onTerminalOutput(event.data)
  
  of teCommandExecuted:
    # Command was executed, might want to log or handle specially
    discard
  
  of teProcessTerminated:
    # Process terminated, might want to show notification
    discard
  
  of teError:
    # Handle terminal errors
    echo "Terminal error: ", event.data

proc handleShortcutEvent(integration: TerminalIntegration, event: ShortcutEvent) =
  # Don't handle shortcuts if drag is in progress
  if integration.isDragControlled:
    return
  
  case event.action:
  of saToggleTerminal:
    integration.toggleVisibility()
  
  of saFocusTerminal:
    integration.setVisibility(tvVisible)
    integration.focusTerminal()
  
  of saFocusEditor:
    integration.focusEditor()
  
  of saNewTerminalSession:
    discard integration.createNewSession()
  
  of saCloseTerminalSession:
    discard integration.closeCurrentSession()
  
  of saSwitchToNextSession:
    integration.switchToNextSession()
  
  of saSwitchToPrevSession:
    integration.switchToPreviousSession()
  
  of saClearTerminal:
    integration.clearCurrentTerminal()
  
  of saScrollTerminalUp:
    if integration.terminalPanel != nil:
      integration.terminalPanel.scrollUp(5)
  
  of saScrollTerminalDown:
    if integration.terminalPanel != nil:
      integration.terminalPanel.scrollDown(5)
  
  of saCustom:
    # Handle custom shortcuts
    discard

# Default configuration
proc defaultTerminalConfig*(): TerminalIntegrationConfig =
  TerminalIntegrationConfig(
    defaultTerminalHeight: 300.0,
    minTerminalHeight: 100.0,
    maxTerminalHeight: 600.0,
    enableKeyboardShortcuts: true,
    autoCreateFirstSession: false,
    defaultShell: getDefaultShell(),
    fontSize: 14.0
  )

# Initialization
proc newTerminalIntegration*(
  uiService: UIService,
  renderer: Renderer,
  font: ptr rl.Font,
  bounds: rl.Rectangle,
  statusBarBounds: rl.Rectangle,
  componentManager: ComponentManager,  # Add main ComponentManager
  config: TerminalIntegrationConfig = defaultTerminalConfig()
): TerminalIntegration =
  result = TerminalIntegration(
    config: config,
    terminalService: nil,
    lastTerminalUpdate: 0.0,
    keyboardManager: nil,
    terminalPanel: nil,
    dragHandler: nil,
    visibility: tvHidden,  # Start with terminal hidden by default
    bounds: initHiddenBounds(bounds, statusBarBounds),
    originalBounds: bounds,
    statusBarBounds: statusBarBounds,
    isInitialized: false,
    uiService: uiService,
    renderer: renderer,
    font: font,
    componentManager: componentManager,  # Store main ComponentManager
    isDragControlled: false,
    onVisibilityChanged: nil,
    onSessionChanged: nil,
    onTerminalOutput: nil
  )

proc initialize*(integration: TerminalIntegration): bool =
  if integration.isInitialized:
    return true
  
  try:
    # Lazy initialization - don't create anything until actually needed
    # Just mark as initialized for now
    integration.isInitialized = true
    return true
    
  except Exception as e:
    echo "Failed to initialize terminal integration: ", e.msg
    return false

proc cleanup*(integration: TerminalIntegration) =
  if not integration.isInitialized:
    return
  
  # Stop terminal service
  if integration.terminalService != nil:
    integration.terminalService.stop()
  
  # Remove terminal panel from UI service
  if integration.terminalPanel != nil and integration.uiService != nil:
    discard integration.uiService.removeComponent(integration.terminalPanel.id)
  
  integration.isInitialized = false

# Event handling
proc handleDragEvent(integration: TerminalIntegration, event: DragEvent) =
  case event.eventType:
  of detDragStart:
    integration.isDragControlled = true
    # Disable keyboard shortcuts during drag
    integration.keyboardManager.disable()
  
  of detDragUpdate:
    # Panel height is already updated via onPanelHeightChanged callback
    discard
  
  of detDragEnd, detAnimationComplete:
    integration.isDragControlled = false
    integration.keyboardManager.enable()
    
    # Update visibility state based on final panel height
    if integration.dragHandler.isFullyOpen():
      integration.visibility = tvVisible
      integration.focusTerminal()
      # Ensure terminal session is active and ready for input
      if integration.terminalService != nil:
        let activeSession = integration.terminalService.getActiveSession()
        if activeSession.isSome and integration.terminalPanel != nil:
          integration.terminalPanel.setFocus(true)
    elif integration.dragHandler.isClosed():
      integration.visibility = tvHidden
      integration.focusEditor()
    
    if integration.onVisibilityChanged != nil:
      integration.onVisibilityChanged(integration.dragHandler.isOpen())
  
  of detDragCancel:
    integration.isDragControlled = false
    integration.keyboardManager.enable()

proc handlePanelHeightChanged(integration: TerminalIntegration, height: float32, progress: float32) =
  if integration.terminalPanel != nil:
    # Update terminal panel bounds to match drag position
    var newBounds = integration.originalBounds
    newBounds.height = height
    newBounds.y = integration.statusBarBounds.y - height
    integration.terminalPanel.resize(newBounds)
    
    # Show/hide panel based on height
    integration.terminalPanel.isVisible = height > 0.0
    
    # Update panel focus based on progress and ensure proper focus management
    if progress > 0.8:
      # Terminal is mostly open, ensure it has focus
      if not integration.terminalPanel.focused:
        integration.focusTerminal()
    elif progress < 0.2:
      # Terminal is mostly closed, return focus to editor
      if integration.terminalPanel.focused:
        integration.focusEditor()
    elif progress <= 0.1 and integration.terminalPanel.focused:
      integration.terminalPanel.setFocus(false)
    
    # Update integration bounds to match new height
    integration.bounds.height = height
    integration.bounds.y = integration.statusBarBounds.y - height

# Focus management
proc getCurrentFocus*(integration: TerminalIntegration): FocusableComponent =
  if integration.keyboardManager != nil:
    integration.keyboardManager.focusManager.getCurrentFocus()
  else:
    fcNone

# Session management
proc createNewSession*(integration: TerminalIntegration, name: string = "", workingDir: string = ""): Option[TerminalSession] =
  if integration.terminalService == nil:
    return none(TerminalSession)
  
  # Mark drag handler as starting terminal for smoother animation
  if integration.dragHandler != nil:
    integration.dragHandler.setTerminalStarting(true)
  
  try:
    let session = integration.terminalService.createSession(name, workingDir)
    
    # Start terminal service if this is the first session
    if integration.terminalService.getSessionCount() == 1:
      integration.terminalService.start()
      if not integration.isVisible():
        integration.setVisibility(tvVisible)
    
    # Set up callback to handle when terminal process is ready
    proc onTerminalReady() =
      if integration.dragHandler != nil:
        integration.dragHandler.setTerminalStarting(false)
      echo "Terminal session ready: ", session.name
    
    # The session is created immediately (non-blocking)
    # The actual shell process starts asynchronously
    return some(session)
    
  except Exception as e:
    echo "Failed to create terminal session: ", e.msg
    # Reset terminal starting state on error
    if integration.dragHandler != nil:
      integration.dragHandler.setTerminalStarting(false)
    return none(TerminalSession)

proc closeCurrentSession*(integration: TerminalIntegration): bool =
  if integration.terminalService == nil:
    return false
  let activeSession = integration.terminalService.getActiveSession()
  if activeSession.isSome:
    let closeResult = integration.terminalService.closeSession(activeSession.get().id)
    if integration.terminalService.getSessionCount() == 0:
      integration.setVisibility(tvHidden)
    return closeResult
  return false

proc switchToNextSession*(integration: TerminalIntegration) =
  if integration.terminalService == nil:
    return
  let sessions = integration.terminalService.getAllSessions()
  if sessions.len <= 1:
    return
  let currentId = integration.terminalService.activeSessionId
  var nextIndex = 0
  for i, session in sessions:
    if session.id == currentId:
      nextIndex = (i + 1) mod sessions.len
      break
  discard integration.terminalService.setActiveSession(sessions[nextIndex].id)

proc switchToPreviousSession*(integration: TerminalIntegration) =
  if integration.terminalService == nil:
    return
  let sessions = integration.terminalService.getAllSessions()
  if sessions.len <= 1:
    return
  let currentId = integration.terminalService.activeSessionId
  var prevIndex = sessions.len - 1
  for i, session in sessions:
    if session.id == currentId:
      prevIndex = if i == 0: sessions.len - 1 else: i - 1
      break
  discard integration.terminalService.setActiveSession(sessions[prevIndex].id)

proc getCurrentSession*(integration: TerminalIntegration): Option[TerminalSession] =
  if integration.terminalService != nil:
    integration.terminalService.getActiveSession()
  else:
    none(TerminalSession)

proc getAllSessions*(integration: TerminalIntegration): seq[TerminalSession] =
  if integration.terminalService != nil:
    integration.terminalService.getAllSessions()
  else:
    @[]

# Terminal operations
proc sendCommand*(integration: TerminalIntegration, command: string): bool =
  if integration.terminalService != nil:
    integration.terminalService.sendCommand(command)
  else:
    false

proc sendInput*(integration: TerminalIntegration, input: string): bool =
  if integration.terminalService != nil:
    integration.terminalService.sendInput(input)
  else:
    false

proc clearCurrentTerminal*(integration: TerminalIntegration) =
  let session = integration.getCurrentSession()
  if session.isSome:
    discard integration.terminalService.clearSessionBuffer(session.get().id)
    
    if integration.terminalPanel != nil:
      integration.terminalPanel.clear()

# Input handling
proc handleKeyInput*(integration: TerminalIntegration, key: int32): bool =
  if not integration.isInitialized or integration.keyboardManager == nil:
    return false
  
  # Let keyboard manager handle shortcuts first
  if integration.keyboardManager != nil and integration.keyboardManager.processKeyInput(key):
    return true
  
  # If terminal is focused, let it handle the input
  if integration.getCurrentFocus() == fcTerminal and integration.terminalPanel != nil:
    return integration.terminalPanel.handleKeyInput(key)
  
  return false

proc handleTextInput*(integration: TerminalIntegration, text: string): bool =
  if not integration.isInitialized:
    return false
  
  # If terminal is focused, let it handle the input
  if integration.getCurrentFocus() == fcTerminal and integration.terminalPanel != nil:
    return integration.terminalPanel.handleTextInput(text)
  
  return false

proc handleMouseDown*(integration: TerminalIntegration, mousePos: rl.Vector2): bool =
  if not integration.isInitialized:
    return false
  
  # Ensure components are initialized when user starts interacting with drag
  discard integration.ensureComponentsInitialized()
  
  # Check terminal panel header drag first
  if integration.terminalPanel != nil:
    if integration.terminalPanel.handleHeaderMouseDown(mousePos):
      return true
  
  # Let drag handler try to handle the mouse down first
  if integration.dragHandler != nil and integration.dragHandler.handleMouseDown(mousePos):
    return true
  
  return false

proc handleMouseMove*(integration: TerminalIntegration, mousePos: rl.Vector2): bool =
  if not integration.isInitialized:
    return false
  
  # Ensure components are initialized when user moves mouse (in case drag started before initialization)
  discard integration.ensureComponentsInitialized()
  
  # Check terminal panel header drag first
  if integration.terminalPanel != nil and integration.terminalPanel.handleHeaderMouseMove(mousePos):
    return true
  
  # Let drag handler handle mouse movement
  if integration.dragHandler != nil:
    return integration.dragHandler.handleMouseMove(mousePos)
  
  return false

proc handleMouseUp*(integration: TerminalIntegration, mousePos: rl.Vector2): bool =
  if not integration.isInitialized:
    return false
  
  # Check terminal panel header drag first
  if integration.terminalPanel != nil and integration.terminalPanel.handleHeaderMouseUp(mousePos):
    return true
  
  # Let drag handler handle mouse up
  if integration.dragHandler != nil:
    return integration.dragHandler.handleMouseUp(mousePos)
  
  return false

proc handleMouseWheel*(integration: TerminalIntegration, wheelMove: float32): bool =
  if not integration.isInitialized or not integration.isVisible():
    return false
  
  if integration.terminalPanel != nil:
    return integration.terminalPanel.handleMouseWheel(wheelMove)
  
  return false

# Update and rendering
proc update*(integration: TerminalIntegration) =
  if not integration.isInitialized:
    return
  
  # Lightweight update with throttling to maintain smooth animations
  let currentTime = times.getTime().toUnixFloat()
  
  # Throttle terminal service updates to prevent blocking (every 50ms = ~20fps)
  if integration.terminalService != nil and integration.terminalService.running:
    if currentTime - integration.lastTerminalUpdate > 0.05:
      # Update terminal service directly with error protection
      try:
        integration.terminalService.update()
      except:
        discard  # Ignore errors to maintain animation smoothness
      integration.lastTerminalUpdate = currentTime
  
  # Update keyboard manager only if it exists (lightweight operation)
  if integration.keyboardManager != nil:
    integration.keyboardManager.update()
  
  # Update drag handler only if it exists
  if integration.dragHandler != nil:
    integration.dragHandler.update()
  
  # Update terminal panel only if it exists
  if integration.terminalPanel != nil:
    integration.terminalPanel.update()

proc resize*(integration: TerminalIntegration, newBounds: rl.Rectangle, newStatusBarBounds: rl.Rectangle) =
  integration.bounds = newBounds
  integration.originalBounds = newBounds
  integration.statusBarBounds = newStatusBarBounds
  
  # Update drag handler bounds
  if integration.dragHandler != nil:
    integration.dragHandler.setStatusBarBounds(newStatusBarBounds)
    integration.dragHandler.setMaxPanelHeight(newBounds.height)
  
  # Terminal panel will be resized automatically by drag handler

# Configuration
proc updateConfig*(integration: TerminalIntegration, newConfig: TerminalIntegrationConfig) =
  integration.config = newConfig
  
  if integration.terminalService != nil:
    var serviceConfig = integration.terminalService.getConfig()
    serviceConfig.defaultShell = newConfig.defaultShell
    integration.terminalService.updateConfig(serviceConfig)

proc getConfig*(integration: TerminalIntegration): TerminalIntegrationConfig =
  integration.config

# Status and information
proc getSessionCount*(integration: TerminalIntegration): int =
  if integration.terminalService != nil:
    integration.terminalService.getSessionCount()
  else:
    0

proc getActiveSessionName*(integration: TerminalIntegration): string =
  let session = integration.getCurrentSession()
  if session.isSome:
    session.get().name
  else:
    ""

proc isTerminalFocused*(integration: TerminalIntegration): bool =
  integration.getCurrentFocus() == fcTerminal

proc getTerminalOutput*(integration: TerminalIntegration, sessionId: int = -1): seq[TerminalLine] =
  if integration.terminalService != nil:
    let targetId = if sessionId == -1: integration.terminalService.activeSessionId else: sessionId
    integration.terminalService.getSessionOutput(targetId)
  else:
    @[]

# Event callbacks
proc setOnVisibilityChanged*(integration: TerminalIntegration, callback: proc(visible: bool) {.closure.}) =
  integration.onVisibilityChanged = callback

proc setOnSessionChanged*(integration: TerminalIntegration, callback: proc(sessionId: int) {.closure.}) =
  integration.onSessionChanged = callback

proc setOnTerminalOutput*(integration: TerminalIntegration, callback: proc(output: string) {.closure.}) =
  integration.onTerminalOutput = callback