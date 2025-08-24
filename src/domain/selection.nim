## Selection Domain Model
## Pure business logic for text selection operations

import std/[algorithm, options, strutils]
import results
import ../shared/[types, errors]
import document

# Selection creation and validation
proc createSelection*(
    start: CursorPos, finish: CursorPos, active: bool = true
): Selection =
  Selection(start: start, finish: finish, active: active)

proc createEmptySelection*(pos: CursorPos): Selection =
  Selection(start: pos, finish: pos, active: false)

proc validateSelection*(
    selection: Selection, doc: Document
): Result[void, EditorError] =
  if not doc.isValidPosition(selection.start):
    return err(
      EditorError(msg: "Invalid selection start position", code: "INVALID_SELECTION")
    )

  if not doc.isValidPosition(selection.finish):
    return
      err(EditorError(msg: "Invalid selection end position", code: "INVALID_SELECTION"))

  ok()

# Selection queries
proc isValid*(selection: Selection, doc: Document): bool =
  validateSelection(selection, doc).isOk

proc isEmpty*(selection: Selection): bool =
  not selection.active or selection.start == selection.finish

proc isForward*(selection: Selection): bool =
  selection.start <= selection.finish

proc isBackward*(selection: Selection): bool =
  selection.finish < selection.start

proc getDirection*(selection: Selection): int =
  ## Returns 1 for forward, -1 for backward, 0 for empty
  if selection.isEmpty():
    0
  elif selection.isForward():
    1
  else:
    -1

proc getAnchor*(selection: Selection): CursorPos =
  ## Returns the anchor point (start of selection)
  selection.start

proc getCursor*(selection: Selection): CursorPos =
  ## Returns the cursor point (end of selection)
  selection.finish

proc getRange*(selection: Selection): tuple[start: CursorPos, finish: CursorPos] =
  ## Returns normalized range (start <= finish)
  let normalized = selection.normalize()
  (start: normalized.start, finish: normalized.finish)

proc getLength*(selection: Selection, doc: Document): Result[int, EditorError] =
  if selection.isEmpty():
    return ok(0)

  let textResult = doc.getText(selection.start, selection.finish)
  if textResult.isErr:
    return err(textResult.error)

  ok(textResult.get().len)

proc getSelectedText*(
    selection: Selection, doc: Document
): Result[string, EditorError] =
  if selection.isEmpty():
    return ok("")

  doc.getText(selection.start, selection.finish)

# Selection modifications
proc moveTo*(selection: var Selection, pos: CursorPos, keepAnchor: bool = false) =
  if keepAnchor:
    selection.finish = pos
    selection.active = true
  else:
    selection.start = pos
    selection.finish = pos
    selection.active = false

proc extendTo*(selection: var Selection, pos: CursorPos) =
  selection.finish = pos
  selection.active = true

proc shrinkTo*(selection: var Selection, pos: CursorPos) =
  if selection.isEmpty():
    return

  let normalized = selection.normalize()
  if pos < normalized.start:
    selection.start = normalized.start
    selection.finish = normalized.start
  elif pos > normalized.finish:
    selection.start = normalized.finish
    selection.finish = normalized.finish
  else:
    selection.finish = pos

proc clear*(selection: var Selection) =
  selection.active = false
  selection.finish = selection.start

proc selectAll*(selection: var Selection, doc: Document) =
  selection.start = CursorPos(line: 0, col: 0)
  selection.finish =
    CursorPos(line: doc.lineCount() - 1, col: doc.lineLength(doc.lineCount() - 1))
  selection.active = true

# Word and line selection
proc selectWord*(
    selection: var Selection, pos: CursorPos, doc: Document
): Result[void, EditorError] =
  let lineResult = doc.getLine(pos.line)
  if lineResult.isErr:
    return err(lineResult.error)

  let line = lineResult.get()
  if pos.col >= line.len:
    return err(EditorError(msg: "Position beyond line end", code: "INVALID_POSITION"))

  var start = pos.col
  var finish = pos.col

  # Find word boundaries
  if pos.col < line.len and not line[pos.col].isAlphaNumeric():
    # If on non-alphanumeric, select just that character
    finish = start + 1
  else:
    # Find start of word
    while start > 0 and (line[start - 1].isAlphaNumeric() or line[start - 1] == '_'):
      dec start

    # Find end of word
    while finish < line.len and (line[finish].isAlphaNumeric() or line[finish] == '_'):
      inc finish

  selection.start = CursorPos(line: pos.line, col: start)
  selection.finish = CursorPos(line: pos.line, col: finish)
  selection.active = true

  ok()

