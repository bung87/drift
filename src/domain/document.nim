## Document Domain Model
## Pure business logic for document operations without external dependencies

import std/[strutils, options]
import results
import ../shared/types
import ../shared/errors

# Document creation
proc newDocument*(
    content: string = "", metadata: DocumentMetadata = DocumentMetadata()
): Document =
  let lines =
    if content.len == 0:
      @[""]
    else:
      content.splitLines()
  Document(
    lines: lines,
    metadata: metadata,
    undoStack: @[],
    redoStack: @[],
    maxUndoSize: 1000,
    isModified: false,
    version: 0,
  )

proc newDocumentFromLines*(
    lines: seq[string], metadata: DocumentMetadata = DocumentMetadata()
): Document =
  Document(
    lines: lines,
    metadata: metadata,
    undoStack: @[],
    redoStack: @[],
    maxUndoSize: 1000,
    isModified: false,
    version: 0,
  )

# Document queries
proc lineCount*(doc: Document): int =
  doc.lines.len

proc totalLength*(doc: Document): int =
  var total = 0
  for line in doc.lines:
    total += line.len
  total + (doc.lines.len - 1) * doc.metadata.lineEnding.len

proc isEmpty*(doc: Document): bool =
  doc.lines.len == 1 and doc.lines[0].len == 0

proc isValidPosition*(doc: Document, pos: CursorPos): bool =
  if pos.line < 0 or pos.line >= doc.lines.len:
    return false
  if pos.col < 0 or pos.col > doc.lines[pos.line].len:
    return false
  return true

proc lineLength*(doc: Document, lineNum: int): int =
  if lineNum >= 0 and lineNum < doc.lines.len:
    doc.lines[lineNum].len
  else:
    0

proc getLine*(doc: Document, lineNum: int): Result[string, EditorError] =
  if lineNum < 0 or lineNum >= doc.lines.len:
    return err(newEditorError("INVALID_LINE", "Line number out of bounds"))
  ok(doc.lines[lineNum])

proc getText*(
    doc: Document, start: CursorPos, finish: CursorPos
): Result[string, EditorError] =
  if not doc.isValidPosition(start) or not doc.isValidPosition(finish):
    return err(newEditorError("INVALID_POSITION", "Invalid position"))

  let normalizedStart = min(start, finish)
  let normalizedEnd = max(start, finish)

  if normalizedStart.line == normalizedEnd.line:
    # Single line selection
    let line = doc.lines[normalizedStart.line]
    return ok(line[normalizedStart.col ..< normalizedEnd.col])

  # Multi-line selection
  var textResult = ""
  for lineNum in normalizedStart.line .. normalizedEnd.line:
    if lineNum == normalizedStart.line:
      # First line - from start column to end
      textResult.add(doc.lines[lineNum][normalizedStart.col .. ^1])
    elif lineNum == normalizedEnd.line:
      # Last line - from beginning to end column
      textResult.add(doc.lines[lineNum][0 ..< normalizedEnd.col])
    else:
      # Middle lines - entire line
      textResult.add(doc.lines[lineNum])

    # Add line ending except for the last line
    if lineNum < normalizedEnd.line:
      textResult.add(doc.metadata.lineEnding)

  ok(textResult)

proc getFullText*(doc: Document): string =
  doc.lines.join(doc.metadata.lineEnding)

# Document mutations
proc pushUndo*(doc: Document, edit: TextEdit) =
  doc.undoStack.add(edit)
  if doc.undoStack.len > doc.maxUndoSize:
    doc.undoStack.delete(0)
  doc.redoStack.setLen(0) # Clear redo stack on new edit
  doc.isModified = true
  inc doc.version

proc insertText*(
    doc: Document, pos: CursorPos, text: string
): Result[CursorPos, EditorError] =
  if not doc.isValidPosition(pos):
    return err(newEditorError("INVALID_POSITION", "Invalid position"))

  let lines = text.splitLines()
  let originalText = doc.lines[pos.line]

  # Create undo operation
  let undoEdit =
    TextEdit(operation: eoDelete, position: pos, content: text, previousContent: "")

  if lines.len == 1:
    # Single line insertion
    doc.lines[pos.line] =
      originalText[0 ..< pos.col] & text & originalText[pos.col .. ^1]
    let newPos = CursorPos(line: pos.line, col: pos.col + text.len)
    doc.pushUndo(undoEdit)
    return ok(newPos)
  else:
    # Multi-line insertion
    let firstLine = originalText[0 ..< pos.col] & lines[0]
    let lastLine = lines[^1] & originalText[pos.col .. ^1]

    # Replace current line with first line
    doc.lines[pos.line] = firstLine

    # Insert middle lines
    for i in 1 ..< lines.len - 1:
      doc.lines.insert(lines[i], pos.line + i)

    # Insert last line
    doc.lines.insert(lastLine, pos.line + lines.len - 1)

    let newPos = CursorPos(line: pos.line + lines.len - 1, col: lines[^1].len)
    doc.pushUndo(undoEdit)
    return ok(newPos)

