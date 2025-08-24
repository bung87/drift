## Terminal Integration Example
## Complete example showing how to integrate the terminal system into a Raylib application

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

  ExampleApp* = ref object
    state*: ApplicationState
    screenWidth*: int32
    screenHeight*: int32
    font*: rl.Font
    uiService*: UIService
    renderer*: Renderer
    terminalIntegration*: TerminalIntegration
    profiler*: PerformanceProfiler
    showPerformanceInfo*: bool
    lastUpdateTime*: float
    frameCount*: int
    statusBarHeight*: float32
    statusBarBounds*: rl.Rectangle
    mousePosition*: rl.Vector2
    showDragZoneHighlight*: bool

# Application initialization
proc initializeApp*(width: int32 = 1200, height: int32 = 800): ExampleApp =
  # Initialize Raylib
  rl.initWindow(width, height, "Folx Editor - Terminal Integration Example")
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
  
  # Calculate terminal bounds (can expand up to 40% of screen)
  let terminalHeight = float32(height) * 0.4
  let terminalBounds = rl.Rectangle(
    x: 0,
    y: statusBarBounds.y - terminalHeight,
    width: float32(width),
    height: terminalHeight
  )
  
  # Initialize terminal integration with drag support
  let terminalConfig = TerminalIntegrationConfig(
    defaultTerminalHeight: terminalHeight,
    minTerminalHeight: 100.0,
    maxTerminalHeight: terminalHeight,
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
    echo "Terminal visibility changed: ", visible
  )
  
  terminalIntegration.setOnSessionChanged(proc(sessionId: int) =
    if sessionId > 0:
      echo "Active session changed to: ", sessionId
    else:
      echo "No active session"
  )
  
  terminalIntegration.setOnTerminalOutput(proc(output: string) =
    echo "Terminal output received: ", output.len, " characters"
  )
  
  # Initialize terminal integration
  if not terminalIntegration.initialize():
    echo "Failed to initialize terminal integration"
    quit(1)
  
  # Create performance profiler
  let profiler = newPerformanceProfiler(1000)
  profiler.profilingEnabled = true
  
  result = ExampleApp(
    state: asStarting,
    screenWidth: width,
    screenHeight: height,
    font: font,
    uiService: uiService,
    renderer: renderer,
    terminalIntegration: terminalIntegration,
    profiler: profiler,
    showPerformanceInfo: false,
    lastUpdateTime: times.getTime().toUnixFloat(),
    frameCount: 0,
    statusBarHeight: statusBarHeight,
    statusBarBounds: statusBarBounds,
    mousePosition: rl.Vector2(x: 0, y: 0),
    showDragZoneHighlight: false
  )
  
  result.state = asRunning

# Input handling
proc handleInput(app: ExampleApp) =
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
    
    let terminalHeight = float32(app.screenHeight) * 0.4
    let newBounds = rl.Rectangle(
      x: 0,
      y: app.statusBarBounds.y - terminalHeight,
      width: float32(app.screenWidth),
      height: terminalHeight
    )
    app.terminalIntegration.resize(newBounds, app.statusBarBounds)

# Update logic
proc update(app: ExampleApp) =
  let currentTime = times.getTime().toUnixFloat()
  let deltaTime = currentTime - app.lastUpdateTime
  app.lastUpdateTime = currentTime
  
  app.profiler.startFrame()
  
  # Update terminal integration
  app.terminalIntegration.update()
  
  # Update UI service
  app.uiService.update(deltaTime)
  
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
proc renderEditor(app: ExampleApp) =
  # Render a simple editor background
  let editorBounds = rl.Rectangle(
    x: 0, y: 0,
    width: float32(app.screenWidth),
    height: app.statusBarBounds.y
  )
  
  rl.drawRectangleRec(editorBounds, rl.Color(r: 40, g: 44, b: 52, a: 255))
  
  # Draw some sample editor content
  let sampleText = &"""// Welcome to Folx Editor Terminal Integration Example with Drag Support
// Drag upward from the status bar to reveal terminal
// Press {when defined(macosx): "Cmd" else: "Ctrl"}+` to toggle terminal
// Press F1 to show performance info
// Press Escape to close terminal or exit

#include <iostream>

int main() {
    std::cout << "Hello, World!" << std::endl;
    return 0;
}"""
  
  rl.drawTextEx(app.font, sampleText.cstring, 
                rl.Vector2(x: 20, y: 20), 
                16, 1.0, rl.WHITE)

proc renderPerformanceInfo(app: ExampleApp) =
  if not app.showPerformanceInfo:
    return
  
  let perfSummary = app.profiler.getPerformanceSummary()
  let fps = app.profiler.getFPS()
  let sessionCount = app.terminalIntegration.getSessionCount()
  let activeSessionName = app.terminalIntegration.getActiveSessionName()
  
  let perfText = &"""Performance Info (F1 to toggle):
{perfSummary}

Terminal Info:
Sessions: {sessionCount}
Active: {activeSessionName}
Focus: {app.terminalIntegration.getCurrentFocus()}
Visible: {app.terminalIntegration.isVisible()}
Frame: {app.frameCount}"""
  
  # Draw background
  let textSize = rl.measureTextEx(app.font, perfText.cstring, 12, 1.0)
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
                12, 1.0, rl.YELLOW)

proc render(app: ExampleApp) =
  app.profiler.markRenderStart()
  
  rl.beginDrawing()
  rl.clearBackground(rl.Color(r: 30, g: 30, b: 30, a: 255))
  
  # Render editor
  app.renderEditor()
  
  # Render UI components (including terminal)
  app.uiService.render()
  
  # Render performance info
  app.renderPerformanceInfo()
  
  # Draw status bar with drag zone highlighting
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
  
  let statusText = if app.terminalIntegration.isVisible():
                     &"Terminal: {app.terminalIntegration.getActiveSessionName()} | " &
                     &"Sessions: {app.terminalIntegration.getSessionCount()} | " &
                     when defined(macosx): "Cmd+` to hide" else: "Ctrl+` to hide"
                   else:
                     when defined(macosx): "Drag from status bar edge or Cmd+` to show terminal | F1: Performance | Esc: Exit"
                     else: "Drag from status bar edge or Ctrl+` to show terminal | F1: Performance | Esc: Exit"
  
  rl.drawTextEx(app.font, statusText.cstring,
                rl.Vector2(x: 10, y: app.statusBarBounds.y + 8),
                12, 1.0, rl.LIGHTGRAY)
  
  rl.endDrawing()
  
  app.profiler.markRenderEnd()

# Cleanup
proc cleanup(app: ExampleApp) =
  echo "Cleaning up application..."
  
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
proc run(app: ExampleApp) =
  echo "Starting Folx Editor Terminal Integration Example with Drag Support"
  echo ""
  echo "=== Drag Interaction ==="
  echo "  Hover over the top edge of the status bar and drag upward to reveal terminal"
  echo "  The terminal panel will smoothly follow your drag movement"
  echo "  Release to snap open/closed based on position and velocity"
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
  let app = initializeApp(1200, 800)
  app.run()