# Git Panel Component - VS Code inspired design
import raylib as rl
import std/[strutils, options, sequtils, os, tables, sets]
import chronos
import ../infrastructure/external/git_client
import ../infrastructure/external/lsp_client_async
import ../infrastructure/rendering/[theme, renderer]
import ../infrastructure/input/[keyboard, mouse, input_handler]
import ../services/ui_service
import ../services/component_manager
import ../icons


type
  GitFileChange = object
    path: string
    stagedStatus: git_client.GitFileStatus
    workingStatus: git_client.GitFileStatus

  GitRepository = object
    currentBranch: string
    isDirty: bool

  GitPanelState = enum
    gpsLoading
    gpsReady
    gpsError

  GitPanel* = ref object of ui_service.UIComponent
    # Git state
    gitClient: GitClient
    componentManager: ComponentManager # Component manager for unified input handling
    repository: Option[GitRepository]
    fileChanges: seq[GitFileChange]
    gitState: GitPanelState

    # UI state
    themeManager: ThemeManager
    renderer: Renderer
    currentPath: string

    # Selection and interaction
    selectedFileIndex: int
    selectedFile: string
    selectedFiles: HashSet[string] # Set of selected file paths
    collapsedSections: HashSet[string] # Collapsed section states using string keys

    # Collapsible sections
    showStagedFiles: bool
    showUnstagedFiles: bool

    # Scroll and layout
    scrollOffset: float32
    lastUpdate: float
    updateInterval: float32

    # Error handling
    errorMessage: string

    # Commit area
    commitMessage: string
    commitMessageLines: seq[string] # Multi-line text as sequence of strings
    commitAreaHeight: float32       # Dynamic commit area height
    commitInputFocused: bool        # Input focus state
    cursorPosition: int             # Text cursor management
    showCommitArea: bool

# Helper functions (defined before they are used)
proc updateCommitMessageLines*(panel: GitPanel) =
  ## Update the commit message lines from the commit message string
  panel.commitMessageLines = panel.commitMessage.split('\n')

proc getCurrentLine*(panel: GitPanel): int =
  ## Get the current line number based on cursor position
  var currentPos = 0
  for i, line in panel.commitMessageLines:
    if currentPos + line.len >= panel.cursorPosition:
      return i
    currentPos += line.len + 1  # +1 for newline
  return panel.commitMessageLines.len - 1

proc getLineStartPosition*(panel: GitPanel, lineIndex: int): int =
  ## Get the cursor position at the start of a specific line
  var pos = 0
  for i in 0..<lineIndex:
    if i < panel.commitMessageLines.len:
      pos += panel.commitMessageLines[i].len + 1  # +1 for newline
  return pos

proc getGitClient*(panel: GitPanel): GitClient =
  ## Get the git client from the panel
  return panel.gitClient

proc newGitPanel*(
    id: string,
    componentManager: ComponentManager,
    gitClient: GitClient,
    themeManager: ThemeManager,
    renderer: Renderer
): GitPanel =
  if gitClient.isNil:
    raise newException(ValueError, "GitClient cannot be nil")

  result = GitPanel(
    gitClient: gitClient,
    componentManager: componentManager,
    themeManager: themeManager,
    renderer: renderer,
    gitState: gpsLoading,
    selectedFileIndex: -1,
    selectedFile: "",
    showStagedFiles: true,
    showUnstagedFiles: true,
    scrollOffset: 0.0,
    lastUpdate: 0.0,
    updateInterval: 1.0,
    errorMessage: "",
    commitMessage: "",
    commitMessageLines: @[""], # Initialize with empty line
    commitAreaHeight: 80.0, # Default minimum height
    commitInputFocused: false, # Initially not focused
    cursorPosition: 0, # Start at beginning
    showCommitArea: true,
    fileChanges: @[],
    repository: none(GitRepository),
    currentPath: "",
    selectedFiles: initHashSet[string](),
    collapsedSections: initHashSet[string]()
  )

  # Initialize UIComponent fields
  result.id = id
  result.name = "GitPanel"
  result.state = csVisible
  result.bounds = rl.Rectangle(x: 0, y: 0, width: 0, height: 0)
  result.zIndex = 1
  result.isVisible = true
  result.isEnabled = true
  result.isDirty = true
  result.parent = nil
  result.children = @[]
  result.data = initTable[string, string]()

proc setPath*(panel: GitPanel, path: string) =
  panel.currentPath = path
  panel.isDirty = true

proc setBounds*(panel: GitPanel, bounds: rl.Rectangle) =
  panel.bounds = bounds
  panel.isDirty = true

proc updateRepository*(panel: GitPanel) {.async.} =
  if panel.gitClient.isNil:
    panel.gitState = gpsError
    panel.errorMessage = "Git client not available"
    return
    
  try:
    let repoResult = await panel.gitClient.getRepositoryInfo(panel.currentPath)
    if repoResult.isOk:
      let repo = repoResult.get()
      panel.repository = some(GitRepository(
        currentBranch: repo.currentBranch,
        isDirty: repo.hasChanges
      ))
      panel.gitState = gpsReady
    else:
      panel.gitState = gpsError
      panel.errorMessage = "Failed to get repository status"
  except:
    panel.gitState = gpsError
    panel.errorMessage = "Error updating repository"