proc deleteText*(
    doc: Document, start: CursorPos, finish: CursorPos
): Result[string, EditorError] =
  if not doc.isValidPosition(start) or not doc.isValidPosition(finish):
    return err(newEditorError("INVALID_POSITION", "Invalid position"))

  let normalizedStart = min(start, finish)
  let normalizedEnd = max(start, finish)

  # Get the text that will be deleted for undo
  let deletedText = doc.getText(normalizedStart, normalizedEnd).get()

  # Create undo operation
  let undoEdit = TextEdit(
    operation: eoInsert,
    position: normalizedStart,
    content: deletedText,
    previousContent: "",
  )

  if normalizedStart.line == normalizedEnd.line:
    # Single line deletion
    let line = doc.lines[normalizedStart.line]
    doc.lines[normalizedStart.line] =
      line[0 ..< normalizedStart.col] & line[normalizedEnd.col .. ^1]
  else:
    # Multi-line deletion
    let firstLine = doc.lines[normalizedStart.line][0 ..< normalizedStart.col]
    let lastLine = doc.lines[normalizedEnd.line][normalizedEnd.col .. ^1]

    # Remove lines in between
    for i in countdown(normalizedEnd.line, normalizedStart.line + 1):
      doc.lines.delete(i)

    # Combine first and last line parts
    doc.lines[normalizedStart.line] = firstLine & lastLine

  doc.pushUndo(undoEdit)
  ok(deletedText)

proc replaceText*(
    doc: Document, start: CursorPos, finish: CursorPos, newText: string
): Result[CursorPos, EditorError] =
  let deletedText = doc.deleteText(start, finish)
  if deletedText.isErr:
    return err(deletedText.error)

  # Insert new text at start position
  doc.insertText(start, newText)

# Line operations
proc insertLine*(
    doc: Document, lineNum: int, content: string = ""
): Result[void, EditorError] =
  if lineNum < 0 or lineNum > doc.lines.len:
    return err(newEditorError("INVALID_LINE", "Invalid line number"))

  doc.lines.insert(content, lineNum)

  let undoEdit = TextEdit(
    operation: eoDelete,
    position: CursorPos(line: lineNum, col: 0),
    content: content & doc.metadata.lineEnding,
    previousContent: "",
  )
  doc.pushUndo(undoEdit)
  Result[void, EditorError].ok()

proc deleteLine*(doc: Document, lineNum: int): Result[string, EditorError] =
  if lineNum < 0 or lineNum >= doc.lines.len:
    return err(newEditorError("INVALID_LINE", "Invalid line number"))

  if doc.lines.len == 1:
    # Don't delete the last line, just clear it
    let content = doc.lines[0]
    doc.lines[0] = ""

    let undoEdit = TextEdit(
      operation: eoInsert,
      position: CursorPos(line: 0, col: 0),
      content: content,
      previousContent: "",
    )
    doc.pushUndo(undoEdit)
    return ok(content)

  let deletedLine = doc.lines[lineNum]
  doc.lines.delete(lineNum)

  let undoEdit = TextEdit(
    operation: eoInsert,
    position: CursorPos(line: lineNum, col: 0),
    content: deletedLine & doc.metadata.lineEnding,
    previousContent: "",
  )
  doc.pushUndo(undoEdit)
  ok(deletedLine)

# Undo/Redo operations
proc canUndo*(doc: Document): bool =
  doc.undoStack.len > 0

proc canRedo*(doc: Document): bool =
  doc.redoStack.len > 0

proc undo*(doc: Document): Result[CursorPos, EditorError] =
  if not doc.canUndo():
    return err(newEditorError("NO_UNDO", "Nothing to undo"))

  let edit = doc.undoStack.pop()
  doc.redoStack.add(edit)

  case edit.operation
  of eoInsert:
    discard doc.insertText(edit.position, edit.content)
    ok(CursorPos(line: edit.position.line, col: edit.position.col + edit.content.len))
  of eoDelete:
    let endPos =
      CursorPos(line: edit.position.line, col: edit.position.col + edit.content.len)
    discard doc.deleteText(edit.position, endPos)
    ok(edit.position)
  of eoReplace:
    discard doc.replaceText(edit.position, edit.position, edit.previousContent)
    ok(edit.position)

