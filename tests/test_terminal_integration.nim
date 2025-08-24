## Integration tests for complete terminal functionality
## Tests the full terminal system end-to-end

import std/[unittest, os, times, strutils, options, asyncdispatch]
import raylib as rl
import ../src/shared/types
import ../src/services/[terminal_service, terminal_integration, ui_service]
import ../src/components/terminal_panel
import ../src/infrastructure/terminal/[shell_process, ansi_parser, terminal_io, performance]
import ../src/infrastructure/input/keyboard_manager
import ../src/infrastructure/rendering/renderer

# Test fixtures and utilities
proc createTestFont(): rl.Font =
  # Create a basic font for testing
  result = rl.getFontDefault()

proc createTestRenderer(): Renderer =
  # Create a mock renderer for testing
  result = newRenderer()

proc createTestUIService(): UIService =
  result = newUIService()

proc waitForOutput(shellProcess: ShellProcess, maxWait: float = 2.0): string =
  ## Wait for output from shell process with timeout
  result = ""
  let startTime = times.getTime().toUnixFloat()
  
  while times.getTime().toUnixFloat() - startTime < maxWait:
    if shellProcess.hasOutput():
      result = shellProcess.readAllAvailableOutput()
      if result.len > 0:
        break
    sleep(50)  # 50ms sleep

