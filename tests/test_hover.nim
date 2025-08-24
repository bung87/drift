# Simple test file for hover functionality
proc testFunction(): string =
  ## This is a test function that returns a greeting
  return "Hello, World!"

let testVariable = 42
let greeting = "Welcome to Folx"

# Main test
when isMainModule:
  echo testFunction()
  echo testVariable