proc updateFileChanges*(panel: GitPanel) {.async.} =
  if panel.gitClient.isNil:
    panel.errorMessage = "Git client not available"
    return
    
  try:
    let statusResult = await panel.gitClient.getStatus(panel.currentPath)
    if statusResult.isOk:
      let changes = statusResult.get()
      panel.fileChanges = @[]

      for change in changes:
        let fileChange = GitFileChange(
          path: change.path,
          stagedStatus: change.stagedStatus,
          workingStatus: change.workingStatus
        )
        panel.fileChanges.add(fileChange)

      panel.isDirty = true
    else:
      panel.errorMessage = "Failed to update file changes"
  except:
    panel.errorMessage = "Failed to update file changes"

proc updateBranches*(panel: GitPanel) {.async.} =
  # Future enhancement for branch switching
  discard

# Full update
proc update*(panel: GitPanel) {.async.} =
  let currentTime = rl.getTime()
  if currentTime - panel.lastUpdate < panel.updateInterval:
    return

  panel.lastUpdate = currentTime
  await panel.updateRepository()

  if panel.gitState == gpsReady:
    await panel.updateFileChanges()
    await panel.updateBranches()



# Git operations
proc stageFile*(panel: GitPanel, filePath: string) {.async.} =
  if panel.repository.isNone or panel.gitClient.isNil:
    return

  try:
    let fullPath = panel.currentPath / filePath
    let addResult = await panel.gitClient.addFile(fullPath)
    if addResult.isOk:
      await panel.updateFileChanges()
  except:
    panel.errorMessage = "Failed to stage file"

proc unstageFile*(panel: GitPanel, filePath: string) {.async.} =
  if panel.repository.isNone or panel.gitClient.isNil:
    return

  try:
    let fullPath = panel.currentPath / filePath
    let resetResult = await panel.gitClient.resetFile(fullPath)
    if resetResult.isOk:
      await panel.updateFileChanges()
  except:
    panel.errorMessage = "Failed to unstage file"

proc commitChanges*(panel: GitPanel, message: string) {.async.} =
  if panel.repository.isNone or panel.gitClient.isNil or message.strip().len == 0:
    return

  try:
    let commitResult = await panel.gitClient.commit(panel.currentPath, message)
    if commitResult.isOk:
      panel.commitMessage = ""
      await panel.updateFileChanges()
  except:
    panel.errorMessage = "Failed to commit changes"

# Helper function to handle async operations
proc handleAsyncOperation*(panel: GitPanel, operation: proc() {.async.}) =
  asyncSpawn operation()

# Layout calculation
type
  LayoutInfo = object
    headerBounds: Rectangle
    commitBounds: Rectangle
    fileListBounds: Rectangle

# Helper functions for consolidating similar operations
proc getUIFont*(panel: GitPanel): Option[ptr rl.Font] =
  let font = panel.renderer.getFont("ui")
  if font != nil:
    result = some(font)
  else:
    result = none(ptr rl.Font)

proc getUIColors*(panel: GitPanel): tuple[
  background: rl.Color,
  text: rl.Color,
  textMuted: rl.Color,
  accent: rl.Color,
  border: rl.Color,
  selection: rl.Color,
  sidebar: rl.Color
] =
  result = (
    background: panel.themeManager.getUIColor(uiBackground),
    text: panel.themeManager.getUIColor(uiText),
    textMuted: panel.themeManager.getUIColor(uiTextMuted),
    accent: panel.themeManager.getUIColor(uiAccent),
    border: panel.themeManager.getUIColor(uiBorder),
    selection: panel.themeManager.getUIColor(uiSelection),
    sidebar: panel.themeManager.getUIColor(uiSidebar)
  )

proc getFilesByStatus*(panel: GitPanel): tuple[unstaged: seq[GitFileChange],
    staged: seq[GitFileChange]] =
  result.unstaged = panel.fileChanges.filterIt(it.workingStatus !=
      git_client.gfsUnmodified)
  result.staged = panel.fileChanges.filterIt(it.stagedStatus !=
      git_client.gfsUnmodified)

proc getStatusColor*(status: git_client.GitFileStatus): rl.Color =
  case status:
    of git_client.gfsModified: rl.Color(r: 255, g: 215, b: 0, a: 255) # Yellow
    of git_client.gfsUntracked: rl.Color(r: 63, g: 169, b: 245, a: 255) # Blue
    of git_client.gfsAdded: rl.Color(r: 0, g: 255, b: 0, a: 255) # Green
    of git_client.gfsDeleted: rl.Color(r: 255, g: 0, b: 0, a: 255) # Red
    else: rl.Color(r: 128, g: 128, b: 128, a: 255) # Gray

proc measureTextOnce*(panel: GitPanel, font: ptr rl.Font, text: string,
    fontSize: float32 = 12.0): rl.Vector2 =
  panel.renderer.measureText(font[], text, fontSize, 1.0)