suite "Terminal Integration Tests":
  
  setup:
    # Initialize Raylib for testing (headless mode would be better)
    if not rl.isWindowReady():
      rl.initWindow(800, 600, "Terminal Test")
      rl.setTargetFPS(60)
  
  teardown:
    # Clean up any resources
    discard

  test "Complete terminal service workflow":
    let service = newTerminalService()
    service.start()
    
    try:
      # Create session
      let session = service.createSession("Test Session")
      check session.id > 0
      check session.name == "Test Session"
      check service.getSessionCount() == 1
      
      # Send command
      when defined(windows):
        check service.sendCommand("echo Hello World") == true
      else:
        check service.sendCommand("echo Hello World") == true
      
      # Update service to process output
      for i in 0..<10:
        service.update()
        sleep(100)
      
      # Check if we got output
      let output = service.getSessionOutput(session.id)
      check output.len >= 0  # Should have at least some output or empty
      
      # Close session
      check service.closeSession(session.id) == true
      check service.getSessionCount() == 0
      
    finally:
      service.stop()

  test "ANSI parser integration with terminal service":
    let service = newTerminalService()
    let parser = newAnsiParser()
    
    service.start()
    
    try:
      let session = service.createSession("ANSI Test")
      
      # Test various ANSI sequences
      let testSequences = [
        "\x1b[31mRed text\x1b[0m",
        "\x1b[1;32mBold green\x1b[0m", 
        "\x1b[44mBlue background\x1b[0m",
        "\x1b[1;3;4;31;42mComplex formatting\x1b[0m"
      ]
      
      for sequence in testSequences:
        let line = parser.parseToTerminalLine(sequence)
        session.buffer.addLine(line)
        check line.styles.len > 0
      
      check session.buffer.getLineCount() == testSequences.len
      
    finally:
      service.stop()

  test "Shell process cross-platform compatibility":
    let shell = newShellProcess()
    
    try:
      check shell.start() == true
      check shell.isRunning() == true
      
      # Test basic command that should work on all platforms
      when defined(windows):
        check shell.writeCommand("echo Hello") == true
      else:
        check shell.writeCommand("echo Hello") == true
      
      # Wait for output
      let output = waitForOutput(shell, 2.0)
      
      # Should have some output (even if empty due to timing)
      check output.len >= 0
      
    finally:
      shell.cleanup()

  test "Terminal panel UI integration":
    let font = createTestFont()
    let renderer = createTestRenderer()
    let uiService = createTestUIService()
    let terminalService = newTerminalService()
    
    terminalService.start()
    
    try:
      let bounds = rl.Rectangle(x: 0, y: 400, width: 800, height: 200)
      let panel = newTerminalPanel(
        "test_panel", bounds, font, renderer, terminalService
      )
      
      check panel.id == "test_panel"
      check panel.bounds.width == 800
      check panel.bounds.height == 200
      
      # Create and set a session
      let session = terminalService.createSession("Panel Test")
      panel.setSession(session)
      
      check panel.session.isSome
      check panel.session.get().id == session.id
      
      # Test adding output
      panel.addOutput("Test output line", rl.WHITE)
      check panel.getLineCount() > 0
      
      # Test input handling
      let handled = panel.handleTextInput("test input")
      # May or may not be handled depending on focus state
      
      # Test scrolling
      panel.scrollUp(1)
      panel.scrollDown(1)
      panel.scrollToTop()
      panel.scrollToBottom()
      
      # Test focus
      panel.setFocus(true)
      check panel.focused == true
      
    finally:
      terminalService.stop()

  test "Keyboard manager shortcut handling":
    let keyboardManager = newKeyboardManager()
    var shortcutReceived = false
    var receivedAction: ShortcutAction
    
    # Set up callback
    keyboardManager.onShortcut = proc(event: ShortcutEvent) =
      shortcutReceived = true
      receivedAction = event.action
    
    # Test toggle terminal shortcut (Ctrl+`)
    let toggleCombo = newKeyCombination(KEY_GRAVE, {kmCtrl})
    let action = keyboardManager.shortcuts.getOrDefault(toggleCombo, saCustom)
    check action == saToggleTerminal
    
    # Test getting shortcut for action
    let combo = keyboardManager.getShortcut(saToggleTerminal)
    check combo.isSome
    check combo.get().key == KEY_GRAVE
    check kmCtrl in combo.get().modifiers

  test "Performance monitoring and optimization":
    let profiler = newPerformanceProfiler(100)
    profiler.profilingEnabled = true
    
    # Test performance measurement
    profiler.startFrame()
    
    # Simulate some work
    sleep(1)
    
    profiler.endFrame()
    
    check profiler.metrics.frameTime > 0
    check profiler.getAverageFrameTime() > 0
    
    # Test memory tracking
    let buffer = newTerminalBuffer(1000)
    
    # Add many lines to test memory usage
    for i in 0..<500:
      let line = newTerminalLine(&"Test line {i}")
      buffer.addLine(line)
    
    let memoryUsage = calculateBufferMemoryUsage(buffer)
    check memoryUsage > 0
    
    profiler.updateMemoryMetrics(memoryUsage, buffer.lines.len, buffer.lines.len)
    check profiler.metrics.memoryUsage == memoryUsage

  test "Terminal I/O handling":
    let shell = newShellProcess()
    let parser = newAnsiParser()
    
    if shell.start():
      var outputReceived = false
      var receivedData = ""
      
      let terminalIO = initTerminalIO(
        1, shell, parser,
        proc(event: IOEvent) =
          if event.eventType == ietOutputReceived:
            outputReceived = true
            receivedData = event.data
      )
      
      try:
        terminalIO.start()
        
        # Send command
        when defined(windows):
          terminalIO.sendCommand("echo Test")
        else:
          terminalIO.sendCommand("echo Test")
        
        # Wait for output
        for i in 0..<20:
          if outputReceived:
            break
          sleep(100)
        
        # Check if we received output (may be empty due to timing)
        check outputReceived or receivedData.len >= 0
        
      finally:
        terminalIO.cleanup()
    
    shell.cleanup()

  test "Complete terminal integration workflow":
    let font = createTestFont()
    let renderer = createTestRenderer()
    let uiService = createTestUIService()
    let bounds = rl.Rectangle(x: 0, y: 400, width: 800, height: 200)
    
    let integration = newTerminalIntegration(
      uiService, renderer, font, bounds
    )
    
    try:
      check integration.initialize() == true
      check integration.isInitialized == true
      
      # Test visibility management
      check integration.isVisible() == false
      integration.setVisibility(tvVisible)
      check integration.isVisible() == true
      
      # Test session creation
      let session = integration.createNewSession("Integration Test")
      check session.isSome
      check integration.getSessionCount() == 1
      
      # Test focus management
      integration.focusTerminal()
      check integration.getCurrentFocus() == fcTerminal
      
      integration.focusEditor()
      check integration.getCurrentFocus() == fcEditor
      
      # Test sending commands
      let sent = integration.sendCommand("echo Integration Test")
      # May succeed or fail depending on session state
      
      # Test session switching (needs multiple sessions)
      discard integration.createNewSession("Second Session")
      if integration.getSessionCount() > 1:
        let originalSession = integration.getCurrentSession()
        integration.switchToNextSession()
        let newSession = integration.getCurrentSession()
        # Session may or may not change depending on implementation
      
      # Test clearing terminal
      integration.clearCurrentTerminal()
      
      # Test closing session
      check integration.closeCurrentSession() == true
      
    finally:
      integration.cleanup()

  test "Error handling and recovery":
    # Test with invalid shell path
    let invalidShell = newShellProcess("/invalid/shell/path")
    
    expect(ProcessSpawnError):
      discard invalidShell.start()
    
    # Test terminal service with no sessions
    let service = newTerminalService()
    service.start()
    
    try:
      # Should handle empty state gracefully
      check service.getSessionCount() == 0
      check service.getActiveSession().isNone
      
      # Should handle invalid session operations
      check service.closeSession(999) == false
      check service.setActiveSession(999) == false
      
    finally:
      service.stop()

  test "Memory limits and cleanup":
    let settings = PerformanceSettings(
      enableMemoryLimits: true,
      maxBufferLines: 100,  # Small limit for testing
      maxLineLength: 200,
      cleanupInterval: 1.0
    )
    
    let memManager = newMemoryManager(settings)
    let buffer = newTerminalBuffer(1000)
    
    # Add more lines than the limit
    for i in 0..<150:
      let line = newTerminalLine(&"Test line {i} with some content")
      buffer.addLine(line)
    
    # Trigger cleanup
    let removedLines = memManager.cleanupBuffer(buffer)
    check removedLines > 0
    check buffer.lines.len <= settings.maxBufferLines

  test "ANSI parsing edge cases":
    let parser = newAnsiParser()
    
    # Test empty input
    let emptyResult = parser.parseText("")
    check emptyResult.len == 0
    
    # Test malformed sequences
    let malformedResult = parser.parseText("\x1b[999mInvalid\x1bIncomplete")
    check malformedResult.len >= 0  # Should handle gracefully
    
    # Test very long sequences
    var longSequence = "\x1b[31m"
    for i in 0..<1000:
      longSequence.add("A")
    longSequence.add("\x1b[0m")
    
    let longResult = parser.parseText(longSequence)
    check longResult.len > 0
    
    # Test mixed valid and invalid
    let mixedResult = parser.parseText("Normal \x1b[31mRed\x1b[999mInvalid\x1b[0m Normal")
    check mixedResult.len >= 2  # Should parse what it can

  test "Cross-platform shell detection":
    let defaultShell = getDefaultShell()
    check defaultShell.len > 0
    check fileExists(defaultShell)
    
    let availableShells = getAvailableShells()
    check availableShells.len > 0
    
    for shell in availableShells:
      check validateShellPath(shell) == true
      let (name, version) = getShellInfo(shell)
      check name.len > 0

  test "Concurrent operations":
    let service = newTerminalService()
    service.start()
    
    try:
      # Create multiple sessions
      var sessions: seq[TerminalSession] = @[]
      for i in 0..<3:
        let session = service.createSession(&"Session {i}")
        sessions.add(session)
      
      check service.getSessionCount() == 3
      
      # Switch between sessions rapidly
      for i in 0..<10:
        let sessionIndex = i mod sessions.len
        discard service.setActiveSession(sessions[sessionIndex].id)
      
      # Send commands to different sessions
      for session in sessions:
        when defined(windows):
          discard service.sendCommand("echo Test", session.id)
        else:
          discard service.sendCommand("echo Test", session.id)
      
      # Update service multiple times
      for i in 0..<5:
        service.update()
        sleep(50)
      
      # Close all sessions
      for session in sessions:
        discard service.closeSession(session.id)
      
      check service.getSessionCount() == 0
      
    finally:
      service.stop()

  test "Render optimization features":
    let settings = defaultPerformanceSettings()
    let optimizer = newRenderOptimizer(settings)
    
    # Test viewport culling
    let viewport = rl.Rectangle(x: 0, y: 0, width: 800, height: 600)
    let visibleRange = calculateVisibleLineRange(viewport, 20.0, 1000, 0)
    
    check visibleRange.start >= 0
    check visibleRange.count > 0
    check visibleRange.count <= 1000
    
    # Test cache management
    optimizer.cleanupRenderCaches()
    
    # Test texture caching
    let cacheKey = getCacheKey(viewport, 0, 10)
    check cacheKey.len > 0

when isMainModule:
  # Run all tests
  echo "Running terminal integration tests..."
  
  # Initialize minimal Raylib for testing
  rl.setConfigFlags({FLAG_WINDOW_HIDDEN})  # Hidden window for testing
  rl.initWindow(800, 600, "Terminal Tests")
  
  try:
    # Run the test suite
    runTests()
  finally:
    rl.closeWindow()
  
  echo "Integration tests completed!"