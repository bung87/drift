## Explorer main module - Production-ready file explorer using services
##
## The Explorer now inherits from UIComponent to integrate with the new infrastructure.
## This provides:
## - Consistent state management through UIComponent fields
## - Integration with UIService for layout and focus management
## - Automatic registration with the component system
## - Standard lifecycle methods (update, render, cleanup)
##
## Key integration points:
## - Explorer.id: Inherited component identifier
## - Explorer.bounds: Component positioning and sizing
## - Explorer.isVisible/isEnabled: Standard UI state
## - syncComponentState(): Synchronizes internal state with UIComponent
## - Integration with infrastructure modules under src/infrastructure/

import std/[os, times, strutils, tables, options, algorithm, osproc]
import raylib as rl
import results
import ../services/ui_service
import ../services/file_service
import ../shared/types
import ../shared/errors
import ../infrastructure/rendering/renderer
import ../components/context_menu
import types as explorer_types, rendering
import ../explorer/file_operations
import ../components/input_dialog
import ../components/simple_notification
import ../services/component_manager
import ../infrastructure/input/input_handler
import ../infrastructure/input/keyboard
import ../infrastructure/input/mouse
import ../infrastructure/clipboard
# import ../infrastructure/ui/cursor_manager
# import ../infrastructure/filesystem/file_manager
# import ../shared/constants

export explorer_types, rendering

# Constants
const SCROLLBAR_WIDTH* = 12.0

type Explorer* = ref object of UIComponent
  ## File explorer component that inherits from UIComponent for infrastructure integration.
  ## Provides file system navigation, selection, and operations with full UI service integration.
  uiService*: UIService # Reference to UI service for component management
  fileService*: FileService # File system operations service
  componentManager*: ComponentManager # Reference to ComponentManager for input handling
  clipboardService*: ClipboardService # Clipboard operations service
  explorerState*: ExplorerState # Internal explorer state (files, selection, etc.)
  config*: ExplorerConfig # Display and behavior configuration
  events*: seq[ExplorerEvent] # Event queue for external communication
  lastUpdateTime*: float64 # Last update timestamp for animations/timing
  contextMenu*: ContextMenu # Right-click context menu
  contextMenuTarget*: Option[ExplorerFileInfo] # Target file/folder for context menu
  inputDialog*: InputDialog
  notificationManager*: NotificationManager # User feedback notifications

# Forward declarations
proc refreshDirectory*(explorer: Explorer)
proc applyFilter*(explorer: Explorer)
proc updateScrollLimits*(explorer: Explorer, viewportHeight: float32)
proc addToHistory*(explorer: Explorer, path: string)
proc syncComponentState*(explorer: Explorer)
proc isGitRepository*(explorer: Explorer): bool
proc handleInput*(explorer: Explorer, event: UnifiedInputEvent): bool
proc registerInputHandlers*(explorer: Explorer): Result[void, EditorError]
proc handleMouseEvent*(explorer: Explorer, event: MouseEvent): bool
proc handleKeyboardEvent*(explorer: Explorer, event: InputEvent): bool
proc handleMouseLeftClick*(explorer: Explorer, mousePos: rl.Vector2)
proc handleMouseRightClick*(explorer: Explorer, mousePos: rl.Vector2)

# Constructor
proc newExplorer*(
    uiService: UIService, fileService: FileService, componentManager: ComponentManager, 
    clipboardService: ClipboardService, startDir: string = ""
): Explorer =
  result = Explorer(
    uiService: uiService,
    fileService: fileService,
    componentManager: componentManager,
    clipboardService: clipboardService,
    explorerState: ExplorerState(
      currentDirectory:
        if startDir.len > 0:
          startDir
        else:
          getCurrentDir(),
      selectedIndex: -1,
      files: @[],
      filteredFiles: @[],
      openDirs: initTable[string, bool](),
      rootCollapsed: false,
      scrollY: 0.0,
      scrollMaxY: 0.0,
      searchQuery: "",
      isVisible: true,
      showHiddenFiles: false,
      sortBy: sbName,
      sortOrder: soAscending,
      refreshing: false,
      errorMessage: "",
      lastRefreshTime: times.getTime(),
      history: @[],
      historyIndex: -1,
      lastClickTime: 0.0,
      lastClickedPath: "",
      hoveredItem: none(int),
      tooltipText: "",
      tooltipVisible: false,
      tooltipPosition: rl.Vector2(x: 0, y: 0),
    ),
    config: defaultExplorerConfig(uiService.theme),
    events: @[],
    lastUpdateTime: 0.0,
    contextMenu: nil,
    contextMenuTarget: none(ExplorerFileInfo),
    inputDialog: nil,
    notificationManager: nil,
  )

  # Initialize UIComponent fields
  result.id = "file_explorer"
  result.name = "File Explorer"
  result.state = csVisible
  result.bounds = rl.Rectangle(x: 0, y: 0, width: 300, height: 600)
  result.zIndex = uiService.nextZIndex
  uiService.nextZIndex += 1
  result.isVisible = true
  result.isEnabled = true
  result.isDirty = true
  result.parent = nil
  result.children = @[]
  result.data = initTable[string, string]()

  # Register with UI service
  uiService.components[result.id] = result

  # Use the main ComponentManager instead of creating a temporary one
  if componentManager == nil:
    echo "Warning: No ComponentManager provided to explorer"
  
  # Create context menu using main ComponentManager
  try:
    result.contextMenu = newContextMenu(
      componentManager,
      "explorer_context_menu",
      cmcEmpty,
      rl.Vector2(x: 0, y: 0)
    )
    echo "DEBUG: Explorer context menu created successfully"
  except EditorError as e:
    echo "Warning: Failed to create explorer context menu: ", e.msg
    result.contextMenu = nil

  # Initialize input dialog using main ComponentManager
  try:
    result.inputDialog = newInputDialog(
      componentManager,
      "explorer_input_dialog"
    )
  except EditorError as e:
    echo "Warning: Failed to create explorer input dialog: ", e.msg
    result.inputDialog = nil

  # Initialize notification manager using main ComponentManager
  result.notificationManager = newNotificationManager(
    componentManager,
    result.bounds # Use explorer bounds as container
  )

  # Sync component state to ensure UIComponent and Explorer state are consistent
  result.syncComponentState()

  # Don't register input handlers automatically - this will be done when the explorer panel becomes active
  # The registration will be handled by the main application when switching panels

  # Initialize the explorer
  result.refreshDirectory()


# Global context menu callback
var globalContextMenuCallback: proc(actionId: string, targetPath: string)

proc setGlobalContextMenuCallback*(callback: proc(actionId: string, targetPath: string)) =
  globalContextMenuCallback = callback

# Context menu action handler
proc validatePath(path: string): bool =
  ## Validate that a path is safe to operate on
  return path.len > 0 and not path.contains("..") and path.isAbsolute

proc showErrorDialog(explorer: Explorer, message: string) =
  ## Show error message to user
  if explorer.notificationManager != nil:
    discard explorer.notificationManager.showError(message)
  elif explorer.inputDialog != nil:
    explorer.inputDialog.errorMessage = message
  else:
    echo "Error: ", message

proc showSuccessMessage(explorer: Explorer, message: string) =
  ## Show success message to user
  if explorer.notificationManager != nil:
    discard explorer.notificationManager.showSuccess(message)
  else:
    echo "Success: ", message

proc showInfoMessage(explorer: Explorer, message: string) =
  ## Show info message to user
  if explorer.notificationManager != nil:
    discard explorer.notificationManager.showInfo(message)
  else:
    echo "Info: ", message

