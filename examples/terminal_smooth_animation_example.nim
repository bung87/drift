## Enhanced Terminal Animation Example
## Demonstrates smooth animations and non-blocking terminal startup

import std/[times, os]
import raylib as rl
import ../src/shared/types
import ../src/services/[terminal_service, terminal_integration, ui_service]
import ../src/components/terminal_panel
import ../src/infrastructure/terminal/[shell_process, terminal_buffer]
import ../src/infrastructure/input/drag_interaction
import ../src/infrastructure/rendering/renderer

type
  ExampleState = object
    terminalIntegration: TerminalIntegration
    renderer: Renderer
    font: rl.Font
    running: bool
    showInstructions: bool
    lastFrameTime: float
    frameCount: int
    fps: float

proc initExample(): ExampleState =
  # Initialize Raylib
  rl.initWindow(1200, 800, "Terminal Smooth Animation Demo")
  rl.setTargetFPS(60)
  
  # Load font
  let font = rl.getFontDefault()
  
  # Create renderer
  let renderer = newRenderer()
  
  # Create terminal integration with smooth animation config
  let config = TerminalIntegrationConfig(
    defaultTerminalHeight: 300.0,
    minTerminalHeight: 50.0,
    maxTerminalHeight: 600.0,
    enableKeyboardShortcuts: true,
    autoCreateFirstSession: false,  # We'll create it manually to show async behavior
    defaultShell: getDefaultShell(),
    fontSize: 14.0
  )
  
  let terminalIntegration = newTerminalIntegration(
    config,
    onVisibilityChanged = proc(visible: bool) =
      echo "Terminal visibility changed: ", visible,
    onSessionChanged = proc(sessionId: int) =
      echo "Active session changed to: ", sessionId,
    onTerminalOutput = proc(sessionId: int, output: string) =
      echo "Output from session ", sessionId, ": ", output[0..min(50, output.len-1)], "..."
  )
  
  # Initialize the integration
  terminalIntegration.initialize()
  
  result = ExampleState(
    terminalIntegration: terminalIntegration,
    renderer: renderer,
    font: font,
    running: true,
    showInstructions: true,
    lastFrameTime: times.getTime().toUnixFloat(),
    frameCount: 0,
    fps: 0.0
  )

proc updateFPS(state: var ExampleState) =
  let currentTime = times.getTime().toUnixFloat()
  state.frameCount += 1
  
  if currentTime - state.lastFrameTime >= 1.0:
    state.fps = float(state.frameCount) / (currentTime - state.lastFrameTime)
    state.frameCount = 0
    state.lastFrameTime = currentTime

proc drawInstructions(state: ExampleState) =
  if not state.showInstructions:
    return
  
  let instructions = [
    "Terminal Smooth Animation Demo",
    "",
    "Controls:",
    "  T/CTRL+` - Toggle terminal (smooth animation)",
    "  D - Drag terminal header to resize",
    "  C - Create new terminal session (async)",
    "  ENTER - Send test command",
    "  ESC - Close current session",
    "  H - Toggle this help",
    "  Q - Quit",
    "",
    "Features Demonstrated:",
    "- Smooth slide-in/out animations",
    "- Non-blocking async terminal startup",
    "- Visual feedback during startup",
    "- Responsive drag interactions",
    "- Proper error handling",
    "",
    "Notice how the terminal animates smoothly",
    "even when creating new sessions!"
  ]
  
  let padding = 20.0
  let lineHeight = 20.0
  let bgWidth = 400.0
  let bgHeight = float32(instructions.len) * lineHeight + padding * 2
  
  # Draw semi-transparent background
  state.renderer.drawRectangle(
    rl.Rectangle(x: padding, y: padding, width: bgWidth, height: bgHeight),
    rl.Color(r: 0, g: 0, b: 0, a: 180)
  )
  
  # Draw border
  state.renderer.drawRectangleOutline(
    rl.Rectangle(x: padding, y: padding, width: bgWidth, height: bgHeight),
    rl.Color(r: 100, g: 150, b: 200, a: 255)
  )
  
  # Draw instructions
  for i, instruction in instructions:
    let y = padding + 10 + float32(i) * lineHeight
    let color = if instruction.len == 0:
      rl.BLANK
    elif instruction.startsWith("Terminal") or instruction.startsWith("Controls") or instruction.startsWith("Features"):
      rl.Color(r: 255, g: 255, b: 100, a: 255)  # Yellow for headers
    elif instruction.startsWith("  "):
      rl.Color(r: 150, g: 255, b: 150, a: 255)  # Light green for controls
    else:
      rl.Color(r: 200, g: 200, b: 200, a: 255)  # Light gray for descriptions
    
    if color != rl.BLANK:
      state.renderer.drawText(
        addr state.font, instruction,
        rl.Vector2(x: padding + 10, y: y),
        14.0, 1.0, color
      )

