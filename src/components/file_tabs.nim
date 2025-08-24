## File Tab System - Core data structures and types
## 
## This module provides the core file tab data structures including:
## - FileTabState enum for tab states
## - FileTab type for individual tab management
## - FileTabBar component inheriting from UIComponent
## - Basic property management and bounds calculation

import std/[tables, options, times, os, strutils, sequtils]
import raylib as rl
import ../services/component_manager
import ../services/ui_service # For UIComponent type
import ../services/editor_service # For file saving functionality

import ../infrastructure/input/[keyboard, mouse, input_handler] # For UnifiedInputEvent
import ../infrastructure/rendering/theme # For UI color types
import ../infrastructure/ui/cursor_manager # For cursor priority types
import confirmation_dialog # For save confirmation dialogs
import results

const TabDragThreshold = 8.0 # pixels

# File tab state enumeration
type
  FileTabState* = enum
    ftsNormal = "normal"
    ftsActive = "active"
    ftsModified = "modified"
    ftsHover = "hover"
    ftsClosing = "closing"

# Individual file tab data structure
type
  FileTab* = ref object
    id*: string                      # Unique identifier for the tab
    filePath*: string                # Full file path
    fileName*: string                # Just the filename part
    displayName*: string             # Shortened name for display
    fullPath*: string                # Complete file path (same as filePath for clarity)
    state*: FileTabState             # Current tab state
    isModified*: bool                # Whether file has unsaved changes
    bounds*: rl.Rectangle            # Tab bounds for positioning and click detection
    closeButtonBounds*: rl.Rectangle # Close button bounds within the tab
    isClosable*: bool                # Whether tab can be closed
    lastAccessed*: Time              # Last time this tab was accessed

# File tab # File tab bar component
type FileTabBar* = ref object of UIComponent
    # ComponentManager integration
    componentManager*: ComponentManager
    editorService*: EditorService     # For file saving operations

    # Tab collection and state
    tabs*: seq[FileTab]           # Collection of open tabs
    activeTabIndex*: int          # Index of currently active tab
    lastActiveTabIndex*: int      # Track the previously active tab for switching

    # Layout configuration
    maxTabWidth*: float32         # Maximum width for individual tabs
    minTabWidth*: float32         # Minimum width for individual tabs
    tabHeight*: float32           # Height of tabs
    scrollOffset*: float32        # Horizontal scroll offset for overflow
    maxScrollOffset*: float32     # Maximum scroll offset

    # Visual configuration
    showCloseButtons*: bool       # Whether to show close buttons on tabs
    showScrollButtons*: bool      # Whether to show scroll buttons for overflow
    showModifiedIndicators*: bool # Whether to show modified indicators
    showFileIcons*: bool          # Whether to show file type icons
    tabSpacing*: float32          # Spacing between tabs

    # Input handling state
    hoveredTabIndex*: int         # Index of currently hovered tab (-1 if none)
    draggedTabIndex*: int         # Index of tab being dragged (-1 if none)
    isDragging*: bool             # Whether a tab is currently being dragged
    dragStartX*: float32          # X position where drag started
    lastMousePos*: rl.Vector2     # Track mouse position for drag rendering

    # Dialog components
    confirmationDialog*: ConfirmationDialog # Dialog for save confirmations

    # Event callbacks
    onTabActivated*: proc(tabBar: FileTabBar, tabIndex: int)
    onTabClosed*: proc(tabBar: FileTabBar, tabIndex: int)
    onTabReordered*: proc(tabBar: FileTabBar, fromIndex: int, toIndex: int)

# Tab display name resolution types and functions
type
  TabDisplayInfo* = object
    displayName*: string       # The name to show in the tab
    tooltip*: string           # Full path tooltip text
    showPath*: bool            # Whether path segments are shown
    pathSegments*: seq[string] # Path components used in display

proc resolveDisplayPaths*(filePaths: seq[string]): Table[string,
    TabDisplayInfo] =
  ## Resolve display names for a collection of file paths
  ## Returns a mapping of filePath -> TabDisplayInfo
  ## Implements smart path shortening algorithm:
  ## 1. Start with just filename
  ## 2. Add parent directories as needed to resolve conflicts
  ## 3. Use ellipsis for very long paths

  result = initTable[string, TabDisplayInfo]()

  if filePaths.len == 0:
    return

  # Step 1: Group files by filename to identify conflicts
  var filenameGroups = initTable[string, seq[string]]()

  for filePath in filePaths:
    let filename = extractFilename(filePath)
    if not filenameGroups.hasKey(filename):
      filenameGroups[filename] = @[]
    filenameGroups[filename].add(filePath)

  # Step 2: For each group, determine the minimal path needed to distinguish files
  for filename, paths in filenameGroups:
    if paths.len == 1:
      # No conflict - just use filename
      let filePath = paths[0]
      result[filePath] = TabDisplayInfo(
        displayName: filename,
        tooltip: filePath,
        showPath: false,
        pathSegments: @[filename]
      )
    else:
      # Conflict exists - need to show distinguishing path segments
      var pathComponents: seq[seq[string]] = @[]

      # Split each path into components (excluding filename)
      for filePath in paths:
        let dir = parentDir(filePath)
        var components: seq[string] = @[]
        if dir != "" and dir != ".":
          # Split directory path into components
          let normalizedDir = dir.replace('\\', '/')
          components = normalizedDir.split('/').filterIt(it.len > 0)
        components.add(filename) # Add filename as last component
        pathComponents.add(components)

      # For each file, find the minimal path needed to distinguish it from others
      for i, filePath in paths:
        let components = pathComponents[i]
        let filename = components[^1]

        # Try to use just the parent directory and filename
        if components.len >= 2:
          let parentDir = components[^2]

          # Check if parent/filename is unique
          var isUnique = true
          for j, otherPath in paths:
            if i != j:
              let otherComponents = pathComponents[j]
              if otherComponents.len >= 2 and
                 otherComponents[^1] == filename and
                 otherComponents[^2] == parentDir:
                isUnique = false
                break

          if isUnique:
            result[filePath] = TabDisplayInfo(
              displayName: parentDir & "/" & filename,
              tooltip: filePath,
              showPath: true,
              pathSegments: @[parentDir, filename]
            )
            continue

        # If parent/filename isn't unique, try increasing path segments
        var found = false
        for segmentsToUse in countup(2, components.len):
          let startIdx = max(0, components.len - segmentsToUse)
          let displaySegments = components[startIdx..^1]
          let candidateName = displaySegments.join("/")

          # Check if this name conflicts with any other file
          var hasConflict = false
          for j, otherPath in paths:
            if i != j:
              let otherComponents = pathComponents[j]
              if otherComponents.len >= segmentsToUse:
                let otherStartIdx = max(0, otherComponents.len - segmentsToUse)
                let otherDisplaySegments = otherComponents[otherStartIdx..^1]
                let otherCandidateName = otherDisplaySegments.join("/")

                if candidateName == otherCandidateName:
                  hasConflict = true
                  break

          if not hasConflict:
            # Found a unique name with minimal segments
            result[filePath] = TabDisplayInfo(
              displayName: candidateName,
              tooltip: filePath,
              showPath: true,
              pathSegments: displaySegments
            )
            found = true
            break

        # If no unique name found even with full path, use full path
        if not found:
          result[filePath] = TabDisplayInfo(
            displayName: components.join("/"),
            tooltip: filePath,
            showPath: true,
            pathSegments: components
          )

