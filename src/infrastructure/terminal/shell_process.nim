## Shell Process Management
## Cross-platform shell process spawning and I/O handling

import std/[osproc, streams, os, strutils, strtabs, times]
import raylib as rl
# import ../../shared/types  # Unused import
import ../../terminal/core/terminal_errors

type
  PlatformType* = enum
    ptUnix,     # Linux, macOS, and other Unix-like systems
    ptWindows   # Windows

  ProcessState* = enum
    psNotStarted,
    psRunning,
    psTerminated,
    psError

  ProcessStartResult* = object
    success*: bool
    errorMessage*: string
    process*: Process

  ShellProcess* = ref object
    process*: Process
    platform*: PlatformType
    inputStream*: Stream
    outputStream*: Stream
    errorStream*: Stream
    state*: ProcessState
    shellPath*: string
    workingDirectory*: string
    environment*: seq[(string, string)]
    processId*: int
    startTime*: float
    lastOutputTime*: float
    outputBuffer*: string
    errorBuffer*: string
    starting*: bool
    startCallback*: proc(success: bool, errorMsg: string) {.closure.}



# Platform detection and configuration
proc detectPlatform(): PlatformType =
  when defined(windows):
    ptWindows
  else:
    ptUnix

proc getDefaultShell*(): string =
  ## Get the default shell for the current platform
  when defined(windows):
    # Try PowerShell first, then fall back to cmd.exe
    let powershell = findExe("powershell.exe")
    if powershell.len > 0:
      return powershell
    
    let cmd = getEnv("COMSPEC")
    if cmd.len > 0:
      return cmd
    
    return "cmd.exe"
  else:
    # Unix-like systems
    let shell = getEnv("SHELL")
    if shell.len > 0:
      return shell
    
    # Try common shells in order of preference
    for shellName in ["/bin/zsh", "/bin/bash", "/bin/sh"]:
      if fileExists(shellName):
        return shellName
    
    return "/bin/sh"  # Fallback

proc getProcessOptions(platform: PlatformType): set[ProcessOption] =
  ## Get appropriate process options for the platform
  case platform:
  of ptUnix:
    {poStdErrToStdOut, poUsePath}  # Removed poDaemon to prevent issues
  of ptWindows:
    {poStdErrToStdOut, poUsePath}  # Removed poDaemon to prevent issues

proc newShellProcess*(
  shellPath: string = "",
  workingDir: string = "",
  env: seq[(string, string)] = @[],
  startCallback: proc(success: bool, errorMsg: string) {.closure.} = nil
): ShellProcess =
  ## Create a new shell process instance
  let platform = detectPlatform()
  let shell = if shellPath.len > 0: shellPath else: getDefaultShell()
  let workDir = if workingDir.len > 0: workingDir else: getCurrentDir()
  
  ShellProcess(
    process: nil,
    platform: platform,
    inputStream: nil,
    outputStream: nil,
    errorStream: nil,
    state: psNotStarted,
    shellPath: shell,
    workingDirectory: workDir,
    environment: env,
    processId: 0,
    startTime: 0.0,
    lastOutputTime: 0.0,
    outputBuffer: "",
    errorBuffer: "",
    starting: false,
    startCallback: startCallback
  )

proc startProcessAsync(shellProcess: ShellProcess): ProcessStartResult =
  ## Internal proc to start the process (can be called async)
  try:
    let options = getProcessOptions(shellProcess.platform)
    
    # Prepare environment variables
    var env: StringTableRef = nil
    if shellProcess.environment.len > 0:
      env = newStringTable()
      for (key, value) in shellProcess.environment:
        env[key] = value
    
    # Start the process
    var process: Process
    when defined(windows):
      # On Windows, we might need to adjust the command
      var args: seq[string] = @[]
      if shellProcess.shellPath.endsWith("powershell.exe"):
        args = @["-NoLogo", "-NoProfile", "-Command", "-"]
      elif shellProcess.shellPath.endsWith("cmd.exe"):
        args = @["/Q"]  # Quiet mode
      
      process = startProcess(
        command = shellProcess.shellPath,
        workingDir = shellProcess.workingDirectory,
        args = args,
        env = env,
        options = options
      )
    else:
      # Unix-like systems - use interactive mode for proper shell experience
      var args: seq[string] = @[]
      if shellProcess.shellPath.endsWith("bash"):
        args = @["-i"]  # Interactive mode only for better prompt control
      elif shellProcess.shellPath.endsWith("zsh"):
        args = @["-i"]  # Interactive mode only for better prompt control  
      elif shellProcess.shellPath.endsWith("sh"):
        args = @["-i"]  # Interactive mode
      
      process = startProcess(
        command = shellProcess.shellPath,
        workingDir = shellProcess.workingDirectory,
        args = args,
        env = env,
        options = options
      )
    
    return ProcessStartResult(success: true, errorMessage: "", process: process)
    
  except OSError as e:
    return ProcessStartResult(success: false, errorMessage: "Failed to start shell process: " & e.msg, process: nil)
  except Exception as e:
    return ProcessStartResult(success: false, errorMessage: "Unexpected error starting shell: " & e.msg, process: nil)

