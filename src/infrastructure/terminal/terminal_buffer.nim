## Terminal Buffer Component
## High-performance terminal output buffer with advanced line management,
## memory optimization, and search capabilities

import std/[sequtils, strutils, strformat, times, deques, algorithm, tables]
import raylib as rl
import ../../shared/types
import ../../terminal/core/terminal_errors

type
  BufferLineType* = enum
    bltNormal,      # Regular terminal output
    bltCommand,     # User input command
    bltError,       # Error message
    bltSystem,      # System notification
    bltPrompt       # Shell prompt

  BufferLine* = ref object
    text*: string
    styles*: seq[TerminalTextStyle]
    lineType*: BufferLineType
    timestamp*: float
    wrapped*: bool          # True if this line is a continuation of previous
    originalIndex*: int     # Original line number before wrapping
    searchMatches*: seq[tuple[start: int, length: int]]  # Search hit positions

  SearchResult* = object
    lineIndex*: int
    startPos*: int
    length*: int
    text*: string

  BufferCursor* = object
    line*: int
    column*: int
    visible*: bool
    blinkTime*: float

  BufferSelection* = object
    active*: bool
    startLine*: int
    startColumn*: int
    endLine*: int
    endColumn*: int

  TerminalBufferConfig* = object
    maxLines*: int
    maxLineLength*: int
    enableLineWrapping*: bool
    wrapWidth*: int
    enableSearch*: bool
    enableHistory*: bool
    historySize*: int
    autoCleanup*: bool
    cleanupThreshold*: float  # Cleanup when buffer exceeds this ratio of maxLines

  TerminalBuffer* = ref object
    # Core buffer data
    lines*: seq[BufferLine]
    config*: TerminalBufferConfig
    totalLinesAdded*: int
    
    # Display management
    cursor*: BufferCursor
    selection*: BufferSelection
    scrollOffset*: int
    visibleLineCount*: int
    
    # Performance tracking
    lastCleanup*: float
    memoryUsage*: int
    
    # Search functionality
    searchQuery*: string
    searchResults*: seq[SearchResult]
    currentSearchIndex*: int
    
    # History management
    commandHistory*: Deque[string]
    historyIndex*: int
    
    # Line wrapping cache
    wrappedLines*: seq[BufferLine]
    wrapCacheDirty*: bool
    
    # Callbacks
    onLineAdded*: proc(line: BufferLine) {.closure.}
    onBufferCleared*: proc() {.closure.}
    onSearchComplete*: proc(resultCount: int) {.closure.}

# Default configuration
proc defaultBufferConfig*(): TerminalBufferConfig =
  TerminalBufferConfig(
    maxLines: 10000,
    maxLineLength: 1000,
    enableLineWrapping: true,
    wrapWidth: 80,
    enableSearch: true,
    enableHistory: true,
    historySize: 1000,
    autoCleanup: true,
    cleanupThreshold: 1.2
  )

# Constructor
proc newTerminalBuffer*(config: TerminalBufferConfig = defaultBufferConfig()): TerminalBuffer =
  result = TerminalBuffer(
    lines: @[],
    config: config,
    totalLinesAdded: 0,
    
    cursor: BufferCursor(
      line: 0,
      column: 0,
      visible: true,
      blinkTime: 0.5
    ),
    
    selection: BufferSelection(
      active: false,
      startLine: 0,
      startColumn: 0,
      endLine: 0,
      endColumn: 0
    ),
    
    scrollOffset: 0,
    visibleLineCount: 25,
    lastCleanup: times.getTime().toUnixFloat(),
    memoryUsage: 0,
    
    searchQuery: "",
    searchResults: @[],
    currentSearchIndex: -1,
    
    commandHistory: initDeque[string](config.historySize),
    historyIndex: -1,
    
    wrappedLines: @[],
    wrapCacheDirty: false,
    
    onLineAdded: nil,
    onBufferCleared: nil,
    onSearchComplete: nil
  )

# Memory management
proc estimateLineMemory(line: BufferLine): int =
  ## Estimate memory usage of a buffer line
  result = sizeof(BufferLine)
  result += line.text.len
  result += line.styles.len * sizeof(TerminalTextStyle)
  result += line.searchMatches.len * sizeof(tuple[start: int, length: int])

