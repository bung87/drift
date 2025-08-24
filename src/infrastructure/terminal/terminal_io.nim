## Terminal I/O Handler
## Real-time I/O handling with background processing for terminal operations

import std/[deques, times]
import raylib as rl
# import ../../shared/types  # Unused import
# import ../../terminal/core/terminal_errors  # Unused import
import shell_process, ansi_parser

type
  IOEventType* = enum
    ietOutputReceived,
    ietInputSent,
    ietProcessTerminated,
    ietError

  IOEvent* = object
    eventType*: IOEventType
    sessionId*: int
    data*: string
    timestamp*: float

  InputCommand* = object
    sessionId*: int
    data*: string
    timestamp*: float
    isCommand*: bool  # true for commands (with newline), false for raw input

  TerminalIO* = ref object
    sessionId*: int
    shellProcess*: ShellProcess
    ansiParser*: AnsiParser
    running*: bool
    inputQueue*: Deque[InputCommand]
    outputBuffer*: string
    eventCallback*: proc(event: IOEvent) {.closure.}
    lastOutputTime*: float
    pollInterval*: float

  TerminalIOManager* = ref object
    ioHandlers*: seq[TerminalIO]
    managerRunning*: bool
    globalEventCallback*: proc(event: IOEvent) {.closure.}

var globalIOManager*: TerminalIOManager

proc initTerminalIO*(sessionId: int, shellProcess: ShellProcess, 
                    ansiParser: AnsiParser, 
                    eventCallback: proc(event: IOEvent) {.closure.} = nil,
                    pollInterval: float = 0.016): TerminalIO =
  result = TerminalIO(
    sessionId: sessionId,
    shellProcess: shellProcess,
    ansiParser: ansiParser,
    running: false,
    inputQueue: initDeque[InputCommand](),
    outputBuffer: "",
    eventCallback: eventCallback,
    lastOutputTime: 0.0,
    pollInterval: pollInterval
  )

# Input handling
proc queueInput*(terminalIO: TerminalIO, data: string, isCommand: bool = false) =
  ## Queue input data to be sent to the shell process
  let command = InputCommand(
    sessionId: terminalIO.sessionId,
    data: data,
    timestamp: times.getTime().toUnixFloat(),
    isCommand: isCommand
  )
  
  terminalIO.inputQueue.addLast(command)

proc processInputQueue(terminalIO: TerminalIO) =
  ## Process queued input commands (non-blocking with safety limits)
  if terminalIO.shellProcess == nil or not terminalIO.shellProcess.isRunning():
    # Clear queue if process is not running to prevent buildup
    terminalIO.inputQueue.clear()
    return
  
  var commandsToProcess: seq[InputCommand] = @[]
  var processedCount = 0
  const maxCommandsPerCycle = 10  # Limit commands per cycle to prevent blocking
  
  # Get pending commands with limit
  while terminalIO.inputQueue.len > 0 and processedCount < maxCommandsPerCycle:
    commandsToProcess.add(terminalIO.inputQueue.popFirst())
    inc processedCount
  
  # Process commands with error resilience
  for command in commandsToProcess:
    if terminalIO.shellProcess.isRunning():
      try:
        let success = if command.isCommand:
          terminalIO.shellProcess.writeCommand(command.data)
        else:
          terminalIO.shellProcess.writeInput(command.data)
        
        if success and terminalIO.eventCallback != nil:
          try:
            let event = IOEvent(
              eventType: ietInputSent,
              sessionId: terminalIO.sessionId,
              data: command.data,
              timestamp: command.timestamp
            )
            # Call event callback directly
            try:
              terminalIO.eventCallback(event)
            except Exception:
              discard
          except Exception:
            # Ignore callback errors to prevent blocking
            discard
      except Exception:
        # Don't spam error logs - just skip this command
        # Clear remaining queue on repeated failures
        if terminalIO.inputQueue.len > 5:
          terminalIO.inputQueue.clear()
        break

