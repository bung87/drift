## VSCode-Style Find and Replace Panel for Drift Editor
## Refactored to use ComponentManager architecture

import std/[strutils, os, tables, re, algorithm, options]
import raylib as rl
import ../shared/errors
import ../services/[ui_service, component_manager]
import ../infrastructure/input/[input_handler, keyboard, mouse]
import ../infrastructure/rendering/theme
import ../icons
import results


# Find and Replace types
type
  SearchScope* = enum
    ssCurrentFile = "current_file"
    ssProject = "project"

  SearchOptions* = object
    caseSensitive*: bool
    wholeWord*: bool
    useRegex*: bool
    filePattern*: string

  SearchResult* = object
    filePath*: string
    lineNumber*: int
    columnStart*: int
    columnEnd*: int
    lineContent*: string
    matchedText*: string

  SearchState* = enum
    ssIdle = "idle"
    ssSearching = "searching"
    ssResults = "results"
    ssError = "error"

  ControlType* = enum
    ctNone = "none"
    ctFindInput = "find_input"
    ctReplaceInput = "replace_input"
    ctPrevious = "previous"
    ctNext = "next"
    ctClose = "close"
    ctReplace = "replace"
    ctReplaceAll = "replaceAll"
    ctIncludeInput = "includeInput"
    ctExcludeInput = "excludeInput"

  Control* = object
    controlType*: ControlType
    bounds*: rl.Rectangle
    isEnabled*: bool
    isHovered*: bool

  # Callback types
  FileOpenCallback* = proc(filePath: string): bool
  CursorSetCallback* = proc(line: int, col: int)
  HighlightCallback* = proc(results: seq[SearchResult])
  ClearFocusCallback* = proc()

  SearchReplacePanel* = ref object of UIComponent
    # ComponentManager integration
    componentManager*: ComponentManager
    
    # Search state
    searchState*: SearchState
    findText*: string
    replaceText*: string
    includePattern*: string
    excludePattern*: string
    scope*: SearchScope
    options*: SearchOptions
    results*: seq[SearchResult]
    currentMatchIndex*: int
    totalMatches*: int
    
    # UI state
    controls*: Table[ControlType, Control]
    focusedControl*: ControlType
    lastFocusedInput*: ControlType
    statusText*: string
    statusTextTimeout*: float32
    panelHeight*: float32
    
    # Callbacks
    onOpenFile*: FileOpenCallback
    onSetCursor*: CursorSetCallback
    onHighlight*: HighlightCallback
    onClearFocus*: ClearFocusCallback
    
    # Error state
    errorMessage*: string
    regexError*: bool

# Constants
const
  PANEL_PADDING = 8.0
  INPUT_HEIGHT = 26.0
  CONTROL_SPACING = 4.0
  INPUT_SECTION_HEIGHT = 52.0
  LABEL_HEIGHT = 16.0
  SECTION_SPACING = 6.0
  BUTTON_SIZE = 18.0

# Forward declarations
proc handleInput*(panel: SearchReplacePanel, event: UnifiedInputEvent): bool
proc render*(panel: SearchReplacePanel)
proc registerInputHandlers*(panel: SearchReplacePanel): Result[void, EditorError]
proc initializeControls*(panel: SearchReplacePanel)
proc updateLayout*(panel: SearchReplacePanel)
proc performSearch*(panel: SearchReplacePanel)
proc findNext*(panel: SearchReplacePanel)
proc findPrevious*(panel: SearchReplacePanel)
proc replaceCurrentMatch*(panel: SearchReplacePanel)
proc replaceAll*(panel: SearchReplacePanel)
proc show*(panel: SearchReplacePanel)
proc hide*(panel: SearchReplacePanel)
proc handleMouseClick*(panel: SearchReplacePanel, pos: MousePosition)
proc handleMouseMove*(panel: SearchReplacePanel, pos: MousePosition)
proc handleMouseEvent*(panel: SearchReplacePanel, event: MouseEvent): bool
proc handleKeyboardEvent*(panel: SearchReplacePanel, event: InputEvent): bool
proc updateControlHover*(panel: SearchReplacePanel, mousePos: rl.Vector2)
proc handleControlClick*(panel: SearchReplacePanel, mousePos: rl.Vector2)
proc renderFindInput(panel: SearchReplacePanel)
proc renderReplaceInput(panel: SearchReplacePanel)
proc renderIncludeInput(panel: SearchReplacePanel)
proc renderExcludeInput(panel: SearchReplacePanel)
proc renderButtons(panel: SearchReplacePanel)
proc renderMatchCounter(panel: SearchReplacePanel)