proc selectLine*(
    selection: var Selection, lineNum: int, doc: Document
): Result[void, EditorError] =
  if lineNum < 0 or lineNum >= doc.lineCount():
    return err(EditorError(msg: "Line number out of bounds", code: "INVALID_LINE"))

  selection.start = CursorPos(line: lineNum, col: 0)
  selection.finish = CursorPos(line: lineNum, col: doc.lineLength(lineNum))
  selection.active = true

  ok()

proc selectLines*(
    selection: var Selection, startLine: int, endLine: int, doc: Document
): Result[void, EditorError] =
  let normalizedStart = min(startLine, endLine)
  let normalizedEnd = max(startLine, endLine)

  if normalizedStart < 0 or normalizedEnd >= doc.lineCount():
    return err(EditorError(msg: "Line numbers out of bounds", code: "INVALID_RANGE"))

  selection.start = CursorPos(line: normalizedStart, col: 0)
  selection.finish = CursorPos(line: normalizedEnd, col: doc.lineLength(normalizedEnd))
  selection.active = true

  ok()

# Selection expansion/contraction
proc expandToWord*(selection: var Selection, doc: Document): Result[void, EditorError] =
  if selection.isEmpty():
    return selectWord(selection, selection.start, doc)

  # Expand both ends to word boundaries
  let startLineResult = doc.getLine(selection.start.line)
  let endLineResult = doc.getLine(selection.finish.line)

  if startLineResult.isErr:
    return err(startLineResult.error)
  if endLineResult.isErr:
    return err(endLineResult.error)

  let startLine = startLineResult.get()
  let endLine = endLineResult.get()

  # Expand start to word boundary
  var newStart = selection.start.col
  while newStart > 0 and
      (startLine[newStart - 1].isAlphaNumeric() or startLine[newStart - 1] == '_'):
    dec newStart

  # Expand end to word boundary
  var newEnd = selection.finish.col
  while newEnd < endLine.len and
      (endLine[newEnd].isAlphaNumeric() or endLine[newEnd] == '_'):
    inc newEnd

  selection.start.col = newStart
  selection.finish.col = newEnd

  ok()

proc expandToLine*(selection: var Selection, doc: Document): Result[void, EditorError] =
  if selection.isEmpty():
    return selectLine(selection, selection.start.line, doc)

  let normalized = selection.normalize()
  selection.start = CursorPos(line: normalized.start.line, col: 0)
  selection.finish =
    CursorPos(line: normalized.finish.line, col: doc.lineLength(normalized.finish.line))

  ok()

# Multiple selections support
type MultiSelection* = object
  selections*: seq[Selection]
  primary*: int # Index of primary selection

proc newMultiSelection*(): MultiSelection =
  MultiSelection(selections: @[], primary: -1)

proc newMultiSelection*(primary: Selection): MultiSelection =
  MultiSelection(selections: @[primary], primary: 0)

proc addSelection*(multi: var MultiSelection, selection: Selection) =
  multi.selections.add(selection)
  if multi.primary == -1:
    multi.primary = 0

proc removeSelection*(multi: var MultiSelection, index: int) =
  if index >= 0 and index < multi.selections.len:
    multi.selections.delete(index)
    if multi.primary >= multi.selections.len:
      multi.primary = multi.selections.len - 1
    if multi.selections.len == 0:
      multi.primary = -1

proc getPrimarySelection*(multi: MultiSelection): Option[Selection] =
  if multi.primary >= 0 and multi.primary < multi.selections.len:
    some(multi.selections[multi.primary])
  else:
    none(Selection)

proc getAllSelections*(multi: MultiSelection): seq[Selection] =
  multi.selections

proc hasSelections*(multi: MultiSelection): bool =
  multi.selections.len > 0

proc selectionCount*(multi: MultiSelection): int =
  multi.selections.len

proc clearAll*(multi: var MultiSelection) =
  multi.selections.setLen(0)
  multi.primary = -1

# Selection merging and overlap detection
proc overlaps*(a, b: Selection): bool =
  if a.isEmpty() or b.isEmpty():
    return false

  let aNorm = a.normalize()
  let bNorm = b.normalize()

  not (aNorm.finish < bNorm.start or bNorm.finish < aNorm.start)

proc merge*(a, b: Selection): Selection =
  if a.isEmpty():
    return b
  if b.isEmpty():
    return a

  let aNorm = a.normalize()
  let bNorm = b.normalize()

  let newStart = min(aNorm.start, bNorm.start)
  let newEnd = max(aNorm.finish, bNorm.finish)

  Selection(start: newStart, finish: newEnd, active: true)

