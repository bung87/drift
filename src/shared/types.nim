## Shared types for the Drift editor
## Pure domain types without external dependencies

import std/[options, times, os]
import raylib as rl

# Text cursor position
type CursorPos* = object
  line*: int # 0-based line number
  col*: int # 0-based column number

# Text selection range
type Selection* = object
  start*: CursorPos
  finish*: CursorPos
  active*: bool

# Text editing operation types
type EditOperation* = enum
  eoInsert = "insert"
  eoDelete = "delete"
  eoReplace = "replace"

# Text edit for undo/redo
type TextEdit* = object
  operation*: EditOperation
  position*: CursorPos
  content*: string
  previousContent*: string

# Document metadata
type DocumentMetadata* = object
  language*: string
  encoding*: string
  tabSize*: int
  useSpaces*: bool
  lineEnding*: string # "\n", "\r\n", or "\r"

# Document state
type Document* = ref object
  lines*: seq[string]
  metadata*: DocumentMetadata
  undoStack*: seq[TextEdit]
  redoStack*: seq[TextEdit]
  maxUndoSize*: int
  isModified*: bool
  version*: int # Incremented on each change

# Document statistics
type DocumentStats* = object
  lineCount*: int
  characterCount*: int
  wordCount*: int
  nonWhitespaceCharCount*: int

# Language Server Protocol position (0-based)
type LSPPosition* = object
  line*: int
  character*: int

# Language Server Protocol range
type LSPRange* = object
  start*: LSPPosition
  `end`*: LSPPosition

# Hover information from LSP or built-in help
type HoverInfo* = object
  content*: string
  range*: Option[LSPRange]

# Notification types
type NotificationType* = enum
  ntInfo = "info"
  ntWarning = "warning"
  ntError = "error"
  ntSuccess = "success"

# Sidebar panel types
type SidebarPanel* = enum
  spExplorer = "explorer"
  spSearch = "search"
  spGit = "git"
  spExtensions = "extensions"

# File type detection
type FileType* = enum
  ftText = "text"
  ftBinary = "binary"
  ftUnknown = "unknown"

type GitFileStatusEnum* = enum
  gfsUnmodified = "unmodified"
  gfsModified = "modified"
  gfsAdded = "added"
  gfsDeleted = "deleted"
  gfsRenamed = "renamed"
  gfsUntracked = "untracked"
  gfsIgnored = "ignored"

# Git repository information
type GitInfo* = object
  branch*: string
  hasChanges*: bool
  ahead*: int
  behind*: int

# Syntax token types
type TokenType* = enum
  ttKeyword = "keyword"
  ttIdentifier = "identifier"
  ttString = "string"
  ttNumber = "number"
  ttComment = "comment"
  ttOperator = "operator"
  ttPunctuation = "punctuation"
  ttType = "type"
  ttFunction = "function"
  ttVariable = "variable"
  ttWhitespace = "whitespace"
  ttUnknown = "unknown"

# Syntax highlighting token
type Token* = object
  tokenType*: TokenType
  start*: int # Start position in line
  length*: int # Token length
  line*: int # Line number (0-based)

type TextEditorState* = ref object
  cursor*: CursorPos
  selection*: Selection
  scrollOffset*: int
  scrollX*: float32
  scrollY*: float32
  maxScrollOffset*: int
  visibleLines*: int
  isModified*: bool
  isFocused*: bool
  lastClickTime*: float64
  doubleClickTime*: float64
  dragStartPos*: CursorPos
  isDragging*: bool
  showHover*: bool
  hoverInfo*: Option[HoverInfo]
  lastHoverTime*: float64
  # Fields for hover and rendering
  lineHeight*: float32
  fontSize*: float32
  text*: Document
  font*: rl.Font
  hoverPosition*: CursorPos
  sidebarWidth*: float32
  lastHoverSymbol*: string # Track last hovered symbol for synchronization
  hoverActiveSymbol*: string # Symbol currently under the mouse for robust hover sync
  # Enhanced hover state management
  hoverScreenPosition*: rl.Vector2 # Store actual screen coordinates for consistent rendering
  hoverRequestId*: int # Track request order to avoid race conditions
  pendingHoverRequest*: bool # Track if a hover request is pending
  lastHoverRequestTime*: float64 # Track when last request was made for debouncing