# Constructor
proc newSearchReplacePanel*(
    componentManager: ComponentManager,
    id: string,
    bounds: rl.Rectangle,
    onOpenFile: FileOpenCallback = nil,
    onSetCursor: CursorSetCallback = nil,
    onHighlight: HighlightCallback = nil,
    onClearFocus: ClearFocusCallback = nil
): Result[SearchReplacePanel, EditorError] =
  ## Create new search/replace panel using ComponentManager
  
  let panel = SearchReplacePanel(
    componentManager: componentManager,
    searchState: ssIdle,
    findText: "",
    replaceText: "",
    includePattern: "*.nim",
    excludePattern: "",
    scope: ssCurrentFile,
    options: SearchOptions(caseSensitive: false, wholeWord: false, useRegex: false),
    results: @[],
    currentMatchIndex: -1,
    totalMatches: 0,
    controls: initTable[ControlType, Control](),
    focusedControl: ctFindInput,
    lastFocusedInput: ctFindInput,
    statusText: "",
    statusTextTimeout: 0.0,
    panelHeight: INPUT_SECTION_HEIGHT * 2 + SECTION_SPACING,
    onOpenFile: onOpenFile,
    onSetCursor: onSetCursor,
    onHighlight: onHighlight,
    onClearFocus: onClearFocus,
    errorMessage: "",
    regexError: false
  )
  
  # Initialize UIComponent base
  panel.id = id
  panel.name = "SearchReplacePanel"
  panel.state = csHidden
  panel.bounds = bounds
  panel.zIndex = 100 # High z-index for panel
  panel.isVisible = false
  panel.isEnabled = true
  panel.isDirty = true
  panel.data = initTable[string, string]()
  
  # Register with ComponentManager
  let registerResult = componentManager.registerComponent(
    id,
    panel,
    proc(event: UnifiedInputEvent): bool = panel.handleInput(event),
    proc(bounds: rl.Rectangle) = 
      panel.bounds = bounds
      panel.render()
  )
  
  if registerResult.isErr:
    return err(registerResult.error)
  
  # Initialize controls and layout
  panel.initializeControls()
  panel.updateLayout()
  
  # Note: Input handling is now done through ComponentManager's event system
  # No need to register global commands that could conflict
  
  return ok(panel)

# Input handling registration
proc registerInputHandlers*(panel: SearchReplacePanel): Result[void, EditorError] =
  ## Register standardized input handlers using ComponentManager
  
  var keyHandlers = initTable[KeyCombination, proc()]()
  
  # Escape to close
  keyHandlers[KeyCombination(key: ekEscape, modifiers: {})] = proc() =
    panel.hide()
  
  # Enter to search
  keyHandlers[KeyCombination(key: ekEnter, modifiers: {})] = proc() =
    panel.performSearch()
  
  # Ctrl+F to focus find input
  keyHandlers[KeyCombination(key: ekF, modifiers: {mkCtrl})] = proc() =
    # Clear focus from text editor when focusing search panel inputs
    if panel.onClearFocus != nil:
      panel.onClearFocus()
    panel.focusedControl = ctFindInput
    panel.componentManager.markComponentDirty(panel.id)
  
  # F3 or Ctrl+G to find next
  keyHandlers[KeyCombination(key: ekF3, modifiers: {})] = proc() =
    panel.findNext()
  
  keyHandlers[KeyCombination(key: ekG, modifiers: {mkCtrl})] = proc() =
    panel.findNext()
  
  # Shift+F3 or Ctrl+Shift+G to find previous
  keyHandlers[KeyCombination(key: ekF3, modifiers: {mkShift})] = proc() =
    panel.findPrevious()
  
  keyHandlers[KeyCombination(key: ekG, modifiers: {mkCtrl, mkShift})] = proc() =
    panel.findPrevious()
  
  # Tab navigation between inputs
  keyHandlers[KeyCombination(key: ekTab, modifiers: {})] = proc() =
    # Clear focus from text editor when navigating between search panel inputs
    if panel.onClearFocus != nil:
      panel.onClearFocus()
    case panel.focusedControl:
    of ctFindInput: panel.focusedControl = ctReplaceInput
    of ctReplaceInput: panel.focusedControl = ctIncludeInput
    of ctIncludeInput: panel.focusedControl = ctExcludeInput
    of ctExcludeInput: panel.focusedControl = ctFindInput
    else: panel.focusedControl = ctFindInput
    panel.componentManager.markComponentDirty(panel.id)
  
  let keyResult = panel.componentManager.registerInputHandlers(
    panel.id,
    keyHandlers,
    initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  )
  
  if keyResult.isErr:
    return err(keyResult.error)
  
  # Register mouse handlers for clicks
  let dragResult = panel.componentManager.registerDragHandlers(
    panel.id,
    proc(pos: MousePosition) = panel.handleMouseClick(pos),
    proc(pos: MousePosition) = panel.handleMouseMove(pos),
    proc(pos: MousePosition) = discard
  )
  
  return dragResult