proc truncateDisplayName*(displayName: string, maxWidth: float32,
    font: ptr rl.Font, fontSize: float32): string =
  ## Truncate a display name to fit within the given width, preserving the filename
  ## Uses ellipsis (...) in the middle of the path while keeping the filename visible

  if font == nil:
    return displayName

  let textWidth = rl.measureText(font[], displayName, fontSize, 1.0).x
  if textWidth <= maxWidth:
    return displayName

  # If the text is too long, try to preserve the filename by truncating the path
  let parts = displayName.split("/")
  if parts.len <= 1:
    # Single component - truncate from the end
    let ellipsis = "..."
    let ellipsisWidth = rl.measureText(font[], ellipsis, fontSize, 1.0).x
    let availableWidth = maxWidth - ellipsisWidth

    if availableWidth <= 0:
      return ellipsis

    # Binary search for the right length
    var left = 0
    var right = displayName.len
    var bestLength = 0

    while left <= right:
      let mid = (left + right) div 2
      let testText = displayName[0..<mid]
      let testWidth = rl.measureText(font[], testText, fontSize, 1.0).x

      if testWidth <= availableWidth:
        bestLength = mid
        left = mid + 1
      else:
        right = mid - 1

    if bestLength > 0:
      return displayName[0..<bestLength] & ellipsis
    else:
      return ellipsis
  else:
    # Multiple components - preserve filename and truncate path
    let filename = parts[^1]
    let filenameWidth = rl.measureText(font[], filename, fontSize, 1.0).x
    let ellipsis = ".../"
    let ellipsisWidth = rl.measureText(font[], ellipsis, fontSize, 1.0).x
    let availablePathWidth = maxWidth - filenameWidth - ellipsisWidth

    if availablePathWidth <= 0:
      # Not enough space for path - just show filename
      if filenameWidth <= maxWidth:
        return filename
      else:
        # Even filename doesn't fit - truncate it
        return truncateDisplayName(filename, maxWidth, font, fontSize)

    # Try to fit as much of the path as possible
    let pathParts = parts[0..^2] # All parts except filename
    var pathText = ""

    # Add path components from the beginning until we run out of space
    for i, part in pathParts:
      let testPath = if pathText.len == 0: part else: pathText & "/" & part
      let testWidth = rl.measureText(font[], testPath, fontSize, 1.0).x

      if testWidth <= availablePathWidth:
        pathText = testPath
      else:
        break

    if pathText.len > 0:
      return pathText & "/" & ellipsis & filename
    else:
      return ellipsis & filename

proc updateTabDisplayNames*(tabBar: FileTabBar) =
  ## Update display names for all tabs in the tab bar using the resolution algorithm
  if tabBar.tabs.len == 0:
    return

  # Collect all file paths
  let filePaths = tabBar.tabs.mapIt(it.filePath)

  # Resolve display names
  let displayInfo = resolveDisplayPaths(filePaths)

  # Update each tab with its resolved display name
  for tab in tabBar.tabs:
    if displayInfo.hasKey(tab.filePath):
      let info = displayInfo[tab.filePath]
      tab.displayName = info.displayName

proc getTabTooltip*(tab: FileTab): string =
  ## Get the tooltip text for a tab (full file path)
  return tab.filePath

proc shouldShowPath*(tab: FileTab): bool =
  ## Check if the tab should show path information in its display name
  return tab.displayName.contains("/")

# Forward declarations
proc forceCloseTab*(tabBar: FileTabBar, index: int): bool
proc renderTab(tabBar: FileTabBar, tab: FileTab, tabIndex: int, colors: auto, font: rl.Font)
proc renderCloseButton(tabBar: FileTabBar, tab: FileTab, colors: auto)
proc scrollLeft*(tabBar: FileTabBar)
proc scrollRight*(tabBar: FileTabBar)
proc previousTab*(tabBar: FileTabBar)
proc nextTab*(tabBar: FileTabBar)
proc isPointInLeftScrollButton*(tabBar: FileTabBar, x, y: float32): bool
proc isPointInRightScrollButton*(tabBar: FileTabBar, x, y: float32): bool