# Output handling
proc processOutput(terminalIO: TerminalIO) =
  ## Process output from shell process (non-blocking with safety checks)
  if terminalIO.shellProcess == nil:
    return
    
  if not terminalIO.shellProcess.isRunning():
    if terminalIO.eventCallback != nil:
      try:
        let event = IOEvent(
          eventType: ietProcessTerminated,
          sessionId: terminalIO.sessionId,
          data: "Shell process terminated",
          timestamp: times.getTime().toUnixFloat()
        )
        # Call event callback directly
        try:
          terminalIO.eventCallback(event)
        except Exception:
          discard
      except Exception:
        # Ignore callback errors
        discard
    return
  
  try:
    # Use truly non-blocking read - only get what's immediately available
    if terminalIO.shellProcess.hasOutput():
      let output = terminalIO.shellProcess.readAllAvailableOutput()
      if output.len > 0:
        # Limit buffer size to prevent memory issues
        const maxBufferSize = 512 * 1024  # Reduced to 512KB limit
        if terminalIO.outputBuffer.len + output.len > maxBufferSize:
          # Clear buffer if it gets too large
          terminalIO.outputBuffer = output[max(0, output.len - maxBufferSize div 2)..^1]
        else:
          terminalIO.outputBuffer.add(output)
        
        # Update last output time
        terminalIO.lastOutputTime = times.getTime().toUnixFloat()
        
        # Emit event with error protection using callSoon to prevent blocking
        if terminalIO.eventCallback != nil:
          try:
            let event = IOEvent(
              eventType: ietOutputReceived,
              sessionId: terminalIO.sessionId,
              data: output,
              timestamp: terminalIO.lastOutputTime
            )
            # Call event callback directly
            try:
              terminalIO.eventCallback(event)
            except Exception:
              discard
          except Exception:
            # Ignore callback errors to prevent blocking
            discard
        
  except Exception:
    # Don't log every I/O error to prevent spam
    # Just ignore and continue
    discard

# Processing
proc processIO(terminalIO: TerminalIO) =
  ## Process I/O operations (non-blocking with timeout protection)
  if not terminalIO.running:
    return
  
  # Skip processing if shell process is not ready to prevent blocking
  if terminalIO.shellProcess == nil or not terminalIO.shellProcess.isRunning():
    return
    
  try:
    # Process input queue with timeout protection
    terminalIO.processInputQueue()
    
    # Process output with safety checks
    terminalIO.processOutput()
    
  except Exception as e:
    # Don't log terminal errors during normal I/O processing to prevent spam
    # Only emit event callback if it's a critical error
    if terminalIO.eventCallback != nil:
      let event = IOEvent(
        eventType: ietError,
        sessionId: terminalIO.sessionId,
        data: "I/O processing error",  # Simplified error message
        timestamp: times.getTime().toUnixFloat()
      )
      # Call error callback directly
      try:
        terminalIO.eventCallback(event)
      except Exception:
        # Ignore callback errors to prevent cascading failures
        discard

# Lifecycle management
proc start*(terminalIO: TerminalIO) =
  ## Start I/O processing
  if terminalIO.running:
    return
  
  terminalIO.running = true
  terminalIO.lastOutputTime = times.getTime().toUnixFloat()

proc stop*(terminalIO: TerminalIO) =
  ## Stop I/O processing
  if not terminalIO.running:
    return
  
  terminalIO.running = false
  
  # Clear input queue safely
  try:
    terminalIO.inputQueue.clear()
  except Exception:
    discard
  
  # Clear output buffer safely
  try:
    terminalIO.outputBuffer = ""
  except Exception:
    discard
  
  # Reset callback to prevent future calls
  terminalIO.eventCallback = nil

proc cleanup*(terminalIO: TerminalIO) =
  ## Clean up resources
  terminalIO.stop()

# Output retrieval
proc getAndClearOutput*(terminalIO: TerminalIO): string =
  ## Get all accumulated output and clear the buffer (thread-safe)
  try:
    result = terminalIO.outputBuffer
    terminalIO.outputBuffer = ""
  except Exception:
    result = ""

proc peekOutput*(terminalIO: TerminalIO): string =
  ## Get accumulated output without clearing the buffer (thread-safe)
  try:
    result = terminalIO.outputBuffer
  except Exception:
    result = ""

proc hasOutput*(terminalIO: TerminalIO): bool =
  ## Check if there's output available (thread-safe)
  try:
    result = terminalIO.outputBuffer.len > 0
  except Exception:
    result = false

# Input operations
proc sendInput*(terminalIO: TerminalIO, data: string) =
  ## Send raw input to the shell
  terminalIO.queueInput(data, isCommand = false)

proc sendCommand*(terminalIO: TerminalIO, command: string) =
  ## Send a command to the shell (adds newline)
  terminalIO.queueInput(command, isCommand = true)