# Input event handling
proc handleInput*(panel: SearchReplacePanel, event: UnifiedInputEvent): bool =
  ## Handle unified input events
  if not panel.isVisible:
    return false
  
  case event.kind:
  of uiekMouse:
    return panel.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    let keyEvent = event.keyEvent
    
    case keyEvent.key:
    of ekEscape:
      if keyEvent.eventType == ietKeyPressed:
        panel.hide()
        return true
    of ekEnter:
      if keyEvent.eventType == ietKeyPressed:
        panel.performSearch()
        return true
    of ekF:
      if keyEvent.eventType == ietKeyPressed and keyEvent.modifiers == {mkCtrl}:
        # Clear focus from text editor when focusing search panel via Ctrl+F
        if panel.onClearFocus != nil:
          panel.onClearFocus()
        panel.focusedControl = ctFindInput
        panel.componentManager.markComponentDirty(panel.id)
        return true
    of ekF3:
      if keyEvent.eventType == ietKeyPressed:
        if mkShift in keyEvent.modifiers:
          panel.findPrevious()
        else:
          panel.findNext()
        return true
    of ekG:
      if keyEvent.eventType == ietKeyPressed:
        if mkCtrl in keyEvent.modifiers:
          if mkShift in keyEvent.modifiers:
            panel.findPrevious()
          else:
            panel.findNext()
        return true
    of ekTab:
      if keyEvent.eventType == ietKeyPressed:
        # Clear focus from text editor when navigating between search panel inputs
        if panel.onClearFocus != nil:
          panel.onClearFocus()
        case panel.focusedControl:
        of ctFindInput: panel.focusedControl = ctReplaceInput
        of ctReplaceInput: panel.focusedControl = ctIncludeInput
        of ctIncludeInput: panel.focusedControl = ctExcludeInput
        of ctExcludeInput: panel.focusedControl = ctFindInput
        else: panel.focusedControl = ctFindInput
        panel.componentManager.markComponentDirty(panel.id)
        return true
    else:
      # Handle text input for focused controls
      if keyEvent.eventType == ietKeyPressed and keyEvent.character.int32 > 0:
        let charStr = $char(keyEvent.character.int32)
        case panel.focusedControl:
        of ctFindInput:
          panel.findText.add(charStr)
          panel.componentManager.markComponentDirty(panel.id)
          return true
        of ctReplaceInput:
          panel.replaceText.add(charStr)
          panel.componentManager.markComponentDirty(panel.id)
          return true
        of ctIncludeInput:
          panel.includePattern.add(charStr)
          panel.componentManager.markComponentDirty(panel.id)
          return true
        of ctExcludeInput:
          panel.excludePattern.add(charStr)
          panel.componentManager.markComponentDirty(panel.id)
          return true
        else:
          discard
      
      # Handle backspace
      if keyEvent.eventType == ietKeyPressed and keyEvent.key == ekBackspace:
        case panel.focusedControl:
        of ctFindInput:
          if panel.findText.len > 0:
            panel.findText = panel.findText[0..^2]
            panel.componentManager.markComponentDirty(panel.id)
            return true
        of ctReplaceInput:
          if panel.replaceText.len > 0:
            panel.replaceText = panel.replaceText[0..^2]
            panel.componentManager.markComponentDirty(panel.id)
            return true
        of ctIncludeInput:
          if panel.includePattern.len > 0:
            panel.includePattern = panel.includePattern[0..^2]
            panel.componentManager.markComponentDirty(panel.id)
            return true
        of ctExcludeInput:
          if panel.excludePattern.len > 0:
            panel.excludePattern = panel.excludePattern[0..^2]
            panel.componentManager.markComponentDirty(panel.id)
            return true
        else:
          discard
  of uiekCombined:
    # Handle combined events (mouse + keyboard)
    return false
  
  return false

proc handleMouseEvent*(panel: SearchReplacePanel, event: MouseEvent): bool =
  ## Handle mouse events
  if not panel.isVisible:
    return false
  
  let mousePos = rl.Vector2(x: event.position.x, y: event.position.y)
  
  # Check if mouse is over panel
  if not rl.checkCollisionPointRec(mousePos, panel.bounds):
    return false
  
  case event.eventType:
  of metMoved:
    panel.updateControlHover(mousePos)
    # Only consume mouse move events if we're actually doing something with them
    # This allows hover effects to work in other components
    return false
  of metButtonPressed:
    if event.button == mbLeft:
      panel.handleControlClick(mousePos)
      return true
  else:
    discard
  
  return false

proc handleKeyboardEvent*(panel: SearchReplacePanel, event: InputEvent): bool =
  ## Handle keyboard events for text input
  if not panel.isVisible:
    return false
  
  # Handle text input for focused control
  if event.eventType == ietCharInput:
    let char = char(event.character.int32)
    case panel.focusedControl:
    of ctFindInput:
      panel.findText.add(char)
      panel.componentManager.markComponentDirty(panel.id)
      return true
    of ctReplaceInput:
      panel.replaceText.add(char)
      panel.componentManager.markComponentDirty(panel.id)
      return true
    of ctIncludeInput:
      panel.includePattern.add(char)
      panel.componentManager.markComponentDirty(panel.id)
      return true
    of ctExcludeInput:
      panel.excludePattern.add(char)
      panel.componentManager.markComponentDirty(panel.id)
      return true
    else:
      discard
  
  # Handle backspace
  if event.eventType == ietKeyPressed and event.key == ekBackspace:
    case panel.focusedControl:
    of ctFindInput:
      if panel.findText.len > 0:
        panel.findText = panel.findText[0..^2]
        panel.componentManager.markComponentDirty(panel.id)
        return true
    of ctReplaceInput:
      if panel.replaceText.len > 0:
        panel.replaceText = panel.replaceText[0..^2]
        panel.componentManager.markComponentDirty(panel.id)
        return true
    of ctIncludeInput:
      if panel.includePattern.len > 0:
        panel.includePattern = panel.includePattern[0..^2]
        panel.componentManager.markComponentDirty(panel.id)
        return true
    of ctExcludeInput:
      if panel.excludePattern.len > 0:
        panel.excludePattern = panel.excludePattern[0..^2]
        panel.componentManager.markComponentDirty(panel.id)
        return true
    else:
      discard
  
  return false