proc drawStatusBar(state: ExampleState) =
  let statusY = float32(rl.getScreenHeight()) - 60.0
  let statusHeight = 60.0
  
  # Background
  state.renderer.drawRectangle(
    rl.Rectangle(x: 0, y: statusY, width: float32(rl.getScreenWidth()), height: statusHeight),
    rl.Color(r: 40, g: 40, b: 40, a: 255)
  )
  
  # Status information
  let sessionCount = if state.terminalIntegration.terminalService != nil:
    state.terminalIntegration.terminalService.getSessionCount()
  else:
    0
  
  let isVisible = state.terminalIntegration.isVisible()
  let activeSessionName = state.terminalIntegration.getActiveSessionName()
  
  let statusText = [
    "FPS: " & $int(state.fps),
    "Sessions: " & $sessionCount,
    "Terminal: " & (if isVisible: "Visible" else: "Hidden"),
    "Active: " & activeSessionName
  ]
  
  # Draw status items
  var x = 20.0
  for text in statusText:
    state.renderer.drawText(
      addr state.font, text,
      rl.Vector2(x: x, y: statusY + 10),
      12.0, 1.0, rl.Color(r: 180, g: 180, b: 180, a: 255)
    )
    x += 150.0
  
  # Draw terminal state indicator
  let indicatorX = float32(rl.getScreenWidth()) - 150.0
  let indicatorY = statusY + 20.0
  let indicatorSize = 20.0
  
  let indicatorColor = if not isVisible:
    rl.Color(r: 100, g: 100, b: 100, a: 255)  # Gray when hidden
  elif sessionCount == 0:
    rl.Color(r: 255, g: 200, b: 100, a: 255)  # Orange when no sessions
  else:
    rl.Color(r: 100, g: 255, b: 100, a: 255)  # Green when active
  
  state.renderer.drawRectangle(
    rl.Rectangle(x: indicatorX, y: indicatorY, width: indicatorSize, height: indicatorSize),
    indicatorColor
  )
  
  state.renderer.drawText(
    addr state.font, "Terminal",
    rl.Vector2(x: indicatorX + 30, y: indicatorY + 2),
    12.0, 1.0, rl.WHITE
  )

proc handleInput(state: var ExampleState) =
  # Handle window close
  if rl.windowShouldClose():
    state.running = false
    return
  
  # Handle keyboard shortcuts
  if rl.isKeyPressed(rl.KeyboardKey.Q):
    state.running = false
  elif rl.isKeyPressed(rl.KeyboardKey.H):
    state.showInstructions = not state.showInstructions
  elif rl.isKeyPressed(rl.KeyboardKey.T) or 
       (rl.isKeyDown(rl.KeyboardKey.LeftControl) and rl.isKeyPressed(rl.KeyboardKey.Grave)):
    # Toggle terminal with smooth animation
    echo "Toggling terminal..."
    state.terminalIntegration.toggleVisibility()
  elif rl.isKeyPressed(rl.KeyboardKey.C):
    # Create new session (async - won't block UI)
    echo "Creating new terminal session asynchronously..."
    let session = state.terminalIntegration.createNewSession("Demo Session")
    if session.isSome:
      echo "Session creation initiated: ", session.get().name
    else:
      echo "Failed to initiate session creation"
  elif rl.isKeyPressed(rl.KeyboardKey.Enter):
    # Send test command to active terminal
    if state.terminalIntegration.isVisible():
      echo "Sending test command..."
      discard state.terminalIntegration.sendCommand("echo 'Hello from smooth terminal!' && date")
  elif rl.isKeyPressed(rl.KeyboardKey.Escape):
    # Close current session
    if state.terminalIntegration.closeCurrentSession():
      echo "Closed current terminal session"
  
  # Handle mouse input for drag interactions
  let mousePos = rl.getMousePosition()
  
  if rl.isMouseButtonPressed(rl.MouseButton.Left):
    discard state.terminalIntegration.handleMouseDown(mousePos)
  
  if rl.isMouseButtonDown(rl.MouseButton.Left):
    discard state.terminalIntegration.handleMouseMove(mousePos)
  
  if rl.isMouseButtonReleased(rl.MouseButton.Left):
    discard state.terminalIntegration.handleMouseUp(mousePos)
  
  # Handle mouse wheel for scrolling
  let wheelMove = rl.getMouseWheelMove()
  if wheelMove != 0:
    discard state.terminalIntegration.handleMouseWheel(wheelMove)
  
  # Handle text input
  var charPressed = rl.getCharPressed()
  while charPressed > 0:
    if state.terminalIntegration.isVisible():
      discard state.terminalIntegration.handleTextInput($char(charPressed))
    charPressed = rl.getCharPressed()
  
  # Handle key input for terminal
  var key = rl.getKeyPressed()
  while key != rl.KeyboardKey.Null:
    if state.terminalIntegration.isVisible():
      discard state.terminalIntegration.handleKeyInput(key.int32)
    key = rl.getKeyPressed()

