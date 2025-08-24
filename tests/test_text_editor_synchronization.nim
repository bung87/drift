## Test text editor synchronization between component and service
## Tests for task 5: Fix basic text editing operations synchronization

import std/[unittest, options, times]
import ../src/services/editor_service
import ../src/shared/[types]
import ../src/infrastructure/[filesystem/file_manager, rendering/theme]
import ../src/domain/document

# Test suite for editor service synchronization
suite "Editor Service Synchronization Tests":
  var
    editorService: EditorService
    fileManager: FileManager
    theme: Theme

  setup:
    # Initialize dependencies
    fileManager = newFileManager()
    theme = Theme()  # Use default theme constructor
    
    # Create services
    editorService = newEditorService(fileManager, theme)
    
    # Set editor service to insert mode for text operations
    editorService.mode = emInsert
    
    # Create a test document
    let testContent = "Hello World\nSecond Line\nThird Line"
    let metadata = DocumentMetadata(
      language: "plaintext",
      encoding: "utf-8",
      tabSize: 4,
      useSpaces: true,
      lineEnding: "\n"
    )
    let document = newDocument(testContent, metadata)
    editorService.document = document

  test "insertText operation works correctly":
    # Set initial cursor position
    editorService.cursor = CursorPos(line: 0, col: 5)
    
    # Insert text
    let insertResult = editorService.insertText(" Test")
    
    # Check that operation succeeded
    check insertResult.isOk
    check editorService.cursor.col == 10  # 5 + 5 characters inserted
    
    # Verify document content was updated
    let lineResult = editorService.document.getLine(0)
    check lineResult.isOk
    check lineResult.get() == "Hello Test World"

  test "deleteSelection operation works correctly":
    # Set cursor and create selection
    editorService.cursor = CursorPos(line: 0, col: 11)
    editorService.selection = Selection(
      start: CursorPos(line: 0, col: 6),
      finish: CursorPos(line: 0, col: 11),
      active: true
    )
    
    # Delete selection
    let deleteResult = editorService.deleteSelection()
    
    # Check that operation succeeded
    check deleteResult.isOk
    check editorService.cursor.col == 6  # Cursor moved to selection start
    check not editorService.selection.active
    
    # Verify document content
    let lineResult = editorService.document.getLine(0)
    check lineResult.isOk
    check lineResult.get() == "Hello "

  test "deleteChar operation works correctly":
    # Set cursor position
    editorService.cursor = CursorPos(line: 0, col: 5)
    
    # Delete character backward (backspace)
    let deleteResult = editorService.deleteChar(forward = false)
    
    # Check that operation succeeded
    check deleteResult.isOk
    check editorService.cursor.col == 4  # Moved back one position
    
    # Verify document content
    let lineResult = editorService.document.getLine(0)
    check lineResult.isOk
    check lineResult.get() == "Hell World"

  test "insertNewline operation works correctly":
    # Set cursor position
    editorService.cursor = CursorPos(line: 0, col: 5)
    
    # Insert newline
    let insertResult = editorService.insertNewline()
    
    # Check that operation succeeded
    check insertResult.isOk
    check editorService.cursor.line == 1  # Moved to next line
    check editorService.cursor.col == 0   # At start of new line
    
    # Verify document content
    let line0Result = editorService.document.getLine(0)
    let line1Result = editorService.document.getLine(1)
    check line0Result.isOk
    check line1Result.isOk
    check line0Result.get() == "Hello"
    check line1Result.get() == " World"

  test "error handling for invalid mode":
    # Set service to normal mode (not insert mode)
    editorService.mode = emNormal
    
    # Try to insert text
    let insertResult = editorService.insertText("test")
    
    # Check that operation failed with appropriate error
    check insertResult.isErr
    check insertResult.error.code == "INVALID_MODE"
    
    # Document should be unchanged
    let lineResult = editorService.document.getLine(0)
    check lineResult.isOk
    check lineResult.get() == "Hello World"  # Original content

  test "cursor position validation":
    # Test valid cursor position
    let validPos = CursorPos(line: 0, col: 5)
    check editorService.document.isValidPosition(validPos)
    
    # Test invalid cursor position (beyond document)
    let invalidPos = CursorPos(line: 10, col: 0)
    check not editorService.document.isValidPosition(invalidPos)
    
    # Test invalid column position
    let invalidCol = CursorPos(line: 0, col: 100)
    check not editorService.document.isValidPosition(invalidCol)