proc handleMouseClick*(panel: SearchReplacePanel, pos: MousePosition) =
  ## Handle mouse click events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  panel.handleControlClick(mousePos)

proc handleMouseMove*(panel: SearchReplacePanel, pos: MousePosition) =
  ## Handle mouse move events
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  panel.updateControlHover(mousePos)

proc updateControlHover*(panel: SearchReplacePanel, mousePos: rl.Vector2) =
  ## Update hover state for controls
  for controlType, control in panel.controls.mpairs:
    let wasHovered = control.isHovered
    control.isHovered = rl.checkCollisionPointRec(mousePos, control.bounds)
    
    if wasHovered != control.isHovered:
      panel.componentManager.markComponentDirty(panel.id)

proc handleControlClick*(panel: SearchReplacePanel, mousePos: rl.Vector2) =
  ## Handle clicks on controls
  for controlType, control in panel.controls:
    if rl.checkCollisionPointRec(mousePos, control.bounds):
      case controlType:
      of ctFindInput, ctReplaceInput, ctIncludeInput, ctExcludeInput:
        # Clear focus from text editor when focusing search panel inputs
        if panel.onClearFocus != nil:
          panel.onClearFocus()
        panel.focusedControl = controlType
        panel.lastFocusedInput = controlType
      of ctPrevious:
        panel.findPrevious()
      of ctNext:
        panel.findNext()
      of ctClose:
        panel.hide()
      of ctReplace:
        panel.replaceCurrentMatch()
      of ctReplaceAll:
        panel.replaceAll()
      else:
        discard
      
      panel.componentManager.markComponentDirty(panel.id)
      break

# Control initialization and layout
proc initializeControls*(panel: SearchReplacePanel) =
  ## Initialize all UI controls
  for controlType in [ctFindInput, ctPrevious, ctNext, ctClose, ctReplaceInput,
                      ctReplace, ctReplaceAll, ctIncludeInput, ctExcludeInput]:
    panel.controls[controlType] = Control(
      controlType: controlType,
      bounds: rl.Rectangle(),
      isEnabled: true,
      isHovered: false
    )