proc updateMemoryUsage(buffer: TerminalBuffer) =
  ## Recalculate total memory usage
  buffer.memoryUsage = sizeof(TerminalBuffer)
  for line in buffer.lines:
    buffer.memoryUsage += estimateLineMemory(line)
  for line in buffer.wrappedLines:
    buffer.memoryUsage += estimateLineMemory(line)

proc shouldCleanup(buffer: TerminalBuffer): bool =
  ## Check if buffer cleanup is needed
  if not buffer.config.autoCleanup:
    return false
  
  let threshold = int(float(buffer.config.maxLines) * buffer.config.cleanupThreshold)
  return buffer.lines.len > threshold

proc cleanup*(buffer: TerminalBuffer): int =
  ## Clean up old lines from buffer, returns number of lines removed
  if not buffer.shouldCleanup():
    return 0
  
  let linesToRemove = buffer.lines.len - buffer.config.maxLines
  if linesToRemove <= 0:
    return 0
  
  # Remove oldest lines
  for i in 0..<linesToRemove:
    if buffer.lines.len > 0:
      buffer.lines.delete(0)
  
  # Update indices
  buffer.scrollOffset = max(0, buffer.scrollOffset - linesToRemove)
  if buffer.cursor.line >= linesToRemove:
    buffer.cursor.line -= linesToRemove
  else:
    buffer.cursor.line = 0
  
  # Update selection if active
  if buffer.selection.active:
    buffer.selection.startLine = max(0, buffer.selection.startLine - linesToRemove)
    buffer.selection.endLine = max(0, buffer.selection.endLine - linesToRemove)
  
  # Invalidate wrapped lines cache
  buffer.wrapCacheDirty = true
  
  buffer.lastCleanup = times.getTime().toUnixFloat()
  buffer.updateMemoryUsage()
  
  return linesToRemove

# Line management
proc wrapLine(text: string, width: int, styles: seq[TerminalTextStyle] = @[]): seq[BufferLine] =
  ## Wrap a long line into multiple lines
  if text.len <= width:
    return @[BufferLine(
      text: text,
      styles: styles,
      lineType: bltNormal,
      timestamp: times.getTime().toUnixFloat(),
      wrapped: false,
      originalIndex: 0,
      searchMatches: @[]
    )]
  
  result = @[]
  var pos = 0
  var lineIndex = 0
  
  while pos < text.len:
    let endPos = min(pos + width, text.len)
    let lineText = text[pos..<endPos]
    
    # Adjust styles for this line segment
    var lineStyles: seq[TerminalTextStyle] = @[]
    for style in styles:
      if style.endPos > pos and style.startPos < endPos:
        let adjustedStyle = TerminalTextStyle(
          startPos: max(0, style.startPos - pos),
          endPos: min(lineText.len, style.endPos - pos),
          color: style.color,
          backgroundColor: style.backgroundColor,
          bold: style.bold,
          italic: style.italic,
          underline: style.underline
        )
        if adjustedStyle.startPos < adjustedStyle.endPos:
          lineStyles.add(adjustedStyle)
    
    result.add(BufferLine(
      text: lineText,
      styles: lineStyles,
      lineType: bltNormal,
      timestamp: times.getTime().toUnixFloat(),
      wrapped: lineIndex > 0,
      originalIndex: lineIndex,
      searchMatches: @[]
    ))
    
    pos = endPos
    inc lineIndex

proc addLine*(buffer: TerminalBuffer, text: string, styles: seq[TerminalTextStyle] = @[], 
              lineType: BufferLineType = bltNormal) =
  ## Add a new line to the buffer
  var linesToAdd: seq[BufferLine]
  
  # Handle line wrapping if enabled
  if buffer.config.enableLineWrapping and text.len > buffer.config.wrapWidth:
    linesToAdd = wrapLine(text, buffer.config.wrapWidth, styles)
  else:
    # Truncate if line is too long and wrapping is disabled
    let finalText = if text.len > buffer.config.maxLineLength:
                      text[0..<buffer.config.maxLineLength] & "..."
                    else:
                      text
    
    linesToAdd = @[BufferLine(
      text: finalText,
      styles: styles,
      lineType: lineType,
      timestamp: times.getTime().toUnixFloat(),
      wrapped: false,
      originalIndex: 0,
      searchMatches: @[]
    )]
  
  # Add lines to buffer
  for line in linesToAdd:
    buffer.lines.add(line)
    inc buffer.totalLinesAdded
    
    # Trigger callback
    if buffer.onLineAdded != nil:
      buffer.onLineAdded(line)
  
  # Invalidate wrap cache
  buffer.wrapCacheDirty = true
  
  # Auto-cleanup if needed
  if buffer.shouldCleanup():
    discard buffer.cleanup()
  
  # Update cursor to end of buffer
  buffer.cursor.line = buffer.lines.len - 1
  buffer.cursor.column = linesToAdd[^1].text.len