proc mergeOverlapping*(multi: var MultiSelection) =
  if multi.selections.len <= 1:
    return

  # Sort selections by start position
  multi.selections.sort do(a, b: Selection) -> int:
    if a.start < b.start:
      -1
    elif a.start == b.start:
      0
    else:
      1

  var merged: seq[Selection] = @[]
  var current = multi.selections[0]

  for i in 1 ..< multi.selections.len:
    let next = multi.selections[i]
    if current.overlaps(next):
      current = current.merge(next)
    else:
      merged.add(current)
      current = next

  merged.add(current)
  multi.selections = merged

  # Update primary index
  if multi.primary >= multi.selections.len:
    multi.primary = multi.selections.len - 1

# Selection transformation utilities
proc transformSelection*(selection: Selection, edit: TextEdit): Selection =
  ## Transform a selection after a text edit operation
  var newSelection = selection

  case edit.operation
  of eoInsert:
    let insertLines = edit.content.count('\n')
    let lastLineLen =
      if insertLines > 0:
        edit.content[edit.content.rfind('\n') + 1 .. ^1].len
      else:
        edit.content.len

    # Transform start position
    if selection.start.line > edit.position.line or (
      selection.start.line == edit.position.line and
      selection.start.col >= edit.position.col
    ):
      if selection.start.line == edit.position.line:
        if insertLines == 0:
          newSelection.start.col += edit.content.len
        else:
          newSelection.start.line += insertLines
          newSelection.start.col =
            newSelection.start.col - edit.position.col + lastLineLen
      else:
        newSelection.start.line += insertLines

    # Transform end position
    if selection.finish.line > edit.position.line or (
      selection.finish.line == edit.position.line and
      selection.finish.col >= edit.position.col
    ):
      if selection.finish.line == edit.position.line:
        if insertLines == 0:
          newSelection.finish.col += edit.content.len
        else:
          newSelection.finish.line += insertLines
          newSelection.finish.col =
            newSelection.finish.col - edit.position.col + lastLineLen
      else:
        newSelection.finish.line += insertLines
  of eoDelete:
    let deleteLines = edit.content.count('\n')
    let endPos = CursorPos(
      line: edit.position.line + deleteLines,
      col:
        if deleteLines > 0:
          edit.content[edit.content.rfind('\n') + 1 .. ^1].len
        else:
          edit.position.col + edit.content.len,
    )

    # Transform start position
    if selection.start >= endPos:
      newSelection.start.line -= deleteLines
      if selection.start.line == endPos.line:
        newSelection.start.col = edit.position.col + (selection.start.col - endPos.col)
    elif selection.start > edit.position:
      newSelection.start = edit.position

    # Transform end position
    if selection.finish >= endPos:
      newSelection.finish.line -= deleteLines
      if selection.finish.line == endPos.line:
        newSelection.finish.col =
          edit.position.col + (selection.finish.col - endPos.col)
    elif selection.finish > edit.position:
      newSelection.finish = edit.position
  of eoReplace:
    # Replace is delete + insert
    let deleteEdit = TextEdit(
      operation: eoDelete,
      position: edit.position,
      content: edit.previousContent,
      previousContent: "",
    )
    let insertEdit = TextEdit(
      operation: eoInsert,
      position: edit.position,
      content: edit.content,
      previousContent: "",
    )

    newSelection = transformSelection(newSelection, deleteEdit)
    newSelection = transformSelection(newSelection, insertEdit)

  newSelection

# Selection history for undo/redo
type SelectionState* = object
  selection*: Selection
  multiSelection*: Option[MultiSelection]

type SelectionHistory* = object
  states*: seq[SelectionState]
  current*: int
  maxSize*: int

proc newSelectionHistory*(maxSize: int = 100): SelectionHistory =
  SelectionHistory(states: @[], current: -1, maxSize: maxSize)

proc pushState*(history: var SelectionHistory, state: SelectionState) =
  # Remove any states after current
  if history.current < history.states.len - 1:
    history.states.setLen(history.current + 1)

  history.states.add(state)
  inc history.current

  # Limit size
  if history.states.len > history.maxSize:
    history.states.delete(0)
    dec history.current

proc canUndo*(history: SelectionHistory): bool =
  history.current > 0

proc canRedo*(history: SelectionHistory): bool =
  history.current < history.states.len - 1

proc undo*(history: var SelectionHistory): Option[SelectionState] =
  if history.canUndo():
    dec history.current
    some(history.states[history.current])
  else:
    none(SelectionState)

proc redo*(history: var SelectionHistory): Option[SelectionState] =
  if history.canRedo():
    inc history.current
    some(history.states[history.current])
  else:
    none(SelectionState)

proc getCurrentState*(history: SelectionHistory): Option[SelectionState] =
  if history.current >= 0 and history.current < history.states.len:
    some(history.states[history.current])
  else:
    none(SelectionState)