proc updateLayout*(panel: SearchReplacePanel) =
  ## Update layout of all controls using UIService layout system
  # Increased height to accommodate vertically stacked include/exclude inputs
  panel.panelHeight = INPUT_SECTION_HEIGHT * 5 + LABEL_HEIGHT * 2 + SECTION_SPACING * 3.0
  
  var currentY = panel.bounds.y + PANEL_PADDING
  let findInputY = currentY + (INPUT_SECTION_HEIGHT - INPUT_HEIGHT) / 2
  
  # Find input
  panel.controls[ctFindInput].bounds = rl.Rectangle(
    x: panel.bounds.x + PANEL_PADDING,
    y: findInputY,
    width: panel.bounds.width - (PANEL_PADDING * 2) - 80.0, # Space for buttons
    height: INPUT_HEIGHT
  )
  
  # Navigation buttons
  let totalButtonsWidth = (BUTTON_SIZE * 3) + (CONTROL_SPACING * 2)
  let buttonStartX = panel.bounds.x + panel.bounds.width - PANEL_PADDING - totalButtonsWidth
  
  panel.controls[ctPrevious].bounds = rl.Rectangle(
    x: buttonStartX,
    y: findInputY + (INPUT_HEIGHT - BUTTON_SIZE) / 2,
    width: BUTTON_SIZE,
    height: BUTTON_SIZE
  )
  
  panel.controls[ctNext].bounds = rl.Rectangle(
    x: buttonStartX + BUTTON_SIZE + CONTROL_SPACING,
    y: findInputY + (INPUT_HEIGHT - BUTTON_SIZE) / 2,
    width: BUTTON_SIZE,
    height: BUTTON_SIZE
  )
  
  panel.controls[ctClose].bounds = rl.Rectangle(
    x: buttonStartX + (BUTTON_SIZE + CONTROL_SPACING) * 2,
    y: findInputY + (INPUT_HEIGHT - BUTTON_SIZE) / 2,
    width: BUTTON_SIZE,
    height: BUTTON_SIZE
  )
  
  # Replace section
  currentY += INPUT_SECTION_HEIGHT
  let replaceInputY = currentY + (INPUT_SECTION_HEIGHT - INPUT_HEIGHT) / 2
  
  panel.controls[ctReplaceInput].bounds = rl.Rectangle(
    x: panel.bounds.x + PANEL_PADDING,
    y: replaceInputY,
    width: panel.bounds.width - (PANEL_PADDING * 2) - 80.0,
    height: INPUT_HEIGHT
  )
  
  # Replace buttons
  let replaceButtonsWidth = (BUTTON_SIZE * 2) + CONTROL_SPACING
  let replaceButtonStartX = panel.bounds.x + panel.bounds.width - PANEL_PADDING - replaceButtonsWidth
  
  panel.controls[ctReplace].bounds = rl.Rectangle(
    x: replaceButtonStartX,
    y: replaceInputY + (INPUT_HEIGHT - BUTTON_SIZE) / 2,
    width: BUTTON_SIZE,
    height: BUTTON_SIZE
  )
  
  panel.controls[ctReplaceAll].bounds = rl.Rectangle(
    x: replaceButtonStartX + BUTTON_SIZE + CONTROL_SPACING,
    y: replaceInputY + (INPUT_HEIGHT - BUTTON_SIZE) / 2,
    width: BUTTON_SIZE,
    height: BUTTON_SIZE
  )
  
  # File pattern inputs - stacked vertically
  currentY += INPUT_SECTION_HEIGHT + SECTION_SPACING
  let includeInputY = currentY + (INPUT_SECTION_HEIGHT - INPUT_HEIGHT) / 2
  
  # Calculate full width for stacked layout
  let totalWidth = panel.bounds.width - (PANEL_PADDING * 2)
  
  panel.controls[ctIncludeInput].bounds = rl.Rectangle(
    x: panel.bounds.x + PANEL_PADDING,
    y: includeInputY,
    width: totalWidth,
    height: INPUT_HEIGHT
  )
  
  # Stack exclude input below include input
  let excludeInputY = includeInputY + INPUT_HEIGHT + 8.0  # 8px spacing between inputs
  panel.controls[ctExcludeInput].bounds = rl.Rectangle(
    x: panel.bounds.x + PANEL_PADDING,
    y: excludeInputY,
    width: totalWidth,
    height: INPUT_HEIGHT
  )
  
  # Update bounds using ComponentManager
  discard panel.componentManager.updateComponentBounds(panel.id, panel.bounds)

# Search functionality
proc getSearchPaths(panel: SearchReplacePanel): seq[string] =
  ## Get paths to search based on scope
  case panel.scope:
  of ssCurrentFile:
    return @[]  # Current file handled separately
  of ssProject:
    # Use FileManager to get project files
    let fileManager = panel.componentManager.getFileManager()
    return @["."]  # Search current directory

proc matchesFilePattern(filePath: string, pattern: string): bool =
  ## Check if file matches the include pattern
  if pattern.len == 0:
    return true
  
  let fileName = extractFilename(filePath)
  if pattern.contains("*"):
    let patternExt = pattern.replace("*", "")
    return fileName.endsWith(patternExt)
  else:
    return fileName.contains(pattern)

proc getFilesToSearch(panel: SearchReplacePanel): seq[string] =
  ## Get list of files to search
  let searchPaths = panel.getSearchPaths()
  var files: seq[string] = @[]
  
  for path in searchPaths:
    for file in walkDirRec(path):
      let fileName = extractFilename(file)
      if matchesFilePattern(file, panel.includePattern) and
         not matchesFilePattern(file, panel.excludePattern):
        files.add(file)
  
  return files

proc searchInFile(panel: SearchReplacePanel, filePath: string): seq[SearchResult] =
  ## Search for text in a single file
  var results: seq[SearchResult] = @[]
  
  try:
    let content = readFile(filePath)
    let lines = content.splitLines()
    
    var searchPattern = panel.findText
    var targetLine = ""
    
    if panel.options.useRegex:
      try:
        let regex = re(searchPattern)
        for lineNum, line in lines:
          var pos = 0
          while pos < line.len:
            let matchBounds = line.findBounds(regex, pos)
            if matchBounds.first == -1:
              break
            
            results.add(SearchResult(
              filePath: filePath,
              lineNumber: lineNum + 1,
              columnStart: matchBounds.first,
              columnEnd: matchBounds.last,
              lineContent: line,
              matchedText: line[matchBounds.first..matchBounds.last]
            ))
            pos = matchBounds.last + 1
      except RegexError:
        panel.regexError = true
        panel.errorMessage = "Invalid regular expression"
        return @[]
    else:
      # Simple text search
      for lineNum, line in lines:
        targetLine = if panel.options.caseSensitive: line else: line.toLowerAscii()
        searchPattern = if panel.options.caseSensitive: panel.findText else: panel.findText.toLowerAscii()
        
        var pos = 0
        while pos < targetLine.len:
          let foundPos = targetLine.find(searchPattern, pos)
          if foundPos == -1:
            break
          
          # Check whole word if enabled
          if panel.options.wholeWord:
            let beforeChar = if foundPos > 0: targetLine[foundPos - 1] else: ' '
            let afterChar = if foundPos + searchPattern.len < targetLine.len: 
              targetLine[foundPos + searchPattern.len] else: ' '
            
            if not (beforeChar.isAlphaNumeric() or afterChar.isAlphaNumeric()):
              results.add(SearchResult(
                filePath: filePath,
                lineNumber: lineNum + 1,
                columnStart: foundPos,
                columnEnd: foundPos + searchPattern.len - 1,
                lineContent: line,
                matchedText: line[foundPos..<foundPos + searchPattern.len]
              ))
          else:
            results.add(SearchResult(
              filePath: filePath,
              lineNumber: lineNum + 1,
              columnStart: foundPos,
              columnEnd: foundPos + searchPattern.len - 1,
              lineContent: line,
              matchedText: line[foundPos..<foundPos + searchPattern.len]
            ))
          
          pos = foundPos + 1
  
  except IOError:
    discard  # Skip files that can't be read
  
  return results

