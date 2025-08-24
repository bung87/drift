## Editor Service
## Coordinates document operations and editor state management

import std/[options, times, os, strutils]
import results
import ../shared/errors
import ../shared/types
import ../domain
import ../infrastructure/rendering/theme
import ../infrastructure/filesystem/file_manager
import ../infrastructure/external/git_client
import ../enhanced_syntax

# Editor service state
type EditorService* = ref object # Core document state
  document*: Document
  selection*: Selection
  multiSelection*: MultiSelection
  selectionHistory*: SelectionHistory

  # Editor state
  cursor*: CursorPos
  viewport*: tuple[startLine: int, endLine: int]

  # File management
  currentFile*: Option[string]
  isModified*: bool
  lastSavedTime*: Option[Time]

  # Syntax highlighting
  syntaxHighlighter*: SyntaxHighlighter

  # Infrastructure dependencies
  fileManager*: FileManager
  gitClient*: Option[GitClient]
  theme*: Theme

  # Settings
  tabSize*: int
  useSpaces*: bool
  autoSave*: bool
  autoSaveInterval*: int # seconds
  showLineNumbers*: bool
  wordWrap*: bool

  # Event callbacks
  onDocumentChanged*: proc(service: EditorService)
  onSelectionChanged*: proc(service: EditorService)
  onModeChanged*: proc(service: EditorService)

# Service creation
proc newEditorService*(fileManager: FileManager, theme: Theme): EditorService =
  let metadata = DocumentMetadata(
    language: "plaintext",
    encoding: "utf-8",
    tabSize: 4,
    useSpaces: true,
    lineEnding: "\n",
  )

  EditorService(
    document: newDocument("", metadata),
    selection: createEmptySelection(CursorPos(line: 0, col: 0)),
    multiSelection: newMultiSelection(),
    selectionHistory: newSelectionHistory(),
    cursor: CursorPos(line: 0, col: 0),
    viewport: (startLine: 0, endLine: 50),
    currentFile: none(string),
    isModified: false,
    lastSavedTime: none(Time),
    syntaxHighlighter: newSyntaxHighlighter(langPlainText),
    fileManager: fileManager,
    gitClient: none(GitClient),
    theme: theme,
    tabSize: 4,
    useSpaces: true,
    autoSave: false,
    autoSaveInterval: 300,
    showLineNumbers: true,
    wordWrap: false,
    onDocumentChanged: nil,
    onSelectionChanged: nil,
    onModeChanged: nil,
  )