proc addTerminalLine*(buffer: TerminalBuffer, line: TerminalLine) =
  ## Add a TerminalLine (for compatibility with existing code)
  buffer.addLine(line.text, line.styles, bltNormal)

proc insertLine*(buffer: TerminalBuffer, index: int, text: string, 
                styles: seq[TerminalTextStyle] = @[], lineType: BufferLineType = bltNormal) =
  ## Insert a line at a specific position
  if index < 0 or index > buffer.lines.len:
    return
  
  let line = BufferLine(
    text: text,
    styles: styles,
    lineType: lineType,
    timestamp: times.getTime().toUnixFloat(),
    wrapped: false,
    originalIndex: 0,
    searchMatches: @[]
  )
  
  buffer.lines.insert(line, index)
  inc buffer.totalLinesAdded
  buffer.wrapCacheDirty = true
  
  if buffer.onLineAdded != nil:
    buffer.onLineAdded(line)

proc removeLine*(buffer: TerminalBuffer, index: int): bool =
  ## Remove a line at a specific position
  if index < 0 or index >= buffer.lines.len:
    return false
  
  buffer.lines.delete(index)
  buffer.wrapCacheDirty = true
  
  # Adjust cursor and selection
  if buffer.cursor.line > index:
    dec buffer.cursor.line
  elif buffer.cursor.line == index and buffer.cursor.line >= buffer.lines.len:
    buffer.cursor.line = max(0, buffer.lines.len - 1)
    buffer.cursor.column = 0
  
  if buffer.selection.active:
    if buffer.selection.startLine > index:
      dec buffer.selection.startLine
    if buffer.selection.endLine > index:
      dec buffer.selection.endLine
  
  return true

proc clear*(buffer: TerminalBuffer) =
  ## Clear all lines from the buffer
  buffer.lines.setLen(0)
  buffer.wrappedLines.setLen(0)
  buffer.wrapCacheDirty = false
  
  # Reset cursor and selection
  buffer.cursor.line = 0
  buffer.cursor.column = 0
  buffer.selection.active = false
  buffer.scrollOffset = 0
  
  # Clear search results
  buffer.searchResults.setLen(0)
  buffer.currentSearchIndex = -1
  
  buffer.updateMemoryUsage()
  
  if buffer.onBufferCleared != nil:
    buffer.onBufferCleared()

# Access methods
proc getLine*(buffer: TerminalBuffer, index: int): BufferLine =
  ## Get a line by index (with bounds checking)
  if index >= 0 and index < buffer.lines.len:
    buffer.lines[index]
  else:
    nil

proc getLineCount*(buffer: TerminalBuffer): int =
  ## Get total number of lines in buffer
  buffer.lines.len

proc getVisibleLines*(buffer: TerminalBuffer, startLine: int = -1, 
                     lineCount: int = -1): seq[BufferLine] =
  ## Get visible lines based on scroll offset and visible line count
  let start = if startLine >= 0: startLine else: buffer.scrollOffset
  let count = if lineCount >= 0: lineCount else: buffer.visibleLineCount
  
  let startIdx = max(0, start)
  let endIdx = min(buffer.lines.len, start + count)
  
  if startIdx < endIdx:
    buffer.lines[startIdx..<endIdx]
  else:
    @[]

proc getWrappedLines*(buffer: TerminalBuffer): seq[BufferLine] =
  ## Get lines with wrapping applied (cached)
  if buffer.wrapCacheDirty or buffer.wrappedLines.len == 0:
    buffer.wrappedLines.setLen(0)
    
    for line in buffer.lines:
      if buffer.config.enableLineWrapping and line.text.len > buffer.config.wrapWidth:
        let wrapped = wrapLine(line.text, buffer.config.wrapWidth, line.styles)
        buffer.wrappedLines.add(wrapped)
      else:
        buffer.wrappedLines.add(line)
    
    buffer.wrapCacheDirty = false
  
  return buffer.wrappedLines

