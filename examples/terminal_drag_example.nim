## Terminal Drag Interaction Example
## Enhanced example showing drag-to-reveal terminal functionality with smooth animations

import std/[os, times, strutils, strformat]
import raylib as rl
import ../src/shared/types
import ../src/services/[terminal_integration, ui_service]
import ../src/infrastructure/rendering/renderer
import ../src/infrastructure/terminal/performance
import ../src/infrastructure/input/drag_interaction

type
  ApplicationState* = enum
    asStarting,
    asRunning,
    asShuttingDown

  DragExampleApp* = ref object
    state*: ApplicationState
    screenWidth*: int32
    screenHeight*: int32
    font*: rl.Font
    uiService*: UIService
    renderer*: Renderer
    terminalIntegration*: TerminalIntegration
    profiler*: PerformanceProfiler
    
    # UI elements
    statusBarHeight*: float32
    statusBarBounds*: rl.Rectangle
    editorBounds*: rl.Rectangle
    
    # Interaction state
    showPerformanceInfo*: bool
    showDragZoneHighlight*: bool
    lastUpdateTime*: float
    frameCount*: int
    mousePosition*: rl.Vector2
    
    # Demo state
    terminalMessages*: seq[string]
    lastMessageTime*: float

# Application initialization
proc initializeApp*(width: int32 = 1400, height: int32 = 900): DragExampleApp =
  # Initialize Raylib
  rl.initWindow(width, height, "Folx Editor - Terminal Drag Interaction Demo")
  rl.setTargetFPS(60)
  
  # Load font
  let font = rl.loadFontEx("resources/fonts/consola.ttf", 16, nil, 0)
  if font.texture.id == 0:
    # Fallback to default font if custom font not found
    let defaultFont = rl.getFontDefault()
    echo "Warning: Could not load custom font, using default"
  
  # Initialize services
  let renderer = newRenderer()
  let uiService = newUIService()
  
  # Calculate UI bounds
  let statusBarHeight = 30.0
  let statusBarBounds = rl.Rectangle(
    x: 0,
    y: float32(height) - statusBarHeight,
    width: float32(width),
    height: statusBarHeight
  )
  
  let editorBounds = rl.Rectangle(
    x: 0, y: 0,
    width: float32(width),
    height: float32(height) - statusBarHeight
  )
  
  # Calculate terminal bounds (can expand up to 60% of screen)
  let maxTerminalHeight = float32(height) * 0.6
  let terminalBounds = rl.Rectangle(
    x: 0,
    y: statusBarBounds.y - maxTerminalHeight,
    width: float32(width),
    height: maxTerminalHeight
  )
  
  # Initialize terminal integration with drag support
  let terminalConfig = TerminalIntegrationConfig(
    defaultTerminalHeight: maxTerminalHeight,
    minTerminalHeight: 100.0,
    maxTerminalHeight: maxTerminalHeight,
    enableKeyboardShortcuts: true,
    autoCreateFirstSession: true,
    defaultShell: getDefaultShell(),
    fontSize: 14.0
  )
  
  let terminalIntegration = newTerminalIntegration(
    uiService, renderer, font, terminalBounds, statusBarBounds, terminalConfig
  )
  
  # Set up event callbacks
  terminalIntegration.setOnVisibilityChanged(proc(visible: bool) =
    echo &"Terminal visibility changed: {visible}"
  )
  
  terminalIntegration.setOnSessionChanged(proc(sessionId: int) =
    if sessionId > 0:
      echo &"Active session changed to: {sessionId}"
    else:
      echo "No active session"
  )
  
  terminalIntegration.setOnTerminalOutput(proc(output: string) =
    echo &"Terminal output received: {output.len} characters"
  )
  
  # Initialize terminal integration
  if not terminalIntegration.initialize():
    echo "Failed to initialize terminal integration"
    quit(1)
  
  # Create performance profiler
  let profiler = newPerformanceProfiler(1000)
  profiler.profilingEnabled = true
  
  result = DragExampleApp(
    state: asStarting,
    screenWidth: width,
    screenHeight: height,
    font: font,
    uiService: uiService,
    renderer: renderer,
    terminalIntegration: terminalIntegration,
    profiler: profiler,
    
    statusBarHeight: statusBarHeight,
    statusBarBounds: statusBarBounds,
    editorBounds: editorBounds,
    
    showPerformanceInfo: false,
    showDragZoneHighlight: false,
    lastUpdateTime: times.getTime().toUnixFloat(),
    frameCount: 0,
    mousePosition: rl.Vector2(x: 0, y: 0),
    
    terminalMessages: @[],
    lastMessageTime: 0.0
  )
  
  result.state = asRunning
  
  # Add some demo messages
  result.terminalMessages = @[
    "Welcome to the Terminal Drag Demo!",
    "Drag upward from the status bar to reveal the terminal",
    "Use smooth gestures for best experience",
    &"Platform shortcuts: {when defined(macosx): \"Cmd\" else: \"Ctrl\"}+` to toggle",
    "Try different drag speeds and distances"
  ]