proc executeWithErrorHandling(explorer: Explorer, operation: proc(): explorer_types.FileOperationResult, successMessage: string = "") =
  ## Execute a file operation with proper error handling
  try:
    let result = operation()
    if result.success:
      if successMessage.len > 0:
        showSuccessMessage(explorer, successMessage)
      # Add refresh event to update file list after successful operation
      explorer.events.add(ExplorerEvent(
        kind: eeSelectionChanged, # Reuse existing event to trigger refresh
        filePath: "",
        timestamp: times.getTime()
      ))
      explorer.uiService.markComponentDirty(explorer.id)
    else:
      showErrorDialog(explorer, result.error)
  except Exception as e:
    showErrorDialog(explorer, "Operation failed: " & e.msg)

proc handleContextMenuAction*(explorer: Explorer, actionId: string, targetPath: string) =
  ## Handle context menu actions with improved error handling and validation
  
  # Validate input parameters
  if actionId.len == 0:
    showErrorDialog(explorer, "Invalid action")
    return
  
  # Validate target path for file operations
  if targetPath.len > 0 and actionId notin ["new_file", "new_folder", "refresh", "collapse_all"]:
    if not validatePath(targetPath):
      showErrorDialog(explorer, "Invalid file path")
      return
    if not fileExists(targetPath) and not dirExists(targetPath):
      showErrorDialog(explorer, "File or directory not found: " & targetPath)
      return

  case actionId
  of "open":
    if explorer.contextMenuTarget.isSome:
      let target = explorer.contextMenuTarget.get()
      if target.kind == fkFile:
        # Add event through the event system
        explorer.events.add(ExplorerEvent(
          kind: eeFileOpened,
          filePath: target.path,
          timestamp: times.getTime()
        ))
  
  of "open_to_side":
    if explorer.contextMenuTarget.isSome:
      let target = explorer.contextMenuTarget.get()
      if target.kind == fkFile:
        # Add event for opening to side - for now, treat as regular open
        explorer.events.add(ExplorerEvent(
          kind: eeFileOpened,
          filePath: target.path,
          timestamp: times.getTime()
        ))
  
  of "reveal":
    # Reveal file/folder in system file manager with error handling
    try:
      when defined(macosx):
        let exitCode = execShellCmd("open -R \"" & targetPath & "\"")
        if exitCode != 0:
          showErrorDialog(explorer, "Failed to reveal file in Finder")
      elif defined(windows):
        let exitCode = execShellCmd("explorer /select,\"" & targetPath & "\"")
        if exitCode != 0:
          showErrorDialog(explorer, "Failed to reveal file in Explorer")
      else:
        let exitCode = execShellCmd("xdg-open \"" & targetPath.parentDir & "\"")
        if exitCode != 0:
          showErrorDialog(explorer, "Failed to open file manager")
    except Exception as e:
      showErrorDialog(explorer, "Failed to reveal file: " & e.msg)
  
  of "copy_path":
    # Copy absolute path to clipboard
    try:
      explorer.clipboardService.setText(targetPath)
      showInfoMessage(explorer, "Copied path to clipboard")
    except Exception as e:
      showErrorDialog(explorer, "Failed to copy path: " & e.msg)
  
  of "copy_relative_path":
    # Copy relative path to clipboard
    try:
      let relativePath = relativePath(targetPath, explorer.explorerState.currentDirectory)
      explorer.clipboardService.setText(relativePath)
      showInfoMessage(explorer, "Copied relative path to clipboard")
    except Exception as e:
      showErrorDialog(explorer, "Failed to copy relative path: " & e.msg)
  
  of "rename":
    if explorer.inputDialog != nil and explorer.contextMenuTarget.isSome:
      let target = explorer.contextMenuTarget.get()
      let oldName = target.name
      explorer.inputDialog.show(
        prompt = "Rename to:",
        initial = oldName,
        placeholder = "Enter new name",
        cb = proc(newNameOpt: Option[string]) =
          if newNameOpt.isSome:
            let newName = newNameOpt.get().strip()
            if newName.len == 0:
              explorer.inputDialog.errorMessage = "Name cannot be empty"
              return
            if newName == oldName:
              explorer.inputDialog.hide()
              return
            # Validate new name
            if "/" in newName or "\\" in newName:
              explorer.inputDialog.errorMessage = "Name cannot contain path separators"
              return
            
            executeWithErrorHandling(explorer, proc(): explorer_types.FileOperationResult =
              renameFile(target.path, newName)
            , "File renamed successfully")
      )
    else:
      showErrorDialog(explorer, "Cannot rename: no target selected")
  
  of "delete":
    let info = getExplorerFileInfo(targetPath)
    if info.isSome and explorer.inputDialog != nil:
      let fileInfo = info.get()
      let name = fileInfo.name
      let isDir = fileInfo.kind == fkDirectory
      let prompt = if isDir:
        "Are you sure you want to delete the folder '" & name & "'?\nThis will permanently delete all its contents."
      else:
        "Are you sure you want to delete the file '" & name & "'?\nThis action cannot be undone."
      
      explorer.inputDialog.show(
        prompt = prompt,
        initial = "",
        placeholder = "",
        okLabel = "Delete",
        cancelLabel = "Cancel",
        cb = proc(confirmOpt: Option[string]) =
          if confirmOpt.isSome:
            executeWithErrorHandling(explorer, proc(): explorer_types.FileOperationResult =
              if isDir:
                deleteDirectory(targetPath, true)
              else:
                deleteFile(targetPath)
            , "Item deleted successfully")
          else:
            explorer.inputDialog.hide()
      )
    else:
      showErrorDialog(explorer, "Cannot delete: file not found or no dialog available")
  
  of "git_stage":
    if explorer.isGitRepository():
      try:
        let (output, exitCode) = execCmdEx("git add \"" & targetPath & "\"", workingDir = explorer.explorerState.currentDirectory)
        if exitCode == 0:
          showSuccessMessage(explorer, "File staged successfully")
          explorer.uiService.markComponentDirty(explorer.id)
        else:
          showErrorDialog(explorer, "Failed to stage file: " & output)
      except Exception as e:
        showErrorDialog(explorer, "Git staging failed: " & e.msg)
    else:
      showErrorDialog(explorer, "Not a Git repository")
  
  of "git_discard":
    if explorer.isGitRepository():
      try:
        let (output, exitCode) = execCmdEx("git checkout -- \"" & targetPath & "\"", workingDir = explorer.explorerState.currentDirectory)
        if exitCode == 0:
          showSuccessMessage(explorer, "Changes discarded successfully")
          explorer.uiService.markComponentDirty(explorer.id)
        else:
          showErrorDialog(explorer, "Failed to discard changes: " & output)
      except Exception as e:
        showErrorDialog(explorer, "Git discard failed: " & e.msg)
    else:
      showErrorDialog(explorer, "Not a Git repository")
  
  of "git_stage_all":
    if explorer.isGitRepository():
      try:
        let workDir = if targetPath.len > 0: targetPath else: explorer.explorerState.currentDirectory
        let (output, exitCode) = execCmdEx("git add .", workingDir = workDir)
        if exitCode == 0:
          showSuccessMessage(explorer, "All changes staged successfully")
          explorer.uiService.markComponentDirty(explorer.id)
        else:
          showErrorDialog(explorer, "Failed to stage all: " & output)
      except Exception as e:
        showErrorDialog(explorer, "Git staging failed: " & e.msg)
    else:
      showErrorDialog(explorer, "Not a Git repository")
  
  of "run":
    if fileExists(targetPath):
      try:
        let ext = targetPath.splitFile().ext.toLower()
        let command = case ext
          of ".nim": "nim c -r \"" & targetPath & "\""
          of ".py": "python \"" & targetPath & "\""
          of ".js": "node \"" & targetPath & "\""
          of ".sh", ".bash": "bash \"" & targetPath & "\""
          else: "\"" & targetPath & "\""
        
        showInfoMessage(explorer, "Running: " & command)
        discard execShellCmd(command)
      except Exception as e:
        showErrorDialog(explorer, "Failed to run file: " & e.msg)
    else:
      showErrorDialog(explorer, "File does not exist")
  
  of "debug":
    if fileExists(targetPath):
      let ext = targetPath.splitFile().ext.toLower()
      case ext
      of ".nim":
        showInfoMessage(explorer, "Starting Nim debugger...")
        # TODO: Implement proper debugger integration
      else:
        showInfoMessage(explorer, "Starting debugger...")
        # TODO: Add more debugger support
    else:
      showErrorDialog(explorer, "File does not exist")
  
  of "format":
    if fileExists(targetPath):
      try:
        let ext = targetPath.splitFile().ext.toLower()
        let command = case ext
          of ".nim": "nimpretty \"" & targetPath & "\""
          of ".py": "black \"" & targetPath & "\""
          of ".js", ".ts": "prettier --write \"" & targetPath & "\""
          else: ""
        
        if command.len > 0:
          let exitCode = execShellCmd(command)
          if exitCode == 0:
            showSuccessMessage(explorer, "File formatted successfully")
            explorer.uiService.markComponentDirty(explorer.id)
          else:
            showErrorDialog(explorer, "Failed to format file")
        else:
          showErrorDialog(explorer, "No formatter available for: " & ext)
      except Exception as e:
        showErrorDialog(explorer, "Formatting failed: " & e.msg)
    else:
      showErrorDialog(explorer, "File does not exist")
  
  of "format_all":
    if dirExists(targetPath):
      try:
        # Format all supported files in directory
        let commands = @[
          "find \"" & targetPath & "\" -name \"*.nim\" -exec nimpretty {} \\;",
          "find \"" & targetPath & "\" -name \"*.py\" -exec black {} \\;",
          "find \"" & targetPath & "\" -name \"*.js\" -o -name \"*.ts\" | xargs prettier --write"
        ]
        
        for command in commands:
          discard execShellCmd(command)
        
        showSuccessMessage(explorer, "All files formatted successfully")
        explorer.uiService.markComponentDirty(explorer.id)
      except Exception as e:
        showErrorDialog(explorer, "Bulk formatting failed: " & e.msg)
    else:
      showErrorDialog(explorer, "Directory does not exist")
  
  of "new_file":
    if explorer.inputDialog != nil:
      explorer.inputDialog.show(
        prompt = "New file name:",
        initial = "",
        placeholder = "Enter file name (e.g., main.nim)",
        cb = proc(nameOpt: Option[string]) =
          if nameOpt.isSome:
            let fileName = nameOpt.get().strip()
            if fileName.len == 0:
              explorer.inputDialog.errorMessage = "File name cannot be empty"
              return
            if "/" in fileName or "\\" in fileName:
              explorer.inputDialog.errorMessage = "File name cannot contain path separators"
              return
            
            let baseDir = if targetPath.len > 0 and dirExists(targetPath): targetPath else: explorer.explorerState.currentDirectory
            let filePath = baseDir / fileName
            
            executeWithErrorHandling(explorer, proc(): explorer_types.FileOperationResult =
              createFile(filePath, "")
            , "File created successfully")
      )
    else:
      showErrorDialog(explorer, "No input dialog available")
  
  of "new_folder":
    if explorer.inputDialog != nil:
      explorer.inputDialog.show(
        prompt = "New folder name:",
        initial = "",
        placeholder = "Enter folder name",
        cb = proc(nameOpt: Option[string]) =
          if nameOpt.isSome:
            let folderName = nameOpt.get().strip()
            if folderName.len == 0:
              explorer.inputDialog.errorMessage = "Folder name cannot be empty"
              return
            if "/" in folderName or "\\" in folderName:
              explorer.inputDialog.errorMessage = "Folder name cannot contain path separators"
              return
            
            let baseDir = if targetPath.len > 0 and dirExists(targetPath): targetPath else: explorer.explorerState.currentDirectory
            let folderPath = baseDir / folderName
            
            executeWithErrorHandling(explorer, proc(): explorer_types.FileOperationResult =
              createDirectory(folderPath)
            , "Folder created successfully")
      )
    else:
      showErrorDialog(explorer, "No input dialog available")
  
  of "refresh":
    explorer.uiService.markComponentDirty(explorer.id)
    showInfoMessage(explorer, "Explorer refreshed")
  
  of "collapse_all":
    # Request state change - mark dirty for refresh
    explorer.uiService.markComponentDirty(explorer.id)
    showInfoMessage(explorer, "All directories collapsed")
  
  of "paste":
    try:
      let clipboardText = explorer.clipboardService.getText()
      if clipboardText.len == 0:
        showErrorDialog(explorer, "Nothing to paste")
        return
      
      if clipboardText.startsWith("COPY:") or clipboardText.startsWith("CUT:"):
        let isCut = clipboardText.startsWith("CUT:")
        let srcPath = if isCut: clipboardText[4..^1] else: clipboardText[5..^1]
        
        if not fileExists(srcPath) and not dirExists(srcPath):
          showErrorDialog(explorer, "Source file no longer exists")
          return
        
        let destDir = if targetPath.len > 0 and dirExists(targetPath): targetPath else: explorer.explorerState.currentDirectory
        let destName = srcPath.splitFile().name & srcPath.splitFile().ext
        let destPath = destDir / destName
        
        if fileExists(destPath) or dirExists(destPath):
          # Prompt for overwrite or new name
          if explorer.inputDialog != nil:
            explorer.inputDialog.show(
              prompt = "File '" & destName & "' already exists.\nOverwrite or enter new name:",
              initial = destName,
              placeholder = "Enter new name or keep to overwrite",
              cb = proc(nameOpt: Option[string]) =
                if nameOpt.isSome:
                  let newName = nameOpt.get().strip()
                  if newName.len == 0:
                    explorer.inputDialog.errorMessage = "Name cannot be empty"
                    return
                  
                  let finalDestPath = destDir / newName
                  executeWithErrorHandling(explorer, proc(): explorer_types.FileOperationResult =
                    if isCut:
                      let moveResult = file_operations.moveFile(srcPath, finalDestPath)
                      if moveResult.success:
                        explorer.clipboardService.setText("")  # Clear clipboard after cut
                      moveResult
                    else:
                      file_operations.copyFile(srcPath, finalDestPath)
                  , if isCut: "File moved successfully" else: "File copied successfully")
            )
        else:
          executeWithErrorHandling(explorer, proc(): explorer_types.FileOperationResult =
            if isCut:
              let moveResult = file_operations.moveFile(srcPath, destPath)
              if moveResult.success:
                rl.setClipboardText("")  # Clear clipboard after cut
              moveResult
            else:
              file_operations.copyFile(srcPath, destPath)
          , if isCut: "File moved successfully" else: "File copied successfully")
      else:
        showErrorDialog(explorer, "Invalid clipboard content")
    except Exception as e:
      showErrorDialog(explorer, "Paste operation failed: " & e.msg)
  
  of "compare":
    # TODO: Implement file comparison
    showInfoMessage(explorer, "File comparison not yet implemented")
  
  of "copy":
    try:
      explorer.clipboardService.setText("COPY:" & targetPath)
      showInfoMessage(explorer, "File copied to clipboard")
    except Exception as e:
      showErrorDialog(explorer, "Failed to copy: " & e.msg)
  
  of "cut":
    try:
      explorer.clipboardService.setText("CUT:" & targetPath)
      showInfoMessage(explorer, "File cut to clipboard")
    except Exception as e:
      showErrorDialog(explorer, "Failed to cut: " & e.msg)
  
  else:
    showErrorDialog(explorer, "Unknown context menu action: " & actionId)
  
  # Mark component as dirty for UI updates
  explorer.isDirty = true
  explorer.uiService.markComponentDirty(explorer.id)