# Document operations
proc openFile*(service: EditorService, filePath: string): Result[void, EditorError] =
  let readResult = service.fileManager.readFile(filePath)
  if readResult.isErr:
    return err(readResult.error)

  let content = readResult.get()
  let detectedLang = detectLanguage(filePath)
  let metadata = DocumentMetadata(
    language: $detectedLang,
    encoding: "utf-8",
    tabSize: service.tabSize,
    useSpaces: service.useSpaces,
    lineEnding: "\n",
  )

  service.document = newDocument(content, metadata)
  service.currentFile = some(filePath)
  service.isModified = false
  service.lastSavedTime = some(getTime())

  # Reset editor state
  service.cursor = CursorPos(line: 0, col: 0)
  service.selection = createEmptySelection(service.cursor)
  service.multiSelection = newMultiSelection()

  # Setup syntax highlighting
  service.syntaxHighlighter = newSyntaxHighlighter(detectedLang)

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc newFile*(service: EditorService): Result[void, EditorError] =
  echo "[DEBUG] newFile called - creating new empty document"
  let metadata = DocumentMetadata(
    language: "plaintext",
    encoding: "utf-8",
    tabSize: service.tabSize,
    useSpaces: service.useSpaces,
    lineEnding: "\n",
  )

  # Ensure document has at least one line to avoid empty state issues
  service.document = newDocument("\n", metadata)
  service.currentFile = none(string)
  service.isModified = false
  service.lastSavedTime = none(Time)

  # Reset editor state
  service.cursor = CursorPos(line: 0, col: 0)
  service.selection = createEmptySelection(service.cursor)
  service.multiSelection = newMultiSelection()

  # Set plaintext syntax
  service.syntaxHighlighter = newSyntaxHighlighter(langPlainText)

  echo "[DEBUG] newFile: document created with " & $service.document.lineCount() & " lines"
  echo "[DEBUG] newFile: initial content='" & service.document.getFullText() & "'"

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc saveFile*(
    service: EditorService, filePath: string = ""
): Result[void, EditorError] =
  echo "[DEBUG] EditorService.saveFile called filePath='" & filePath & "' currentFileSet=" & $service.currentFile.isSome & " isModified=" & $service.isModified
  let targetPath =
    if filePath.len > 0:
      filePath
    elif service.currentFile.isSome:
      service.currentFile.get()
    else:
      return err(EditorError(msg: "No file path specified", code: "NO_FILE_PATH"))

  let content = service.document.getFullText()
  echo "[DEBUG] saveFile: content length=" & $content.len & " content='" & content & "'"
  
  if content.len == 0:
    echo "[DEBUG] saveFile: WARNING - saving empty file"
  
  echo "[DEBUG] saveFile: writing to path='" & targetPath & "'"
  let writeResult = service.fileManager.writeFile(targetPath, content)
  if writeResult.isErr:
    echo "[DEBUG] saveFile: ERROR - " & writeResult.error.msg
    return err(writeResult.error)

  echo "[DEBUG] saveFile: SUCCESS - file saved"
  service.currentFile = some(targetPath)
  service.isModified = false
  service.lastSavedTime = some(getTime())
  service.document.isModified = false

  # Update syntax highlighting if needed
  if filePath.len > 0 and filePath != service.currentFile.get(""):
    let detectedLang = detectLanguage(filePath)
    service.syntaxHighlighter = newSyntaxHighlighter(detectedLang)

  ok()

proc closeFile*(service: EditorService): Result[void, EditorError] =
  if service.isModified:
    return err(EditorError(msg: "File has unsaved changes", code: "UNSAVED_CHANGES"))

  let metadata = DocumentMetadata()
  service.document = newDocument("", metadata)
  service.currentFile = none(string)
  service.isModified = false
  service.lastSavedTime = none(Time)

  # Reset editor state
  service.cursor = CursorPos(line: 0, col: 0)
  service.selection = createEmptySelection(service.cursor)
  service.multiSelection = newMultiSelection()

  ok()