proc getText*(buffer: TerminalBuffer, startLine: int = 0, endLine: int = -1): string =
  ## Get text content from a range of lines
  let lastLine = if endLine >= 0: min(endLine, buffer.lines.len - 1) else: buffer.lines.len - 1
  
  result = ""
  for i in startLine..lastLine:
    if i >= 0 and i < buffer.lines.len:
      result.add(buffer.lines[i].text)
      if i < lastLine:
        result.add("\n")

# Cursor management
proc setCursor*(buffer: TerminalBuffer, line: int, column: int) =
  ## Set cursor position with bounds checking
  buffer.cursor.line = clamp(line, 0, max(0, buffer.lines.len - 1))
  
  if buffer.cursor.line < buffer.lines.len:
    buffer.cursor.column = clamp(column, 0, buffer.lines[buffer.cursor.line].text.len)
  else:
    buffer.cursor.column = 0

proc moveCursor*(buffer: TerminalBuffer, deltaLine: int, deltaColumn: int) =
  ## Move cursor by relative amount
  buffer.setCursor(buffer.cursor.line + deltaLine, buffer.cursor.column + deltaColumn)

proc getCursorPosition*(buffer: TerminalBuffer): tuple[line: int, column: int] =
  ## Get current cursor position
  (buffer.cursor.line, buffer.cursor.column)

# Scrolling
proc scroll*(buffer: TerminalBuffer, deltaLines: int) =
  ## Scroll the buffer by a number of lines
  let maxOffset = max(0, buffer.lines.len - buffer.visibleLineCount)
  buffer.scrollOffset = clamp(buffer.scrollOffset + deltaLines, 0, maxOffset)

proc scrollToTop*(buffer: TerminalBuffer) =
  ## Scroll to the top of the buffer
  buffer.scrollOffset = 0

proc scrollToBottom*(buffer: TerminalBuffer) =
  ## Scroll to the bottom of the buffer
  buffer.scrollOffset = max(0, buffer.lines.len - buffer.visibleLineCount)

proc scrollToCursor*(buffer: TerminalBuffer) =
  ## Scroll to make cursor visible
  let cursorLine = buffer.cursor.line
  let viewStart = buffer.scrollOffset
  let viewEnd = buffer.scrollOffset + buffer.visibleLineCount - 1
  
  if cursorLine < viewStart:
    buffer.scrollOffset = cursorLine
  elif cursorLine > viewEnd:
    buffer.scrollOffset = cursorLine - buffer.visibleLineCount + 1

proc isAtBottom*(buffer: TerminalBuffer): bool =
  ## Check if scrolled to bottom
  buffer.scrollOffset >= max(0, buffer.lines.len - buffer.visibleLineCount)

# Selection management
proc startSelection*(buffer: TerminalBuffer, line: int, column: int) =
  ## Start text selection
  buffer.selection.active = true
  buffer.selection.startLine = clamp(line, 0, buffer.lines.len - 1)
  buffer.selection.endLine = buffer.selection.startLine
  
  if buffer.selection.startLine < buffer.lines.len:
    buffer.selection.startColumn = clamp(column, 0, buffer.lines[buffer.selection.startLine].text.len)
    buffer.selection.endColumn = buffer.selection.startColumn
  else:
    buffer.selection.startColumn = 0
    buffer.selection.endColumn = 0

proc updateSelection*(buffer: TerminalBuffer, line: int, column: int) =
  ## Update selection end position
  if not buffer.selection.active:
    return
  
  buffer.selection.endLine = clamp(line, 0, buffer.lines.len - 1)
  
  if buffer.selection.endLine < buffer.lines.len:
    buffer.selection.endColumn = clamp(column, 0, buffer.lines[buffer.selection.endLine].text.len)
  else:
    buffer.selection.endColumn = 0

proc clearSelection*(buffer: TerminalBuffer) =
  ## Clear current selection
  buffer.selection.active = false