proc finishProcessStart(shellProcess: ShellProcess, result: ProcessStartResult) =
  ## Complete the process startup with the result
  shellProcess.starting = false
  
  if result.success:
    # Set up the process
    shellProcess.process = result.process
    shellProcess.inputStream = shellProcess.process.inputStream
    shellProcess.outputStream = shellProcess.process.outputStream
    shellProcess.errorStream = shellProcess.process.errorStream
    
    # Update state
    shellProcess.state = psRunning
    shellProcess.processId = shellProcess.process.processID
    shellProcess.startTime = times.getTime().toUnixFloat()
    shellProcess.lastOutputTime = shellProcess.startTime
    
    # Send initial newline and prompt command to trigger shell prompt display
    try:
      # Wait a brief moment for shell to initialize
      shellProcess.inputStream.write("\n")
      shellProcess.inputStream.flush()
      # Send a simple command to ensure prompt appears
      shellProcess.inputStream.write("echo 'Shell ready'\n")
      shellProcess.inputStream.flush()
    except:
      discard
    
    # Call success callback
    if shellProcess.startCallback != nil:
      shellProcess.startCallback(true, "")
  else:
    # Set error state
    shellProcess.state = psError
    let error = newTerminalError(tecProcessSpawn, result.errorMessage, "shell_process.startAsync")
    logTerminalError(error)
    
    # Call error callback
    if shellProcess.startCallback != nil:
      shellProcess.startCallback(false, result.errorMessage)

proc startAsync*(shellProcess: ShellProcess): bool =
  ## Start the shell process asynchronously to prevent UI blocking
  if shellProcess.state == psRunning or shellProcess.starting:
    return shellProcess.state == psRunning
  
  shellProcess.starting = true
  shellProcess.state = psNotStarted
  
  # Use timeout protection to prevent hanging
  try:
    # Start with a timeout mechanism
    let startTime = times.getTime().toUnixFloat()
    let startResult = shellProcess.startProcessAsync()
    let endTime = times.getTime().toUnixFloat()
    
    # Check if startup took too long (more than 5 seconds)
    if endTime - startTime > 5.0:
      shellProcess.starting = false
      shellProcess.state = psError
      if shellProcess.startCallback != nil:
        shellProcess.startCallback(false, "Process startup timed out")
      return false
    
    shellProcess.finishProcessStart(startResult)
    return shellProcess.state == psRunning
  except Exception as e:
    shellProcess.starting = false
    shellProcess.state = psError
    if shellProcess.startCallback != nil:
      shellProcess.startCallback(false, "Startup failed: " & e.msg)
    return false

proc start*(shellProcess: ShellProcess): bool =
  ## Start the shell process (synchronous version for compatibility)
  if shellProcess.state == psRunning:
    return true
  
  # Add timeout protection for synchronous start as well
  let startTime = times.getTime().toUnixFloat()
  
  try:
    let syncStartResult = shellProcess.startProcessAsync()
    let endTime = times.getTime().toUnixFloat()
    
    # Check timeout
    if endTime - startTime > 5.0:
      shellProcess.state = psError
      return false
    
    shellProcess.finishProcessStart(syncStartResult)
    return shellProcess.state == psRunning
  except Exception:
    shellProcess.state = psError
    return false

