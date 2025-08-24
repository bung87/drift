## Terminal Service
## High-level service for managing terminal sessions and coordinating between UI and process management

import std/[tables, sequtils, options, times, os, strutils]
import raylib as rl
import ../shared/types
import ../terminal/core/terminal_errors
import ../infrastructure/terminal/[shell_process, ansi_parser]

type
  TerminalEvent* = object
    eventType*: TerminalEventType
    sessionId*: int
    data*: string
    timestamp*: float

  TerminalEventType* = enum
    teSessionCreated,
    teSessionClosed,
    teSessionActivated,
    teOutputReceived,
    teCommandExecuted,
    teProcessTerminated,
    teError

  TerminalServiceConfig* = object
    maxSessions*: int
    defaultShell*: string
    bufferMaxLines*: int
    outputPollInterval*: float
    autoScrollToBottom*: bool

  TerminalService* = ref object
    config*: TerminalServiceConfig
    sessions*: Table[int, TerminalSession]
    processes*: Table[int, ShellProcess]
    parsers*: Table[int, AnsiParser]
    activeSessionId*: int
    nextSessionId*: int
    eventCallback*: proc(event: TerminalEvent) {.closure.}
    running*: bool
    lastPollTime*: float

# Default configuration
proc defaultTerminalConfig*(): TerminalServiceConfig =
  TerminalServiceConfig(
    maxSessions: 10,
    defaultShell: getDefaultShell(),
    bufferMaxLines: 1000,
    outputPollInterval: 0.016, # ~60 FPS
    autoScrollToBottom: true
  )

# Service initialization
proc newTerminalService*(
  config: TerminalServiceConfig = defaultTerminalConfig(),
  eventCallback: proc(event: TerminalEvent) {.closure.} = nil
): TerminalService =
  result = TerminalService(
    config: config,
    sessions: initTable[int, TerminalSession](),
    processes: initTable[int, ShellProcess](),
    parsers: initTable[int, AnsiParser](),
    activeSessionId: -1,
    nextSessionId: 1,
    eventCallback: eventCallback,
    running: false,
    lastPollTime: 0.0
  )

# Event handling
proc emitEvent(service: TerminalService, eventType: TerminalEventType, 
               sessionId: int = -1, data: string = "") =
  if service.eventCallback != nil:
    let event = TerminalEvent(
      eventType: eventType,
      sessionId: sessionId,
      data: data,
      timestamp: times.getTime().toUnixFloat()
    )
    service.eventCallback(event)

# Session management
proc createSession*(service: TerminalService, 
                   name: string = "", 
                   workingDir: string = "",
                   shellPath: string = ""): TerminalSession =
  if service.sessions.len >= service.config.maxSessions:
    raise newException(CatchableError, "Maximum number of sessions reached")
  
  let sessionId = service.nextSessionId
  inc service.nextSessionId
  
  let sessionName = if name.len > 0: name else: "Terminal " & $sessionId
  let workDir = if workingDir.len > 0: workingDir else: getCurrentDir()
  let shell = if shellPath.len > 0: shellPath else: service.config.defaultShell
  
  # Create session
  let session = newTerminalSession(sessionId, sessionName, workDir)
  session.buffer = newTerminalBuffer(service.config.bufferMaxLines)
  
  # Create ANSI parser
  let parser = newAnsiParser()
  
  # Create shell process with async startup callback
  let process = newShellProcess(shell, workDir, @[], proc(success: bool, errorMsg: string) =
    # Ensure session still exists before updating state
    if sessionId in service.sessions:
      let sessionRef = service.sessions[sessionId]
      if success:
        sessionRef.isActive = true
        service.emitEvent(teOutputReceived, sessionId, "Terminal ready\n")
      else:
        sessionRef.isActive = false
        let error = newTerminalError(tecProcessSpawn, "Failed to start shell process: " & errorMsg, "terminal_service.createSession.callback")
        logTerminalError(error)
        service.emitEvent(teError, sessionId, "Shell startup failed: " & errorMsg)
  )
  
  # Store everything
  service.sessions[sessionId] = session
  service.processes[sessionId] = process
  service.parsers[sessionId] = parser
  
  # Start the shell process asynchronously (non-blocking)
  try:
    if not process.startAsync():
      let error = newTerminalError(tecProcessSpawn, "Failed to start shell process startup", "terminal_service.createSession")
      logTerminalError(error)
      # Clean up on failure
      service.sessions.del(sessionId)
      service.processes.del(sessionId)
      service.parsers.del(sessionId)
      raise error
    
    # Session is created immediately, even if process is still starting
    # The process will become active asynchronously via the callback
    
    # Set as active session if it's the first one
    if service.activeSessionId == -1:
      service.activeSessionId = sessionId
    
    service.emitEvent(teSessionCreated, sessionId, sessionName)
    
    return session
    
  except Exception as e:
    # Clean up on failure
    service.sessions.del(sessionId)
    service.processes.del(sessionId)
    service.parsers.del(sessionId)
    raise