proc getSelectedText*(buffer: TerminalBuffer): string =
  ## Get text of current selection
  if not buffer.selection.active:
    return ""
  
  let startLine = min(buffer.selection.startLine, buffer.selection.endLine)
  let endLine = max(buffer.selection.startLine, buffer.selection.endLine)
  let startCol = if buffer.selection.startLine <= buffer.selection.endLine:
                   buffer.selection.startColumn
                 else:
                   buffer.selection.endColumn
  let endCol = if buffer.selection.startLine <= buffer.selection.endLine:
                 buffer.selection.endColumn
               else:
                 buffer.selection.startColumn
  
  if startLine == endLine:
    # Single line selection
    if startLine < buffer.lines.len:
      let line = buffer.lines[startLine].text
      let start = min(startCol, endCol)
      let stop = max(startCol, endCol)
      return line[start..<min(stop, line.len)]
  else:
    # Multi-line selection
    result = ""
    for lineIdx in startLine..endLine:
      if lineIdx >= buffer.lines.len:
        break
      
      let line = buffer.lines[lineIdx].text
      if lineIdx == startLine:
        result.add(line[startCol..<line.len])
      elif lineIdx == endLine:
        result.add(line[0..<min(endCol, line.len)])
      else:
        result.add(line)
      
      if lineIdx < endLine:
        result.add("\n")
  
  return result

# Search functionality
proc search*(buffer: TerminalBuffer, query: string, caseSensitive: bool = false): int =
  ## Search for text in buffer, returns number of matches found
  if not buffer.config.enableSearch or query.len == 0:
    return 0
  
  buffer.searchQuery = query
  buffer.searchResults.setLen(0)
  buffer.currentSearchIndex = -1
  
  let searchQuery = if caseSensitive: query else: query.toLower()
  
  for lineIdx in 0..<buffer.lines.len:
    let line = buffer.lines[lineIdx]
    let lineText = if caseSensitive: line.text else: line.text.toLower()
    
    var pos = 0
    while true:
      let foundPos = lineText.find(searchQuery, pos)
      if foundPos == -1:
        break
      
      # Store result
      buffer.searchResults.add(SearchResult(
        lineIndex: lineIdx,
        startPos: foundPos,
        length: query.len,
        text: line.text[foundPos..<foundPos + query.len]
      ))
      
      # Add to line's search matches
      line.searchMatches.add((foundPos, query.len))
      
      pos = foundPos + 1
  
  if buffer.onSearchComplete != nil:
    buffer.onSearchComplete(buffer.searchResults.len)
  
  return buffer.searchResults.len

proc findNext*(buffer: TerminalBuffer): bool =
  ## Find next search result
  if buffer.searchResults.len == 0:
    return false
  
  buffer.currentSearchIndex = (buffer.currentSearchIndex + 1) mod buffer.searchResults.len
  
  let result = buffer.searchResults[buffer.currentSearchIndex]
  buffer.setCursor(result.lineIndex, result.startPos)
  buffer.scrollToCursor()
  
  return true

proc findPrevious*(buffer: TerminalBuffer): bool =
  ## Find previous search result
  if buffer.searchResults.len == 0:
    return false
  
  if buffer.currentSearchIndex <= 0:
    buffer.currentSearchIndex = buffer.searchResults.len - 1
  else:
    dec buffer.currentSearchIndex
  
  let result = buffer.searchResults[buffer.currentSearchIndex]
  buffer.setCursor(result.lineIndex, result.startPos)
  buffer.scrollToCursor()
  
  return true

proc clearSearch*(buffer: TerminalBuffer) =
  ## Clear search results
  buffer.searchQuery = ""
  buffer.searchResults.setLen(0)
  buffer.currentSearchIndex = -1
  
  # Clear search matches from lines
  for line in buffer.lines:
    line.searchMatches.setLen(0)

# History management
proc addToHistory*(buffer: TerminalBuffer, command: string) =
  ## Add command to history
  if not buffer.config.enableHistory or command.strip().len == 0:
    return
  
  # Remove duplicates
  var newHistory = initDeque[string](buffer.config.historySize)
  for cmd in buffer.commandHistory:
    if cmd != command:
      newHistory.addLast(cmd)
  buffer.commandHistory = newHistory
  
  # Add to end
  buffer.commandHistory.addLast(command)
  
  # Trim if too large
  while buffer.commandHistory.len > buffer.config.historySize:
    buffer.commandHistory.popFirst()
  
  buffer.historyIndex = -1