proc calculateCommitAreaHeight*(panel: GitPanel): float32 =
  const minHeight = 80.0
  const maxHeight = 120.0
  const lineHeight = 16.0
  const padding = 16.0
  const buttonHeight = 24.0
  const textPadding = 4.0
  const inputPadding = 8.0

  let maxLineWidth = panel.bounds.width - (inputPadding + textPadding) * 2
  var totalVisualLines = 0

  let fontOpt = panel.getUIFont()
  if fontOpt.isSome and panel.commitMessageLines.len > 0:
    let font = fontOpt.get()
    for line in panel.commitMessageLines:
      if line.len == 0:
        totalVisualLines += 1
      else:
        let lineWidth = panel.measureTextOnce(font, line).x
        if lineWidth <= maxLineWidth:
          totalVisualLines += 1
        else:
          # Calculate wrapped lines
          var remainingText = line
          while remainingText.len > 0:
            var wrapIndex = max(1, remainingText.len)
            for j in countdown(remainingText.len - 1, 0):
              let testText = remainingText[0..j]
              if panel.measureTextOnce(font, testText).x <= maxLineWidth:
                wrapIndex = j + 1
                break
            totalVisualLines += 1
            remainingText = if wrapIndex < remainingText.len: remainingText[
                wrapIndex..^1] else: ""
  else:
    totalVisualLines = 1

  let textHeight = float32(totalVisualLines) * lineHeight
  let totalHeight = textHeight + padding + buttonHeight + 8.0

  result = max(minHeight, min(maxHeight, totalHeight))

proc calculateCursorLineAndColumn*(panel: GitPanel): (int, int) =
  # Calculate which line and column the cursor is on
  var currentPos = 0
  var lineIndex = 0
  var columnIndex = 0

  for i, line in panel.commitMessageLines:
    let lineLength = line.len + 1 # +1 for newline character (except last line)
    let isLastLine = i == panel.commitMessageLines.len - 1
    let actualLineLength = if isLastLine: line.len else: lineLength

    if currentPos + actualLineLength >= panel.cursorPosition:
      # Cursor is on this line
      lineIndex = i
      columnIndex = panel.cursorPosition - currentPos
      break

    currentPos += actualLineLength
    lineIndex = i + 1

  # Ensure we don't go beyond the last line
  if lineIndex >= panel.commitMessageLines.len:
    lineIndex = max(0, panel.commitMessageLines.len - 1)
    columnIndex = if panel.commitMessageLines.len > 0: panel.commitMessageLines[
        lineIndex].len else: 0

  result = (lineIndex, columnIndex)

proc calculateLayout*(panel: GitPanel): LayoutInfo =
  let bounds = panel.bounds
  let headerHeight = 40.0
  let commitAreaHeight = panel.calculateCommitAreaHeight()
  let fileListY = bounds.y + headerHeight + commitAreaHeight
  let fileListHeight = bounds.height - headerHeight - commitAreaHeight

  result = LayoutInfo(
    headerBounds: Rectangle(
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: headerHeight
    ),
    commitBounds: Rectangle(
      x: bounds.x,
      y: bounds.y + headerHeight,
      width: bounds.width,
      height: commitAreaHeight
    ),
    fileListBounds: Rectangle(
      x: bounds.x,
      y: fileListY,
      width: bounds.width,
      height: fileListHeight
    )
  )