# Constructor for FileTab
proc newFileTab*(
  id: string,
  filePath: string,
  fileName: string = "",
  displayName: string = ""
): FileTab =
  ## Create a new FileTab with the given parameters
  ## If fileName is empty, it will be extracted from filePath
  ## If displayName is empty, it will default to fileName

  let actualFileName = if fileName.len > 0: fileName else: extractFilename(filePath)
  let actualDisplayName = if displayName.len >
      0: displayName else: actualFileName

  result = FileTab(
    id: id,
    filePath: filePath,
    fileName: actualFileName,
    displayName: actualDisplayName,
    fullPath: filePath,
    state: ftsNormal,
    isModified: false,
    bounds: rl.Rectangle(x: 0, y: 0, width: 0, height: 0),
    closeButtonBounds: rl.Rectangle(x: 0, y: 0, width: 0, height: 0),
    isClosable: true,
    lastAccessed: times.getTime()
  )

# Constructor for FileTabBar
proc newFileTabBar*(
  id: string,
  componentManager: ComponentManager,
  editorService: EditorService,
  tabHeight: float32 = 32.0,
  minTabWidth: float32 = 120.0,
  maxTabWidth: float32 = 240.0
): FileTabBar =
  ## Create a new FileTabBar component with ComponentManager integration

  result = FileTabBar(
    componentManager: componentManager,
    editorService: editorService,
    tabs: @[],
    activeTabIndex: -1,
    lastActiveTabIndex: -1,
    maxTabWidth: maxTabWidth,
    minTabWidth: minTabWidth,
    tabHeight: tabHeight,
    scrollOffset: 0.0,
    maxScrollOffset: 0.0,
    showCloseButtons: true,
    showModifiedIndicators: true,
    showFileIcons: false,
    tabSpacing: 0.0,
    hoveredTabIndex: -1,
    draggedTabIndex: -1,
    isDragging: false,
    dragStartX: 0.0,
    lastMousePos: rl.Vector2(x: 0.0, y: 0.0)
  )

  # Initialize confirmation dialog
  result.confirmationDialog = newConfirmationDialog(componentManager, id & "_confirmation_dialog")

  # Initialize UIComponent fields
  result.id = id
  result.name = "FileTabBar"
  result.state = csVisible
  result.bounds = rl.Rectangle(x: 0, y: 0, width: 0, height: tabHeight)
  result.zIndex = 0 # Lowest possible z-index to avoid interfering with other components
  result.isVisible = true
  result.isEnabled = true
  result.isDirty = false
  result.parent = nil
  result.children = @[]
  result.data = initTable[string, string]()

# Basic property management methods for FileTab
proc updateState*(tab: FileTab, newState: FileTabState) =
  ## Update the state of a file tab
  if tab.state != newState:
    tab.state = newState
    tab.lastAccessed = times.getTime()

proc setModified*(tab: FileTab, modified: bool) =
  ## Set the modified state of a file tab
  if tab.isModified != modified:
    tab.isModified = modified
    # Update state to reflect modification
    if modified and tab.state == ftsNormal:
      tab.state = ftsModified
    elif not modified and tab.state == ftsModified:
      tab.state = ftsNormal

proc updateTabModifiedState*(tabBar: FileTabBar, filePath: string,
    modified: bool) =
  ## Update the modified state of the tab for the given file path
  for tab in tabBar.tabs:
    if tab.filePath == filePath:
      tab.setModified(modified)
      tabBar.isDirty = true
      break

proc updateDisplayName*(tab: FileTab, newDisplayName: string) =
  ## Update the display name of a file tab
  tab.displayName = newDisplayName

# Bounds calculation methods for FileTab
proc calculateTabBounds*(tab: FileTab, x: float32, y: float32, width: float32,
    height: float32) =
  ## Calculate and set the bounds for a file tab
  tab.bounds = rl.Rectangle(x: x, y: y, width: width, height: height)

  # Calculate close button bounds (16x16 px, 4px from right edge with additional gap)
  let closeButtonSize = 16.0f
  let closeButtonMargin = 4.0f
  let rightGap = 4.0f # Additional gap from tab right edge
  tab.closeButtonBounds = rl.Rectangle(
    x: x + width - closeButtonSize - closeButtonMargin - rightGap,
    y: y + (height - closeButtonSize) / 2.0f,
    width: closeButtonSize,
    height: closeButtonSize
  )

proc isPointInTab*(tab: FileTab, x: float32, y: float32): bool =
  ## Check if a point is within the tab bounds
  rl.checkCollisionPointRec(rl.Vector2(x: x, y: y), tab.bounds)

proc isPointInCloseButton*(tab: FileTab, x: float32, y: float32): bool =
  ## Check if a point is within the close button bounds
  rl.checkCollisionPointRec(rl.Vector2(x: x, y: y), tab.closeButtonBounds)

# Basic property management methods for FileTabBar
proc addTab*(tabBar: FileTabBar, tab: FileTab): int =
  ## Add a tab to the tab bar and return its index
  tabBar.tabs.add(tab)
  let index = tabBar.tabs.len - 1

  # If this is the first tab, make it active
  if tabBar.activeTabIndex == -1:
    tabBar.activeTabIndex = index
    tab.updateState(ftsActive)

  # Update display names for all tabs to handle potential conflicts
  tabBar.updateTabDisplayNames()

  # Mark the tab bar as dirty for re-rendering
  tabBar.isDirty = true

  return index