proc performSearch*(panel: SearchReplacePanel) =
  ## Perform search operation
  if panel.findText.len == 0:
    return
  
  panel.searchState = ssSearching
  panel.results = @[]
  panel.currentMatchIndex = -1
  panel.totalMatches = 0
  panel.regexError = false
  panel.errorMessage = ""
  
  try:
    case panel.scope:
    of ssCurrentFile:
      # Search in current file (would need current file path)
      discard
    of ssProject:
      let files = panel.getFilesToSearch()
      for file in files:
        let fileResults = panel.searchInFile(file)
        panel.results.add(fileResults)
    
    panel.totalMatches = panel.results.len
    panel.searchState = if panel.totalMatches > 0: ssResults else: ssIdle
    
    if panel.totalMatches > 0:
      panel.currentMatchIndex = 0
      if panel.onHighlight != nil:
        panel.onHighlight(panel.results)
  
  except:
    panel.searchState = ssError
    panel.errorMessage = "Search failed"
  
  panel.componentManager.markComponentDirty(panel.id)

proc navigateToMatch(panel: SearchReplacePanel, index: int) =
  ## Navigate to a specific search result
  if index >= 0 and index < panel.results.len:
    let result = panel.results[index]
    if panel.onOpenFile != nil:
      discard panel.onOpenFile(result.filePath)
    if panel.onSetCursor != nil:
      panel.onSetCursor(result.lineNumber, result.columnStart)

proc findNext*(panel: SearchReplacePanel) =
  ## Navigate to next search result
  if panel.results.len > 0:
    let nextIndex = (panel.currentMatchIndex + 1) mod panel.results.len
    panel.currentMatchIndex = nextIndex
    panel.navigateToMatch(nextIndex)
    panel.componentManager.markComponentDirty(panel.id)

proc findPrevious*(panel: SearchReplacePanel) =
  ## Navigate to previous search result
  if panel.results.len > 0:
    let prevIndex = if panel.currentMatchIndex <= 0: 
      panel.results.len - 1 else: panel.currentMatchIndex - 1
    panel.currentMatchIndex = prevIndex
    panel.navigateToMatch(prevIndex)
    panel.componentManager.markComponentDirty(panel.id)

proc replaceCurrentMatch*(panel: SearchReplacePanel) =
  ## Replace the current match
  if panel.currentMatchIndex >= 0 and panel.currentMatchIndex < panel.results.len:
    let searchResult = panel.results[panel.currentMatchIndex]
    
    try:
      let content = readFile(searchResult.filePath)
      var lines = content.splitLines()
      
      if searchResult.lineNumber - 1 < lines.len:
        let line = lines[searchResult.lineNumber - 1]
        let beforeText = line[0..<searchResult.columnStart]
        let afterText = line[searchResult.columnEnd + 1..^1]
        
        lines[searchResult.lineNumber - 1] = beforeText & panel.replaceText & afterText
        
        let newContent = lines.join("\n")
        writeFile(searchResult.filePath, newContent)
        
        # Remove this result and update indices
        panel.results.delete(panel.currentMatchIndex)
        panel.totalMatches = panel.results.len
        
        if panel.currentMatchIndex >= panel.results.len and panel.results.len > 0:
          panel.currentMatchIndex = panel.results.len - 1
    
    except IOError:
      panel.errorMessage = "Failed to replace text"
      panel.searchState = ssError
    
    panel.componentManager.markComponentDirty(panel.id)