# Move handleMouseEvent and handleKeyboardEvent above handleInput
proc handleMouseEvent*(panel: GitPanel, event: MouseEvent): bool =
  ## Handle mouse events for git panel
  if not panel.isVisible:
    return false
  
  let mouseVec = rl.Vector2(x: event.position.x, y: event.position.y)
  let layout = panel.calculateLayout()
  
  case event.eventType:
  of metScrolled:
    # Handle scroll wheel
    let wheel = event.scrollDelta.y
    if wheel != 0:
      let listBounds = layout.fileListBounds
      if rl.checkCollisionPointRec(mouseVec, listBounds):
        panel.scrollOffset = max(0.0, panel.scrollOffset - wheel * 20.0)
        panel.isDirty = true
        return true
  of metButtonPressed:
    if event.button == mbLeft:
      # Check commit area clicks first (new position at top)
      let commitBounds = layout.commitBounds
      if rl.checkCollisionPointRec(mouseVec, commitBounds):
        # Check commit button click
        const inputPadding = 8.0
        const buttonGap = 8.0
        const buttonWidth = 70.0
        const buttonHeight = 24.0
        let inputBounds = rl.Rectangle(
          x: commitBounds.x + inputPadding,
          y: commitBounds.y + inputPadding,
          width: commitBounds.width - (inputPadding * 2),
          height: commitBounds.height - inputPadding - 32.0 - buttonGap
        )
        let buttonBounds = rl.Rectangle(
          x: commitBounds.x + commitBounds.width - buttonWidth - inputPadding,
          y: inputBounds.y + inputBounds.height + buttonGap,
          width: buttonWidth,
          height: buttonHeight
        )

        if rl.checkCollisionPointRec(mouseVec, buttonBounds):
          # Commit button clicked
          let hasValidMessage = panel.commitMessageLines.len > 0 and
                               (panel.commitMessageLines.len > 1 or
                                   panel.commitMessageLines[0].strip().len > 0)
          if hasValidMessage:
            let fullMessage = panel.commitMessageLines.join("\n")
            asyncSpawn panel.commitChanges(fullMessage)
            return true
        else:
          # Click in commit input area - set focus and cursor position
          panel.commitInputFocused = true

          # Calculate cursor position based on click location
          const inputPadding = 8.0
          const textPadding = 4.0
          const lineHeight = 16.0
          let clickX = mouseVec.x - (commitBounds.x + inputPadding + textPadding)
          let clickY = mouseVec.y - (commitBounds.y + inputPadding + textPadding)
          let clickedLine = int(clickY / lineHeight)

          # Find the character position within that line
          if clickedLine >= 0 and clickedLine < panel.commitMessageLines.len:
            let line = panel.commitMessageLines[clickedLine]
            let fontOpt = panel.getUIFont()

            if fontOpt.isSome:
              let font = fontOpt.get()
              var bestDistance = float32.high
              var bestPosition = 0

              for i in 0..line.len:
                let textPortion = if i == 0: "" else: line[0..<i]
                let textWidth = panel.measureTextOnce(font, textPortion).x
                let distance = abs(textWidth - clickX)

                if distance < bestDistance:
                  bestDistance = distance
                  bestPosition = i

              # Calculate absolute cursor position
              var absolutePosition = 0
              for i in 0..<clickedLine:
                if i < panel.commitMessageLines.len:
                  absolutePosition += panel.commitMessageLines[i].len + 1
              absolutePosition += bestPosition

              panel.cursorPosition = min(absolutePosition,
                  panel.commitMessage.len)
          else:
            panel.cursorPosition = panel.commitMessage.len

          panel.isDirty = true
          return true
      else:
        # Click outside commit area - remove focus
        panel.commitInputFocused = false
        panel.isDirty = true

      # Check file list area clicks (new dynamic position)
      let listBounds = layout.fileListBounds
      if rl.checkCollisionPointRec(mouseVec, listBounds):
        const itemHeight = 28.0
        const sectionHeaderHeight = 25.0
        const sectionSpacing = 10.0
        let clickY = mouseVec.y - listBounds.y + panel.scrollOffset

        var currentY = 0.0
        let files = panel.getFilesByStatus()

        # Helper proc for handling file clicks
        proc handleFileClick(file: GitFileChange, index: int): bool =
          # Toggle file selection
          if file.path in panel.selectedFiles:
            panel.selectedFiles.excl(file.path)
          else:
            panel.selectedFiles.incl(file.path)
          panel.isDirty = true
          return true

        # Check each section
        let (unstaged, staged) = files
        
        # Handle unstaged files
        if unstaged.len > 0:
          # Check section header click for unstaged
          let headerBounds = rl.Rectangle(
            x: listBounds.x,
            y: listBounds.y + currentY - panel.scrollOffset,
            width: listBounds.width,
            height: sectionHeaderHeight
          )
          if rl.checkCollisionPointRec(mouseVec, headerBounds):
            # Toggle section visibility
            let statusKey = "unstaged"
            if statusKey in panel.collapsedSections:
              panel.collapsedSections.excl(statusKey)
            else:
              panel.collapsedSections.incl(statusKey)
            panel.isDirty = true
            return true

          currentY += sectionHeaderHeight

          # Check file clicks if section is not collapsed
          if "unstaged" notin panel.collapsedSections:
            for i, file in unstaged:
              let fileBounds = rl.Rectangle(
                x: listBounds.x,
                y: listBounds.y + currentY - panel.scrollOffset,
                width: listBounds.width,
                height: itemHeight
              )
              if rl.checkCollisionPointRec(mouseVec, fileBounds):
                return handleFileClick(file, i)
              currentY += itemHeight

            currentY += sectionSpacing

        # Handle staged files
        if staged.len > 0:
          # Check section header click for staged
          let headerBounds = rl.Rectangle(
            x: listBounds.x,
            y: listBounds.y + currentY - panel.scrollOffset,
            width: listBounds.width,
            height: sectionHeaderHeight
          )
          if rl.checkCollisionPointRec(mouseVec, headerBounds):
            # Toggle section visibility
            let statusKey = "staged"
            if statusKey in panel.collapsedSections:
              panel.collapsedSections.excl(statusKey)
            else:
              panel.collapsedSections.incl(statusKey)
            panel.isDirty = true
            return true

          currentY += sectionHeaderHeight

          # Check file clicks if section is not collapsed
          if "staged" notin panel.collapsedSections:
            for i, file in staged:
              let fileBounds = rl.Rectangle(
                x: listBounds.x,
                y: listBounds.y + currentY - panel.scrollOffset,
                width: listBounds.width,
                height: itemHeight
              )
              if rl.checkCollisionPointRec(mouseVec, fileBounds):
                return handleFileClick(file, i)
              currentY += itemHeight

            currentY += sectionSpacing

        return true
  else:
    return false