# Core functionality
proc initialize*(explorer: Explorer) =
  ## Initialize the explorer
  explorer.refreshDirectory()

  # Auto-expand first few directories for better UX and scrollable content
  var expandedCount = 0
  for file in explorer.explorerState.files:
    if file.kind == fkDirectory and expandedCount < 3:
      explorer.explorerState.openDirs[file.path] = true
      expandedCount += 1

  # Refresh again to show expanded content
  if expandedCount > 0:
    explorer.refreshDirectory()

  discard explorer.uiService.setComponentState(explorer.id, csVisible)

proc buildTreeRecursive(
    explorer: Explorer, dirPath: string, level: int
): seq[ExplorerFileInfo] =

  let dirResult = explorer.fileService.listDirectory(dirPath)
  if not dirResult.isOk:
    return

  let fileNodes = dirResult.get()

  # Sort files alphabetically within this directory level
  var sortedNodes = fileNodes
  sortedNodes.sort do(a, b: auto) -> int:
    cmp(a.name.toLower(), b.name.toLower())

  for node in sortedNodes:
    let fileInfo = ExplorerFileInfo(
      name: node.name,
      path: node.path,
      kind: if node.isDirectory: fkDirectory else: fkFile,
      size: node.size,
      modTime: node.lastModified,
      isHidden: node.isHidden,
      permissions: {fpRead}, # Default permissions
      extension: node.name.splitFile().ext,
      isExpanded:
        if node.isDirectory:
          explorer.explorerState.openDirs.getOrDefault(node.path, false)
        else:
          false,
      level: level,
    )
    result.add(fileInfo)

    # If this is a directory and it's expanded, add its contents
    if node.isDirectory and explorer.explorerState.openDirs.getOrDefault(node.path, false):
      let subItems = explorer.buildTreeRecursive(node.path, level + 1)
      result.add(subItems)

  return result

