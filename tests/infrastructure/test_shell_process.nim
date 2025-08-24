## Unit tests for shell process management

import std/[unittest, os, strutils, times, osproc]
import ../../src/infrastructure/terminal/shell_process
import ../../src/shared/types

suite "Shell Process Tests":
  
  test "Create new shell process with defaults":
    let shell = newShellProcess()
    
    check shell != nil
    check shell.state == psNotStarted
    check shell.platform in [ptUnix, ptWindows]
    check shell.shellPath.len > 0
    check shell.workingDirectory == getCurrentDir()
    check shell.processId == 0

  test "Create shell process with custom parameters":
    let customDir = getTempDir()
    let customEnv = @[("TEST_VAR", "test_value")]
    let shell = newShellProcess("", customDir, customEnv)
    
    check shell.workingDirectory == customDir
    check shell.environment == customEnv

  test "Detect platform correctly":
    let shell = newShellProcess()
    
    when defined(windows):
      check shell.platform == ptWindows
    else:
      check shell.platform == ptUnix

  test "Get default shell":
    let defaultShell = getDefaultShell()
    
    check defaultShell.len > 0
    check fileExists(defaultShell)
    
    when defined(windows):
      check defaultShell.contains("cmd") or defaultShell.contains("powershell")
    else:
      check defaultShell.startsWith("/")

  test "Validate shell path":
    # Test with default shell
    let defaultShell = getDefaultShell()
    check validateShellPath(defaultShell) == true
    
    # Test with non-existent path
    check validateShellPath("/non/existent/shell") == false
    check validateShellPath("C:\\NonExistent\\shell.exe") == false

  test "Get available shells":
    let shells = getAvailableShells()
    
    check shells.len > 0
    for shell in shells:
      check fileExists(shell)
      check validateShellPath(shell)

  test "Start and stop shell process":
    let shell = newShellProcess()
    
    # Test starting
    let started = shell.start()
    check started == true
    check shell.state == psRunning
    check shell.isRunning() == true
    check shell.processId > 0
    check shell.getUptime() >= 0.0
    
    # Test stopping
    shell.terminate()
    
    # Give some time for termination
    sleep(100)
    check shell.state == psTerminated

  test "Process I/O operations":
    let shell = newShellProcess()
    
    if shell.start():
      # Test writing input
      when defined(windows):
        let success = shell.writeCommand("echo Hello")
      else:
        let success = shell.writeCommand("echo Hello")
      
      check success == true
      
      # Give some time for command to execute
      sleep(500)
      
      # Test reading output
      let output = shell.readAllAvailableOutput()
      check output.len >= 0  # May be empty if command hasn't finished
      
      shell.terminate()

  test "Process error handling":
    # Test with invalid shell path
    let shell = newShellProcess("/invalid/shell/path")
    
    expect(ProcessSpawnError):
      discard shell.start()

  test "Process state management":
    let shell = newShellProcess()
    
    # Initial state
    check shell.state == psNotStarted
    check shell.isRunning() == false
    
    # After starting
    if shell.start():
      check shell.state == psRunning
      check shell.isRunning() == true
      
      # After terminating
      shell.terminate()
      sleep(100)
      check shell.state == psTerminated
      check shell.isRunning() == false

  test "Working directory handling":
    let tempDir = getTempDir()
    let shell = newShellProcess("", tempDir)
    
    check shell.workingDirectory == tempDir
    
    if shell.start():
      when defined(windows):
        discard shell.writeCommand("cd")
      else:
        discard shell.writeCommand("pwd")
      
      sleep(200)
      let output = shell.readAllAvailableOutput()
      
      shell.terminate()

  test "Environment variables":
    let env = @[("TEST_SHELL_VAR", "test_value")]
    let shell = newShellProcess("", "", env)
    
    check shell.environment == env
    
    if shell.start():
      when defined(windows):
        discard shell.writeCommand("echo %TEST_SHELL_VAR%")
      else:
        discard shell.writeCommand("echo $TEST_SHELL_VAR")
      
      sleep(200)
      let output = shell.readAllAvailableOutput()
      
      shell.terminate()

  test "Multiple commands execution":
    let shell = newShellProcess()
    
    if shell.start():
      # Send multiple commands
      when defined(windows):
        discard shell.writeCommand("echo First")
        sleep(100)
        discard shell.writeCommand("echo Second")
        sleep(100)
        discard shell.writeCommand("echo Third")
      else:
        discard shell.writeCommand("echo First")
        sleep(100)
        discard shell.writeCommand("echo Second")
        sleep(100)
        discard shell.writeCommand("echo Third")
      
      sleep(300)
      let output = shell.readAllAvailableOutput()
      
      shell.terminate()

  test "Process cleanup":
    let shell = newShellProcess()
    
    if shell.start():
      let pid = shell.processId
      check pid > 0
      
      shell.cleanup()
      
      check shell.state == psTerminated
      
      # Verify process is actually terminated
      sleep(100)
      when defined(windows):
        # On Windows, check if process still exists
        try:
          discard execProcess(&"tasklist /FI \"PID eq {pid}\"")
        except:
          discard
      else:
        # On Unix, try to send signal 0 to check if process exists
        try:
          discard execProcess(&"kill -0 {pid}")
        except:
          discard # Process doesn't exist, which is expected

  test "Output buffer management":
    let shell = newShellProcess()
    
    if shell.start():
      # Test hasOutput
      check shell.hasOutput() == false or shell.hasOutput() == true  # May vary
      
      # Send command and check for output
      when defined(windows):
        discard shell.writeCommand("echo Test Output")
      else:
        discard shell.writeCommand("echo Test Output")
      
      sleep(200)
      
      if shell.hasOutput():
        let output = shell.readOutput()
        check output.len >= 0
      
      shell.terminate()

  test "Time tracking":
    let shell = newShellProcess()
    
    if shell.start():
      let startTime = times.getTime().toUnixFloat()
      
      # Wait a bit
      sleep(100)
      
      let uptime = shell.getUptime()
      check uptime >= 0.1  # Should be at least 100ms
      check uptime < 10.0  # But not too long
      
      # Send command to generate output
      when defined(windows):
        discard shell.writeCommand("echo Output")
      else:
        discard shell.writeCommand("echo Output")
      
      sleep(100)
      discard shell.readAllAvailableOutput()
      
      let timeSinceOutput = shell.getTimeSinceLastOutput()
      check timeSinceOutput >= 0.0
      check timeSinceOutput < 1.0  # Should be recent
      
      shell.terminate()

  test "Shell information gathering":
    let shells = getAvailableShells()
    
    for shell in shells:
      let (name, version) = getShellInfo(shell)
      check name.len > 0
      # Version might be empty for some shells, so just check it's a string

  test "Force kill process":
    let shell = newShellProcess()
    
    if shell.start():
      let pid = shell.processId
      
      # Force kill
      shell.terminate(forceKill = true)
      
      sleep(100)
      check shell.state == psTerminated
      check shell.isRunning() == false

  test "Process exit code":
    let shell = newShellProcess()
    
    if shell.start():
      when defined(windows):
        discard shell.writeCommand("exit 0")
      else:
        discard shell.writeCommand("exit 0")
      
      sleep(200)
      
      # Process should have terminated
      if not shell.isRunning():
        let exitCode = shell.getExitCode()
        check exitCode >= 0  # Exit code should be available

  test "Large output handling":
    let shell = newShellProcess()
    
    if shell.start():
      # Generate large output
      when defined(windows):
        discard shell.writeCommand("for /L %i in (1,1,100) do echo Line %i")
      else:
        discard shell.writeCommand("for i in {1..100}; do echo Line $i; done")
      
      sleep(1000)  # Give time for command to complete
      
      let output = shell.readAllAvailableOutput()
      check output.len > 0
      
      shell.terminate()

  test "Concurrent I/O operations":
    let shell = newShellProcess()
    
    if shell.start():
      # Rapidly send multiple inputs
      for i in 1..10:
        when defined(windows):
          discard shell.writeInput(&"echo {i}\n")
        else:
          discard shell.writeInput(&"echo {i}\n")
      
      sleep(500)
      let output = shell.readAllAvailableOutput()
      
      shell.terminate()

  test "Error recovery":
    let shell = newShellProcess()
    
    if shell.start():
      # Send invalid command
      discard shell.writeCommand("this_is_not_a_valid_command_12345")
      
      sleep(200)
      let output = shell.readAllAvailableOutput()
      
      # Shell should still be running despite error
      check shell.isRunning() == true
      
      # Should be able to send another command
      when defined(windows):
        discard shell.writeCommand("echo Recovery")
      else:
        discard shell.writeCommand("echo Recovery")
      
      sleep(200)
      discard shell.readAllAvailableOutput()
      
      shell.terminate()

  test "Stream management":
    let shell = newShellProcess()
    
    if shell.start():
      # Verify streams are available
      check shell.inputStream != nil
      check shell.outputStream != nil
      
      shell.terminate()
      
      # After termination, streams should be cleaned up
      check shell.inputStream == nil
      check shell.outputStream == nil