proc handleKeyboardEvent*(panel: GitPanel, event: InputEvent): bool =
  ## Handle keyboard events for git panel
  if not panel.isVisible:
    return false
  
  # Handle commit input focus
  if panel.commitInputFocused:
    case event.eventType:
    of ietCharInput:
      let char = char(event.character.int32)
      if char.ord >= 32 and char.ord <= 126:  # Printable ASCII
        # Insert character at cursor position
        if panel.cursorPosition <= panel.commitMessage.len:
          panel.commitMessage.insert($char, panel.cursorPosition)
          panel.cursorPosition += 1
          panel.updateCommitMessageLines()
          panel.isDirty = true
          return true
    of ietKeyPressed:
      case event.key:
      of ekBackspace:
        if panel.cursorPosition > 0:
          panel.commitMessage.delete(panel.cursorPosition - 1, panel.cursorPosition - 1)
          panel.cursorPosition -= 1
          panel.updateCommitMessageLines()
          panel.isDirty = true
          return true
      of ekDelete:
        if panel.cursorPosition < panel.commitMessage.len:
          panel.commitMessage.delete(panel.cursorPosition, panel.cursorPosition)
          panel.updateCommitMessageLines()
          panel.isDirty = true
          return true
      of ekLeft:
        if panel.cursorPosition > 0:
          panel.cursorPosition -= 1
          panel.isDirty = true
          return true
      of ekRight:
        if panel.cursorPosition < panel.commitMessage.len:
          panel.cursorPosition += 1
          panel.isDirty = true
          return true
      of ekUp:
        # Move cursor up one line
        let currentLine = panel.getCurrentLine()
        if currentLine > 0:
          let targetLine = currentLine - 1
          panel.cursorPosition = panel.getLineStartPosition(targetLine)
          panel.isDirty = true
          return true
      of ekDown:
        # Move cursor down one line
        let currentLine = panel.getCurrentLine()
        if currentLine < panel.commitMessageLines.len - 1:
          let targetLine = currentLine + 1
          panel.cursorPosition = panel.getLineStartPosition(targetLine)
          panel.isDirty = true
          return true
      of ekEnter:
        # Insert newline at cursor position
        if panel.cursorPosition <= panel.commitMessage.len:
          panel.commitMessage.insert("\n", panel.cursorPosition)
          panel.cursorPosition += 1
          panel.updateCommitMessageLines()
          panel.isDirty = true
          return true
      of ekEscape:
        # Remove focus from commit input
        panel.commitInputFocused = false
        panel.isDirty = true
        return true
      else:
        discard
    else:
      discard
  
  return false

proc handleInput*(panel: GitPanel, event: UnifiedInputEvent): bool =
  ## Handle unified input events for git panel
  if not panel.isVisible:
    return false
  
  case event.kind:
  of uiekMouse:
    return panel.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return panel.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc registerInputHandlers*(panel: GitPanel): Result[void, EditorError] =
  ## Register input handlers with ComponentManager
  # Git panel doesn't need additional keyboard shortcuts
  return ok()

# Rendering
proc renderHeader*(panel: GitPanel) =
  const headerHeight = 40.0
  let bounds = panel.bounds
  let headerBounds = rl.Rectangle(x: bounds.x, y: bounds.y, width: bounds.width,
      height: headerHeight)
  let colors = panel.getUIColors()

  # Draw header background
  panel.renderer.drawRectangle(headerBounds, colors.background)

  let fontOpt = panel.getUIFont()
  if fontOpt.isSome:
    let font = fontOpt.get()

    # Draw title
    panel.renderer.drawText(
      font[],
      "Changes",
      rl.Vector2(x: bounds.x + 8, y: bounds.y + 12),
      14.0, 1.0, colors.text
    )

    # Draw badge with count
    let files = panel.getFilesByStatus()
    if files.unstaged.len > 0:
      let badgeText = $files.unstaged.len
      const badgeWidth = 20.0
      let badgeX = bounds.x + bounds.width - 30
      let badgeBounds = rl.Rectangle(x: badgeX, y: bounds.y + 10,
          width: badgeWidth, height: 20)

      panel.renderer.drawRectangle(badgeBounds, colors.accent)
      panel.renderer.drawText(font[], badgeText, rl.Vector2(x: badgeX + 6,
          y: bounds.y + 12), 12.0, 1.0, rl.White)

    # Draw repository info if available
    if panel.repository.isSome:
      let repo = panel.repository.get()
      panel.renderer.drawText(
        font[], repo.currentBranch,
        rl.Vector2(x: bounds.x + 8, y: bounds.y + 28),
        12.0, 1.0, colors.textMuted
      )