proc removeTab*(tabBar: FileTabBar, index: int): bool =
  ## Remove a tab at the given index, returns true if successful
  if index < 0 or index >= tabBar.tabs.len:
    return false

  tabBar.tabs.delete(index)

  # Adjust active tab index if necessary
  if tabBar.activeTabIndex == index:
    # If we removed the active tab, determine the new active tab
    if tabBar.tabs.len > 0:
      # Try to switch to the previous tab (left neighbor)
      if index > 0 and index - 1 < tabBar.tabs.len:
        tabBar.activeTabIndex = index - 1
      elif index < tabBar.tabs.len:
        # If we removed the first tab, switch to the new first tab
        tabBar.activeTabIndex = index
      else:
        # Fallback to the last tab
        tabBar.activeTabIndex = tabBar.tabs.len - 1

      if tabBar.activeTabIndex >= 0:
        tabBar.tabs[tabBar.activeTabIndex].updateState(ftsActive)
        # Explicitly trigger onTabActivated callback
        if tabBar.onTabActivated != nil:
          tabBar.onTabActivated(tabBar, tabBar.activeTabIndex)
    else:
      tabBar.activeTabIndex = -1
      tabBar.lastActiveTabIndex = -1
  elif tabBar.activeTabIndex > index:
    # Adjust active index if it was after the removed tab
    tabBar.activeTabIndex -= 1
    # Also adjust lastActiveTabIndex if needed
    if tabBar.lastActiveTabIndex > index:
      tabBar.lastActiveTabIndex -= 1

  # Update display names for remaining tabs (conflicts may be resolved)
  tabBar.updateTabDisplayNames()

  # Mark the tab bar as dirty for re-rendering
  tabBar.isDirty = true

  return true

proc getActiveTab*(tabBar: FileTabBar): Option[FileTab] =
  ## Get the currently active tab, if any
  if tabBar.activeTabIndex >= 0 and tabBar.activeTabIndex < tabBar.tabs.len:
    some(tabBar.tabs[tabBar.activeTabIndex])
  else:
    none(FileTab)

proc setActiveTab*(tabBar: FileTabBar, index: int): bool =
  ## Set the active tab by index, returns true if successful
  if index < 0 or index >= tabBar.tabs.len or index == tabBar.activeTabIndex:
    return false

  # Update previous active tab state
  if tabBar.activeTabIndex >= 0 and tabBar.activeTabIndex < tabBar.tabs.len:
    let prevTab = tabBar.tabs[tabBar.activeTabIndex]
    if prevTab.isModified:
      prevTab.updateState(ftsModified)
    else:
      prevTab.updateState(ftsNormal)
    
    # Track the last active tab before switching
    tabBar.lastActiveTabIndex = tabBar.activeTabIndex

  # Update new active tab
  tabBar.activeTabIndex = index
  tabBar.tabs[index].updateState(ftsActive)

  # Mark the tab bar as dirty for re-rendering
  tabBar.isDirty = true

  return true

proc findTabByPath*(tabBar: FileTabBar, filePath: string): Option[int] =
  ## Find a tab by its file path, returns the index if found
  for i, tab in tabBar.tabs:
    if tab.filePath == filePath:
      return some(i)
  return none(int)

proc getTabCount*(tabBar: FileTabBar): int =
  ## Get the number of tabs in the tab bar
  tabBar.tabs.len

# Layout calculation methods for FileTabBar
proc calculateTabLayout*(tabBar: FileTabBar, availableWidth: float32) =
  ## Calculate the layout for all tabs within the available width
  if tabBar.tabs.len == 0:
    return

  let totalTabs = tabBar.tabs.len.float32
  var tabWidth = availableWidth / totalTabs

  # Constrain tab width to min/max bounds
  if tabWidth < tabBar.minTabWidth:
    tabWidth = tabBar.minTabWidth
  elif tabWidth > tabBar.maxTabWidth:
    tabWidth = tabBar.maxTabWidth

  # Calculate total width needed
  let totalNeededWidth = totalTabs * tabWidth

  # Update max scroll offset if tabs exceed available width
  if totalNeededWidth > availableWidth:
    tabBar.maxScrollOffset = totalNeededWidth - availableWidth
  else:
    tabBar.maxScrollOffset = 0.0
    tabBar.scrollOffset = 0.0

  # Constrain scroll offset
  if tabBar.scrollOffset > tabBar.maxScrollOffset:
    tabBar.scrollOffset = tabBar.maxScrollOffset
  elif tabBar.scrollOffset < 0.0:
    tabBar.scrollOffset = 0.0

  # Calculate bounds for each tab
  var currentX = tabBar.bounds.x - tabBar.scrollOffset
  let tabY = tabBar.bounds.y

  for i, tab in tabBar.tabs:
    tab.calculateTabBounds(currentX, tabY, tabWidth, tabBar.tabHeight)
    currentX += tabWidth + tabBar.tabSpacing

proc updateBounds*(tabBar: FileTabBar, bounds: rl.Rectangle) =
  ## Update the bounds of the tab bar and recalculate tab layout
  tabBar.bounds = bounds
  tabBar.calculateTabLayout(bounds.width)
  tabBar.isDirty = true

# Utility methods
proc getTabAt*(tabBar: FileTabBar, x: float32, y: float32): Option[int] =
  ## Get the index of the tab at the given coordinates
  for i, tab in tabBar.tabs:
    if tab.isPointInTab(x, y):
      return some(i)
  return none(int)

proc isCloseButtonAt*(tabBar: FileTabBar, x: float32, y: float32): Option[int] =
  ## Check if the coordinates are over a close button, return tab index if so
  for i, tab in tabBar.tabs:
    if tab.isPointInCloseButton(x, y):
      return some(i)
  return none(int)

# Tab activation methods
proc activateTab*(tabBar: FileTabBar, index: int): bool =
  ## Activate a tab by index and trigger callback, returns true if successful
  if tabBar.setActiveTab(index):
    # Trigger callback if set
    if tabBar.onTabActivated != nil:
      tabBar.onTabActivated(tabBar, index)
    return true
  return false

# Tab collection management methods
proc addTabByPath*(tabBar: FileTabBar, filePath: string): int =
  ## Add a tab for the given file path and return its index
  ## If tab already exists, activate it and return existing index
  let existingIndex = tabBar.findTabByPath(filePath)
  if existingIndex.isSome:
    # Activate the existing tab
    discard tabBar.activateTab(existingIndex.get())
    return existingIndex.get()

  # Create new tab
  let fileName = extractFilename(filePath)
  let tabId = "tab_" & $tabBar.tabs.len & "_" & fileName
  let newTab = newFileTab(tabId, filePath, fileName)

  let newIndex = tabBar.addTab(newTab)
  # Always activate the newly added tab when opening from explorer
  discard tabBar.activateTab(newIndex)
  return newIndex

