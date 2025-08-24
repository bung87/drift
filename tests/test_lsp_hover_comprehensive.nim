## Comprehensive LSP Hover Test with Real Nim File
## Tests the complete flow: initialization, document opening, and hover functionality

import std/[os, times, options, strutils]
import src/lsp_thread_wrapper

proc createTestNimFile(): string =
  ## Create a test Nim file with various symbols to hover over
  let testFile = getCurrentDir() / "test_hover_comprehensive.nim"
  let content = """
# Test file for LSP hover functionality
import std/[strutils, sequtils, tables]

type
  Person* = object
    name*: string
    age*: int
    email*: string

  Company = object
    name: string
    employees: seq[Person]

proc newPerson*(name: string, age: int, email: string): Person =
  ## Creates a new Person instance
  ## 
  ## Args:
  ##   name: The person's full name
  ##   age: The person's age in years  
  ##   email: The person's email address
  result = Person(name: name, age: age, email: email)

proc addEmployee*(company: var Company, person: Person) =
  ## Adds an employee to the company
  company.employees.add(person)

proc getEmployeeCount*(company: Company): int =
  ## Returns the number of employees in the company
  return company.employees.len

proc findEmployeeByName*(company: Company, searchName: string): Option[Person] =
  ## Finds an employee by name (case-insensitive)
  for employee in company.employees:
    if employee.name.toLowerAscii() == searchName.toLowerAscii():
      return some(employee)
  return none(Person)

# Example usage
when isMainModule:
  var myCompany = Company(name: "Tech Corp", employees: @[])
  
  let john = newPerson("John Doe", 30, "john@example.com")
  let jane = newPerson("Jane Smith", 25, "jane@example.com")
  
  myCompany.addEmployee(john)
  myCompany.addEmployee(jane)
  
  echo "Company: ", myCompany.name
  echo "Employee count: ", myCompany.getEmployeeCount()
  
  let foundEmployee = myCompany.findEmployeeByName("john doe")
  if foundEmployee.isSome:
    let emp = foundEmployee.get()
    echo "Found: ", emp.name, " (", emp.age, ")"
"""
  
  writeFile(testFile, content)
  return testFile