proc refreshDirectory*(explorer: Explorer) =
  ## Refresh the current directory using FileService with tree view
  explorer.explorerState.refreshing = true
  explorer.explorerState.errorMessage = ""

  # Build tree structure starting from current directory
  explorer.explorerState.files = explorer.buildTreeRecursive(explorer.explorerState.currentDirectory, 0)

  explorer.explorerState.refreshing = false
  explorer.applyFilter()
  # Note: updateScrollLimits will be called from render with actual viewport height
  explorer.explorerState.lastRefreshTime = times.getTime()
  explorer.addToHistory(explorer.explorerState.currentDirectory)

proc applyFilter*(explorer: Explorer) =
  ## Apply current filter and sort settings
  explorer.explorerState.filteredFiles = @[]

  for file in explorer.explorerState.files:
    # Filter by search query
    if explorer.explorerState.searchQuery.len > 0:
      if not file.name.toLower().contains(explorer.explorerState.searchQuery.toLower()):
        continue

    # Filter hidden files
    if not explorer.explorerState.showHiddenFiles and file.isHidden:
      continue

    # Note: Binary files are still shown but will be ignored when clicked

    explorer.explorerState.filteredFiles.add(file)

  # Note: Sorting is now done at directory level in buildTreeRecursive

proc updateScrollLimits*(explorer: Explorer, viewportHeight: float32) =
  ## Update scroll limits based on content
  let itemHeight = explorer.config.itemHeight
  let headerHeight = HEADER_HEIGHT + DIRECTORY_BAR_HEIGHT
  let availableHeight = viewportHeight - headerHeight
  let contentHeight = explorer.explorerState.filteredFiles.len.float32 * itemHeight
  explorer.explorerState.scrollMaxY = max(0.0, contentHeight - availableHeight)

  # Clamp current scroll position
  explorer.explorerState.scrollY =
    max(0.0, min(explorer.explorerState.scrollMaxY, explorer.explorerState.scrollY))

proc addToHistory*(explorer: Explorer, path: string) =
  ## Add path to navigation history
  if explorer.explorerState.history.len == 0 or explorer.explorerState.history[^1] != path:
    # Remove future history if we're not at the end
    if explorer.explorerState.historyIndex < explorer.explorerState.history.len - 1:
      explorer.explorerState.history = explorer.explorerState.history[0 .. explorer.explorerState.historyIndex]

    explorer.explorerState.history.add(path)
    explorer.explorerState.historyIndex = explorer.explorerState.history.len - 1

# Navigation
proc setDirectory*(explorer: Explorer, path: string) =
  ## Set the current directory
  if dirExists(path):
    explorer.explorerState.currentDirectory = path
    explorer.explorerState.selectedIndex = -1
    explorer.refreshDirectory()

proc navigateUp*(explorer: Explorer) =
  ## Navigate to parent directory
  let parent = parentDir(explorer.explorerState.currentDirectory)
  if parent != explorer.explorerState.currentDirectory:
    explorer.setDirectory(parent)

proc navigateToSelected*(explorer: Explorer) =
  ## Navigate into selected directory
  if explorer.explorerState.selectedIndex >= 0 and
      explorer.explorerState.selectedIndex < explorer.explorerState.filteredFiles.len:
    let selected = explorer.explorerState.filteredFiles[explorer.explorerState.selectedIndex]
    if selected.kind == fkDirectory:
      explorer.setDirectory(selected.path)

proc navigateBack*(explorer: Explorer) =
  ## Navigate back in history
  if explorer.explorerState.historyIndex > 0:
    explorer.explorerState.historyIndex -= 1
    let path = explorer.explorerState.history[explorer.explorerState.historyIndex]
    explorer.explorerState.currentDirectory = path
    explorer.refreshDirectory()

proc navigateForward*(explorer: Explorer) =
  ## Navigate forward in history
  if explorer.explorerState.historyIndex < explorer.explorerState.history.len - 1:
    explorer.explorerState.historyIndex += 1
    let path = explorer.explorerState.history[explorer.explorerState.historyIndex]
    explorer.explorerState.currentDirectory = path
    explorer.refreshDirectory()

# Selection management
proc selectFile*(explorer: Explorer, index: int) =
  ## Select file by index
  if index >= -1 and index < explorer.explorerState.filteredFiles.len:
    explorer.explorerState.selectedIndex = index
    explorer.events.add(
      ExplorerEvent(
        kind: eeSelectionChanged,
        filePath:
          if index >= 0:
            explorer.explorerState.filteredFiles[index].path
          else:
            "",
        timestamp: times.getTime(),
      )
    )

proc selectFileByPath*(explorer: Explorer, path: string) =
  ## Select file by path
  echo "DEBUG: selectFileByPath - searching for path: ", path, ", filteredFiles count: ", explorer.explorerState.filteredFiles.len
  for i, file in explorer.explorerState.filteredFiles:
    echo "DEBUG: selectFileByPath - checking file[", i, "]: ", file.path
    if file.path == path:
      echo "DEBUG: selectFileByPath - found match at index: ", i
      explorer.selectFile(i)
      return
  echo "DEBUG: selectFileByPath - path not found: ", path

proc getSelectedFile*(explorer: Explorer): Option[ExplorerFileInfo] =
  ## Get currently selected file
  if explorer.explorerState.selectedIndex >= 0 and
      explorer.explorerState.selectedIndex < explorer.explorerState.filteredFiles.len:
    some(explorer.explorerState.filteredFiles[explorer.explorerState.selectedIndex])
  else:
    none(ExplorerFileInfo)

# File operations using FileService
proc createNewFile*(explorer: Explorer, name: string): explorer_types.FileOperationResult =
  ## Create a new file in current directory
  let filePath = explorer.explorerState.currentDirectory / name
  let fileResult = explorer.fileService.createFile(filePath, "")

  if fileResult.isOk:
    explorer.refreshDirectory()
    explorer.selectFileByPath(filePath)
    explorer.events.add(
      ExplorerEvent(kind: eeFileCreated, filePath: filePath, timestamp: times.getTime())
    )
    return explorer_types.FileOperationResult(success: true, error: "", affectedFiles: @[filePath])
  else:
    return
      explorer_types.FileOperationResult(success: false, error: fileResult.error.msg, affectedFiles: @[])