proc isRunning*(shellProcess: ShellProcess): bool =
  ## Check if the shell process is still running
  if shellProcess.starting:
    return false  # Not yet running, but starting
  
  if shellProcess.state != psRunning or shellProcess.process == nil:
    return false
  
  try:
    return shellProcess.process.running
  except:
    shellProcess.state = psTerminated
    return false

proc isStarting*(shellProcess: ShellProcess): bool =
  ## Check if the shell process is currently starting
  return shellProcess.starting

proc writeInput*(shellProcess: ShellProcess, data: string): bool =
  ## Write input to the shell process
  if not shellProcess.isRunning() or shellProcess.inputStream == nil:
    return false
  
  try:
    shellProcess.inputStream.write(data)
    shellProcess.inputStream.flush()
    return true
  except IOError as e:
    shellProcess.state = psError
    let error = newTerminalError(tecProcessIO, "Failed to write to shell process: " & e.msg, "shell_process.writeInput")
    logTerminalError(error)
    raise error
  except Exception:
    return false

proc writeCommand*(shellProcess: ShellProcess, command: string): bool =
  ## Write a command to the shell process (adds newline)
  let commandWithNewline = command & "\n"
  return shellProcess.writeInput(commandWithNewline)

proc readOutput*(shellProcess: ShellProcess, maxBytes: int = 1024): string =
  ## Read available output from the shell process (truly non-blocking)
  if not shellProcess.isRunning():
    return ""
  
  # Instead of using streams (which can block), use process.outputHandle directly
  # or accumulate from internal buffer
  try:
    if shellProcess.outputBuffer.len > 0:
      # Return from internal buffer if available
      let returnSize = min(maxBytes, shellProcess.outputBuffer.len)
      result = shellProcess.outputBuffer[0..<returnSize]
      shellProcess.outputBuffer = shellProcess.outputBuffer[returnSize..^1]
      if result.len > 0:
        shellProcess.lastOutputTime = times.getTime().toUnixFloat()
      return result
    else:
      # No buffered data available
      return ""
  except Exception:
    # Any exception - return empty to prevent blocking
    return ""

proc readAllAvailableOutput*(shellProcess: ShellProcess): string =
  ## Read all available output from internal buffer (truly non-blocking)
  if not shellProcess.isRunning():
    return ""
  
  try:
    # Simply return all buffered output at once - no loops or blocking calls
    result = shellProcess.outputBuffer
    shellProcess.outputBuffer = ""
    if result.len > 0:
      shellProcess.lastOutputTime = times.getTime().toUnixFloat()
    return result
  except Exception:
    return ""

proc hasOutput*(shellProcess: ShellProcess): bool =
  ## Check if there's output available in buffer (truly non-blocking)
  if not shellProcess.isRunning():
    return false
  
  try:
    # Simply check if we have buffered data - no stream operations
    return shellProcess.outputBuffer.len > 0
  except Exception:
    return false

proc getExitCode*(shellProcess: ShellProcess): int =
  ## Get the exit code of the shell process (only valid if terminated)
  if shellProcess.process == nil:
    return -1
  
  try:
    return shellProcess.process.peekExitCode()
  except:
    return -1

proc terminate*(shellProcess: ShellProcess, forceKill: bool = false) =
  ## Terminate the shell process
  if shellProcess.process == nil:
    return
  
  try:
    if forceKill:
      shellProcess.process.kill()
    else:
      shellProcess.process.terminate()
    
    # Close streams
    if shellProcess.inputStream != nil:
      shellProcess.inputStream.close()
      shellProcess.inputStream = nil
    
    if shellProcess.outputStream != nil:
      shellProcess.outputStream.close()
      shellProcess.outputStream = nil
    
    if shellProcess.errorStream != nil:
      shellProcess.errorStream.close()
      shellProcess.errorStream = nil
    
    # Wait for process to finish
    discard shellProcess.process.waitForExit(1000)  # Wait up to 1 second
    
    shellProcess.state = psTerminated
    
  except Exception as e:
    shellProcess.state = psError
    let error = newTerminalError(tecResourceCleanup, "Error during process termination: " & e.msg, "shell_process.terminate")
    logTerminalError(error)
    # Don't raise - termination should always succeed