proc testCompleteHoverFlow() =
  echo "=== Comprehensive LSP Hover Test ==="
  echo ""
  
  # Create test file
  let testFile = createTestNimFile()
  defer:
    if fileExists(testFile):
      removeFile(testFile)
  
  echo "Created test file: ", testFile
  echo "File size: ", getFileSize(testFile), " bytes"
  echo ""
  
  # Create and initialize LSP wrapper
  echo "Step 1: Creating LSP wrapper..."
  let wrapper = newLSPWrapper()
  
  echo "Step 2: Initializing LSP with nim language..."
  wrapper.initializeLSP("nim")
  
  # Wait for initialization with progress indication
  echo "Step 3: Waiting for LSP initialization..."
  let initStartTime = getTime()
  var initProgress = 0
  while (getTime() - initStartTime).inSeconds < 20:  # 20 second timeout
    sleep(500)
    wrapper.pollLSPResponses()
    
    inc initProgress
    if initProgress mod 4 == 0:
      echo "  Waiting for initialization... (", (getTime() - initStartTime).inSeconds.int, "s)"
    
    if wrapper.isInitialized:
      echo "✓ LSP initialized successfully!"
      echo "  Status: ", wrapper.getLSPStatus()
      break
      
    let error = wrapper.getLastError()
    if error.len > 0:
      echo "✗ LSP initialization failed: ", error
      return
  
  if not wrapper.isInitialized:
    echo "✗ LSP initialization timed out after 20 seconds"
    echo "  Final status: ", wrapper.getLSPStatus()
    return
  
  # Read file content for document opening
  echo ""
  echo "Step 4: Opening document with LSP..."
  let fileContent = readFile(testFile)
  let fileUri = "file://" & testFile
  
  wrapper.notifyDocumentOpen(fileUri, fileContent, "nim")
  echo "✓ Document open notification sent"
  
  # Wait a moment for document to be processed
  sleep(1000)
  wrapper.pollLSPResponses()
  
  # Test hover on various symbols
  echo ""
  echo "Step 5: Testing hover on various symbols..."
  
  # Test cases: (line, column, expected_symbol)
  let hoverTests = [
    (4, 2, "Person"),           # Type definition
    (15, 5, "newPerson"),       # Function definition  
    (21, 5, "addEmployee"),     # Function definition
    (25, 5, "getEmployeeCount"), # Function definition
    (6, 4, "name"),             # Field in type
    (7, 4, "age"),              # Field in type
    (41, 10, "newPerson"),      # Function call
    (45, 13, "addEmployee"),    # Method call
    (48, 27, "getEmployeeCount"), # Method call
  ]
  
  for i, (line, col, expectedSymbol) in hoverTests:
    echo ""
    echo "Test ", i+1, ": Hovering over '", expectedSymbol, "' at line ", line+1, ", column ", col+1
    
    # Clear previous hover response
    wrapper.clearHoverResponse()
    
    # Request hover
    wrapper.requestHover(fileUri, line, col)
    
    # Wait for hover response
    echo "  Waiting for hover response..."
    let hoverStartTime = getTime()
    var gotResponse = false
    
    while (getTime() - hoverStartTime).inSeconds < 10:  # 10 second timeout
      sleep(200)
      wrapper.pollLSPResponses()
      
      let hoverResponse = wrapper.getLastHoverResponse()
      if hoverResponse.isSome:
        let content = hoverResponse.get()
        echo "  ✓ Hover response received (", content.len, " chars)"
        if content.len > 100:
          echo "    Content preview: ", content[0..99], "..."
        else:
          echo "    Content: ", content
        gotResponse = true
        break
        
      let error = wrapper.getLastError()
      if error.len > 0 and ("hover" in error.toLowerAscii() or "not found" in error.toLowerAscii()):
        echo "  ✗ Hover failed: ", error
        gotResponse = true
        break
    
    if not gotResponse:
      echo "  ? Hover request timed out or no clear response"
      echo "    Last error: ", wrapper.getLastError()
  
  echo ""
  echo "Step 6: Testing hover on invalid positions..."
  
  # Test hover on invalid positions
  let invalidTests = [
    (100, 0, "beyond file end"),
    (0, 100, "beyond line end"),
    (2, 0, "empty line"),
  ]
  
  for i, (line, col, description) in invalidTests:
    echo ""
    echo "Invalid test ", i+1, ": ", description, " (line ", line+1, ", col ", col+1, ")"
    wrapper.clearHoverResponse()
    wrapper.requestHover(fileUri, line, col)
    
    sleep(1000)
    wrapper.pollLSPResponses()
    
    let hoverResponse = wrapper.getLastHoverResponse()
    if hoverResponse.isSome and hoverResponse.get().len > 0:
      echo "  ? Unexpected hover response: ", hoverResponse.get()
    else:
      echo "  ✓ No hover response (as expected)"
  
  echo ""
  echo "Step 7: Rapid hover requests test..."
  
  # Test rapid hover requests
  wrapper.clearHoverResponse()
  for i in 0..4:
    wrapper.requestHover(fileUri, 4, 2)  # Person type
  
  sleep(2000)
  wrapper.pollLSPResponses()
  
  let finalHover = wrapper.getLastHoverResponse()
  if finalHover.isSome:
    echo "✓ Rapid requests handled, final response: ", finalHover.get().len, " chars"
  else:
    echo "? No response to rapid requests"
  
  echo ""
  echo "Step 8: Cleanup..."
  
  # Close document
  wrapper.notifyDocumentClose(fileUri)
  sleep(500)
  wrapper.pollLSPResponses()
  echo "✓ Document closed"
  
  # Shutdown LSP
  wrapper.shutdownLSP()
  sleep(1000)
  wrapper.pollLSPResponses()
  echo "✓ LSP shutdown completed"
  
  echo ""
  echo "=== Test Complete ==="

proc main() =
  echo "LSP Hover Comprehensive Test"
  echo "============================"
  echo "This test creates a real Nim file and tests hover functionality"
  echo "on various symbols including types, functions, and variables."
  echo ""
  
  # Check if nimlsp is available
  let nimlspCheck = gorgeEx("which nimlsp")
  if nimlspCheck.exitCode != 0:
    echo "WARNING: nimlsp not found in PATH"
    echo "Make sure you have nimlsp installed: nimble install nimlsp"
    echo ""
  else:
    echo "✓ nimlsp found at: ", nimlspCheck.output.strip()
    echo ""
  
  testCompleteHoverFlow()

if isMainModule:
  main()