proc createNewDirectory*(explorer: Explorer, name: string): explorer_types.FileOperationResult =
  ## Create a new directory in current directory
  let dirPath = explorer.explorerState.currentDirectory / name
  let res = explorer.fileService.createDirectory(dirPath)

  if res.isOk:
    explorer.refreshDirectory()
    explorer.selectFileByPath(dirPath)
    explorer.events.add(
      ExplorerEvent(
        kind: eeDirectoryCreated, filePath: dirPath, timestamp: times.getTime()
      )
    )
    return explorer_types.FileOperationResult(success: true, error: "", affectedFiles: @[dirPath])
  else:
    return
      explorer_types.FileOperationResult(success: false, error: res.error.msg, affectedFiles: @[])

proc deleteSelected*(explorer: Explorer): explorer_types.FileOperationResult =
  ## Delete selected file or directory
  let selected = explorer.getSelectedFile()
  if selected.isNone:
    return
      explorer_types.FileOperationResult(success: false, error: "No file selected", affectedFiles: @[])

  let file = selected.get()
  let res =
    if file.kind == fkDirectory:
      explorer.fileService.deleteDirectory(file.path, recursive = true)
    else:
      explorer.fileService.deleteFile(file.path)

  if res.isOk:
    explorer.refreshDirectory()
    explorer.events.add(
      ExplorerEvent(
        kind: eeFileDeleted, filePath: file.path, timestamp: times.getTime()
      )
    )
    return explorer_types.FileOperationResult(success: true, error: "", affectedFiles: @[file.path])
  else:
    return
      explorer_types.FileOperationResult(success: false, error: res.error.msg, affectedFiles: @[])

proc renameSelected*(explorer: Explorer, newName: string): explorer_types.FileOperationResult =
  ## Rename selected file or directory
  let selected = explorer.getSelectedFile()
  if selected.isNone:
    return
      explorer_types.FileOperationResult(success: false, error: "No file selected", affectedFiles: @[])

  let file = selected.get()
  let newPath = parentDir(file.path) / newName
  let res = explorer.fileService.moveFile(file.path, newPath)

  if res.isOk:
    explorer.refreshDirectory()
    explorer.selectFileByPath(newPath)
    explorer.events.add(
      ExplorerEvent(
        kind: eeFileRenamed,
        filePath: newPath,
        oldPath: some(file.path),
        timestamp: times.getTime(),
      )
    )
    return explorer_types.FileOperationResult(success: true, error: "", affectedFiles: @[newPath])
  else:
    return
      explorer_types.FileOperationResult(success: false, error: res.error.msg, affectedFiles: @[])

proc copySelected*(explorer: Explorer, destPath: string): explorer_types.FileOperationResult =
  ## Copy selected file to destination
  let selected = explorer.getSelectedFile()
  if selected.isNone:
    return
      explorer_types.FileOperationResult(success: false, error: "No file selected", affectedFiles: @[])

  let file = selected.get()
  let copyResult = explorer.fileService.copyFile(file.path, destPath)

  if copyResult.isOk:
    explorer.refreshDirectory()
    explorer.events.add(
      ExplorerEvent(
        kind: eeFileCopied,
        filePath: destPath,
        oldPath: some(file.path),
        timestamp: times.getTime(),
      )
    )
    return explorer_types.FileOperationResult(success: true, error: "", affectedFiles: @[destPath])
  else:
    return
      explorer_types.FileOperationResult(success: false, error: copyResult.error.msg, affectedFiles: @[])

proc moveSelected*(explorer: Explorer, destPath: string): explorer_types.FileOperationResult =
  ## Move selected file to destination
  let selected = explorer.getSelectedFile()
  if selected.isNone:
    return
      explorer_types.FileOperationResult(success: false, error: "No file selected", affectedFiles: @[])

  let file = selected.get()
  let moveResult = explorer.fileService.moveFile(file.path, destPath)

  if moveResult.isOk:
    explorer.refreshDirectory()
    explorer.events.add(
      ExplorerEvent(
        kind: eeFileMoved,
        filePath: destPath,
        oldPath: some(file.path),
        timestamp: times.getTime(),
      )
    )
    return explorer_types.FileOperationResult(success: true, error: "", affectedFiles: @[destPath])
  else:
    return
      explorer_types.FileOperationResult(success: false, error: moveResult.error.msg, affectedFiles: @[])

# Input handling

# Input handling integration with infrastructure
proc handleInput*(explorer: Explorer, event: UnifiedInputEvent): bool =
  ## Handle unified input events for the explorer
  if not explorer.isVisible:
    return false
  
  case event.kind:
  of uiekMouse:
    return explorer.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return explorer.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc handleMouseEvent*(explorer: Explorer, event: MouseEvent): bool =
  ## Handle mouse events using the infrastructure mouse system
  if not explorer.isVisible:
    return false
  
  # Use event coordinates directly
  let eventMousePos = rl.Vector2(x: event.position.x, y: event.position.y)
  let deltaTime = 0.016 # Approximate frame time
  
  # Update mouse position in state for rendering code
  explorer.explorerState.mousePos = eventMousePos
  
  # Check if mouse is in explorer bounds
  let mouseInExplorer = event.position.x >= explorer.bounds.x and
                       event.position.x <= explorer.bounds.x + explorer.bounds.width and
                       event.position.y >= explorer.bounds.y and
                       event.position.y <= explorer.bounds.y + explorer.bounds.height
  
  if not mouseInExplorer:
    return false
  
  # Handle mouse wheel scrolling
  if event.eventType == metScrolled:
    echo "DEBUG: Explorer scroll event received - wheel: ", event.scrollDelta.y, ", scrollMaxY: ", explorer.explorerState.scrollMaxY
    let wheel = event.scrollDelta.y
    if wheel != 0 and explorer.explorerState.scrollMaxY > 0:
      let itemHeight = explorer.config.itemHeight
      let scrollAmount = wheel * itemHeight * 1.5
      let oldScrollY = explorer.explorerState.scrollY
      explorer.explorerState.scrollY =
        max(0.0, min(explorer.explorerState.scrollMaxY, explorer.explorerState.scrollY - scrollAmount))
      echo "DEBUG: Explorer scroll - oldScrollY: ", oldScrollY, ", newScrollY: ", explorer.explorerState.scrollY, ", scrollAmount: ", scrollAmount
      explorer.componentManager.markComponentDirty(explorer.id)
      return true
    else:
      echo "DEBUG: Explorer scroll ignored - wheel: ", wheel, ", scrollMaxY: ", explorer.explorerState.scrollMaxY
  
  # Handle mouse clicks
  if event.eventType == metButtonPressed:
    case event.button:
    of mbLeft:
      # Handle left click with event coordinates
      explorer.handleMouseLeftClick(eventMousePos)
      return true
    of mbRight:
      # Handle right click with event coordinates
      explorer.handleMouseRightClick(eventMousePos)
      return true
    else:
      return false
  
  return false

proc hasFocus*(explorer: Explorer): bool =
  ## Check if this component has focus
  explorer.uiService.focusedComponent.isSome and
    explorer.uiService.focusedComponent.get().id == explorer.id