proc getSession*(service: TerminalService, sessionId: int): Option[TerminalSession] =
  if sessionId in service.sessions:
    some(service.sessions[sessionId])
  else:
    none(TerminalSession)

proc getActiveSession*(service: TerminalService): Option[TerminalSession] =
  service.getSession(service.activeSessionId)

proc getAllSessions*(service: TerminalService): seq[TerminalSession] =
  result = @[]
  for session in service.sessions.values:
    result.add(session)

proc setActiveSession*(service: TerminalService, sessionId: int): bool =
  if sessionId in service.sessions:
    service.activeSessionId = sessionId
    service.emitEvent(teSessionActivated, sessionId)
    return true
  return false

proc closeSession*(service: TerminalService, sessionId: int): bool =
  if sessionId notin service.sessions:
    return false
  
  # Get references before deletion
  let session = service.sessions[sessionId]
  
  # Terminate process if running
  if sessionId in service.processes:
    let process = service.processes[sessionId]
    process.cleanup()
    service.processes.del(sessionId)
  
  # Clean up parser
  if sessionId in service.parsers:
    service.parsers.del(sessionId)
  
  # Remove session
  service.sessions.del(sessionId)
  
  # Update active session if necessary
  if service.activeSessionId == sessionId:
    service.activeSessionId = -1
    # Try to activate another session
    for id in service.sessions.keys:
      service.activeSessionId = id
      break
  
  service.emitEvent(teSessionClosed, sessionId, session.name)
  return true

proc closeAllSessions*(service: TerminalService) =
  let sessionIds = toSeq(service.sessions.keys)
  for sessionId in sessionIds:
    discard service.closeSession(sessionId)

# Input/Output operations
proc sendInput*(service: TerminalService, input: string, sessionId: int = -1): bool =
  let targetId = if sessionId == -1: service.activeSessionId else: sessionId
  
  if targetId notin service.processes:
    return false
  
  let process = service.processes[targetId]
  if not process.isRunning() or process.isStarting():
    return false
  
  try:
    return process.writeInput(input)
  except TerminalError as e:
    logTerminalError(e)
    service.emitEvent(teError, targetId, "Failed to send input to shell: " & e.msg)
    return false

proc sendCommand*(service: TerminalService, command: string, sessionId: int = -1): bool =
  let targetId = if sessionId == -1: service.activeSessionId else: sessionId
  
  if targetId notin service.processes:
    return false
  
  let process = service.processes[targetId]
  if not process.isRunning():
    return false
  
  try:
    let writeResult = process.writeCommand(command)
    if writeResult:
      service.emitEvent(teCommandExecuted, targetId, command)
    return writeResult
  except TerminalError as e:
    logTerminalError(e)
    service.emitEvent(teError, targetId, "Failed to send command to shell: " & e.msg)
    return false

# Output processing
proc processOutputForSession(service: TerminalService, sessionId: int) =
  # Safety checks with early returns
  if sessionId notin service.sessions or sessionId notin service.processes or sessionId notin service.parsers:
    return
  
  let session = service.sessions[sessionId]
  let process = service.processes[sessionId]
  let parser = service.parsers[sessionId]
  
  # Additional safety checks
  if session == nil or process == nil or parser == nil:
    return
  
  # Check if process is still running or starting
  if process.isStarting():
    # Process is still starting, mark session as active but starting
    if not session.isActive:
      session.isActive = true  # Consider starting sessions as active
    return
  elif not process.isRunning():
    if session.isActive:
      session.isActive = false
      service.emitEvent(teProcessTerminated, sessionId)
    return
  else:
    # Process is running, ensure session is marked as active
    if not session.isActive:
      session.isActive = true
  
  # Use non-blocking approach - don't try to read output immediately
  # Instead, just check if process has output available without blocking
  try:
    if process.hasOutput():
      # Only try to read if we know there's output available
      let output = process.readAllAvailableOutput()
      if output.len > 0:
        # Parse ANSI sequences and add to buffer with error resilience
        try:
          let lines = output.splitLines(keepEol = false)
          for line in lines:
            if line.len > 0:
              try:
                let terminalLine = parser.parseToTerminalLine(line)
                session.buffer.addLine(terminalLine)
              except Exception:
                # If parsing fails, add as plain text
                let plainLine = newTerminalLine(line)
                session.buffer.addLine(plainLine)
          
          service.emitEvent(teOutputReceived, sessionId, output)
        except Exception:
          # Fallback: add output as plain text if parsing completely fails
          let plainLine = newTerminalLine(output)
          session.buffer.addLine(plainLine)
          service.emitEvent(teOutputReceived, sessionId, output)
  except Exception:
    # Don't log every I/O error to prevent spam - just continue
    # Only emit error event for critical issues
    discard