proc update(state: var ExampleState) =
  # Update FPS counter
  state.updateFPS()
  
  # Update terminal integration (handles animations, I/O, etc.)
  state.terminalIntegration.update()
  
  # Handle window resize
  if rl.isWindowResized():
    let newWidth = rl.getScreenWidth()
    let newHeight = rl.getScreenHeight()
    state.terminalIntegration.resize(rl.Rectangle(
      x: 0, y: 0, 
      width: float32(newWidth), 
      height: float32(newHeight)
    ))

proc render(state: ExampleState) =
  rl.beginDrawing()
  defer: rl.endDrawing()
  
  # Clear background
  rl.clearBackground(rl.Color(r: 30, g: 30, b: 35, a: 255))
  
  # Draw main content area background
  state.renderer.drawRectangle(
    rl.Rectangle(x: 0, y: 0, width: float32(rl.getScreenWidth()), height: float32(rl.getScreenHeight() - 60)),
    rl.Color(r: 25, g: 25, b: 30, a: 255)
  )
  
  # Draw example title when terminal is hidden
  if not state.terminalIntegration.isVisible():
    let title = "Smooth Terminal Animation Demo"
    let titleWidth = rl.measureText(title, 32)
    let centerX = (rl.getScreenWidth() - titleWidth) div 2
    let centerY = (rl.getScreenHeight() - 60) div 2 - 100
    
    state.renderer.drawText(
      addr state.font, title,
      rl.Vector2(x: float32(centerX), y: float32(centerY)),
      32.0, 1.0, rl.Color(r: 200, g: 200, b: 255, a: 255)
    )
    
    let subtitle = "Press 'T' or 'Ctrl+`' to toggle terminal with smooth animation"
    let subtitleWidth = rl.measureText(subtitle, 16)
    let subtitleX = (rl.getScreenWidth() - subtitleWidth) div 2
    
    state.renderer.drawText(
      addr state.font, subtitle,
      rl.Vector2(x: float32(subtitleX), y: float32(centerY + 50)),
      16.0, 1.0, rl.Color(r: 150, g: 150, b: 150, a: 255)
    )
  
  # Draw instructions overlay
  state.drawInstructions()
  
  # Draw status bar
  state.drawStatusBar()

proc cleanup(state: ExampleState) =
  # Clean up terminal integration
  state.terminalIntegration.cleanup()
  
  # Close Raylib
  rl.closeWindow()

proc main() =
  echo "Starting Terminal Smooth Animation Demo..."
  echo "This demo shows:"
  echo "- Smooth terminal animations"
  echo "- Non-blocking async process startup"
  echo "- Visual feedback during startup"
  echo "- Responsive drag interactions"
  echo ""
  
  var state = initExample()
  defer: state.cleanup()
  
  # Create an initial session to demonstrate async startup
  echo "Creating initial terminal session (async)..."
  discard state.terminalIntegration.createNewSession("Initial Session")
  
  # Main loop
  while state.running and not rl.windowShouldClose():
    state.handleInput()
    state.update()
    state.render()
    
    # Small delay to prevent 100% CPU usage
    rl.waitTime(0.001)
  
  echo "Demo finished!"

when isMainModule:
  main()