proc handleKeyboardEvent*(explorer: Explorer, event: InputEvent): bool =
  ## Handle keyboard events using the infrastructure keyboard system
  if not explorer.isVisible or not explorer.hasFocus():
    return false
  
  case event.eventType:
  of ietKeyPressed:
    case event.key:
    of ekUp:
      if explorer.explorerState.selectedIndex > 0:
        explorer.selectFile(explorer.explorerState.selectedIndex - 1)
        return true
    of ekDown:
      if explorer.explorerState.selectedIndex < explorer.explorerState.filteredFiles.len - 1:
        explorer.selectFile(explorer.explorerState.selectedIndex + 1)
        return true
    of ekLeft:
      # Tree view: collapse directory if expanded, otherwise go to parent level
      let selected = explorer.getSelectedFile()
      if selected.isSome and selected.get().kind == fkDirectory:
        let path = selected.get().path
        if explorer.explorerState.openDirs.getOrDefault(path, false):
          # Collapse the directory
          explorer.explorerState.openDirs[path] = false
          explorer.refreshDirectory()
        else:
          # Directory is already collapsed, navigate up
          explorer.navigateUp()
      else:
        # File selected, navigate up
        explorer.navigateUp()
      return true
    of ekRight:
      # Tree view: expand directory if collapsed
      let selected = explorer.getSelectedFile()
      if selected.isSome and selected.get().kind == fkDirectory:
        let path = selected.get().path
        if not explorer.explorerState.openDirs.getOrDefault(path, false):
          # Expand the directory
          explorer.explorerState.openDirs[path] = true
          explorer.refreshDirectory()
      return true
    of ekEnter:
      # Tree view: toggle directory expansion or open file
      let selected = explorer.getSelectedFile()
      if selected.isSome:
        let file = selected.get()
        if file.kind == fkDirectory:
          # Toggle directory expansion
          let path = file.path
          if path in explorer.explorerState.openDirs:
            explorer.explorerState.openDirs[path] = not explorer.explorerState.openDirs[path]
          else:
            explorer.explorerState.openDirs[path] = true
          explorer.refreshDirectory()
        else:
          # Open file
          explorer.events.add(
            ExplorerEvent(
              kind: eeFileOpened, filePath: file.path, timestamp: times.getTime()
            )
          )
      return true
    of ekF5:
      explorer.refreshDirectory()
      return true
    of ekBackspace:
      explorer.navigateBack()
      return true
    of ekDelete:
      discard explorer.deleteSelected()
      return true
    of ekF2:
      # Trigger rename mode
      explorer.events.add(
        ExplorerEvent(
          kind: eeRenameRequested,
          filePath:
            if explorer.explorerState.selectedIndex >= 0:
              explorer.explorerState.filteredFiles[explorer.explorerState.selectedIndex].path
            else:
              "",
          timestamp: times.getTime(),
        )
      )
      return true
    else:
      return false
  of ietCharInput:
    # Handle character input for search
    if event.character.int32 >= 32 and event.character.int32 <= 126:
      let char = char(event.character.int32)
      # Add to search query
      explorer.explorerState.searchQuery.add(char)
      explorer.applyFilter()
      explorer.componentManager.markComponentDirty(explorer.id)
      return true
  else:
    return false

proc registerInputHandlers*(explorer: Explorer): Result[void, EditorError] =
  ## Register standardized input handlers using ComponentManager
  
  var keyHandlers = initTable[KeyCombination, proc()]()
  
  # Navigation keys
  keyHandlers[KeyCombination(key: ekUp, modifiers: {})] = proc() =
    if explorer.explorerState.selectedIndex > 0:
      var explorerVar = explorer
      explorerVar.selectFile(explorer.explorerState.selectedIndex - 1)
  
  keyHandlers[KeyCombination(key: ekDown, modifiers: {})] = proc() =
    if explorer.explorerState.selectedIndex < explorer.explorerState.filteredFiles.len - 1:
      var explorerVar = explorer
      explorerVar.selectFile(explorer.explorerState.selectedIndex + 1)
  
  keyHandlers[KeyCombination(key: ekLeft, modifiers: {})] = proc() =
    let selected = explorer.getSelectedFile()
    if selected.isSome and selected.get().kind == fkDirectory:
      let path = selected.get().path
      if explorer.explorerState.openDirs.getOrDefault(path, false):
        explorer.explorerState.openDirs[path] = false
        explorer.refreshDirectory()
      else:
        var explorerVar = explorer
        explorerVar.navigateUp()
    else:
      var explorerVar = explorer
      explorerVar.navigateUp()
  
  keyHandlers[KeyCombination(key: ekRight, modifiers: {})] = proc() =
    let selected = explorer.getSelectedFile()
    if selected.isSome and selected.get().kind == fkDirectory:
      let path = selected.get().path
      if not explorer.explorerState.openDirs.getOrDefault(path, false):
        explorer.explorerState.openDirs[path] = true
        explorer.refreshDirectory()
  
  keyHandlers[KeyCombination(key: ekEnter, modifiers: {})] = proc() =
    let selected = explorer.getSelectedFile()
    if selected.isSome:
      let file = selected.get()
      if file.kind == fkDirectory:
        let path = file.path
        if path in explorer.explorerState.openDirs:
          explorer.explorerState.openDirs[path] = not explorer.explorerState.openDirs[path]
        else:
          explorer.explorerState.openDirs[path] = true
        explorer.refreshDirectory()
      else:
        explorer.events.add(
          ExplorerEvent(
            kind: eeFileOpened, filePath: file.path, timestamp: times.getTime()
          )
        )
  
  keyHandlers[KeyCombination(key: ekF5, modifiers: {})] = proc() =
    explorer.refreshDirectory()
  
  keyHandlers[KeyCombination(key: ekBackspace, modifiers: {})] = proc() =
    var explorerVar = explorer
    explorerVar.navigateBack()
  
  keyHandlers[KeyCombination(key: ekDelete, modifiers: {})] = proc() =
    var explorerVar = explorer
    discard explorerVar.deleteSelected()
  
  keyHandlers[KeyCombination(key: ekF2, modifiers: {})] = proc() =
    explorer.events.add(
      ExplorerEvent(
        kind: eeRenameRequested,
        filePath:
          if explorer.explorerState.selectedIndex >= 0:
            explorer.explorerState.filteredFiles[explorer.explorerState.selectedIndex].path
          else:
            "",
        timestamp: times.getTime(),
      )
    )
  
  # Mouse handlers
  var mouseHandlers = initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  
  mouseHandlers[mbLeft] = proc(pos: MousePosition) =
    let mousePos = rl.Vector2(x: pos.x, y: pos.y)
    var explorerVar = explorer
    explorerVar.handleMouseLeftClick(mousePos)
  
  mouseHandlers[mbRight] = proc(pos: MousePosition) =
    let mousePos = rl.Vector2(x: pos.x, y: pos.y)
    var explorerVar = explorer
    explorerVar.handleMouseRightClick(mousePos)
  
  let keyResult = explorer.componentManager.registerInputHandlers(
    explorer.id,
    keyHandlers,
    mouseHandlers
  )
  
  if keyResult.isErr:
    return err(keyResult.error)
  
  return ok()