proc replaceAll*(panel: SearchReplacePanel) =
  ## Replace all matches
  var replacedCount = 0
  
  # Group results by file for efficient replacement
  var fileResults = initTable[string, seq[SearchResult]]()
  for result in panel.results:
    if result.filePath notin fileResults:
      fileResults[result.filePath] = @[]
    fileResults[result.filePath].add(result)
  
  for filePath, results in fileResults:
    try:
      let content = readFile(filePath)
      var lines = content.splitLines()
      
      # Sort results by line and column (reverse order for replacement)
      let sortedResults = results.sortedByIt((-it.lineNumber, -it.columnStart))
      
      for result in sortedResults:
        if result.lineNumber - 1 < lines.len:
          let line = lines[result.lineNumber - 1]
          let beforeText = line[0..<result.columnStart]
          let afterText = line[result.columnEnd + 1..^1]
          
          lines[result.lineNumber - 1] = beforeText & panel.replaceText & afterText
          replacedCount += 1
      
      let newContent = lines.join("\n")
      writeFile(filePath, newContent)
    
    except IOError:
      continue
  
  # Clear results after replacement
  panel.results = @[]
  panel.currentMatchIndex = -1
  panel.totalMatches = 0
  panel.statusText = $replacedCount & " replacements made"
  panel.statusTextTimeout = 3.0
  
  panel.componentManager.markComponentDirty(panel.id)

# Rendering using ComponentManager services
proc render*(panel: SearchReplacePanel) =
  ## Render using ComponentManager's renderer and theme
  if not panel.isVisible:
    return
  
  let bounds = panel.bounds
  
  # Draw panel background
  let bgColor = panel.componentManager.getUIColor(uiPanel)
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, bgColor)
  
  # Draw border
  let borderColor = panel.componentManager.getUIColor(uiBorder)
  rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
  
  # Render input controls
  panel.renderFindInput()
  panel.renderReplaceInput()
  panel.renderIncludeInput()
  panel.renderExcludeInput()
  
  # Render buttons
  panel.renderButtons()
  
  # Render match counter
  panel.renderMatchCounter()
  
  panel.isDirty = false

proc renderFindInput(panel: SearchReplacePanel) =
  ## Render find input field
  let control = panel.controls[ctFindInput]
  let bounds = control.bounds
  
  # Background
  let inputColor = if panel.focusedControl == ctFindInput:
    panel.componentManager.getUIColor(uiBackground)
  else:
    panel.componentManager.getUIColor(uiPanel)
  
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, inputColor)
  
  # Border
  let borderColor = if panel.focusedControl == ctFindInput:
    panel.componentManager.getUIColor(uiAccent)
  else:
    panel.componentManager.getUIColor(uiBorder)
  
  rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
  
  # Text
  let textColor = panel.componentManager.getUIColor(uiText)
  let text = panel.findText
  if text.len > 0:
    rl.drawText(text, (bounds.x + 8).int32, (bounds.y + 6).int32, 12, textColor)

proc renderReplaceInput(panel: SearchReplacePanel) =
  ## Render replace input field
  let control = panel.controls[ctReplaceInput]
  let bounds = control.bounds
  
  # Background
  let inputColor = if panel.focusedControl == ctReplaceInput:
    panel.componentManager.getUIColor(uiBackground)
  else:
    panel.componentManager.getUIColor(uiPanel)
  
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, inputColor)
  
  # Border
  let borderColor = if panel.focusedControl == ctReplaceInput:
    panel.componentManager.getUIColor(uiAccent)
  else:
    panel.componentManager.getUIColor(uiBorder)
  
  rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
  
  # Text
  let textColor = panel.componentManager.getUIColor(uiText)
  let text = panel.replaceText
  if text.len > 0:
    rl.drawText(text, (bounds.x + 8).int32, (bounds.y + 6).int32, 12, textColor)

proc renderIncludeInput(panel: SearchReplacePanel) =
  ## Render include pattern input field
  let control = panel.controls[ctIncludeInput]
  let bounds = control.bounds
  
  # Background
  let inputColor = if panel.focusedControl == ctIncludeInput:
    panel.componentManager.getUIColor(uiBackground)
  else:
    panel.componentManager.getUIColor(uiPanel)
  
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, inputColor)
  
  # Border
  let borderColor = if panel.focusedControl == ctIncludeInput:
    panel.componentManager.getUIColor(uiAccent)
  else:
    panel.componentManager.getUIColor(uiBorder)
  
  rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
  
  # Text
  let textColor = panel.componentManager.getUIColor(uiText)
  let text = panel.includePattern
  if text.len > 0:
    rl.drawText(text, (bounds.x + 8).int32, (bounds.y + 6).int32, 12, textColor)

proc renderExcludeInput(panel: SearchReplacePanel) =
  ## Render exclude pattern input field
  let control = panel.controls[ctExcludeInput]
  let bounds = control.bounds
  
  # Background
  let inputColor = if panel.focusedControl == ctExcludeInput:
    panel.componentManager.getUIColor(uiBackground)
  else:
    panel.componentManager.getUIColor(uiPanel)
  
  rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, inputColor)
  
  # Border
  let borderColor = if panel.focusedControl == ctExcludeInput:
    panel.componentManager.getUIColor(uiAccent)
  else:
    panel.componentManager.getUIColor(uiBorder)
  
  rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
  
  # Text
  let textColor = panel.componentManager.getUIColor(uiText)
  let text = panel.excludePattern
  if text.len > 0:
    rl.drawText(text, (bounds.x + 8).int32, (bounds.y + 6).int32, 12, textColor)