proc renderFileRow*(panel: GitPanel, change: GitFileChange,
    bounds: rl.Rectangle, isSelected: bool, index: int) =
  let fontOpt = panel.getUIFont()
  if fontOpt.isNone:
    return

  let font = fontOpt.get()
  let colors = panel.getUIColors()
  const itemHeight = 28.0
  const padding = 8.0
  const iconSize = 16.0

  # Background for selected item
  if isSelected:
    panel.renderer.drawRectangle(bounds, colors.selection)

  # Git status icon
  let iconX = bounds.x + padding
  let iconY = bounds.y + (itemHeight - iconSize) / 2
  panel.renderer.drawText(
    font[], "☺",
    rl.Vector2(x: iconX, y: iconY),
    iconSize, 1.0, rl.Color(r: 255, g: 215, b: 0, a: 255)
  )

  # Filename and path
  let filename = change.path.extractFilename()
  let filenameX = iconX + iconSize + padding
  panel.renderer.drawText(font[], filename, rl.Vector2(x: filenameX,
      y: bounds.y + 6), 12.0, 1.0, colors.text)

  let path = change.path.splitFile().dir
  if path.len > 0:
    let pathX = filenameX + panel.measureTextOnce(font, filename).x + 8
    panel.renderer.drawText(font[], path, rl.Vector2(x: pathX, y: bounds.y + 6),
        10.0, 1.0, colors.textMuted)

  # Action buttons
  const buttonAreaWidth = 80.0
  let buttonAreaX = bounds.x + bounds.width - buttonAreaWidth - padding
  let buttonColor = if isSelected: colors.accent else: colors.border

  proc drawActionButton(x: float32, iconName: string) =
    let buttonBounds = rl.Rectangle(x: x, y: bounds.y + 4, width: 20, height: 20)
    panel.renderer.drawRectangle(buttonBounds, buttonColor)
    # Draw SVG icon centered in button
    let iconSize = 12.0
    let iconX = x + (20.0 - iconSize) / 2.0
    let iconY = bounds.y + 4 + (20.0 - iconSize) / 2.0
    drawRasterizedIcon(iconName, iconX, iconY, iconSize, rl.White)

  if change.workingStatus != git_client.gfsUnmodified:
    drawActionButton(buttonAreaX + 40, "git-stage.svg")

  if change.stagedStatus != git_client.gfsUnmodified:
    drawActionButton(buttonAreaX + 10, "git-unstage.svg")

  # Status letter
  let statusLetter = if change.stagedStatus !=
      git_client.gfsUnmodified: change.stagedStatus else: change.workingStatus
  let statusColor = getStatusColor(statusLetter)
  panel.renderer.drawText(
    font[], $statusLetter,
    rl.Vector2(x: bounds.x + bounds.width - 20, y: bounds.y + 6),
    14.0, 1.0, statusColor
  )

proc renderFileList*(panel: GitPanel) =
  let layout = panel.calculateLayout()
  let listBounds = layout.fileListBounds
  let fontOpt = panel.getUIFont()

  if fontOpt.isNone:
    return

  let font = fontOpt.get()
  let colors = panel.getUIColors()
  const itemHeight = 28.0
  const sectionHeaderHeight = 25.0
  const sectionSpacing = 10.0

  # Check if Git is available
  if not panel.gitClient.isAvailable:
    panel.renderer.drawText(font[], "Git is not available or not installed",
                           rl.Vector2(x: listBounds.x + 8, y: listBounds.y +
                               20), 12.0, 1.0, colors.textMuted)
    panel.renderer.drawText(font[], "Please install Git to use version control features",
                           rl.Vector2(x: listBounds.x + 8, y: listBounds.y +
                               40), 10.0, 1.0, colors.textMuted)
    return

  var currentY = 0.0
  let files = panel.getFilesByStatus()

  proc renderSection(title: string, fileList: seq[GitFileChange]) =
    if fileList.len > 0:
      # Section header
      let renderY = listBounds.y + currentY - panel.scrollOffset
      if renderY >= listBounds.y - sectionHeaderHeight and renderY <
          listBounds.y + listBounds.height:
        panel.renderer.drawText(font[], title, rl.Vector2(x: listBounds.x + 8,
            y: renderY), 12.0, 1.0, colors.text)
      currentY += sectionHeaderHeight

      # Files
      for i, change in fileList:
        let renderY = listBounds.y + currentY - panel.scrollOffset
        if renderY >= listBounds.y - itemHeight and renderY < listBounds.y +
            listBounds.height:
          let isSelected = i == panel.selectedFileIndex
          let itemBounds = rl.Rectangle(x: listBounds.x, y: renderY,
              width: listBounds.width, height: itemHeight)
          panel.renderFileRow(change, itemBounds, isSelected, i)
        currentY += itemHeight

      currentY += sectionSpacing

  # Render sections
  if panel.showUnstagedFiles:
    renderSection("▶ Changes", files.unstaged)

  if panel.showStagedFiles:
    renderSection("▶ Staged Changes", files.staged)