# Helper methods for mouse handling
proc handleMouseLeftClick*(explorer: Explorer, mousePos: rl.Vector2) =
  ## Handle left mouse click in explorer using adjusted coordinates
  let headerHeight = HEADER_HEIGHT + DIRECTORY_BAR_HEIGHT
  let listY = explorer.bounds.y + headerHeight
  let listHeight = explorer.bounds.height - headerHeight
  let itemHeight = explorer.config.itemHeight
  
  # Transform global mouse coordinates to local explorer coordinates
  let localMousePos = rl.Vector2(
    x: mousePos.x - explorer.bounds.x,
    y: mousePos.y - explorer.bounds.y
  )
  
  # Debug: Show click position and calculations
  echo "DEBUG: Explorer left click - mousePos: (", mousePos.x, ", ", mousePos.y, "), local: (", localMousePos.x, ", ", localMousePos.y, "), explorer bounds: (", explorer.bounds.x, ", ", explorer.bounds.y, ", ", explorer.bounds.width, ", ", explorer.bounds.height, "), visible: ", explorer.isVisible
  
  # Handle header click to toggle root collapsed/expanded
  if localMousePos.y >= 0 and localMousePos.y <= HEADER_HEIGHT:
    explorer.explorerState.rootCollapsed = not explorer.explorerState.rootCollapsed
    explorer.componentManager.markComponentDirty(explorer.id)
    return
  
  # Skip file list interactions if root is collapsed
  if explorer.explorerState.rootCollapsed:
    return
  
  # Use the proper getFileAtPosition function for accurate item detection
  let listRect = rl.Rectangle(
    x: 0,  # Local coordinates start at 0
    y: headerHeight,
    width: explorer.bounds.width,
    height: listHeight
  )
  
  let itemIndex = getFileAtPosition(
    explorer.explorerState.filteredFiles,
    localMousePos,
    listRect,
    itemHeight,
    explorer.explorerState.scrollY
  )
  
  echo "DEBUG: Explorer item calculation - itemIndex: ", itemIndex, ", filteredFiles count: ", explorer.explorerState.filteredFiles.len, ", scrollY: ", explorer.explorerState.scrollY
  
  if itemIndex >= 0 and itemIndex < explorer.explorerState.filteredFiles.len:
    let clickedFile = explorer.explorerState.filteredFiles[itemIndex]
    
    echo "DEBUG: Clicked file - name: ", clickedFile.name, ", path: ", clickedFile.path, ", kind: ", clickedFile.kind, ", level: ", clickedFile.level
    
    # Handle file selection
    if clickedFile.kind == fkDirectory:
      echo "DEBUG: Toggling directory expansion for: ", clickedFile.path
      
      # Add debouncing mechanism to prevent immediate re-processing
      let currentTime = times.getTime().toUnixFloat()
      
      # Check if this is a rapid re-click on the same path
      if explorer.explorerState.lastClickTime > 0.0 and 
         explorer.explorerState.lastClickedPath == clickedFile.path and 
         (currentTime - explorer.explorerState.lastClickTime) < 0.5:
        echo "DEBUG: Ignoring rapid re-click on same directory"
        return
      
      # Update click tracking
      explorer.explorerState.lastClickTime = currentTime
      explorer.explorerState.lastClickedPath = clickedFile.path
      
      # Store the clicked file path for selection after refresh
      let clickedFilePath = clickedFile.path
      
      # Toggle directory expansion
      let wasExpanded = clickedFile.path in explorer.explorerState.openDirs and explorer.explorerState.openDirs[clickedFile.path]
      if clickedFile.path in explorer.explorerState.openDirs:
        explorer.explorerState.openDirs[clickedFile.path] = not explorer.explorerState.openDirs[clickedFile.path]
        echo "DEBUG: Directory expansion toggled - now: ", explorer.explorerState.openDirs[clickedFile.path]
      else:
        explorer.explorerState.openDirs[clickedFile.path] = true
        echo "DEBUG: Directory expanded: ", clickedFile.path
      
      # Mark as dirty and refresh directory
      explorer.componentManager.markComponentDirty(explorer.id)
      explorer.refreshDirectory()
      echo "DEBUG: After refresh - filteredFiles count: ", explorer.explorerState.filteredFiles.len
      
      # Select the clicked folder by path after refresh
      explorer.selectFileByPath(clickedFilePath)
      echo "DEBUG: Selected folder by path: ", clickedFilePath
      
      # Prevent immediate re-processing by returning early
      return
    else:
      # For files, select immediately since no refresh is needed
      explorer.selectFile(itemIndex)
      
      # Check if file is binary before opening
      let fileType = explorer.fileService.detectFileType(clickedFile.path)
      echo "DEBUG: File type detection for ", clickedFile.path, " = ", fileType
      
      if fileType == ftBinary:
        echo "DEBUG: Skipping binary file: ", clickedFile.path
        return # Don't open binary files
      
      # Also check for executable extensions
      let ext = clickedFile.extension.toLower()
      if ext in ["exe", "out", "dll", "so", "dylib", "bin", "app", "com", "scr", "bat", "cmd", "sh", "ps1"]:
        echo "DEBUG: Skipping executable file: ", clickedFile.path
        return # Don't open executable files
      
      # File is not binary, proceed with opening
      echo "DEBUG: Opening file: ", clickedFile.path
      explorer.events.add(
        ExplorerEvent(
          kind: eeFileOpened, filePath: clickedFile.path, timestamp: times.getTime()
        )
      )
    
    explorer.componentManager.markComponentDirty(explorer.id)

proc handleMouseRightClick*(explorer: Explorer, mousePos: rl.Vector2) =
  ## Handle right mouse click in explorer using adjusted coordinates
  let headerHeight = HEADER_HEIGHT + DIRECTORY_BAR_HEIGHT
  let listY = explorer.bounds.y + headerHeight
  let listHeight = explorer.bounds.height - headerHeight
  let itemHeight = explorer.config.itemHeight
  
  # Transform global mouse coordinates to local explorer coordinates
  let localMousePos = rl.Vector2(
    x: mousePos.x - explorer.bounds.x,
    y: mousePos.y - explorer.bounds.y
  )
  
  # Debug: Show right click position
  echo "DEBUG: Explorer right click - mousePos: (", mousePos.x, ", ", mousePos.y, "), local: (", localMousePos.x, ", ", localMousePos.y, "), explorer bounds: (", explorer.bounds.x, ", ", explorer.bounds.y, ", ", explorer.bounds.width, ", ", explorer.bounds.height, "), visible: ", explorer.isVisible
  
  # Check if context menu is available
  if explorer.contextMenu == nil:
    return
  
  # Skip if root is collapsed
  if explorer.explorerState.rootCollapsed:
    return
  
  # Use the proper getFileAtPosition function for accurate item detection
  let listRect = rl.Rectangle(
    x: 0,  # Local coordinates start at 0
    y: headerHeight,
    width: explorer.bounds.width,
    height: listHeight
  )
  
  let itemIndex = getFileAtPosition(
    explorer.explorerState.filteredFiles,
    localMousePos,
    listRect,
    itemHeight,
    explorer.explorerState.scrollY
  )
  
  echo "DEBUG: Explorer right click item calculation - itemIndex: ", itemIndex, ", scrollY: ", explorer.explorerState.scrollY
  
  if itemIndex < 0 or itemIndex >= explorer.explorerState.filteredFiles.len:
    # Right-click on empty space
    explorer.contextMenuTarget = none(ExplorerFileInfo)
    explorer.contextMenu.context = cmcEmpty
    let currentDir = explorer.explorerState.currentDirectory
    explorer.contextMenu.actionHandler = proc(actionId: string, path: string) = 
      if globalContextMenuCallback != nil:
        globalContextMenuCallback(actionId, currentDir)
    explorer.contextMenu.buildEmptyMenu()
    explorer.contextMenu.show(mousePos)
  else:
    # Right-click on file item
    let file = explorer.explorerState.filteredFiles[itemIndex]
    explorer.contextMenuTarget = some(file)
    explorer.selectFile(itemIndex)
    
    # Determine context and build menu
    if file.kind == fkDirectory:
      explorer.contextMenu.context = cmcFolder
      explorer.contextMenu.actionHandler = proc(actionId: string, path: string) = 
        if globalContextMenuCallback != nil:
          globalContextMenuCallback(actionId, path)
      explorer.contextMenu.buildFolderMenu(file.path, explorer.isGitRepository())
    else:
      explorer.contextMenu.context = cmcFile
      explorer.contextMenu.actionHandler = proc(actionId: string, path: string) = 
        if globalContextMenuCallback != nil:
          globalContextMenuCallback(actionId, path)
      explorer.contextMenu.buildFileMenu(file.path, explorer.isGitRepository())
    
    explorer.contextMenu.show(mousePos)
    
    explorer.componentManager.markComponentDirty(explorer.id)