# Input handling
proc handleInput(app: DragExampleApp) =
  # Update mouse position
  app.mousePosition = rl.getMousePosition()
  
  # Handle mouse input for drag interaction
  if rl.isMouseButtonPressed(rl.MOUSE_BUTTON_LEFT):
    discard app.terminalIntegration.handleMouseDown(app.mousePosition)
  
  if rl.isMouseButtonDown(rl.MOUSE_BUTTON_LEFT):
    discard app.terminalIntegration.handleMouseMove(app.mousePosition)
  
  if rl.isMouseButtonReleased(rl.MOUSE_BUTTON_LEFT):
    discard app.terminalIntegration.handleMouseUp(app.mousePosition)
  
  # Check if mouse is in drag zone for highlighting
  if app.terminalIntegration.dragHandler != nil:
    app.showDragZoneHighlight = app.terminalIntegration.dragHandler.isPointInDragZone(app.mousePosition)
  
  # Handle keyboard input
  var key = rl.getKeyPressed()
  while key != 0:
    # Let terminal integration handle the key first
    if not app.terminalIntegration.handleKeyInput(key):
      # Handle application-specific keys
      case key:
      of KEY_F1:
        app.showPerformanceInfo = not app.showPerformanceInfo
      of KEY_F11:
        rl.toggleFullscreen()
      of KEY_F12:
        # Send demo command to terminal
        let commands = [
          "echo 'Hello from drag demo!'",
          "date",
          "pwd",
          when defined(windows): "dir" else: "ls -la",
          "echo 'Drag interaction working!'"
        ]
        let cmd = commands[app.frameCount mod commands.len]
        discard app.terminalIntegration.sendCommand(cmd)
      of KEY_ESCAPE:
        if app.terminalIntegration.isVisible():
          app.terminalIntegration.setVisibility(tvHidden)
        else:
          app.state = asShuttingDown
      else:
        discard
    
    key = rl.getKeyPressed()
  
  # Handle text input
  var textChar = rl.getCharPressed()
  while textChar != 0:
    discard app.terminalIntegration.handleTextInput($char(textChar))
    textChar = rl.getCharPressed()
  
  # Handle mouse wheel
  let wheelMove = rl.getMouseWheelMove()
  if wheelMove != 0:
    discard app.terminalIntegration.handleMouseWheel(wheelMove)
  
  # Handle window resize
  if rl.isWindowResized():
    app.screenWidth = rl.getScreenWidth()
    app.screenHeight = rl.getScreenHeight()
    
    # Recalculate bounds
    app.statusBarBounds = rl.Rectangle(
      x: 0,
      y: float32(app.screenHeight) - app.statusBarHeight,
      width: float32(app.screenWidth),
      height: app.statusBarHeight
    )
    
    app.editorBounds = rl.Rectangle(
      x: 0, y: 0,
      width: float32(app.screenWidth),
      height: float32(app.screenHeight) - app.statusBarHeight
    )
    
    let maxTerminalHeight = float32(app.screenHeight) * 0.6
    let newTerminalBounds = rl.Rectangle(
      x: 0,
      y: app.statusBarBounds.y - maxTerminalHeight,
      width: float32(app.screenWidth),
      height: maxTerminalHeight
    )
    
    app.terminalIntegration.resize(newTerminalBounds, app.statusBarBounds)

# Update logic
proc update(app: DragExampleApp) =
  let currentTime = times.getTime().toUnixFloat()
  let deltaTime = currentTime - app.lastUpdateTime
  app.lastUpdateTime = currentTime
  
  app.profiler.startFrame()
  
  # Update terminal integration
  app.terminalIntegration.update()
  
  # Update UI service
  app.uiService.update(deltaTime)
  
  # Send demo messages periodically
  if currentTime - app.lastMessageTime > 10.0 and app.terminalMessages.len > 0:
    let msgIndex = (app.frameCount div 600) mod app.terminalMessages.len
    discard app.terminalIntegration.sendCommand(&"echo '{app.terminalMessages[msgIndex]}'")
    app.lastMessageTime = currentTime
  
  # Update performance metrics
  if app.terminalIntegration.terminalService != nil:
    let sessions = app.terminalIntegration.getAllSessions()
    var totalLines = 0
    var totalMemory = 0
    
    for session in sessions:
      totalLines += session.buffer.getLineCount()
      totalMemory += calculateBufferMemoryUsage(session.buffer)
    
    app.profiler.updateMemoryMetrics(totalMemory, sessions.len, totalLines)
  
  app.profiler.endFrame()
  inc app.frameCount