proc pollAllSessions*(service: TerminalService) =
  let currentTime = times.getTime().toUnixFloat()
  
  # Check if enough time has passed since last poll
  if currentTime - service.lastPollTime < service.config.outputPollInterval:
    return
  
  # Return early if no sessions exist
  if service.sessions.len == 0:
    service.lastPollTime = currentTime
    return
  
  service.lastPollTime = currentTime
  
  # Process output for all active sessions with error protection
  # Use round-robin approach to ensure fairness and prevent blocking
  let sessionIds = toSeq(service.sessions.keys)
  var processedCount = 0
  const maxSessionsPerPoll = 3  # Further reduced to prevent any blocking
  
  for sessionId in sessionIds:
    if processedCount >= maxSessionsPerPoll:
      break
    
    try:
      # Quick check - only process if session definitely has activity
      if sessionId in service.processes:
        let process = service.processes[sessionId]
        if process != nil and (process.isRunning() or process.isStarting()):
          service.processOutputForSession(sessionId)
          inc processedCount
    except Exception:
      # Continue with other sessions if one fails - no logging to prevent spam
      continue

# Service lifecycle
proc start*(service: TerminalService) =
  service.running = true
  service.lastPollTime = times.getTime().toUnixFloat()

proc stop*(service: TerminalService) =
  service.running = false
  service.closeAllSessions()

proc update*(service: TerminalService) =
  if not service.running:
    return
  
  service.pollAllSessions()
  
  # Update any terminal I/O handlers if they exist
  # This would be handled by the terminal integration layer

# Utility functions
proc getSessionCount*(service: TerminalService): int =
  service.sessions.len

proc isSessionActive*(service: TerminalService, sessionId: int): bool =
  if sessionId notin service.sessions:
    return false
  
  let session = service.sessions[sessionId]
  let process = service.processes.getOrDefault(sessionId)
  
  # Handle different process states more carefully
  if process == nil:
    return false
  
  # Consider starting or running processes as active
  if process.isStarting():
    return true  # Process is starting, consider active
  elif process.isRunning():
    # Process is running, ensure session state matches
    if not session.isActive:
      session.isActive = true
    return true
  else:
    # Process is not running, session should not be active
    if session.isActive:
      session.isActive = false
    return false

proc getSessionOutput*(service: TerminalService, sessionId: int, 
                      startLine: int = 0, lineCount: int = -1): seq[TerminalLine] =
  if sessionId notin service.sessions:
    return @[]
  
  let session = service.sessions[sessionId]
  let totalLines = session.buffer.getLineCount()
  
  let start = max(0, startLine)
  let count = if lineCount == -1: totalLines - start else: lineCount
  
  return session.buffer.getVisibleLines(start, count)

proc clearSessionBuffer*(service: TerminalService, sessionId: int): bool =
  if sessionId notin service.sessions:
    return false
  
  service.sessions[sessionId].buffer.clear()
  return true

proc restartSession*(service: TerminalService, sessionId: int): bool =
  if sessionId notin service.sessions:
    return false
  
  let session = service.sessions[sessionId]
  let oldWorkingDir = session.workingDirectory
  
  # Close existing process safely
  if sessionId in service.processes:
    try:
      service.processes[sessionId].cleanup()
    except Exception:
      discard
  
  # Mark session as inactive during restart
  session.isActive = false
  
  # Create callback for restart completion
  proc onRestartCompleted(success: bool, errorMsg: string) =
    # Ensure session still exists before updating state
    if sessionId in service.sessions:
      let sessionRef = service.sessions[sessionId]
      if success:
        sessionRef.isActive = true
        service.emitEvent(teSessionCreated, sessionId, "Session restarted")
      else:
        sessionRef.isActive = false
        service.emitEvent(teError, sessionId, "Failed to restart session: " & errorMsg)
  
  # Create new process with callback
  let newProcess = newShellProcess(service.config.defaultShell, oldWorkingDir, @[], onRestartCompleted)
  
  try:
    if newProcess.startAsync():
      service.processes[sessionId] = newProcess
      
      # Reset parser state safely
      if sessionId in service.parsers:
        try:
          service.parsers[sessionId].reset()
        except Exception:
          # Create new parser if reset fails
          service.parsers[sessionId] = newAnsiParser()
      
      return true
    
  except Exception:
    session.isActive = false
    service.emitEvent(teError, sessionId, "Exception during session restart")
  
  return false

# Configuration management
proc updateConfig*(service: TerminalService, newConfig: TerminalServiceConfig) =
  service.config = newConfig

proc getConfig*(service: TerminalService): TerminalServiceConfig =
  service.config

# Event callback management
proc setEventCallback*(service: TerminalService, callback: proc(event: TerminalEvent) {.closure.}) =
  service.eventCallback = callback

proc removeEventCallback*(service: TerminalService) =
  service.eventCallback = nil