# Text editing operations
proc insertText*(service: EditorService, text: string): Result[void, EditorError] =
  let insertResult = service.document.insertText(service.cursor, text)
  if insertResult.isErr:
    return err(insertResult.error)

  service.cursor = insertResult.get()
  service.isModified = true
  service.document.isModified = true

  # Update selection
  service.selection.moveTo(service.cursor)

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc deleteSelection*(service: EditorService): Result[void, EditorError] =
  if types.isEmpty(service.selection):
    return ok() # Nothing to delete

  let deleteResult =
    service.document.deleteText(service.selection.start, service.selection.finish)
  if deleteResult.isErr:
    return err(deleteResult.error)

  service.cursor = service.selection.start
  service.selection.clear()
  service.isModified = true
  service.document.isModified = true

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc deleteChar*(
    service: EditorService, forward: bool = true
): Result[void, EditorError] =
  echo "[DEBUG] deleteChar called, forward=" & $forward & " cursor=" & $service.cursor & " lineCount=" & $service.document.lineCount()
  
  if service.selection.start != service.selection.finish:
    return service.deleteSelection()

  # Check if we have anything to delete
  if not forward:
    # Backspace - check if we're at the beginning of the document
    if service.cursor.line == 0 and service.cursor.col == 0:
      echo "[DEBUG] deleteChar: already at start of document, nothing to delete"
      return ok() # Nothing to delete
    
    # Check if we're at the beginning of a line (need to join with previous line)
    if service.cursor.col == 0 and service.cursor.line > 0:
      # Join with previous line
      let prevLineLength = service.document.lineLength(service.cursor.line - 1)
      let deleteStart = CursorPos(line: service.cursor.line - 1, col: prevLineLength)
      let deleteEnd = CursorPos(line: service.cursor.line, col: 0)
      
      let deleteResult = service.document.deleteText(deleteStart, deleteEnd)
      if deleteResult.isErr:
        return err(deleteResult.error)
      
      service.cursor = deleteStart
      service.isModified = true
      service.document.isModified = true
      
      # Trigger callbacks
      if service.onDocumentChanged != nil:
        service.onDocumentChanged(service)
      
      return ok()

  if forward:
    # Delete forward (Delete key)
    let currentLineLength = service.document.lineLength(service.cursor.line)
    let isLastLine = service.cursor.line == service.document.lineCount() - 1
    if isLastLine and service.cursor.col >= currentLineLength:
      echo "[DEBUG] deleteChar: already at end of document, nothing to delete"
      return ok() # Nothing to delete
    
    let deletePos = CursorPos(line: service.cursor.line, col: service.cursor.col + 1)
    let deleteResult = service.document.deleteText(service.cursor, deletePos)
    if deleteResult.isErr:
      return err(deleteResult.error)
    # Cursor stays at current position for forward delete
  else:
    # Delete backward (Backspace key)
    let deletePos = CursorPos(line: service.cursor.line, col: max(0, service.cursor.col - 1))
    let deleteResult = service.document.deleteText(deletePos, service.cursor)
    if deleteResult.isErr:
      return err(deleteResult.error)
    # Move cursor to the delete position (one character back)
    service.cursor = deletePos

  service.isModified = true
  service.document.isModified = true

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc insertNewline*(service: EditorService): Result[void, EditorError] =
  let insertResult =
    service.document.insertText(service.cursor, service.document.metadata.lineEnding)
  if insertResult.isErr:
    return err(insertResult.error)

  service.cursor = insertResult.get()
  service.isModified = true
  service.document.isModified = true

  # Update selection
  service.selection.moveTo(service.cursor)

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

# Cursor movement
proc moveCursor*(
    service: EditorService, newPos: CursorPos, extendSelection: bool = false
): Result[void, EditorError] =
  if not service.document.isValidPosition(newPos):
    return err(EditorError(msg: "Invalid cursor position", code: "INVALID_POSITION"))

  service.cursor = newPos

  if extendSelection:
    service.selection.extendTo(newPos)
  else:
    service.selection.moveTo(newPos)

  # Trigger callbacks
  if service.onSelectionChanged != nil:
    service.onSelectionChanged(service)

  ok()

proc moveCursorUp*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  if service.cursor.line > 0:
    let newLine = service.cursor.line - 1
    let maxCol = service.document.lineLength(newLine)
    let newPos = CursorPos(line: newLine, col: min(service.cursor.col, maxCol))
    service.moveCursor(newPos, extendSelection)
  else:
    ok()

proc moveCursorDown*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  if service.cursor.line < service.document.lineCount() - 1:
    let newLine = service.cursor.line + 1
    let maxCol = service.document.lineLength(newLine)
    let newPos = CursorPos(line: newLine, col: min(service.cursor.col, maxCol))
    service.moveCursor(newPos, extendSelection)
  else:
    ok()

proc moveCursorLeft*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  if service.cursor.col > 0:
    let newPos = CursorPos(line: service.cursor.line, col: service.cursor.col - 1)
    service.moveCursor(newPos, extendSelection)
  elif service.cursor.line > 0:
    # Move to end of previous line
    let newLine = service.cursor.line - 1
    let newPos = CursorPos(line: newLine, col: service.document.lineLength(newLine))
    service.moveCursor(newPos, extendSelection)
  else:
    ok()