# Rendering
proc renderEditor(app: DragExampleApp) =
  # Render editor background
  rl.drawRectangleRec(app.editorBounds, rl.Color(r: 40, g: 44, b: 52, a: 255))
  
  # Draw editor content with instructions
  let instructionText = """// Terminal Drag Interaction Demo
// 
// Instructions:
// 1. Hover over the top edge of the status bar (it will highlight)
// 2. Click and drag upward to reveal the terminal
// 3. Drag smoothly for best animation experience
// 4. Terminal follows your drag movement in real-time
// 5. Release to snap to open/closed based on position and velocity
//
// Keyboard Shortcuts:""" & 
when defined(macosx): """
// - Cmd+` : Toggle terminal
// - Cmd+Shift+T : New terminal session
// - Cmd+Shift+W : Close current session""" else: """
// - Ctrl+` : Toggle terminal  
// - Ctrl+Shift+T : New terminal session
// - Ctrl+Shift+W : Close current session""" & """
//
// Other Keys:
// - F1 : Toggle performance info
// - F11 : Toggle fullscreen
// - F12 : Send demo command
// - Esc : Close terminal or exit

#include <iostream>
#include <string>

int main() {
    std::cout << "Drag interaction demo running..." << std::endl;
    
    // The terminal panel slides smoothly based on your drag gesture
    // Try different drag speeds and distances to see the animation
    
    return 0;
}"""
  
  rl.drawTextEx(app.font, instructionText.cstring, 
                rl.Vector2(x: 20, y: 20), 
                14, 1.0, rl.WHITE)

proc renderStatusBar(app: DragExampleApp) =
  # Draw status bar background
  let statusColor = if app.showDragZoneHighlight:
                      rl.Color(r: 70, g: 70, b: 120, a: 255)  # Highlight when hovering
                    else:
                      rl.Color(r: 50, g: 50, b: 50, a: 255)   # Normal color
  
  rl.drawRectangleRec(app.statusBarBounds, statusColor)
  
  # Draw drag zone indicator if highlighting
  if app.showDragZoneHighlight:
    let dragZone = rl.Rectangle(
      x: app.statusBarBounds.x,
      y: app.statusBarBounds.y - 10.0,
      width: app.statusBarBounds.width,
      height: 20.0
    )
    rl.drawRectangleRec(dragZone, rl.Color(r: 100, g: 150, b: 200, a: 100))
    
    # Draw drag indicator
    let centerX = app.statusBarBounds.x + app.statusBarBounds.width / 2
    let centerY = app.statusBarBounds.y
    rl.drawText("↑ DRAG UP TO REVEAL TERMINAL ↑".cstring, 
                int32(centerX - 120), int32(centerY - 8), 12, rl.WHITE)
  
  # Status text
  let dragState = if app.terminalIntegration.dragHandler != nil:
                    case app.terminalIntegration.dragHandler.state:
                    of dsIdle: "Ready"
                    of dsTracking: "Tracking..."
                    of dsDragging: "Dragging"
                    of dsAnimating: "Animating"
                  else: "Unknown"
  
  let progress = if app.terminalIntegration.dragHandler != nil:
                   int(app.terminalIntegration.dragHandler.getDragProgress() * 100)
                 else: 0
  
  let statusText = if app.terminalIntegration.isVisible():
                     &"Terminal: {app.terminalIntegration.getActiveSessionName()} | " &
                     &"Sessions: {app.terminalIntegration.getSessionCount()} | " &
                     &"State: {dragState} | Progress: {progress}%"
                   else:
                     &"Hover over status bar edge and drag up | State: {dragState} | " &
                     when defined(macosx): "Cmd+` to toggle" else: "Ctrl+` to toggle"
  
  rl.drawTextEx(app.font, statusText.cstring,
                rl.Vector2(x: 10, y: app.statusBarBounds.y + 8),
                12, 1.0, rl.LIGHTGRAY)