proc sendKeyPress*(terminalIO: TerminalIO, key: int32, modifiers: int32 = 0) =
  ## Send a key press to the shell (converts to appropriate characters)
  var data = ""
  
  case key:
  of rl.KeyboardKey.Enter.int32:
    data = "\n"
  of rl.KeyboardKey.Backspace.int32:
    data = "\b"
  of rl.KeyboardKey.Tab.int32:
    data = "\t"
  of rl.KeyboardKey.Escape.int32:
    data = "\x1b"
  of rl.KeyboardKey.Up.int32:
    data = "\x1b[A"
  of rl.KeyboardKey.Down.int32:
    data = "\x1b[B"
  of rl.KeyboardKey.Right.int32:
    data = "\x1b[C"
  of rl.KeyboardKey.Left.int32:
    data = "\x1b[D"
  of rl.KeyboardKey.Home.int32:
    data = "\x1b[H"
  of rl.KeyboardKey.End.int32:
    data = "\x1b[F"
  of rl.KeyboardKey.PageUp.int32:
    data = "\x1b[5~"
  of rl.KeyboardKey.PageDown.int32:
    data = "\x1b[6~"
  of rl.KeyboardKey.Delete.int32:
    data = "\x1b[3~"
  else:
    # For printable characters, convert key code to character
    if key >= 32 and key <= 126:
      data = $char(key)
    # Handle Ctrl combinations
    elif (modifiers and 0x02) != 0:  # CTRL modifier
      if key >= 65 and key <= 90:  # A-Z
        data = $char(key - 64)  # Convert to control character
  
  if data.len > 0:
    terminalIO.sendInput(data)

# Statistics and monitoring
proc getTimeSinceLastOutput*(terminalIO: TerminalIO): float =
  ## Get time since last output was received
  if terminalIO.lastOutputTime <= 0:
    return 0.0
  return times.getTime().toUnixFloat() - terminalIO.lastOutputTime

proc getInputQueueSize*(terminalIO: TerminalIO): int =
  ## Get the number of queued input commands
  result = terminalIO.inputQueue.len

proc isRunning*(terminalIO: TerminalIO): bool =
  ## Check if I/O processing is running
  terminalIO.running

# Update method
proc update*(terminalIO: TerminalIO) =
  ## Update I/O processing (call this regularly from main thread)
  if not terminalIO.running:
    return
  
  # Safety check before processing
  if terminalIO.shellProcess == nil:
    terminalIO.running = false
    return
  
  # Check if we should continue processing based on time limits
  let currentTime = times.getTime().toUnixFloat()
  if currentTime - terminalIO.lastOutputTime > 20.0:  # Reduced to 20 second timeout
    # Reset if no activity for too long (might indicate hung process)
    if terminalIO.shellProcess != nil and not terminalIO.shellProcess.isRunning():
      terminalIO.running = false
      return
  
  # Process I/O directly but with error protection
  try:
    if terminalIO.running:
      terminalIO.processIO()
  except Exception:
    # Stop processing on critical errors to prevent system hang
    terminalIO.running = false

# Global I/O Manager
proc initTerminalIOManager*(globalEventCallback: proc(event: IOEvent) {.closure.} = nil): TerminalIOManager =
  result = TerminalIOManager(
    ioHandlers: @[],
    managerRunning: false,
    globalEventCallback: globalEventCallback
  )

proc addHandler*(manager: TerminalIOManager, handler: TerminalIO) =
  ## Add an I/O handler to the manager
  manager.ioHandlers.add(handler)
  
  # Set up event forwarding
  if manager.globalEventCallback != nil:
    handler.eventCallback = manager.globalEventCallback

proc removeHandler*(manager: TerminalIOManager, sessionId: int) =
  ## Remove an I/O handler from the manager
  for i in countdown(manager.ioHandlers.len - 1, 0):
    if manager.ioHandlers[i].sessionId == sessionId:
      manager.ioHandlers[i].cleanup()
      manager.ioHandlers.del(i)
      break

proc startAll*(manager: TerminalIOManager) =
  ## Start all I/O handlers
  manager.managerRunning = true
  for handler in manager.ioHandlers:
    handler.start()

proc stopAll*(manager: TerminalIOManager) =
  ## Stop all I/O handlers
  manager.managerRunning = false
  for handler in manager.ioHandlers:
    handler.stop()

proc cleanupAll*(manager: TerminalIOManager) =
  ## Clean up all handlers and manager resources
  for handler in manager.ioHandlers:
    handler.cleanup()
  manager.ioHandlers.setLen(0)

proc getHandler*(manager: TerminalIOManager, sessionId: int): TerminalIO =
  ## Get I/O handler for a specific session
  for handler in manager.ioHandlers:
    if handler.sessionId == sessionId:
      return handler
  return nil

# Initialize global manager
proc initGlobalIOManager*() =
  if globalIOManager == nil:
    globalIOManager = initTerminalIOManager()

# Utility functions
proc processAllIO*(manager: TerminalIOManager) =
  ## Process I/O for all handlers
  for handler in manager.ioHandlers:
    if handler.running:
      handler.processIO()