proc moveCursorRight*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  let currentLineLength = service.document.lineLength(service.cursor.line)
  if service.cursor.col < currentLineLength:
    let newPos = CursorPos(line: service.cursor.line, col: service.cursor.col + 1)
    service.moveCursor(newPos, extendSelection)
  elif service.cursor.line < service.document.lineCount() - 1:
    # Move to beginning of next line
    let newPos = CursorPos(line: service.cursor.line + 1, col: 0)
    service.moveCursor(newPos, extendSelection)
  else:
    ok()

proc moveCursorToLineStart*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  let newPos = CursorPos(line: service.cursor.line, col: 0)
  service.moveCursor(newPos, extendSelection)

proc moveCursorToLineEnd*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  let lineLength = service.document.lineLength(service.cursor.line)
  let newPos = CursorPos(line: service.cursor.line, col: lineLength)
  service.moveCursor(newPos, extendSelection)

proc moveCursorToDocumentStart*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  let newPos = CursorPos(line: 0, col: 0)
  service.moveCursor(newPos, extendSelection)

proc moveCursorToDocumentEnd*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  let lastLine = service.document.lineCount() - 1
  let lastCol = service.document.lineLength(lastLine)
  let newPos = CursorPos(line: lastLine, col: lastCol)
  service.moveCursor(newPos, extendSelection)

proc moveCursorLeftByWord*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  if service.document == nil:
    return ok()
  
  var newLine = service.cursor.line
  var newCol = service.cursor.col
  
  # Move left until we find the start of a word
  if newCol > 0:
    let lineResult = service.document.getLine(newLine)
    if lineResult.isOk:
      let line = lineResult.get()
      newCol -= 1
      
      # Skip non-word characters
      while newCol > 0 and not (line[newCol].isAlphaNumeric() or line[newCol] == '_'):
        newCol -= 1
      
      # Skip word characters to find word start
      while newCol > 0 and (line[newCol - 1].isAlphaNumeric() or line[newCol - 1] == '_'):
        newCol -= 1
  elif newLine > 0:
    # Move to end of previous line
    newLine -= 1
    newCol = service.document.lineLength(newLine)
  
  let newPos = CursorPos(line: newLine, col: newCol)
  service.moveCursor(newPos, extendSelection)

proc moveCursorRightByWord*(
    service: EditorService, extendSelection: bool = false
): Result[void, EditorError] =
  if service.document == nil:
    return ok()
  
  var newLine = service.cursor.line
  var newCol = service.cursor.col
  
  let lineResult = service.document.getLine(newLine)
  if lineResult.isOk:
    let line = lineResult.get()
    
    # Skip current word
    while newCol < line.len and (line[newCol].isAlphaNumeric() or line[newCol] == '_'):
      newCol += 1
    
    # Skip non-word characters
    while newCol < line.len and not (line[newCol].isAlphaNumeric() or line[newCol] == '_'):
      newCol += 1
    
    # If we reached end of line, move to next line
    if newCol >= line.len and newLine < service.document.lineCount() - 1:
      newLine += 1
      newCol = 0
  
  let newPos = CursorPos(line: newLine, col: newCol)
  service.moveCursor(newPos, extendSelection)

# Selection operations
proc selectAll*(service: EditorService): Result[void, EditorError] =
  service.selection.selectAll(service.document)
  service.cursor = service.selection.finish

  # Trigger callbacks
  if service.onSelectionChanged != nil:
    service.onSelectionChanged(service)

  ok()

proc selectWord*(service: EditorService): Result[void, EditorError] =
  let selectResult = service.selection.selectWord(service.cursor, service.document)
  if selectResult.isErr:
    return err(selectResult.error)

  service.cursor = service.selection.finish

  # Trigger callbacks
  if service.onSelectionChanged != nil:
    service.onSelectionChanged(service)

  ok()

proc selectLine*(service: EditorService): Result[void, EditorError] =
  let selectResult = service.selection.selectLine(service.cursor.line, service.document)
  if selectResult.isErr:
    return err(selectResult.error)

  service.cursor = service.selection.finish

  # Trigger callbacks
  if service.onSelectionChanged != nil:
    service.onSelectionChanged(service)

  ok()