proc renderPerformanceInfo(app: DragExampleApp) =
  if not app.showPerformanceInfo:
    return
  
  let perfSummary = app.profiler.getPerformanceSummary()
  let fps = app.profiler.getFPS()
  let sessionCount = app.terminalIntegration.getSessionCount()
  let activeSessionName = app.terminalIntegration.getActiveSessionName()
  
  let dragInfo = if app.terminalIntegration.dragHandler != nil:
                   let handler = app.terminalIntegration.dragHandler
                   &"""
Drag Info:
State: {handler.state}
Height: {handler.currentPanelHeight:.1f}/{handler.maxPanelHeight:.1f}
Progress: {int(handler.getDragProgress() * 100)}%
Velocity: {handler.velocity.y:.1f} px/s
Is Open: {handler.isOpen()}"""
                 else: "Drag handler not available"
  
  let perfText = &"""Performance Info (F1 to toggle):
{perfSummary}

Terminal Info:
Sessions: {sessionCount}
Active: {activeSessionName}
Focus: {app.terminalIntegration.getCurrentFocus()}
Visible: {app.terminalIntegration.isVisible()}
Frame: {app.frameCount}
{dragInfo}

Mouse: ({app.mousePosition.x:.0f}, {app.mousePosition.y:.0f})
In Drag Zone: {app.showDragZoneHighlight}"""
  
  # Draw background
  let textSize = rl.measureTextEx(app.font, perfText.cstring, 11, 1.0)
  let bgRect = rl.Rectangle(
    x: float32(app.screenWidth) - textSize.x - 20,
    y: 10,
    width: textSize.x + 15,
    height: textSize.y + 10
  )
  rl.drawRectangleRec(bgRect, rl.Color(r: 0, g: 0, b: 0, a: 180))
  
  # Draw text
  rl.drawTextEx(app.font, perfText.cstring,
                rl.Vector2(x: bgRect.x + 5, y: bgRect.y + 5),
                11, 1.0, rl.YELLOW)

proc render(app: DragExampleApp) =
  app.profiler.markRenderStart()
  
  rl.beginDrawing()
  rl.clearBackground(rl.Color(r: 30, g: 30, b: 30, a: 255))
  
  # Render editor
  app.renderEditor()
  
  # Render UI components (including terminal)
  app.uiService.render()
  
  # Render status bar (on top of everything)
  app.renderStatusBar()
  
  # Render performance info
  app.renderPerformanceInfo()
  
  # Debug rendering for drag system
  when defined(debug):
    if app.terminalIntegration.dragHandler != nil:
      app.terminalIntegration.dragHandler.renderDebugInfo()
  
  rl.endDrawing()
  
  app.profiler.markRenderEnd()

# Cleanup
proc cleanup(app: DragExampleApp) =
  echo "Cleaning up drag demo application..."
  
  # Cleanup terminal integration
  app.terminalIntegration.cleanup()
  
  # Cleanup UI service
  app.uiService.cleanup()
  
  # Cleanup performance profiler
  cleanupTextCache()
  
  # Unload font
  if app.font.texture.id != 0:
    rl.unloadFont(app.font)
  
  # Close Raylib
  rl.closeWindow()

# Main application loop
proc run(app: DragExampleApp) =
  echo "Starting Terminal Drag Interaction Demo"
  echo ""
  echo "=== Drag Interaction Guide ==="
  echo "1. Hover mouse over the top edge of the status bar"
  echo "2. The drag zone will highlight in blue when ready"
  echo "3. Click and drag upward to reveal terminal panel"
  echo "4. Panel height follows your drag movement smoothly"
  echo "5. Release to snap open/closed based on position and velocity"
  echo "6. Try different drag speeds for different behaviors"
  echo ""
  echo "=== Keyboard Controls ==="
  when defined(macosx):
    echo "  Cmd+` - Toggle terminal"
    echo "  Cmd+Shift+T - New terminal session"
    echo "  Cmd+Shift+W - Close terminal session"
  else:
    echo "  Ctrl+` - Toggle terminal"
    echo "  Ctrl+Shift+T - New terminal session"
    echo "  Ctrl+Shift+W - Close terminal session"
  echo "  F1 - Toggle performance info"
  echo "  F11 - Toggle fullscreen"
  echo "  F12 - Send demo command"
  echo "  Esc - Exit application"
  echo ""
  
  while not rl.windowShouldClose() and app.state == asRunning:
    app.handleInput()
    app.update()
    app.render()
    
    # Periodic cleanup
    if app.frameCount mod 1800 == 0:  # Every 30 seconds at 60 FPS
      cleanupTextCache()
  
  app.state = asShuttingDown
  app.cleanup()

# Entry point
when isMainModule:
  let app = initializeApp(1400, 900)
  app.run()