proc renderCommitArea*(panel: GitPanel) =
  let layout = panel.calculateLayout()
  let commitBounds = layout.commitBounds
  let colors = panel.getUIColors()

  # Update dynamic height
  panel.commitAreaHeight = panel.calculateCommitAreaHeight()

  # Commit area background with border
  panel.renderer.drawRectangle(commitBounds, colors.background)
  let borderBounds = rl.Rectangle(x: commitBounds.x, y: commitBounds.y,
      width: commitBounds.width, height: 1.0)
  panel.renderer.drawRectangle(borderBounds, colors.border)

  let fontOpt = panel.getUIFont()
  if fontOpt.isNone:
    return

  let font = fontOpt.get()

  # Commit message input area
  const inputPadding = 8.0
  const buttonGap = 8.0  # Gap between input and button
  let inputBounds = rl.Rectangle(
    x: commitBounds.x + inputPadding,
    y: commitBounds.y + inputPadding,
    width: commitBounds.width - (inputPadding * 2),
    height: commitBounds.height - inputPadding - 32.0 - buttonGap
  )

  # Input styling based on focus state
  let inputBackgroundColor = if panel.commitInputFocused: colors.selection else: colors.sidebar
  let inputBorderColor = if panel.commitInputFocused: colors.accent else: colors.border
  const borderWidth = 1.0  # Always use thin border

  # Draw input background and border
  panel.renderer.drawRectangle(inputBounds, inputBackgroundColor)

  proc drawBorder(x, y, w, h: float32) =
    panel.renderer.drawRectangle(rl.Rectangle(x: x, y: y, width: w, height: h), inputBorderColor)

  drawBorder(inputBounds.x, inputBounds.y, inputBounds.width, borderWidth)
  drawBorder(inputBounds.x, inputBounds.y + inputBounds.height - borderWidth,
      inputBounds.width, borderWidth)
  drawBorder(inputBounds.x, inputBounds.y, borderWidth, inputBounds.height)
  drawBorder(inputBounds.x + inputBounds.width - borderWidth, inputBounds.y,
      borderWidth, inputBounds.height)

  # Multi-line text rendering
  const lineHeight = 16.0
  const textPadding = 4.0
  let maxLineWidth = inputBounds.width - (textPadding * 2)

  proc renderTextLine(text: string, lineIndex: int) =
    let lineY = inputBounds.y + textPadding + (float32(lineIndex) * lineHeight)
    if lineY < inputBounds.y + inputBounds.height - textPadding:
      panel.renderer.drawText(font[], text, rl.Vector2(x: inputBounds.x +
          textPadding, y: lineY), 12.0, 1.0, colors.text)

  if panel.commitMessageLines.len > 0 and (panel.commitMessageLines.len > 1 or
      panel.commitMessageLines[0].len > 0):
    var currentLineIndex = 0
    for line in panel.commitMessageLines:
      if line.len == 0:
        currentLineIndex += 1
      else:
        let lineWidth = panel.measureTextOnce(font, line).x
        if lineWidth <= maxLineWidth:
          renderTextLine(line, currentLineIndex)
          currentLineIndex += 1
        else:
          # Handle line wrapping
          var remainingText = line
          while remainingText.len > 0:
            var wrapIndex = max(1, remainingText.len)
            for j in countdown(remainingText.len - 1, 0):
              let testText = remainingText[0..j]
              if panel.measureTextOnce(font, testText).x <= maxLineWidth:
                wrapIndex = j + 1
                break

            let lineText = remainingText[0..<wrapIndex]
            renderTextLine(lineText, currentLineIndex)
            currentLineIndex += 1
            remainingText = if wrapIndex < remainingText.len: remainingText[
                wrapIndex..^1] else: ""
  else:
    panel.renderer.drawText(font[], "Enter commit message...",
                           rl.Vector2(x: inputBounds.x + textPadding,
                               y: inputBounds.y + textPadding),
                           12.0, 1.0, colors.textMuted)

  # Draw text cursor when focused
  if panel.commitInputFocused:
    let (cursorLine, cursorColumn) = panel.calculateCursorLineAndColumn()

    # Calculate cursor position accounting for line wrapping
    var visualLine = 0
    var cursorX = inputBounds.x + textPadding
    var cursorY = inputBounds.y + textPadding

    # Find the visual line and X position for the cursor
    for i in 0..<cursorLine:
      if i < panel.commitMessageLines.len:
        let line = panel.commitMessageLines[i]
        if line.len == 0:
          visualLine += 1
        else:
          let lineWidth = panel.renderer.measureText(font[], line, 12.0, 1.0).x
          if lineWidth <= maxLineWidth:
            visualLine += 1
          else:
            # Count wrapped lines
            var remainingText = line
            while remainingText.len > 0:
              var wrapIndex = remainingText.len
              for j in countdown(remainingText.len - 1, 0):
                let testText = remainingText[0..j]
                let testWidth = panel.renderer.measureText(font[], testText,
                    12.0, 1.0).x
                if testWidth <= maxLineWidth:
                  wrapIndex = j + 1
                  break
              if wrapIndex == 0:
                wrapIndex = 1
              visualLine += 1
              remainingText = if wrapIndex < remainingText.len: remainingText[
                  wrapIndex..^1] else: ""

    # Calculate cursor position within the current line
    if cursorLine < panel.commitMessageLines.len:
      let currentLine = panel.commitMessageLines[cursorLine]
      let textBeforeCursor = if cursorColumn <= currentLine.len: currentLine[
          0..<cursorColumn] else: currentLine

      # Handle line wrapping for cursor positioning
      var remainingText = currentLine
      var currentColumn = 0
      var foundCursor = false

      while remainingText.len > 0 and not foundCursor:
        var wrapIndex = remainingText.len
        for j in countdown(remainingText.len - 1, 0):
          let testText = remainingText[0..j]
          let testWidth = panel.renderer.measureText(font[], testText, 12.0, 1.0).x
          if testWidth <= maxLineWidth:
            wrapIndex = j + 1
            break
        if wrapIndex == 0:
          wrapIndex = 1

        if currentColumn + wrapIndex >= cursorColumn:
          # Cursor is on this wrapped line
          let cursorTextPortion = textBeforeCursor[currentColumn..<min(
              cursorColumn, currentColumn + wrapIndex)]
          cursorX = inputBounds.x + textPadding + panel.renderer.measureText(
              font[], cursorTextPortion, 12.0, 1.0).x
          cursorY = inputBounds.y + textPadding + (float32(visualLine) * lineHeight)
          foundCursor = true
        else:
          currentColumn += wrapIndex
          visualLine += 1
          remainingText = if wrapIndex < remainingText.len: remainingText[
              wrapIndex..^1] else: ""
    else:
      # Cursor is beyond the last line
      cursorY = inputBounds.y + textPadding + (float32(visualLine) * lineHeight)

    # Draw the cursor as a vertical line
    if cursorY < inputBounds.y + inputBounds.height - textPadding:
      let cursorColor = panel.themeManager.getUIColor(uiText)
      let cursorBounds = rl.Rectangle(
        x: cursorX,
        y: cursorY,
        width: 1.0,
        height: lineHeight
      )
      panel.renderer.drawRectangle(cursorBounds, cursorColor)

  # Commit button
  const buttonWidth = 70.0
  const buttonHeight = 24.0
  let buttonBounds = rl.Rectangle(
    x: commitBounds.x + commitBounds.width - buttonWidth - inputPadding,
    y: inputBounds.y + inputBounds.height + buttonGap,
    width: buttonWidth, height: buttonHeight
  )

  let hasValidMessage = panel.commitMessageLines.len > 0 and
                       (panel.commitMessageLines.len > 1 or
                           panel.commitMessageLines[0].strip().len > 0)

  # Check if mouse is hovering over button
  let mousePos = rl.getMousePosition()
  let mouseVec = rl.Vector2(x: mousePos.x, y: mousePos.y)
  let isHovering = rl.checkCollisionPointRec(mouseVec, buttonBounds)
  let isPressed = isHovering and rl.isMouseButtonDown(rl.MouseButton.Left)
  
  # Use proper button colors from theme with interactive states
  let buttonColor = if not hasValidMessage:
    panel.themeManager.getUIColor(uiButton).withAlpha(128)  # Semi-transparent when disabled
  elif isPressed:
    panel.themeManager.getUIColor(uiButtonActive)
  elif isHovering:
    panel.themeManager.getUIColor(uiButtonHover)
  else:
    panel.themeManager.getUIColor(uiButton)
  
  let buttonTextColor = if hasValidMessage: 
    panel.themeManager.getUIColor(uiText)
  else: 
    panel.themeManager.getUIColor(uiTextDisabled)

  # Draw button with shadow
  # Draw subtle shadow for depth (only when enabled and not pressed)
  if hasValidMessage and not isPressed:
    let shadowOffset = rl.Vector2(x: 0, y: 1)
    let shadowColor = rl.Color(r: 0, g: 0, b: 0, a: 40)
    let shadowBounds = rl.Rectangle(
      x: buttonBounds.x + shadowOffset.x,
      y: buttonBounds.y + shadowOffset.y,
      width: buttonBounds.width,
      height: buttonBounds.height
    )
    panel.renderer.drawRectangle(shadowBounds, shadowColor)
  
  # Draw the main button
  panel.renderer.drawRectangle(buttonBounds, buttonColor)
  
  # Add subtle border for better definition
  let borderColor = if isHovering and hasValidMessage:
    panel.themeManager.getUIColor(uiBorderActive)
  else:
    panel.themeManager.getUIColor(uiBorder)
  panel.renderer.drawRectangleOutline(buttonBounds, borderColor)
  
  # Draw icon and text
  let iconSize = 12.0
  let textSize = panel.renderer.measureText(font[], "Commit", 12.0, 1.0)
  let totalWidth = iconSize + 4.0 + textSize.x  # icon + gap + text
  let startX = buttonBounds.x + (buttonBounds.width - totalWidth) / 2.0
  
  # Draw commit icon
  let iconX = startX
  let iconY = buttonBounds.y + (buttonBounds.height - iconSize) / 2.0
  if hasValidMessage:
    drawRasterizedIcon("git-commit.svg", iconX, iconY, iconSize, buttonTextColor)
  
  # Draw text next to icon
  let textX = startX + iconSize + 4.0
  let textY = buttonBounds.y + (buttonBounds.height - textSize.y) / 2.0
  panel.renderer.drawText(font[], "Commit", rl.Vector2(x: textX, y: textY),
                         12.0, 1.0, buttonTextColor)

proc render*(panel: GitPanel) =
  let bounds = panel.bounds
  let colors = panel.getUIColors()

  # Background
  panel.renderer.drawRectangle(bounds, colors.sidebar)

  # Render components in order
  panel.renderHeader()
  panel.renderCommitArea()
  panel.renderFileList()

  # Error overlay
  if panel.errorMessage.len > 0:
    let fontOpt = panel.getUIFont()
    if fontOpt.isSome:
      let errorColor = rl.Color(r: 255, g: 100, b: 100, a: 255)
      panel.renderer.drawText(fontOpt.get()[], panel.errorMessage,
                             rl.Vector2(x: bounds.x + 8, y: bounds.y +
                                 bounds.height - 20),
                             12.0, 1.0, errorColor)