proc removeTabByPath*(tabBar: FileTabBar, filePath: string): bool =
  ## Remove a tab by its file path, returns true if successful
  let tabIndex = tabBar.findTabByPath(filePath)
  if tabIndex.isSome:
    return tabBar.removeTab(tabIndex.get())
  return false

proc removeTabByIndex*(tabBar: FileTabBar, index: int): bool =
  ## Remove a tab by its index, returns true if successful
  return tabBar.removeTab(index)

proc reorderTab*(tabBar: FileTabBar, fromIndex: int, toIndex: int): bool =
  ## Reorder a tab from one position to another, returns true if successful
  if fromIndex < 0 or fromIndex >= tabBar.tabs.len or
     toIndex < 0 or toIndex >= tabBar.tabs.len or
     fromIndex == toIndex:
    return false

  # Move the tab
  let tab = tabBar.tabs[fromIndex]
  tabBar.tabs.delete(fromIndex)
  tabBar.tabs.insert(tab, toIndex)

  # Adjust active tab index if necessary
  if tabBar.activeTabIndex == fromIndex:
    tabBar.activeTabIndex = toIndex
  elif tabBar.activeTabIndex > fromIndex and tabBar.activeTabIndex <= toIndex:
    tabBar.activeTabIndex -= 1
  elif tabBar.activeTabIndex < fromIndex and tabBar.activeTabIndex >= toIndex:
    tabBar.activeTabIndex += 1

  # Mark as dirty for re-rendering
  tabBar.isDirty = true

  # Trigger callback if set
  if tabBar.onTabReordered != nil:
    tabBar.onTabReordered(tabBar, fromIndex, toIndex)

  return true

proc activateTabByPath*(tabBar: FileTabBar, filePath: string): bool =
  ## Activate a tab by file path, returns true if successful
  let tabIndex = tabBar.findTabByPath(filePath)
  if tabIndex.isSome:
    return tabBar.activateTab(tabIndex.get())
  return false

proc closeTab*(tabBar: FileTabBar, index: int): bool =
  ## Close a tab by index with callback, returns true if successful
  if index < 0 or index >= tabBar.tabs.len:
    return false

  let tab = tabBar.tabs[index]
  
  # Check if tab is modified and prompt to save
  if tab.isModified:
    # Show confirmation dialog for unsaved changes
    let fileName = extractFilename(tab.filePath)
    let message = "Do you want to save the changes you made to \"" & fileName & "\"?\n\nYour changes will be lost if you don't save them."
    
    tabBar.confirmationDialog.show(message, proc(saveResult: ConfirmationResult) =
      case saveResult:
      of crSave:
        # Save the file using the editor service
        let saveFileResult = tabBar.editorService.saveFile(tab.filePath)
        if saveFileResult.isOk:
          # Mark the tab as unmodified after successful save
          tab.isModified = false
          # Now close the tab
          discard tabBar.forceCloseTab(index)
        else:
          echo "Failed to save file: ", tab.filePath, " - ", saveFileResult.error.msg
          # Don't close the tab if save failed
      of crDontSave:
        # Close without saving
        discard tabBar.forceCloseTab(index)
      of crCancel:
        # Don't close the tab
        echo "Close operation cancelled"
    )
    
    # Return false to indicate the close operation is pending user confirmation
    return false
  else:
    # File is not modified, close immediately
    return tabBar.forceCloseTab(index)

proc forceCloseTab*(tabBar: FileTabBar, index: int): bool =
  ## Force close a tab without confirmation, used internally after user confirms
  if index < 0 or index >= tabBar.tabs.len:
    return false

  let wasActive = index == tabBar.activeTabIndex

  # Remove the tab first (this will update activeTabIndex)
  let result = tabBar.removeTab(index)

  # Trigger callback after tab is removed and activeTabIndex is updated
  if tabBar.onTabClosed != nil:
    tabBar.onTabClosed(tabBar, index)

  return result

proc closeTabByPath*(tabBar: FileTabBar, filePath: string): bool =
  ## Close a tab by file path, returns true if successful
  let tabIndex = tabBar.findTabByPath(filePath)
  if tabIndex.isSome:
    return tabBar.closeTab(tabIndex.get())
  return false

proc closeActiveTab*(tabBar: FileTabBar): bool =
  ## Close the currently active tab, returns true if successful
  if tabBar.activeTabIndex >= 0:
    return tabBar.closeTab(tabBar.activeTabIndex)
  return false

proc hasTab*(tabBar: FileTabBar, filePath: string): bool =
  ## Check if a tab exists for the given file path
  tabBar.findTabByPath(filePath).isSome

proc isEmpty*(tabBar: FileTabBar): bool =
  ## Check if the tab bar has no tabs
  tabBar.tabs.len == 0

proc clear*(tabBar: FileTabBar) =
  ## Remove all tabs from the tab bar
  tabBar.tabs.setLen(0)
  tabBar.activeTabIndex = -1
  tabBar.hoveredTabIndex = -1
  tabBar.draggedTabIndex = -1
  tabBar.isDragging = false
  tabBar.scrollOffset = 0.0
  tabBar.maxScrollOffset = 0.0
  tabBar.isDirty = true