# UI and rendering
proc render*(
    explorer: Explorer,
    rendererContext: renderer.RenderContext,
    x: float32,
    y: float32,
    width: float32,
    height: float32,
    font: rl.Font,
    fontSize: float32,
    zoomLevel: float32 = 1.0,
) =
  ## Render the explorer using the rendering system
  let bounds = rl.Rectangle(x: x, y: y, width: width, height: height)
  
  # Update notification manager bounds
  if explorer.notificationManager != nil:
    explorer.notificationManager.updateBounds(bounds)
  
  renderExplorer(explorer.explorerState, explorer.config, rendererContext, bounds, font, fontSize, zoomLevel)
  
  # Context menu, notifications, and input dialog are now rendered automatically by ComponentManager

proc update*(explorer: Explorer, deltaTime: float32) =
  ## Update explorer state
  let currentTime = times.getTime()
  
  # Scroll wheel handling is now handled by unified input system in handleInput
  
  # Update notification manager
  if explorer.notificationManager != nil:
    explorer.notificationManager.update(deltaTime)
  
  # Update search filter if needed
  if explorer.explorerState.searchQuery.len > 0:
    explorer.applyFilter()
  
  # Update scroll limits
  explorer.updateScrollLimits(explorer.bounds.height)
  
  # Sync component state
  explorer.syncComponentState()

# Event management
proc getEvents*(explorer: Explorer): seq[ExplorerEvent] =
  ## Get and clear pending events
  result = explorer.events
  explorer.events = @[]

proc hasEvents*(explorer: Explorer): bool =
  ## Check if there are pending events
  explorer.events.len > 0

# Configuration and state
proc getConfiguration*(explorer: Explorer): ExplorerConfig =
  explorer.config

proc setConfiguration*(explorer: Explorer, config: ExplorerConfig) =
  explorer.config = config

proc getState*(explorer: Explorer): ExplorerState =
  explorer.explorerState

proc setState*(explorer: Explorer, state: ExplorerState) =
  explorer.explorerState = state
  explorer.refreshDirectory()

# Utility functions
proc getCurrentDirectory*(explorer: Explorer): string =
  explorer.explorerState.currentDirectory

proc getCurrentFile*(explorer: Explorer): string =
  let selected = explorer.getSelectedFile()
  if selected.isSome and selected.get().kind == fkFile:
    selected.get().path
  else:
    ""

proc refresh*(explorer: Explorer) =
  explorer.refreshDirectory()

proc setVisible*(explorer: Explorer, visible: bool) =
  # Update both UIComponent state and Explorer internal state
  explorer.isVisible = visible
  explorer.explorerState.isVisible = visible
  if visible:
    discard explorer.uiService.setComponentState(explorer.id, csVisible)
  else:
    discard explorer.uiService.setComponentState(explorer.id, csHidden)

proc isVisible*(explorer: Explorer): bool =
  # Use UIComponent.isVisible field for consistency
  UIComponent(explorer).isVisible

# Git repository detection
proc isGitRepository*(explorer: Explorer): bool =
  ## Check if current directory is a Git repository
  let gitDir = explorer.explorerState.currentDirectory / ".git"
  return dirExists(gitDir)

# Context menu font setup
proc setContextMenuFont*(explorer: Explorer, font: ptr rl.Font) =
  ## Set the font for the context menu and notifications
  if explorer.contextMenu != nil and explorer.contextMenu.componentManager != nil:
    # Register the font with the ComponentManager's renderer
    explorer.contextMenu.componentManager.renderer.registerFont("ui", font)

proc setWidth*(explorer: Explorer, width: float32) =
  # Update UIComponent bounds directly for better performance
  explorer.bounds.width = width
  # Mark as dirty to trigger layout update
  explorer.isDirty = true

proc setBounds*(explorer: Explorer, bounds: rl.Rectangle) =
  ## Set component bounds and update layout
  explorer.bounds = bounds
  explorer.isDirty = true

proc getBounds*(explorer: Explorer): rl.Rectangle =
  ## Get current component bounds
  explorer.bounds

proc setEnabled*(explorer: Explorer, enabled: bool) =
  ## Set component enabled state
  explorer.isEnabled = enabled
  if not enabled:
    # Clear focus when disabled
    if explorer.uiService.focusedComponent.isSome and
        explorer.uiService.focusedComponent.get().id == explorer.id:
      explorer.uiService.clearFocus()

proc isEnabled*(explorer: Explorer): bool =
  ## Check if component is enabled
  explorer.isEnabled

proc requestFocus*(explorer: Explorer) =
  ## Request focus for this component
  discard explorer.uiService.setFocus(explorer.id)

proc syncComponentState*(explorer: Explorer) =
  ## Sync UIComponent state with Explorer internal state.
  ## This ensures consistency between the inherited UIComponent fields
  ## and the Explorer's internal state management.
  explorer.isVisible = explorer.explorerState.isVisible

  # Update component state in UI service based on internal state
  if explorer.explorerState.isVisible:
    if explorer.isEnabled:
      discard explorer.uiService.setComponentState(explorer.id, csVisible)
    else:
      discard explorer.uiService.setComponentState(explorer.id, csDisabled)
  else:
    discard explorer.uiService.setComponentState(explorer.id, csHidden)

proc markDirty*(explorer: Explorer) =
  ## Mark component as needing redraw
  explorer.isDirty = true
  explorer.uiService.markComponentDirty(explorer.id)

proc cleanup*(explorer: Explorer) =
  ## Clean up component resources and unregister from UI service.
  ## This is important for proper lifecycle management in the infrastructure.
  explorer.events.setLen(0)
  explorer.explorerState.files.setLen(0)
  explorer.explorerState.filteredFiles.setLen(0)
  explorer.explorerState.openDirs.clear()

  # Remove from UI service to prevent memory leaks
  discard explorer.uiService.removeComponent(explorer.id)

proc toggleHidden*(explorer: Explorer) =
  explorer.explorerState.showHiddenFiles = not explorer.explorerState.showHiddenFiles
  explorer.fileService.setShowHiddenFiles(explorer.explorerState.showHiddenFiles)
  explorer.applyFilter()

proc getFileCount*(explorer: Explorer): int =
  explorer.explorerState.filteredFiles.len

proc getOpenDirectories*(explorer: Explorer): seq[string] =
  var openDirs: seq[string] = @[]
  for path, isOpen in explorer.explorerState.openDirs:
    if isOpen:
      openDirs.add(path)
  openDirs

proc setOpenDirectories*(explorer: Explorer, dirs: seq[string]) =
  explorer.explorerState.openDirs.clear()
  for dir in dirs:
    explorer.explorerState.openDirs[dir] = true

proc addOpenDirectory*(explorer: Explorer, dir: string) =
  explorer.explorerState.openDirs[dir] = true

proc removeOpenDirectory*(explorer: Explorer, dir: string) =
  explorer.explorerState.openDirs.del(dir)

proc clearOpenDirectories*(explorer: Explorer) =
  explorer.explorerState.openDirs.clear()

proc toggleSelectedDirectory*(explorer: Explorer) =
  ## Toggle expansion of the selected directory
  let selected = explorer.getSelectedFile()
  if selected.isSome and selected.get().kind == fkDirectory:
    let path = selected.get().path
    if path in explorer.explorerState.openDirs:
      explorer.explorerState.openDirs[path] = not explorer.explorerState.openDirs[path]
    else:
      explorer.explorerState.openDirs[path] = true
    explorer.refreshDirectory()

proc toggleRootCollapsed*(explorer: Explorer) =
  ## Toggle the collapsed state of the project root folder
  explorer.explorerState.rootCollapsed = not explorer.explorerState.rootCollapsed

proc isRootCollapsed*(explorer: Explorer): bool =
  ## Get the current collapsed state of the project root folder
  explorer.explorerState.rootCollapsed

proc setRootCollapsed*(explorer: Explorer, collapsed: bool) =
  ## Set the collapsed state of the project root folder
  explorer.explorerState.rootCollapsed = collapsed