proc getHistoryCommand*(buffer: TerminalBuffer, direction: int): string =
  ## Get command from history (direction: -1 = previous, 1 = next)
  if buffer.commandHistory.len == 0:
    return ""
  
  if direction < 0:  # Previous
    if buffer.historyIndex == -1:
      buffer.historyIndex = buffer.commandHistory.len - 1
    else:
      buffer.historyIndex = max(0, buffer.historyIndex - 1)
  else:  # Next
    if buffer.historyIndex == -1:
      return ""
    buffer.historyIndex = min(buffer.commandHistory.len - 1, buffer.historyIndex + 1)
  
  if buffer.historyIndex >= 0 and buffer.historyIndex < buffer.commandHistory.len:
    return buffer.commandHistory[buffer.historyIndex]
  
  return ""

proc clearHistory*(buffer: TerminalBuffer) =
  ## Clear command history
  buffer.commandHistory.clear()
  buffer.historyIndex = -1

# Export functionality
proc exportToText*(buffer: TerminalBuffer, includeTimestamps: bool = false): string =
  ## Export buffer content to plain text
  result = ""
  
  for line in buffer.lines:
    if includeTimestamps:
      let timestamp = times.fromUnixFloat(line.timestamp).format("HH:mm:ss")
      result.add(&"[{timestamp}] ")
    
    result.add(line.text)
    result.add("\n")

proc exportToHtml*(buffer: TerminalBuffer): string =
  ## Export buffer content to HTML with styling
  result = """<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Terminal Output</title>
  <style>
    body { font-family: 'Courier New', monospace; background: #000; color: #fff; margin: 20px; }
    .line { margin: 0; padding: 0; }
    .timestamp { color: #888; }
    .error { color: #ff6b6b; }
    .command { color: #4ecdc4; }
    .system { color: #ffe66d; }
  </style>
</head>
<body>
"""
  
  for line in buffer.lines:
    let cssClass = case line.lineType:
                   of bltError: "error"
                   of bltCommand: "command" 
                   of bltSystem: "system"
                   else: ""
    
    let timestamp = times.fromUnixFloat(line.timestamp).format("HH:mm:ss")
    result.add(&"""<div class="line {cssClass}">""")
    result.add(&"""<span class="timestamp">[{timestamp}]</span> """)
    result.add(line.text.replace("<", "&lt;").replace(">", "&gt;"))
    result.add("</div>\n")
  
  result.add("</body>\n</html>")

# Statistics and monitoring
proc getStatistics*(buffer: TerminalBuffer): tuple[
  lineCount: int, 
  memoryUsage: int, 
  totalLinesAdded: int,
  searchResultCount: int,
  historySize: int
] =
  ## Get buffer statistics
  buffer.updateMemoryUsage()
  return (
    lineCount: buffer.lines.len,
    memoryUsage: buffer.memoryUsage,
    totalLinesAdded: buffer.totalLinesAdded,
    searchResultCount: buffer.searchResults.len,
    historySize: buffer.commandHistory.len
  )

proc isEmpty*(buffer: TerminalBuffer): bool =
  ## Check if buffer is empty
  buffer.lines.len == 0

# Configuration
proc updateConfig*(buffer: TerminalBuffer, newConfig: TerminalBufferConfig) =
  ## Update buffer configuration
  let oldWrapWidth = buffer.config.wrapWidth
  buffer.config = newConfig
  
  # Invalidate wrap cache if wrap width changed
  if oldWrapWidth != newConfig.wrapWidth:
    buffer.wrapCacheDirty = true
  
  # Adjust history size
  while buffer.commandHistory.len > newConfig.historySize:
    buffer.commandHistory.popFirst()
  
  # Trigger cleanup if needed
  if buffer.shouldCleanup():
    discard buffer.cleanup()

# Callback management
proc setOnLineAdded*(buffer: TerminalBuffer, callback: proc(line: BufferLine) {.closure.}) =
  buffer.onLineAdded = callback

proc setOnBufferCleared*(buffer: TerminalBuffer, callback: proc() {.closure.}) =
  buffer.onBufferCleared = callback

proc setOnSearchComplete*(buffer: TerminalBuffer, callback: proc(resultCount: int) {.closure.}) =
  buffer.onSearchComplete = callback