proc render*(tabBar: FileTabBar, font: rl.Font = rl.getFontDefault()) =
  ## Render the file tab bar
  if tabBar.tabs.len == 0 or not tabBar.isVisible or tabBar.bounds.width <= 0 or
      tabBar.bounds.height <= 0:
    return

  # Use theme manager for colors
  let theme = tabBar.componentManager.themeManager
  let colors = (
    background: theme.getUIColor(uiPanel),
    activeTab: rl.Color(r: 40, g: 40, b: 40, a: 255), # Dark background for active tab
    inactiveTab: theme.getUIColor(uiPanel),
    text: theme.getUIColor(uiText),
    textMuted: theme.getUIColor(uiTextMuted),
    border: theme.getUIColor(uiBorder),
    hover: rl.Color(r: 60, g: 60, b: 60, a: 255), # Darker hover color instead of blue
    dragGhost: rl.Color(r: 180, g: 180, b: 180, a: 128),
    dragIndicator: rl.Color(r: 0, g: 120, b: 255, a: 180)
  )

  # Calculate tab layout if needed
  tabBar.calculateTabLayout(tabBar.bounds.width)

  # Draw each tab (skip ghost tab if dragging)
  for i, tab in tabBar.tabs:
    if tabBar.isDragging and i == tabBar.draggedTabIndex:
      continue # Skip drawing the dragged tab here
    renderTab(tabBar, tab, i, colors, font)

  # Draw ghost tab if dragging
  if tabBar.isDragging and tabBar.draggedTabIndex >= 0 and
      tabBar.draggedTabIndex < tabBar.tabs.len:
    let ghostTab = tabBar.tabs[tabBar.draggedTabIndex]
    let ghostRect = rl.Rectangle(
      x: tabBar.lastMousePos.x - 20.0,
      y: tabBar.lastMousePos.y - 10.0,
      width: ghostTab.bounds.width,
      height: ghostTab.bounds.height
    )
    rl.drawRectangle(ghostRect.x.int32, ghostRect.y.int32,
        ghostRect.width.int32, ghostRect.height.int32, colors.dragGhost)
    # Draw tab text on ghost
    let fontSize = 12.0
    let textPadding = 8.0
    let closeButtonWidth = if tabBar.showCloseButtons: 20.0 else: 0.0
    let availableWidth = ghostRect.width - (textPadding * 2) - closeButtonWidth
    let displayText = truncateDisplayName(ghostTab.displayName, availableWidth,
        font.addr, fontSize)
    let textY = ghostRect.y + (ghostRect.height - fontSize) / 2
    rl.drawText(font, displayText, rl.Vector2(x: ghostRect.x + textPadding,
        y: textY), fontSize, 1.0, colors.text)
    # Draw insertion indicator
    let insertIndex = tabBar.hoveredTabIndex
    if insertIndex >= 0 and insertIndex < tabBar.tabs.len:
      let indicatorX = tabBar.tabs[insertIndex].bounds.x
      let indicatorY = tabBar.tabs[insertIndex].bounds.y
      let indicatorHeight = tabBar.tabs[insertIndex].bounds.height
      let indicatorRect = rl.Rectangle(
        x: indicatorX - 2,
        y: indicatorY,
        width: 4,
        height: indicatorHeight
      )
      rl.drawRectangle(indicatorRect.x.int32, indicatorRect.y.int32,
          indicatorRect.width.int32, indicatorRect.height.int32,
          colors.dragIndicator)
  # Draw bottom border
  let borderRect = rl.Rectangle(
    x: tabBar.bounds.x,
    y: tabBar.bounds.y + tabBar.bounds.height - 1,
    width: tabBar.bounds.width,
    height: 1.0
  )
  rl.drawRectangle(borderRect.x.int32, borderRect.y.int32,
      borderRect.width.int32, borderRect.height.int32, colors.border)

  # Render confirmation dialog if visible
  if tabBar.confirmationDialog.isVisible:
    tabBar.confirmationDialog.render()

proc renderTab(tabBar: FileTabBar, tab: FileTab, tabIndex: int, colors: auto,
    font: rl.Font) =
  ## Render an individual tab
  if tab.bounds.width <= 0 or tab.bounds.height <= 0:
    return

  let isActive = tabIndex == tabBar.activeTabIndex
  let isHovered = tabIndex == tabBar.hoveredTabIndex

  # Choose tab color with modified state consideration
  let baseTabColor =
    if isActive: colors.activeTab
    elif isHovered: colors.hover
    else: colors.inactiveTab
  
  # Add subtle tint for modified files
  let tabColor = 
    if tab.isModified and not isActive:
      # Add a very subtle warm tint to indicate modification
      rl.Color(
        r: min(255'u8, baseTabColor.r + 10'u8),
        g: min(255'u8, baseTabColor.g + 5'u8),
        b: baseTabColor.b,
        a: baseTabColor.a
      )
    else:
      baseTabColor

  # Draw tab background
  rl.drawRectangle(tab.bounds.x.int32, tab.bounds.y.int32,
      tab.bounds.width.int32, tab.bounds.height.int32, tabColor)

  # Draw tab borders (except bottom for active tab)
  let borderColor = colors.border

  # Left border
  if tabIndex > 0:
    let leftBorder = rl.Rectangle(
      x: tab.bounds.x,
      y: tab.bounds.y,
      width: 1.0,
      height: tab.bounds.height
    )
    rl.drawRectangle(leftBorder.x.int32, leftBorder.y.int32,
        leftBorder.width.int32, leftBorder.height.int32, borderColor)

  # Right border
  let rightBorder = rl.Rectangle(
    x: tab.bounds.x + tab.bounds.width - 1,
    y: tab.bounds.y,
    width: 1.0,
    height: tab.bounds.height
  )
  rl.drawRectangle(rightBorder.x.int32, rightBorder.y.int32,
      rightBorder.width.int32, rightBorder.height.int32, borderColor)

  # Top border
  let topBorder = rl.Rectangle(
    x: tab.bounds.x,
    y: tab.bounds.y,
    width: tab.bounds.width,
    height: 1.0
  )
  rl.drawRectangle(topBorder.x.int32, topBorder.y.int32, topBorder.width.int32,
      topBorder.height.int32, borderColor)

  # Bottom border (only for inactive tabs)
  if not isActive:
    let bottomBorder = rl.Rectangle(
      x: tab.bounds.x,
      y: tab.bounds.y + tab.bounds.height - 1,
      width: tab.bounds.width,
      height: 1.0
    )
    rl.drawRectangle(bottomBorder.x.int32, bottomBorder.y.int32,
        bottomBorder.width.int32, bottomBorder.height.int32, borderColor)

  # Draw tab text
  let textColor = if isActive: colors.text else: colors.textMuted
  let fontSize = 12.0
  let textPadding = 8.0

  # Calculate available width for text (leaving space for close button with gap)
  let closeButtonWidth = if tabBar.showCloseButtons: 24.0 else: 0.0 # Increased for gap
  let availableWidth = tab.bounds.width - (textPadding * 2) - closeButtonWidth

  # Truncate display name if needed
  let displayText = truncateDisplayName(tab.displayName, availableWidth,
      font.addr, fontSize)

  # Center text vertically
  let textY = tab.bounds.y + (tab.bounds.height - fontSize) / 2
  let textPos = rl.Vector2(x: tab.bounds.x + textPadding, y: textY)

  # Use the provided font for tab text
  rl.drawText(font, displayText, textPos, fontSize, 1.0, textColor)

  # Draw modified indicator (asterisk like other editors)
  if tab.isModified and tabBar.showModifiedIndicators:
    let asterisk = "*"
    let asteriskSize = fontSize * 0.9 # Slightly smaller than main text
    let asteriskWidth = rl.measureText(font, asterisk, asteriskSize.float32, 1.0.float32).x
    let asteriskX = tab.bounds.x + tab.bounds.width - 28.0 - asteriskWidth # Before close button
    let asteriskY = tab.bounds.y + (tab.bounds.height - asteriskSize) / 2
    let asteriskPos = rl.Vector2(x: asteriskX, y: asteriskY)
    
    # Use a more prominent color for the asterisk
    let asteriskColor = rl.Color(r: 255, g: 180, b: 0, a: 255) # Orange/amber color
    rl.drawText(font, asterisk, asteriskPos, asteriskSize.float32, 1.0.float32, asteriskColor)

  # Draw close button
  if tabBar.showCloseButtons and tab.isClosable:
    renderCloseButton(tabBar, tab, colors)