proc cleanup*(shellProcess: ShellProcess) =
  ## Clean up resources and ensure process is terminated
  if shellProcess.state == psRunning:
    shellProcess.terminate(forceKill = true)
  
  shellProcess.starting = false
  shellProcess.outputBuffer = ""
  shellProcess.errorBuffer = ""
  shellProcess.startCallback = nil

proc getUptime*(shellProcess: ShellProcess): float =
  ## Get the uptime of the shell process in seconds
  if shellProcess.startTime <= 0:
    return 0.0
  
  return times.getTime().toUnixFloat() - shellProcess.startTime

proc getTimeSinceLastOutput*(shellProcess: ShellProcess): float =
  ## Get the time since last output in seconds
  if shellProcess.lastOutputTime <= 0:
    return 0.0
  
  return times.getTime().toUnixFloat() - shellProcess.lastOutputTime

# Utility functions for shell detection and validation
proc validateShellPath*(shellPath: string): bool =
  ## Validate if the given shell path is executable
  try:
    return fileExists(shellPath) and fpUserExec in getFilePermissions(shellPath)
  except:
    return false

proc getAvailableShells*(): seq[string] =
  ## Get a list of available shell executables
  result = @[]
  
  when defined(windows):
    # Windows shells
    let shells = [
      "powershell.exe",
      "pwsh.exe",  # PowerShell Core
      "cmd.exe"
    ]
    
    for shell in shells:
      let path = findExe(shell)
      if path.len > 0:
        result.add(path)
    
    # Also check COMSPEC
    let comspec = getEnv("COMSPEC")
    if comspec.len > 0 and comspec notin result:
      result.add(comspec)
  else:
    # Unix-like systems
    let shells = [
      "/bin/zsh",
      "/bin/bash",
      "/bin/fish",
      "/bin/sh",
      "/usr/bin/zsh",
      "/usr/bin/bash",
      "/usr/bin/fish"
    ]
    
    for shell in shells:
      if validateShellPath(shell):
        result.add(shell)

proc collectOutputAsync*(shellProcess: ShellProcess) =
  ## Collect output from shell process in background (non-blocking approach)
  if shellProcess.outputStream == nil or not shellProcess.isRunning():
    return
  
  try:
    # Try to read a small amount without blocking
    var buffer = newString(1024)  # Larger buffer for shell output including prompts
    let bytesRead = shellProcess.outputStream.readData(addr buffer[0], 1024)
    if bytesRead > 0:
      let newOutput = buffer[0..<bytesRead]
      shellProcess.outputBuffer.add(newOutput)
      shellProcess.lastOutputTime = times.getTime().toUnixFloat()
      
      # If this looks like the first output and no prompt is visible, send commands to ensure prompt
      if shellProcess.outputBuffer.len <= 1024 and not shellProcess.outputBuffer.contains("$") and not shellProcess.outputBuffer.contains(">"):
        try:
          shellProcess.inputStream.write("PS1='$ '; export PS1\n")
          shellProcess.inputStream.flush()
        except:
          discard
  except:
    # Any exception means no data available - this is normal
    discard

proc getShellInfo*(shellPath: string): tuple[name: string, version: string] =
  ## Get information about a shell executable
  result = (name: "", version: "")
  
  if not validateShellPath(shellPath):
    return
  
  let filename = extractFilename(shellPath)
  result.name = filename
  
  # Try to get version information
  try:
    when defined(windows):
      if filename.contains("powershell") or filename.contains("pwsh"):
        let output = execProcess(shellPath & " -Command '$PSVersionTable.PSVersion.ToString()'")
        result.version = output.strip()
      elif filename.contains("cmd"):
        result.version = "Windows Command Prompt"
    else:
      if filename.contains("bash"):
        let output = execProcess(shellPath & " --version")
        let lines = output.splitLines()
        if lines.len > 0:
          result.version = lines[0]
      elif filename.contains("zsh"):
        let output = execProcess(shellPath & " --version")
        result.version = output.strip()
      elif filename.contains("fish"):
        let output = execProcess(shellPath & " --version")
        result.version = output.strip()
  except:
    discard  # Version detection failed, but that's okay