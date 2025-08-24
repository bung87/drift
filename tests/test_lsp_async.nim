## Test file for the modularized async LSP implementation
## Tests the non-blocking, thread-safe LSP client

import std/[os, options]
import chronos except Result
import ../src/lsp_client_async
import ../src/lsp_async_runner
import ../src/lsp_ui_integration

import unittest2

from times import epochTime
import chronos/timer except Result

proc waitForCondition(condition: proc(): bool, timeout: float = 5.0): bool =
  ## Helper to wait for a condition with timeout
  let startTime = epochTime()
  while epochTime() - startTime < timeout:
    if condition():
      return true
    sleep(50)
  return false

suite "LSP Async Client Tests":
  test "Create and destroy LSP client":
    let client = newLSPClient()
    check client != nil

    let (state, error) = client.getState()
    check state == lspUninitialized
    check error == ""

  test "LSP client message queuing":
    let client = newLSPClient()

    # Queue some messages
    client.queueRequest(LSPMessage(kind: lmkInitialize))
    client.queueRequest(
      LSPMessage(kind: lmkHover, uri: "file:///test.nim", line: 0, character: 0)
    )

    # Messages should be queued
    check client.getResponse().isNone

  test "LSP async runner lifecycle":
    let runner = newLSPAsyncRunner()
    check runner != nil

    # Start the runner
    runner.start()
    sleep(200) # Give it time to start

    # Should not be ready yet (not initialized)
    check not runner.isReady()
    check runner.getStatus() == "Not initialized"

    # Stop the runner
    runner.stop()

  test "LSP UI integration basic operations":
    let lsp = newLSPUIIntegration()
    check lsp != nil

    # Should not be ready initially
    check not lsp.isReady()
    check lsp.getStatus() == "Not initialized"

    # Request hover before initialization should be no-op
    lsp.requestHover("file:///test.nim", 0, 0)
    check lsp.checkHoverResponse().isNone

  test "LSP UI state management":
    var state = newLSPUIState()

    # Initial state
    check not state.isReady()
    check state.getStatus() == "Not initialized"
    check not state.hasHover()
    check state.getHoverContent() == ""

    # Update hover position
    state.updateHover("/test.nim", 10, 5)
    check state.lastHoverLine == 10
    check state.lastHoverChar == 5

  test "Non-blocking hover request":
    let lsp = newLSPUIIntegration()

    # Multiple rapid hover requests should be debounced
    lsp.requestHover("file:///test.nim", 0, 0)
    lsp.requestHover("file:///test.nim", 0, 0)
    lsp.requestHover("file:///test.nim", 0, 0)

    # Should not crash or block

  test "Document version tracking":
    let lsp = newLSPUIIntegration()

    # Open a file
    lsp.notifyFileOpened("/test.nim", "echo \"Hello\"")

    # Change the file multiple times
    lsp.notifyFileChanged("/test.nim", "echo \"Hello World\"")
    lsp.notifyFileChanged("/test.nim", "echo \"Hello World!\"")

    # Close the file
    lsp.notifyFileClosed("/test.nim")

    # Should handle all operations gracefully

  test "Async message processing":
    proc testAsync() {.async.} =
      let client = newLSPClient()

      # Start async processing
      asyncSpawn client.start()

      # Queue a message
      let id = client.initialize()
      check id > 0

      # Give it some time to process
      await sleepAsync(chronos.milliseconds(100))

      # Stop the client
      client.stop()
      await client.waitForStop()

    waitFor testAsync()

  test "Thread safety - concurrent operations":
    let runner = newLSPAsyncRunner()
    runner.start()

    # Simulate concurrent operations
    for i in 0 .. 10:
      discard runner.requestHover("file:///test.nim", i, i)
      sleep(10)

    # Check responses
    let responses = runner.checkResponses()

    runner.stop()

  test "Error handling - invalid hover request":
    let runner = newLSPAsyncRunner()
    runner.start()

    # Request hover with invalid coordinates
    discard runner.requestHover("", -1, -1)

    runner.stop()

  test "Memory safety - large message queue":
    let client = newLSPClient()

    # Queue many messages
    for i in 0 .. 1000:
      client.queueRequest(
        LSPMessage(
          kind: lmkHover, uri: "file:///test" & $i & ".nim", line: i, character: i
        )
      )

    # Should not crash or leak memory

  test "Cleanup and resource management":
    # Create and destroy multiple instances
    for i in 0 .. 5:
      let runner = newLSPAsyncRunner()
      runner.start()
      sleep(50)
      runner.stop()

    # Should not leak resources

echo "Running LSP async implementation tests..."

# Additional integration test
proc integrationTest() =
  echo "\nIntegration Test: Simulating editor usage"

  var lspState = newLSPUIState()

  # Initialize LSP (would connect to real server in production)
  echo "Initializing LSP..."
  # lspState.initialize()  # Commented out as it requires real LSP server

  # Simulate file open
  echo "Opening file..."
  lspState.integration.notifyFileOpened(
    "/test.nim",
    """
import std/strutils

proc hello(name: string) =
  echo "Hello, " & name

hello("World")
""",
  )

  # Simulate hover requests at different positions
  echo "Simulating hover requests..."
  for line in 0 .. 5:
    for col in [0, 5, 10]:
      lspState.updateHover("/test.nim", line, col)
      sleep(50)
      lspState.checkUpdates()

      if lspState.hasHover():
        echo "  Hover at ",
          line,
          ":",
          col,
          " -> ",
          lspState.getHoverContent()[0 .. min(30, lspState.getHoverContent().len - 1)]

  # Simulate file changes
  echo "Simulating file changes..."
  lspState.integration.notifyFileChanged(
    "/test.nim",
    """
import std/strutils

proc hello(name: string): string =
  result = "Hello, " & name

echo hello("Nim")
""",
  )