proc clearSelection*(service: EditorService) =
  service.selection.clear()
  service.multiSelection.clearAll()

  # Trigger callbacks
  if service.onSelectionChanged != nil:
    service.onSelectionChanged(service)

# Undo/Redo operations
proc undo*(service: EditorService): Result[void, EditorError] =
  echo "[DEBUG] undo called"
  let undoResult = service.document.undo()
  if undoResult.isErr:
    return err(undoResult.error)

  service.cursor = undoResult.get()
  service.selection.moveTo(service.cursor)
  service.isModified = service.document.isModified

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc redo*(service: EditorService): Result[void, EditorError] =
  let redoResult = service.document.redo()
  if redoResult.isErr:
    return err(redoResult.error)

  service.cursor = redoResult.get()
  service.selection.moveTo(service.cursor)
  service.isModified = service.document.isModified

  # Trigger callbacks
  if service.onDocumentChanged != nil:
    service.onDocumentChanged(service)

  ok()

proc canUndo*(service: EditorService): bool =
  service.document.canUndo()

proc canRedo*(service: EditorService): bool =
  service.document.canRedo()

# Search and replace
proc findText*(
    service: EditorService, pattern: string, caseSensitive: bool = false
): Option[CursorPos] =
  service.document.findText(pattern, service.cursor, caseSensitive)

proc replaceAll*(
    service: EditorService,
    pattern: string,
    replacement: string,
    caseSensitive: bool = false,
): int =
  let count = service.document.replaceAll(pattern, replacement, caseSensitive)
  if count > 0:
    service.isModified = true
    service.document.isModified = true

    # Trigger callbacks
    if service.onDocumentChanged != nil:
      service.onDocumentChanged(service)

  count

# Syntax highlighting
proc getTokensForLine*(service: EditorService, lineNum: int): seq[enhanced_syntax.Token] =
  if lineNum < 0 or lineNum >= service.document.lineCount():
    return @[]

  let lineResult = service.document.getLine(lineNum)
  if lineResult.isErr:
    return @[]

  let line = lineResult.get()
  service.syntaxHighlighter.tokenize(line)

# Utility functions
proc getSelectedText*(service: EditorService): string =
  if service.selection.start == service.selection.finish:
    return ""

  let textResult = service.selection.getSelectedText(service.document)
  if textResult.isOk:
    textResult.get()
  else:
    ""

proc getCurrentLine*(service: EditorService): string =
  let lineResult = service.document.getLine(service.cursor.line)
  if lineResult.isOk:
    lineResult.get()
  else:
    ""

proc getDocumentStats*(service: EditorService): DocumentStats =
  service.document.getStats()

proc isAtDocumentStart*(service: EditorService): bool =
  service.cursor.line == 0 and service.cursor.col == 0

proc isAtDocumentEnd*(service: EditorService): bool =
  let lastLine = service.document.lineCount() - 1
  let lastCol = service.document.lineLength(lastLine)
  service.cursor.line == lastLine and service.cursor.col == lastCol

proc hasSelection*(service: EditorService): bool =
  service.selection.start != service.selection.finish

proc getFileName*(service: EditorService): string =
  if service.currentFile.isSome:
    splitFile(service.currentFile.get()).name
  else:
    "Untitled"

proc getFilePath*(service: EditorService): string =
  service.currentFile.get("")

# Auto-save functionality
proc shouldAutoSave*(service: EditorService): bool =
  if not service.autoSave or not service.isModified or service.currentFile.isNone:
    return false

  if service.lastSavedTime.isNone:
    return true

  let elapsed = getTime() - service.lastSavedTime.get()
  elapsed.inSeconds >= service.autoSaveInterval

proc performAutoSave*(service: EditorService): Result[void, EditorError] =
  if not service.shouldAutoSave():
    return ok()

  service.saveFile()