proc renderButtons(panel: SearchReplacePanel) =
  ## Render all buttons
  for controlType in [ctPrevious, ctNext, ctClose, ctReplace, ctReplaceAll]:
    if controlType in panel.controls:
      let control = panel.controls[controlType]
      let bounds = control.bounds
      
      # Background
      let buttonColor = if control.isHovered:
        panel.componentManager.getUIColor(uiButtonHover)
      else:
        panel.componentManager.getUIColor(uiButton)
      
      rl.drawRectangle(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, buttonColor)
      
      # Border
      let borderColor = panel.componentManager.getUIColor(uiBorder)
      rl.drawRectangleLines(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, borderColor)
      
      # Icon
      let iconSize = 12.0
      let iconX = bounds.x + (bounds.width - iconSize) / 2.0
      let iconY = bounds.y + (bounds.height - iconSize) / 2.0
      let iconColor = if control.isHovered:
        panel.componentManager.getUIColor(uiText)
      else:
        panel.componentManager.getUIColor(uiTextMuted)
      
      let iconName = case controlType:
        of ctPrevious: "chevron-up.svg"
        of ctNext: "chevron-down.svg"
        of ctClose: "close.svg"
        of ctReplace: "replace.svg"
        of ctReplaceAll: "replace-all.svg"
        else: ""
      
      if iconName.len > 0:
        drawRasterizedIcon(iconName, iconX, iconY, iconSize, iconColor)

proc renderMatchCounter(panel: SearchReplacePanel) =
  ## Render match counter and status
  let textColor = panel.componentManager.getUIColor(uiTextMuted)
  let textY = panel.bounds.y + panel.bounds.height - 20
  
  if panel.totalMatches > 0:
    let counterText = if panel.currentMatchIndex >= 0:
      $(panel.currentMatchIndex + 1) & " of " & $panel.totalMatches
    else:
      $panel.totalMatches & " matches"
    
    rl.drawText(counterText, (panel.bounds.x + 8).int32, textY.int32, 10, textColor)
  elif panel.errorMessage.len > 0:
    let errorColor = panel.componentManager.getUIColor(uiError)
    rl.drawText(panel.errorMessage, (panel.bounds.x + 8).int32, textY.int32, 10, errorColor)

# Panel visibility and state management
proc show*(panel: SearchReplacePanel) =
  ## Show the search/replace panel
  panel.isVisible = true
  # Clear focus from text editor when showing the panel so inputs capture typing
  if panel.onClearFocus != nil:
    panel.onClearFocus()
  panel.focusedControl = ctFindInput
  if panel.componentManager != nil:
    discard panel.componentManager.setComponentVisibility(panel.id, true)
    panel.componentManager.markComponentDirty(panel.id)

proc hide*(panel: SearchReplacePanel) =
  ## Hide the search/replace panel
  panel.isVisible = false
  panel.focusedControl = ctNone
  if panel.componentManager != nil:
    discard panel.componentManager.setComponentVisibility(panel.id, false)
    panel.componentManager.markComponentDirty(panel.id)

proc update*(panel: SearchReplacePanel, deltaTime: float32) =
  ## Update panel state
  if panel.statusTextTimeout > 0:
    panel.statusTextTimeout -= deltaTime
    if panel.statusTextTimeout <= 0:
      panel.statusText = ""
      panel.componentManager.markComponentDirty(panel.id)

# Utility functions
proc setScope*(panel: SearchReplacePanel, scope: SearchScope) =
  ## Set search scope
  panel.scope = scope
  panel.componentManager.markComponentDirty(panel.id)

proc setOptions*(panel: SearchReplacePanel, options: SearchOptions) =
  ## Set search options
  panel.options = options
  panel.componentManager.markComponentDirty(panel.id)

proc getCurrentMatch*(panel: SearchReplacePanel): Option[SearchResult] =
  ## Get current search result
  if panel.currentMatchIndex >= 0 and panel.currentMatchIndex < panel.results.len:
    some(panel.results[panel.currentMatchIndex])
  else:
    none(SearchResult)

proc getMatchCount*(panel: SearchReplacePanel): int =
  ## Get total match count
  panel.totalMatches

proc getCurrentMatchIndex*(panel: SearchReplacePanel): int =
  ## Get current match index
  panel.currentMatchIndex

proc clearResults*(panel: SearchReplacePanel) =
  ## Clear all search results
  panel.results = @[]
  panel.currentMatchIndex = -1
  panel.totalMatches = 0
  panel.searchState = ssIdle
  panel.componentManager.markComponentDirty(panel.id)

# Component state management
proc setVisible*(panel: SearchReplacePanel, visible: bool) =
  ## Set panel visibility using ComponentManager
  panel.isVisible = visible
  if panel.componentManager != nil:
    discard panel.componentManager.setComponentVisibility(panel.id, visible)
    panel.componentManager.markComponentDirty(panel.id)

proc cleanup*(panel: SearchReplacePanel) =
  ## Clean up resources
  panel.clearResults()
  panel.controls.clear()
  discard panel.componentManager.unregisterComponent(panel.id)

# Type alias for backward compatibility
type SearchReplace* = SearchReplacePanel