proc renderCloseButton(tabBar: FileTabBar, tab: FileTab, colors: auto) =
  ## Render the close button for a tab
  let buttonSize = 12.0
  let buttonPadding = 2.0
  let rightGap = 4.0 # Gap from tab right edge

  # Update close button bounds with proper gap
  tab.closeButtonBounds = rl.Rectangle(
    x: tab.bounds.x + tab.bounds.width - buttonSize - buttonPadding * 2 -
    rightGap,
    y: tab.bounds.y + (tab.bounds.height - buttonSize) / 2,
    width: buttonSize + buttonPadding * 2,
    height: buttonSize + buttonPadding * 2
  )

  # Draw close button background on hover
  let mousePos = rl.getMousePosition()
  let isHovered = rl.checkCollisionPointRec(mousePos, tab.closeButtonBounds)

  if isHovered:
    rl.drawRectangle(tab.closeButtonBounds.x.int32,
        tab.closeButtonBounds.y.int32, tab.closeButtonBounds.width.int32,
        tab.closeButtonBounds.height.int32, colors.hover)

  # Draw X symbol with better visibility
  let centerX = tab.closeButtonBounds.x + tab.closeButtonBounds.width / 2
  let centerY = tab.closeButtonBounds.y + tab.closeButtonBounds.height / 2
  let crossSize = buttonSize / 2.5 # Make it slightly larger

  # Use a more visible color and thicker lines
  let color = if isHovered: colors.text else: colors.textMuted
  let lineThickness = 1.5 # Thicker lines for better visibility

  # Draw X using two diagonal lines (more recognizable as close button)
  # Top-left to bottom-right diagonal
  let diag1 = rl.Rectangle(
    x: centerX - crossSize,
    y: centerY - crossSize,
    width: crossSize * 2,
    height: lineThickness
  )
  # Rotate this rectangle by 45 degrees - for now use simple approach

  # Bottom-left to top-right diagonal
  let diag2 = rl.Rectangle(
    x: centerX - crossSize,
    y: centerY + crossSize,
    width: crossSize * 2,
    height: lineThickness
  )

  # For now, draw a simple + rotated to X using lines
  # Diagonal line 1: top-left to bottom-right
  for i in 0..<int(crossSize * 2):
    let x = centerX - crossSize + float32(i)
    let y = centerY - crossSize + float32(i)
    let pixelRect = rl.Rectangle(x: x, y: y, width: lineThickness,
        height: lineThickness)
    rl.drawRectangle(pixelRect.x.int32, pixelRect.y.int32,
        pixelRect.width.int32, pixelRect.height.int32, color)

  # Diagonal line 2: top-right to bottom-left
  for i in 0..<int(crossSize * 2):
    let x = centerX + crossSize - float32(i)
    let y = centerY - crossSize + float32(i)
    let pixelRect = rl.Rectangle(x: x, y: y, width: lineThickness,
        height: lineThickness)
    rl.drawRectangle(pixelRect.x.int32, pixelRect.y.int32,
        pixelRect.width.int32, pixelRect.height.int32, color)