proc redo*(doc: Document): Result[CursorPos, EditorError] =
  if not doc.canRedo():
    return err(newEditorError("NO_REDO", "Nothing to redo"))

  let edit = doc.redoStack.pop()
  doc.undoStack.add(edit)

  # Perform the original operation
  case edit.operation
  of eoInsert:
    discard doc.insertText(edit.position, edit.content)
    ok(CursorPos(line: edit.position.line, col: edit.position.col + edit.content.len))
  of eoDelete:
    let endPos =
      CursorPos(line: edit.position.line, col: edit.position.col + edit.content.len)
    discard doc.deleteText(edit.position, endPos)
    ok(edit.position)
  of eoReplace:
    discard doc.replaceText(edit.position, edit.position, edit.content)
    ok(edit.position)

# Text transformation utilities
proc normalizeLineEndings*(doc: Document, newLineEnding: string = "\n") =
  doc.metadata.lineEnding = newLineEnding
  doc.isModified = true
  inc doc.version

proc convertTabsToSpaces*(doc: Document) =
  let tabReplacement = " ".repeat(doc.metadata.tabSize)
  for i in 0 ..< doc.lines.len:
    doc.lines[i] = doc.lines[i].replace("\t", tabReplacement)
  doc.metadata.useSpaces = true
  doc.isModified = true
  inc doc.version

proc convertSpacesToTabs*(doc: Document) =
  let spacePattern = " ".repeat(doc.metadata.tabSize)
  for i in 0 ..< doc.lines.len:
    doc.lines[i] = doc.lines[i].replace(spacePattern, "\t")
  doc.metadata.useSpaces = false
  doc.isModified = true
  inc doc.version

# Search utilities
proc findText*(
    doc: Document,
    pattern: string,
    startPos: CursorPos = CursorPos(line: 0, col: 0),
    caseSensitive: bool = false,
): Option[CursorPos] =
  let searchPattern =
    if caseSensitive:
      pattern
    else:
      pattern.toLower()

  for lineNum in startPos.line ..< doc.lines.len:
    let startCol = if lineNum == startPos.line: startPos.col else: 0
    let line =
      if caseSensitive:
        doc.lines[lineNum]
      else:
        doc.lines[lineNum].toLower()

    let foundCol = line.find(searchPattern, startCol)
    if foundCol >= 0:
      return some(CursorPos(line: lineNum, col: foundCol))

  none(CursorPos)

proc replaceAll*(
    doc: Document, pattern: string, replacement: string, caseSensitive: bool = false
): int =
  var replacementCount = 0
  let searchPattern =
    if caseSensitive:
      pattern
    else:
      pattern.toLower()

  for lineNum in 0 ..< doc.lines.len:
    let line = doc.lines[lineNum]
    let lowerLine =
      if caseSensitive:
        line
      else:
        line.toLower()

    var newLine = ""
    var pos = 0

    while true:
      let foundPos = lowerLine.find(searchPattern, pos)
      if foundPos == -1:
        newLine.add(line[pos .. ^1])
        break

      newLine.add(line[pos ..< foundPos])
      newLine.add(replacement)
      pos = foundPos + pattern.len
      inc replacementCount

    if newLine != line:
      doc.lines[lineNum] = newLine

  if replacementCount > 0:
    doc.isModified = true
    inc doc.version

  replacementCount

# Document validation
proc validate*(doc: Document): Result[void, EditorError] =
  if doc.lines.len == 0:
    return err(newEditorError("EMPTY_DOCUMENT", "Document cannot be empty"))

  for i, line in doc.lines:
    if '\0' in line:
      return err(newEditorError("INVALID_CONTENT", "Document contains null characters"))

  Result[void, EditorError].ok()

# Document statistics
proc getStats*(doc: Document): DocumentStats =
  var stats = DocumentStats()
  stats.lineCount = doc.lines.len

  for line in doc.lines:
    stats.characterCount += line.len
    for c in line:
      if not c.isSpaceAscii():
        inc stats.nonWhitespaceCharCount

    # Simple word counting (split by whitespace)
    let words = line.splitWhitespace()
    stats.wordCount += words.len

  # Add line endings to character count
  stats.characterCount += (doc.lines.len - 1) * doc.metadata.lineEnding.len

  stats
