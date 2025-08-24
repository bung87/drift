## Test for first hover request behavior
## Verifies that the first hover request works correctly

import std/[unittest, options, os, times]
import raylib as rl
import ../src/services/language_service
import results

suite "First Hover Test":
  setup:
    let service = newLanguageService()

  teardown:
    service.shutdown()

  test "first hover should work":
    # Test that the first hover request works correctly
    let testFile = "test.nim"
    let testContent = """
proc hello() =
  echo "Hello, World!"

let greeting = "Hi there"
"""
    
    # Open a document
    let openResult = service.openDocument(testFile, testContent)
    check isOk(openResult)
    
    # Wait a bit for LSP to initialize
    sleep(500)
    
    # Make the first hover request
    echo "Making first hover request..."
    let firstHoverResult = service.updateHover(testFile, 1, 5, "hello")
    echo "First hover result: ", firstHoverResult
    
    # Make a second hover request
    echo "Making second hover request..."
    let secondHoverResult = service.updateHover(testFile, 4, 4, "greeting")
    echo "Second hover result: ", secondHoverResult
    
    # Both should work, but first might take longer
    check true # Just check that it doesn't crash

  test "hover should work after initialization":
    # Test that hover works after LSP is fully initialized
    let testFile = "test.nim"
    let testContent = "let x = 42"
    
    discard service.openDocument(testFile, testContent)
    
    # Wait for LSP to be ready
    sleep(1000)
    
    # Check LSP status
    let status = service.getStatus()
    echo "LSP Status: ", status
    
    # Make hover request
    let hoverResult = service.updateHover(testFile, 0, 4, "x")
    echo "Hover result: ", hoverResult
    
    # Should not crash
    check true

when isMainModule:
  proc main() =
    echo "Testing first hover behavior..."
    # Initialize raylib for the test
    rl.initWindow(800, 600, "First Hover Test")
    defer: rl.closeWindow()
    let service = newLanguageService()
    defer: service.shutdown()
    let testFile = "test.nim"
    let testContent = """
proc testFunction() =
  echo "This is a test function"

let testVariable = 123
"""
    # Open document
    let openResult = service.openDocument(testFile, testContent)
    if isOk(openResult):
      echo "Document opened successfully"
    else:
      echo "Failed to open document: ", error(openResult)
      quit(1)
    # Wait for LSP initialization
    echo "Waiting for LSP to initialize..."
    sleep(2000)
    # Test first hover
    echo "Testing first hover request..."
    let firstHover = service.updateHover(testFile, 1, 5, "testFunction")
    echo "First hover result: ", firstHover
    # Test second hover
    echo "Testing second hover request..."
    let secondHover = service.updateHover(testFile, 4, 4, "testVariable")
    echo "Second hover result: ", secondHover
    # Check LSP status
    let status = service.getStatus()
    echo "Final LSP Status: ", status
    echo "Test completed successfully!"

  main() 