# Document change event
type DocumentChange* = object
  edit*: TextEdit
  newCursor*: CursorPos
  newSelection*: Option[Selection]

# Position utilities
proc `==`*(a, b: CursorPos): bool =
  a.line == b.line and a.col == b.col

proc `<`*(a, b: CursorPos): bool =
  if a.line < b.line:
    true
  elif a.line == b.line:
    a.col < b.col
  else:
    false

proc `<=`*(a, b: CursorPos): bool =
  a == b or a < b

# Selection utilities
proc isEmpty*(selection: Selection): bool =
  not selection.active or selection.start == selection.finish

proc normalize*(selection: Selection): Selection =
  ## Ensure start <= finish
  result = selection
  if result.active and result.finish < result.start:
    swap(result.start, result.finish)

proc contains*(selection: Selection, pos: CursorPos): bool =
  if not selection.active or selection.isEmpty():
    return false
  let normalized = selection.normalize()
  pos >= normalized.start and pos <= normalized.finish

# LSP position conversion utilities
proc toLSP*(pos: CursorPos): LSPPosition =
  LSPPosition(line: pos.line, character: pos.col)

proc fromLSP*(pos: LSPPosition): CursorPos =
  CursorPos(line: pos.line, col: pos.character)

# Terminal types for integrated terminal functionality
type
  TerminalTextStyle* = object
    startPos*: int
    endPos*: int
    color*: rl.Color
    backgroundColor*: rl.Color
    bold*: bool
    italic*: bool
    underline*: bool

  TerminalLine* = object
    text*: string
    styles*: seq[TerminalTextStyle]
    timestamp*: float

  TerminalBuffer* = ref object
    lines*: seq[TerminalLine]
    maxLines*: int
    currentLine*: int
    cursorColumn*: int
    scrollOffset*: int

  TerminalSession* = ref object
    id*: int
    name*: string
    buffer*: TerminalBuffer
    workingDirectory*: string
    isActive*: bool
    created*: float

# Terminal utility functions
proc newTerminalTextStyle*(startPos: int, endPos: int, color: rl.Color = rl.WHITE,
                          backgroundColor: rl.Color = rl.BLACK, bold: bool = false,
                          italic: bool = false, underline: bool = false): TerminalTextStyle =
  TerminalTextStyle(
    startPos: startPos,
    endPos: endPos,
    color: color,
    backgroundColor: backgroundColor,
    bold: bold,
    italic: italic,
    underline: underline
  )

proc newTerminalLine*(text: string, styles: seq[TerminalTextStyle] = @[]): TerminalLine =
  TerminalLine(
    text: text,
    styles: styles,
    timestamp: times.getTime().toUnixFloat()
  )

proc newTerminalBuffer*(maxLines: int = 1000): TerminalBuffer =
  TerminalBuffer(
    lines: @[],
    maxLines: maxLines,
    currentLine: 0,
    cursorColumn: 0,
    scrollOffset: 0
  )

proc newTerminalSession*(id: int, name: string, workingDir: string = ""): TerminalSession =
  TerminalSession(
    id: id,
    name: name,
    buffer: newTerminalBuffer(),
    workingDirectory: if workingDir.len > 0: workingDir else: getCurrentDir(),
    isActive: false,
    created: times.getTime().toUnixFloat()
  )

# Terminal buffer operations
proc addLine*(buffer: TerminalBuffer, line: TerminalLine) =
  buffer.lines.add(line)
  if buffer.lines.len > buffer.maxLines:
    buffer.lines.delete(0)
  buffer.currentLine = buffer.lines.len - 1

proc getVisibleLines*(buffer: TerminalBuffer, start: int, count: int): seq[TerminalLine] =
  let startIdx = max(0, start)
  let endIdx = min(buffer.lines.len, start + count)
  if startIdx < endIdx:
    buffer.lines[startIdx..<endIdx]
  else:
    @[]

proc clear*(buffer: TerminalBuffer) =
  buffer.lines.setLen(0)
  buffer.currentLine = 0
  buffer.cursorColumn = 0
  buffer.scrollOffset = 0

proc getLineCount*(buffer: TerminalBuffer): int =
  buffer.lines.len

proc isEmpty*(buffer: TerminalBuffer): bool =
  buffer.lines.len == 0

# Terminal error types are now centralized in src/terminal/core/terminal_errors.nim