## Test file to verify mouse click and cursor positioning fixes
## 
## Issues that were fixed:
## 1. Single clicks don't work - The cursor doesn't move when clicking
## 2. Cursor blink stuck at beginning - The cursor always appears at the start of the file
##
## Expected behavior after fixes:
## - Mouse clicks should position the cursor at the clicked location
## - Cursor should blink at the correct position
## - Text editor should be focused and ready for input

proc testFunction() =
  echo "This is a test function"
  let x = 42
  let y = "hello world"
  
  if x > 0:
    echo "x is positive"
  else:
    echo "x is not positive"

proc anotherFunction(param: string): int =
  result = param.len * 2

when isMainModule:
  testFunction()
  let result = anotherFunction("test")
  echo "Result: ", result