proc handleInput*(tabBar: FileTabBar, event: UnifiedInputEvent): bool =
  ## Handle input for the file tab bar
  ## Returns true if input was handled

  # First check if confirmation dialog is visible and handle its input
  if tabBar.confirmationDialog.isVisible:
    return tabBar.confirmationDialog.handleInput(event)

  # Only handle input if the tab bar has tabs and is visible
  if tabBar.tabs.len == 0 or not tabBar.isVisible:
    # Debug: FileTabBar - no tabs or not visible
    return false

  case event.kind:
  of uiekMouse:
    let mouseEvent = event.mouseEvent
    let mousePos = mouseEvent.position
    tabBar.lastMousePos = rl.Vector2(x: mousePos.x, y: mousePos.y)

    # Check if mouse is within the tab bar bounds
    if float32(mousePos.x) < tabBar.bounds.x or 
       float32(mousePos.x) > tabBar.bounds.x + tabBar.bounds.width or
       float32(mousePos.y) < tabBar.bounds.y or 
       float32(mousePos.y) > tabBar.bounds.y + tabBar.bounds.height:
      # Clear hover state if mouse is outside tab bar
      if tabBar.hoveredTabIndex != -1:
        tabBar.hoveredTabIndex = -1
        tabBar.isDirty = true
        tabBar.componentManager.clearCursor(tabBar.id)
      return false
    
    # Check if mouse is over any tab
    var overAnyTab = false
    for tab in tabBar.tabs:
      if tab.isPointInTab(float32(mousePos.x), float32(mousePos.y)):
        overAnyTab = true
        break
    
    # If not over any tab, don't handle the event
    if not overAnyTab:
      # Clear hover state
      if tabBar.hoveredTabIndex != -1:
        tabBar.hoveredTabIndex = -1
        tabBar.isDirty = true
        tabBar.componentManager.clearCursor(tabBar.id)
      return false

    let isClicked = mouseEvent.eventType == metButtonPressed

    # Update hover state
    var newHoveredIndex = -1
    for i, tab in tabBar.tabs:
      if tab.isPointInTab(float32(mousePos.x), float32(mousePos.y)):
        newHoveredIndex = i
        break

    # Update cursor based on hover state
    if newHoveredIndex >= 0:
      tabBar.componentManager.setCursor(tabBar.id, rl.MouseCursor.PointingHand, cpUI)
    else:
      tabBar.componentManager.clearCursor(tabBar.id)

    # Update hover state if changed
    if tabBar.hoveredTabIndex != newHoveredIndex:
      tabBar.hoveredTabIndex = newHoveredIndex
      tabBar.isDirty = true

    # Handle mouse clicks
    if isClicked:
      # Check if clicked on a tab
      for i, tab in tabBar.tabs:
        if tab.isPointInTab(float32(mousePos.x), float32(mousePos.y)):
          # Check if clicked on close button
          if tabBar.showCloseButtons and tab.isPointInCloseButton(float32(mousePos.x), float32(mousePos.y)):
            discard tabBar.closeTab(i)
            return true

          # Activate the tab
          discard tabBar.activateTab(i)
          return true

      # Check if clicked on scroll buttons
      if tabBar.showScrollButtons:
        if tabBar.isPointInLeftScrollButton(float32(mousePos.x), float32(mousePos.y)):
          tabBar.scrollLeft()
          return true
        elif tabBar.isPointInRightScrollButton(float32(mousePos.x), float32(mousePos.y)):
          tabBar.scrollRight()
          return true

    return false

  of uiekKeyboard:
    # Handle keyboard input for tab navigation
    let keyEvent = event.keyEvent
    if keyEvent.eventType == ietKeyPressed:
      case keyEvent.key:
      of ekTab:
        if mkCtrl in keyEvent.modifiers:
          if mkShift in keyEvent.modifiers:
            tabBar.previousTab()
          else:
            tabBar.nextTab()
          return true
      else:
        discard

    return false

  of uiekCombined:
    return false


# Scroll button methods
proc scrollLeft*(tabBar: FileTabBar) =
  ## Scroll tabs to the left
  if tabBar.scrollOffset > 0:
    tabBar.scrollOffset = max(0.0, tabBar.scrollOffset - tabBar.maxTabWidth)
    tabBar.isDirty = true

proc scrollRight*(tabBar: FileTabBar) =
  ## Scroll tabs to the right
  if tabBar.scrollOffset < tabBar.maxScrollOffset:
    tabBar.scrollOffset = min(tabBar.maxScrollOffset, tabBar.scrollOffset +
        tabBar.maxTabWidth)
    tabBar.isDirty = true

proc isPointInLeftScrollButton*(tabBar: FileTabBar, x, y: float32): bool =
  ## Check if point is in left scroll button
  if not tabBar.showScrollButtons or tabBar.scrollOffset <= 0:
    return false

  let buttonSize = 20.0
  let buttonRect = rl.Rectangle(
    x: tabBar.bounds.x + 5.0,
    y: tabBar.bounds.y + (tabBar.bounds.height - buttonSize) / 2,
    width: buttonSize,
    height: buttonSize
  )

  return rl.checkCollisionPointRec(rl.Vector2(x: x, y: y), buttonRect)

proc isPointInRightScrollButton*(tabBar: FileTabBar, x, y: float32): bool =
  ## Check if point is in right scroll button
  if not tabBar.showScrollButtons or tabBar.scrollOffset >=
      tabBar.maxScrollOffset:
    return false

  let buttonSize = 20.0
  let buttonRect = rl.Rectangle(
    x: tabBar.bounds.x + tabBar.bounds.width - buttonSize - 5.0,
    y: tabBar.bounds.y + (tabBar.bounds.height - buttonSize) / 2,
    width: buttonSize,
    height: buttonSize
  )

  return rl.checkCollisionPointRec(rl.Vector2(x: x, y: y), buttonRect)

# Tab navigation methods
proc previousTab*(tabBar: FileTabBar) =
  ## Navigate to the previous tab
  if tabBar.tabs.len == 0:
    return

  let newIndex = if tabBar.activeTabIndex <= 0: tabBar.tabs.len -
      1 else: tabBar.activeTabIndex - 1
  discard tabBar.setActiveTab(newIndex)

proc nextTab*(tabBar: FileTabBar) =
  ## Navigate to the next tab
  if tabBar.tabs.len == 0:
    return

  let newIndex = if tabBar.activeTabIndex >= tabBar.tabs.len -
      1: 0 else: tabBar.activeTabIndex + 1
  discard tabBar.setActiveTab(newIndex)
