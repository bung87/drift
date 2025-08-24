import raylib as rl
import std/[os, strutils, options, osproc, tables]

import chronos except Result
import results
import shared/[types, errors, constants]
import domain/document

import application/types
import infrastructure/external/git_client
import infrastructure/rendering/[theme as infra_theme, renderer]
import infrastructure/filesystem/file_manager
import infrastructure/input/[input_handler, keyboard, mouse]
import infrastructure/ui/cursor_manager
import infrastructure/terminal/shell_process
import services/[component_manager, editor_service, ui_service, file_service,
    language_service, notification_service, diagnostic_service,
    terminal_integration]
import infrastructure/clipboard
import status_bar_service, icons, resources
import explorer/[types as explorer_types, explorer,
    rendering as explorer_rendering]
import components/[text_editor, welcome_screen_component, command_palette,
    search_replace, git_panel, file_tabs, terminal_panel, context_menu,
    input_dialog, simple_notification]
import button_group
import os_files/dialog

var app: EditorApp


proc calculateLayout(
    windowWidth, windowHeight, sidebarWidth: float32,
    terminalHeight: float32 = 0.0
): tuple[sidebar: rl.Rectangle, editor: rl.Rectangle, fileTabs: rl.Rectangle] =
  let sidebarRect = rl.Rectangle(
    x: 0,
    y: TITLEBAR_HEIGHT.float32,
    width: sidebarWidth,
    height: windowHeight - TITLEBAR_HEIGHT.float32 - STATUSBAR_HEIGHT.float32,
  )

  let fileTabsRect = rl.Rectangle(
    x: sidebarWidth,
    y: TITLEBAR_HEIGHT.float32,
    width: windowWidth - sidebarWidth,
    height: FILETAB_HEIGHT.float32,
  )

  let editorRect = rl.Rectangle(
    x: sidebarWidth,
    y: TITLEBAR_HEIGHT.float32 + FILETAB_HEIGHT.float32,
    width: windowWidth - sidebarWidth,
    height: windowHeight - TITLEBAR_HEIGHT.float32 - FILETAB_HEIGHT.float32 -
    STATUSBAR_HEIGHT.float32 - terminalHeight,
  )
  return (sidebarRect, editorRect, fileTabsRect)

# ===== Zoom Management Functions =====

proc zoomIn*(editorApp: EditorApp) =
  editorApp.config.editor.zoomLevel = min(editorApp.config.editor.zoomLevel *
      1.1, 3.0)
  discard

proc zoomOut*(editorApp: EditorApp) =
  editorApp.config.editor.zoomLevel = max(editorApp.config.editor.zoomLevel *
      0.9, 0.5)
  discard

proc resetZoom*(editorApp: EditorApp) =
  editorApp.config.editor.zoomLevel = 1.0
  discard

proc setZoomLevel*(editorApp: EditorApp, level: float32) =
  editorApp.config.editor.zoomLevel = max(0.5, min(level, 3.0))
  discard

proc setApplicationState*(editorApp: EditorApp, newState: ApplicationState) =
  editorApp.state.applicationState = newState
  case newState:
  of asWelcome:
    if editorApp.componentManager != nil:
      if editorApp.welcomeScreen != nil:
        discard editorApp.componentManager.setComponentVisibility(
            "welcome_screen", true)
      if editorApp.textEditor != nil:
        discard editorApp.componentManager.setComponentVisibility("text_editor", false)
  of asEditor:
    if editorApp.componentManager != nil:
      if editorApp.welcomeScreen != nil:
        discard editorApp.componentManager.setComponentVisibility(
            "welcome_screen", false)
      if editorApp.textEditor != nil:
        discard editorApp.componentManager.setComponentVisibility("text_editor", true)

    if editorApp.explorerService != nil and editorApp.sidebarWidth > 0:
      let layout = calculateLayout(editorApp.windowWidth,
          editorApp.windowHeight,

editorApp.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
      editorApp.sidebarBounds = layout.sidebar
      editorApp.explorerService.bounds = editorApp.sidebarBounds

      # Explorer registration is handled elsewhere - don't register here to avoid duplicates
  of asLoading:
    discard

proc registerExplorerService(app: EditorApp) =
  ## Register explorer service with ComponentManager for proper event handling
  if app.componentManager != nil and app.explorerService != nil:
    # Unregister first to avoid duplicates
    discard app.componentManager.unregisterComponent("explorer")

    # Register explorer component with proper callbacks
    let registerResult = app.componentManager.registerComponent(
      "explorer",
      app.explorerService,
      proc(event: UnifiedInputEvent): bool =
      if app.state.applicationState != asWelcome and app.state.sidebarMode == 
          smExplorer and app.sidebarWidth > 0:
        let handled = app.explorerService.handleInput(event)
        if handled and event.kind == uiekMouse:
          let mouseEvent = event.mouseEvent
          echo "DEBUG: Explorer handled event at (", mouseEvent.position.x, ", ", mouseEvent.position.y, ")"
        return handled
      else:
        return false,
      proc(bounds: rl.Rectangle) =
      if app.state.applicationState != asWelcome and app.state.sidebarMode == 
          smExplorer and app.sidebarWidth > 0:
        app.explorerService.bounds = bounds
        app.renderer.setViewport(bounds)
        let fontSize = app.themeManager.currentTheme.getScaledUIFontSize(
            app.config.editor.zoomLevel)
        app.explorerService.render(
          app.renderer.currentContext,
          bounds.x, bounds.y, bounds.width, bounds.height,
          app.font, fontSize, app.config.editor.zoomLevel
        )
    )

    if registerResult.isOk:
      let inputResult = app.explorerService.registerInputHandlers()
      if inputResult.isErr:
        discard

proc updateComponentVisibility*(app: EditorApp) =
  let showEditorComponents = (app.state.applicationState != asWelcome)
  # Skip setting isVisible directly on UIComponent - let components manage their own visibility
  if app.explorerService != nil:
    app.explorerService.setVisible(showEditorComponents and
        app.state.sidebarMode == smExplorer and app.sidebarWidth > 0)

proc updateStatusBarForFile(app: EditorApp, filePath: string) =
  ## Update status bar with file type and git information when a file is opened
  if app.statusBarService == nil:
    return
    
  # Determine file type based on extension
  var fileType = "Text"
  if filePath.len > 0:
    let ext = filePath.splitFile().ext.toLower()
    case ext
    of ".nim":
      fileType = "Nim"
    of ".ts", ".tsx":
      fileType = "TypeScript"
    of ".js", ".jsx":
      fileType = "JavaScript"
    of ".py":
      fileType = "Python"
    of ".rs":
      fileType = "Rust"
    of ".go":
      fileType = "Go"
    of ".cpp", ".cc", ".cxx":
      fileType = "C++"
    of ".c":
      fileType = "C"
    of ".md":
      fileType = "Markdown"
    else:
      fileType = "Text"
  
  # Get git branch information
  var gitBranch = ""
  var gitDirty = false
  
  if app.gitPanel != nil and filePath.len > 0:
    try:
      # Access git client through the git panel
      let gitClient = app.gitPanel.getGitClient()
      if gitClient != nil:
        let branchResult = waitFor gitClient.getCurrentBranch(filePath.parentDir())
        if branchResult.isOk:
          gitBranch = branchResult.get()
          
        # Check if repository is dirty
        let statusResult = waitFor gitClient.getStatus(filePath.parentDir())
        if statusResult.isOk:
          let status = statusResult.get()
          gitDirty = status.len > 0
    except:
      # Ignore git errors and continue with empty branch info
      discard
  
  # Update status bar with all information
  app.statusBarService.updateAll(
    gitBranch = gitBranch,
    gitDirty = gitDirty,
    line = app.cursor.line + 1,
    column = app.cursor.col + 1,
    fileType = fileType
  )

proc openFileInApp(editorApp: EditorApp, filePath: string): bool =
  # Use EditorService to open the file
  let openResult = editorApp.editorService.openFile(filePath)
  if openResult.isErr:
    echo "Failed to open file: ", openResult.error.msg
    return false

  # Update app-level state for compatibility
  editorApp.currentFile = filePath
  editorApp.cursor = CursorPos(line: 0, col: 0)
  editorApp.isModified = false

  setApplicationState(editorApp, asEditor)

  # Update language service
  if editorApp.languageService != nil:
    let content = editorApp.editorService.document.getFullText()
    discard editorApp.languageService.openDocument(filePath, content)

  # Update text editor with the document from EditorService
  if editorApp.textEditor != nil:
    editorApp.textEditor.setDocumentWithPath(editorApp.editorService.document, filePath)

  if editorApp.fileTabBar != nil:
    if editorApp.fileTabBar.hasTab(filePath):
      discard editorApp.fileTabBar.activateTabByPath(filePath)
    else:
      let tabIndex = app.fileTabBar.addTabByPath(filePath)
      echo "DEBUG: Added tab for file: ", filePath, ", tabIndex: ", tabIndex, ", total tabs: ", app.fileTabBar.tabs.len

  if app.welcomeScreen != nil:
    app.welcomeScreen.addRecentFile(filePath)
  
  # Update status bar with file information
  updateStatusBarForFile(editorApp, filePath)
  
  result = true

proc updateExplorer(app: EditorApp) =
  if app.currentDir.len > 0:
    app.explorerService.setDirectory(app.currentDir)


proc switchTheme(app: EditorApp)
proc updateButtonStates(app: EditorApp)

proc initializeTitleBarButtons(app: EditorApp, gitIsAvailable: bool) =
  let buttonBounds = rl.Rectangle(x: 0, y: 0, width: 120,
      height: TITLEBAR_HEIGHT)

  app.titleBarButtons = newButtonGroup(buttonBounds, 3)
  app.titleBarButtons.id = "title_bar_buttons"
  app.titleBarButtons.name = "Title Bar Buttons"
  app.titleBarButtons.state = csVisible
  app.titleBarButtons.bounds = buttonBounds
  app.titleBarButtons.zIndex = app.uiService.nextZIndex
  app.uiService.nextZIndex += 1
  app.titleBarButtons.isVisible = true
  app.titleBarButtons.isEnabled = true
  app.titleBarButtons.isDirty = true

  app.titleBarButtons.registerWithComponentManager(app.componentManager)

  app.titleBarButtons.addIconButton("Explorer", "explorer.svg")
  app.titleBarButtons.addIconButton("Search", "search.svg")
  app.titleBarButtons.addIconButton("Git", "git.svg")
  
  # Disable Git button if git is not available
  if not gitIsAvailable:
    app.titleBarButtons.setButtonEnabled(2, false)

  # Set up button click callback
  app.titleBarButtons.setOnButtonClick(proc(buttonIndex: int) =
    case buttonIndex:
    of 0: # Explorer
      app.state.sidebarMode = smExplorer
      app.sidebarWidth = if app.sidebarWidth > 0: 0.0 else: 300.0

      # Recalculate layout to update bounds
      let layout = calculateLayout(app.windowWidth, app.windowHeight,
          app.sidebarWidth, app.terminalIntegration.getEffectiveHeight())
      app.sidebarBounds = layout.sidebar
      app.editorBounds = layout.editor
      app.fileTabsBounds = layout.fileTabs

      # Handle explorer visibility and registration
      if app.explorerService != nil:
        if app.sidebarWidth > 0:
          # Show explorer when explorer mode is activated
          app.explorerService.setVisible(true)
          # Register explorer with ComponentManager
          if app.componentManager != nil:
            # First ensure any existing registration is removed
            let prevUnregResult = app.componentManager.unregisterComponent(
                app.explorerService.id)
            if prevUnregResult.isErr:
              discard
            # Explorer registration is handled elsewhere - don't register here to avoid duplicates
            let registerResult = Result[void, EditorError].ok()
            if registerResult.isOk:
              let inputResult = app.explorerService.registerInputHandlers()
              if inputResult.isErr:
                discard
            else:
              discard
        else:
          app.explorerService.setVisible(false)
          if app.componentManager != nil:
            let unregResult = app.componentManager.unregisterComponent(
                app.explorerService.id)
            if unregResult.isOk:
              discard
            else:
              discard
      if app.searchReplace != nil:
        app.searchReplace.hide()
      if app.gitPanel != nil and app.componentManager != nil:
        discard app.componentManager.setComponentVisibility("git_panel", false)
    of 1: # Search
      app.state.sidebarMode = smSearch
      app.sidebarWidth = if app.sidebarWidth > 0: 0.0 else: 300.0
      let layout = calculateLayout(app.windowWidth, app.windowHeight,
          app.sidebarWidth, app.terminalIntegration.getEffectiveHeight())
      app.sidebarBounds = layout.sidebar
      app.editorBounds = layout.editor
      app.fileTabsBounds = layout.fileTabs
      if app.explorerService != nil:
        app.explorerService.setVisible(false)
        if app.componentManager != nil:
          let unregResult = app.componentManager.unregisterComponent(
              app.explorerService.id)
          if unregResult.isOk:
            discard
          else:
            discard
      if app.searchReplace != nil and app.sidebarWidth > 0:
        app.searchReplace.show()
        app.searchReplace.setScope(ssProject)
        app.searchReplace.clearResults()
      if app.gitPanel != nil and app.componentManager != nil:
        discard app.componentManager.setComponentVisibility("git_panel", false)
    of 2: # Git
      # Only allow Git mode if git is available
      if app.gitIsAvailable:
        app.state.sidebarMode = smGit
        app.sidebarWidth = if app.sidebarWidth > 0: 0.0 else: 300.0
        let layout = calculateLayout(app.windowWidth, app.windowHeight,
            app.sidebarWidth, app.terminalIntegration.getEffectiveHeight())
        app.sidebarBounds = layout.sidebar
        app.editorBounds = layout.editor
        app.fileTabsBounds = layout.fileTabs
        if app.explorerService != nil:
          app.explorerService.setVisible(false)
          if app.componentManager != nil:
            let unregResult = app.componentManager.unregisterComponent(
                app.explorerService.id)
            if unregResult.isOk:
              discard
            else:
              discard
        if app.gitPanel != nil and app.sidebarWidth > 0 and
                app.componentManager != nil:
          discard app.componentManager.setComponentVisibility("git_panel", true)
          discard app.gitPanel.update()
        if app.searchReplace != nil:
          app.searchReplace.hide()
      else:
        # Git is not available, do nothing
        discard
    else:
      discard


    var buttonStates = @[false, false, false]
    case app.state.sidebarMode:
    of smExplorer:
      buttonStates[0] = app.sidebarWidth > 0
    of smSearch:
      buttonStates[1] = app.sidebarWidth > 0
    of smGit:
      buttonStates[2] = app.sidebarWidth > 0 and app.gitIsAvailable
    else:
      discard

    app.titleBarButtons.setButtonStates(buttonStates)
  )


  var initialButtonStates = @[false, false, false]
  initialButtonStates[0] = app.sidebarWidth > 0 and app.state.sidebarMode == smExplorer
  initialButtonStates[2] = app.sidebarWidth > 0 and app.state.sidebarMode == smGit and app.gitIsAvailable
  app.titleBarButtons.setButtonStates(initialButtonStates)
  
  # Ensure Git button is disabled when git is not available
  if not app.gitIsAvailable:
    app.titleBarButtons.setButtonEnabled(2, false)


proc updateButtonStates(app: EditorApp) =
  let explorerActive = app.sidebarWidth > 0 and app.state.sidebarMode == smExplorer
  let searchActive = app.sidebarWidth > 0 and app.state.sidebarMode == smSearch
  let gitActive = app.sidebarWidth > 0 and app.state.sidebarMode == smGit and app.gitIsAvailable
  app.titleBarButtons.setButtonStates(@[explorerActive, searchActive, gitActive])
  
  # Ensure Git button is disabled when git is not available
  if not app.gitIsAvailable:
    app.titleBarButtons.setButtonEnabled(2, false)

proc initializeApp(): Result[void, EditorError] =
  try:
    initGlobalCursorManager(debugMode = false)
    # Initialize services and components
    let keyboardHandler = newKeyboardHandler()
    let mouseHandler = newMouseHandler()
    let inputHandler = newInputHandler()
    let themeManager = newThemeManager()
    let renderer = newRenderer(themeManager)
    let fileManager = newFileManager()
    let fileService = newFileService(fileManager)
    let editorService = newEditorService(fileManager,
        themeManager.currentTheme)
    let uiService =
      newUIService(themeManager.currentTheme, renderer,
          inputHandler)
    var gitClient: GitClient = nil
    var gitIsAvailable = false
    # Check Git availability synchronously
    let (output, exitCode) = execCmdEx("git --version")
    gitIsAvailable = exitCode == 0 and output.strip().startsWith("git version")
    if gitIsAvailable:
      gitClient = newGitClient()
    let languageService = newLanguageService()

    # Initialize service-based status bar
    var statusBarService =
      newStatusBarService(uiService, renderer, themeManager)

    let notificationService = newNotificationService(uiService)

    # Initialize ComponentManager for standardized architecture
    let componentManager = newComponentManager(
      uiService,
      inputHandler,
      renderer,
      themeManager,
      globalCursorManager,
      fileManager
    )

    # Initialize ComponentManager
    let initResult = componentManager.initialize()
    if initResult.isErr:
      echo "Warning: Failed to initialize ComponentManager: ",
          initResult.error.msg

    let commandPalette = newCommandPalette(
      "command_palette",
      componentManager
    )

    let paletteInitResult = commandPalette.initialize()
    if paletteInitResult.isErr:
      echo "Warning: Failed to initialize CommandPalette: ",
          paletteInitResult.error.msg

    let clipboardService = newClipboardService()
    var explorerService = newExplorer(uiService, fileService,
        componentManager, clipboardService, getCurrentDir())
    explorerService.initialize()
    explorerService.setContextMenuFont(addr app.font)

    setGlobalContextMenuCallback(proc(actionId: string, targetPath: string) =
      explorerService.handleContextMenuAction(actionId, targetPath)
    )

    let maxTerminalHeight = float32(WINDOW_WIDTH) * 0.6
    let terminalBounds = rl.Rectangle(
      x: 0,
      y: float32(WINDOW_HEIGHT) - statusBarService.bounds.height -
          maxTerminalHeight,
      width: float32(WINDOW_WIDTH),
      height: maxTerminalHeight
    )

    let terminalConfig = TerminalIntegrationConfig(
      defaultTerminalHeight: maxTerminalHeight,
      minTerminalHeight: 100.0,
      maxTerminalHeight: maxTerminalHeight,
      enableKeyboardShortcuts: true,
      autoCreateFirstSession: true,
      defaultShell: getDefaultShell(),
      fontSize: 14.0
    )

    let terminalIntegration = newTerminalIntegration(
      uiService,
      renderer,
      addr app.font,
      terminalBounds,
      statusBarService.bounds,
      componentManager,
      terminalConfig
    )

    if not terminalIntegration.initialize():
      echo "Warning: Failed to initialize terminal integration"
    else:
      discard

    let searchReplaceResult = newSearchReplacePanel(
      componentManager,
      "search_replace",
      rl.Rectangle(x: 0, y: TITLEBAR_HEIGHT.float32,
          width: SIDEBAR_WIDTH.float32, height: 200),
      onOpenFile = proc(filePath: string): bool =
      let success = openFileInApp(app, filePath)
      # Note: openFileInApp already handles setting the document in textEditor
      # No need to set it again here since it uses editorService.document
      return success,
      onSetCursor = proc(line: int, col: int) =
      app.cursor = CursorPos(line: line, col: col)
      if app.textEditor != nil:
        app.textEditor.setCursor(CursorPos(line: line, col: col))
      # Update status bar with new cursor position
      if app.statusBarService != nil and app.currentFile.len > 0:
        updateStatusBarForFile(app, app.currentFile),
      onClearFocus = proc() =
      if app.textEditor != nil:
        app.textEditor.clearFocus()
    )
    var searchReplace: SearchReplacePanel
    if searchReplaceResult.isOk:
      searchReplace = searchReplaceResult.get()
    else:
      searchReplace = nil

    var gitPanel: GitPanel = nil
    if gitIsAvailable:
      gitPanel = newGitPanel(
        "git_panel",
        componentManager,
        gitClient,
        themeManager,
        renderer
      )
      gitPanel.setPath(getCurrentDir())

    app = EditorApp(
      windowWidth: WINDOW_WIDTH.float32,
      windowHeight: WINDOW_HEIGHT.float32,
      sidebarWidth: SIDEBAR_WIDTH.float32,
      currentFile: "",
      currentDir: getCurrentDir(),
      cursor: CursorPos(line: 0, col: 0),
      isModified: false,
      gitIsAvailable: gitIsAvailable,
      state: AppState(
        applicationState: asWelcome,
        isRunning: true,
        appStartTime: rl.getTime(),
        delayedNotificationSent: false,
        sidebarMode: smExplorer,
        currentDir: getCurrentDir(),
        files: @[],
        cursor: CursorState(),
        scrollOffset: ScrollState(),
        gitState: GitState(),
        statusBarElements: @[],
        explorerVisible: true,
        searchVisible: false,
        gitPanelVisible: false,
        terminalVisible: false,
        commandPaletteVisible: false
      ),
      config: defaultAppConfig(),
      componentManager: componentManager,
      explorerService: explorerService,
      renderer: renderer,
      themeManager: themeManager,
      uiService: uiService,
      languageService: languageService,
      editorService: editorService,
      notificationService: notificationService,
      terminalIntegration: terminalIntegration,
      searchReplace: searchReplace,
      gitPanel: gitPanel,
      commandPalette: commandPalette,
      statusBarService: statusBarService,

    )

    initializeTitleBarButtons(app, gitIsAvailable)
    updateButtonStates(app)

    discard statusBarService.addGitBranch("", isDirty = false,
        priority = 100)
    discard statusBarService.addDiagnostics(0, 0, priority = 90)

    discard statusBarService.addFileType("Text", priority = 10)
    discard statusBarService.addLineEnding("LF", priority = 20)
    discard statusBarService.addEncoding("UTF-8", priority = 30)
    discard statusBarService.addLineColumn(1, 1, priority = 40)

    if gitIsAvailable:
      let gitPanelRegisterResult = componentManager.registerComponent(
        gitPanel.id,
        gitPanel,
        proc(event: UnifiedInputEvent): bool = gitPanel.handleInput(event),
        proc(bounds: rl.Rectangle) =
        gitPanel.bounds = bounds
        gitPanel.render()
      )

      if gitPanelRegisterResult.isErr:
        echo "Warning: Failed to register GitPanel with ComponentManager: ", gitPanelRegisterResult.error.msg

    app.state.sidebarMode = smExplorer

    if app.explorerService != nil:
      app.explorerService.setVisible(app.state.sidebarMode == smExplorer)

    if app.titleBarButtons != nil:
      var correctedButtonStates = @[false, false, false, false]
      correctedButtonStates[0] = app.sidebarWidth > 0 and
          app.state.sidebarMode == smExplorer
      correctedButtonStates[3] = if app.terminalIntegration !=
          nil: app.terminalIntegration.isActuallyVisible() else: false
      app.titleBarButtons.setButtonStates(correctedButtonStates)

    rl.setConfigFlags(
      rl.flags(rl.ConfigFlags.WindowResizable, rl.ConfigFlags.WindowHighdpi)
    )
    rl.initWindow(WINDOW_WIDTH.int32, WINDOW_HEIGHT.int32, "Drift Editor")
    rl.setTargetFPS(60)

    app.windowWidth = rl.getScreenWidth().float32
    app.windowHeight = rl.getScreenHeight().float32

    app.font = loadProfessionalFont(14)
    app.renderer.registerFont("ui", app.font.addr)

    app.notificationService = newNotificationService(app.uiService)

    app.diagnosticService = newDiagnosticService(app.uiService, app.renderer,
        app.themeManager)

    app.languageService.setNotificationService(app.notificationService)

    app.languageService.setDiagnosticService(app.diagnosticService)

    app.welcomeScreen = newWelcomeScreenComponent(
      app.componentManager,
      "welcome_screen",
      rl.Rectangle(x: 0, y: 0, width: app.windowWidth,
          height: app.windowHeight)
    )
    
    # Set up welcome screen action handlers
    app.welcomeScreen.onNewFile = proc() =
      # Use EditorService to create a new file
      let newResult = app.editorService.newFile()
      if newResult.isErr:
        echo "Failed to create new file: ", newResult.error.msg
        return
      
      app.currentFile = ""
      app.cursor = CursorPos(line: 0, col: 0)
      app.isModified = false
      setApplicationState(app, asEditor)
      
      if app.textEditor != nil:
        app.textEditor.setDocument(app.editorService.document)
      
    app.welcomeScreen.onOpenFile = proc() =
      var di: DialogInfo
      di.title = "Open File"
      di.kind = dkOpenFile
      di.filters = @[(name: "All Files", ext: "*.*")]
      let filePath = di.show()
      if filePath.len > 0:
        discard openFileInApp(app, filePath)
        
    app.welcomeScreen.onOpenFolder = proc() =
      var di: DialogInfo
      di.title = "Open Folder"
      di.kind = dkSelectFolder
      let folderPath = di.show()
      if folderPath.len > 0:
        app.currentDir = folderPath
        setApplicationState(app, asEditor)
        
        # Ensure sidebar is visible and set to explorer mode
        app.state.sidebarMode = smExplorer
        app.sidebarWidth = 300.0
        
        # Update layout with new sidebar width
        let layout = calculateLayout(app.windowWidth, app.windowHeight,
            app.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
        app.sidebarBounds = layout.sidebar
        app.editorBounds = layout.editor
        app.fileTabsBounds = layout.fileTabs
        
        # Update explorer bounds and make it visible
        if app.explorerService != nil:
          app.explorerService.bounds = app.sidebarBounds
          app.explorerService.setVisible(true)
          
        updateExplorer(app)
        registerExplorerService(app)
        
    app.welcomeScreen.onCloneRepo = proc() =
      # TODO: Implement git clone functionality
      discard app.notificationService.addNotification("Git clone not implemented yet", ntWarning)
      
    app.welcomeScreen.onDocumentation = proc() =
      # TODO: Implement documentation opening
      discard app.notificationService.addNotification("Documentation not implemented yet", ntInfo)
      
    app.welcomeScreen.onOpenRecent = proc(path: string) =
      if fileExists(path):
        discard openFileInApp(app, path)
        addRecentFile(app.welcomeScreen, path)
      else:
        discard app.notificationService.addNotification("File not found: " & path, ntError)
    
    if app.state.applicationState == asWelcome:
      app.welcomeScreen.show()
    else:
      app.welcomeScreen.hide()

    preloadCommonIcons()

    let currentDir = getCurrentDir()
    app.currentDir = currentDir
    updateExplorer(app)

    let layout = calculateLayout(app.windowWidth, app.windowHeight,
        app.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
    app.sidebarBounds = layout.sidebar
    app.editorBounds = layout.editor
    app.fileTabsBounds = layout.fileTabs

    if app.explorerService != nil:
      app.explorerService.bounds = app.sidebarBounds

    let inputDialog = newInputDialog(
      app.componentManager,
      "input_dialog"
    )
    app.inputDialog = inputDialog
    app.explorerService.inputDialog = inputDialog


    app.contextMenu = newContextMenu(
      app.componentManager,
      "context_menu",
      cmcEmpty,
      rl.Vector2(x: 0, y: 0)
    )


    let notificationManager = newNotificationManager(
      app.componentManager,
      rl.Rectangle(x: 0, y: 0, width: app.windowWidth, height: app.windowHeight)
    )
    app.notificationManager = notificationManager

    let args = commandLineParams()

    if args.len > 0:
      let path = expandFilename(args[0]).absolutePath()

      if fileExists(path):
        # Use EditorService to open the file
        let openResult = app.editorService.openFile(path)
        if openResult.isErr:
          echo "Failed to open file from command line: ", openResult.error.msg
        else:
          app.currentFile = path
          app.cursor = CursorPos(line: 0, col: 0)
          # Set application state to editor since a file was provided
          setApplicationState(app, asEditor)

          # Ensure explorer service is registered with ComponentManager
          registerExplorerService(app)

          if app.textEditor != nil:
            app.textEditor.setDocumentWithPath(app.editorService.document, path)
      elif dirExists(path):
        app.currentDir = path

        setApplicationState(app, asEditor)

        # Ensure explorer service is registered with ComponentManager
        registerExplorerService(app)
      else:
        discard

    updateExplorer(app)
    return ok()
  except Exception as e:
    return err(newEditorError("INIT_FAILED", "Failed to initialize: " & e.msg))

proc switchTheme(app: EditorApp) =
  ## Switch to next available theme
  let themeNames = app.themeManager.getThemeNames()
  if themeNames.len < 2:
    return

  let currentName = app.themeManager.getCurrentThemeName()
  let currentIndex = themeNames.find(currentName)
  let nextIndex = (currentIndex + 1) mod themeNames.len
  let nextThemeName = themeNames[nextIndex]

  discard app.themeManager.setTheme(nextThemeName)

  # Update welcome screen (theme is handled automatically by ComponentManager)
  if app.welcomeScreen != nil:
    app.componentManager.markComponentDirty(app.welcomeScreen.id)

proc handleInput(app: EditorApp): bool =
  let mousePos = rl.getMousePosition()
  var handled = false
  var resizingTerminal = false
  # Use app.resizingTerminalPanel to track drag state

  # ComponentManager input processing (highest priority)
  if app.componentManager != nil:
    # Process input events through ComponentManager first
    let inputEvents = app.componentManager.processInput()

    # Handle explorer context menu input FIRST (highest priority when visible)
    # This ensures context menu input is processed before other components
    if app.explorerService != nil and app.explorerService.contextMenu != nil and
        app.explorerService.contextMenu.isVisible:
      for event in inputEvents:
        if app.explorerService.contextMenu.handleInput(event):
          return true

    # Handle text editor input (high priority when focused)
    if app.textEditor != nil and app.textEditor.editorState.isFocused:
      for event in inputEvents:
        if app.textEditor.handleInput(event):
          return true

    # Check if any other components handled input
    if app.welcomeScreen != nil and app.welcomeScreen.isVisible:
      for event in inputEvents:
        if app.welcomeScreen.handleInput(event):
          return true

    if app.inputDialog != nil and app.inputDialog.isVisible:
      for event in inputEvents:
        if app.inputDialog.handleInput(event):
          return true

    if app.contextMenu != nil and app.contextMenu.isVisible:
      for event in inputEvents:
        if app.contextMenu.handleInput(event):
          return true

    if app.searchReplace != nil and app.searchReplace.isVisible:
      for event in inputEvents:
        if app.searchReplace.handleInput(event):
          return true

    let events = app.explorerService.getEvents()
    for event in events:
      case event.kind
      of eeFileOpened:
        if event.filePath.len > 0:
          let success = openFileInApp(app, event.filePath)
          # Note: openFileInApp already handles setting the document in textEditor
          # No need to set it again here since it uses editorService.document
          handled = true
          return true
      of eeSelectionChanged:
        discard
      of eeFileCreated, eeDirectoryCreated:
        discard
      of eeFileDeleted:
        discard
      of eeFileRenamed, eeFileMoved, eeFileCopied:
        discard
      of eeRenameRequested:
        discard

    if events.len > 0:
      handled = true
      return true

  if app.statusBarService != nil:
    let dragZoneHeight = 12.0
    let statusBar = app.statusBarService
    let dragZone = rl.Rectangle(
      x: statusBar.bounds.x,
      y: statusBar.bounds.y,
      width: statusBar.bounds.width,
      height: dragZoneHeight
    )
    if rl.checkCollisionPointRec(mousePos, dragZone):
      # Handle terminal panel drag detection through ComponentManager
      if app.terminalIntegration != nil:
        let dragResult = app.statusBarService.handleDragDetection(mousePos,
            proc() =
          app.terminalIntegration.toggleVisibility()
        )
        if dragResult:
          handled = true
          return true

  # Handle sidebar resizing using direct input (not through ComponentManager to avoid double processing)
  let currentMousePos = rl.getMousePosition()
  
  # Check if mouse is in resize zone
  let resizeZoneWidth = 8.0
  let inResizeZone = currentMousePos.x >= app.sidebarWidth - resizeZoneWidth and
                    currentMousePos.x <= app.sidebarWidth + resizeZoneWidth and
                    currentMousePos.y >= 0 and currentMousePos.y <= app.windowHeight

  if rl.isMouseButtonPressed(rl.MouseButton.Left) and inResizeZone:
    app.state.isResizingSidebar = true
    app.state.resizeStartX = currentMousePos.x
    return true
  elif app.state.isResizingSidebar and rl.isMouseButtonDown(rl.MouseButton.Left):
    let newWidth = max(150.0, min(app.windowWidth * 0.5, currentMousePos.x))
    app.sidebarWidth = newWidth
    let layout = calculateLayout(app.windowWidth, app.windowHeight,
        app.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
    app.sidebarBounds = layout.sidebar
    app.editorBounds = layout.editor

    # Update terminal panel width to match editor width
    if app.terminalIntegration != nil:
      let terminalBounds = rl.Rectangle(
        x: app.sidebarWidth, # Align with editor (after sidebar)
        y: app.terminalIntegration.bounds.y,
        width: app.windowWidth - app.sidebarWidth, # Same width as editor
        height: app.terminalIntegration.bounds.height
      )
      app.terminalIntegration.resize(terminalBounds,
          app.statusBarService.bounds)
    return true
  elif rl.isMouseButtonReleased(rl.MouseButton.Left):
    app.state.isResizingSidebar = false
    return true


  if app.state.applicationState != asWelcome:
    discard
  let ctrlPressed = rl.isKeyDown(rl.KeyboardKey.LeftControl) or rl.isKeyDown(
      rl.KeyboardKey.RightControl)
  let cmdPressed = rl.isKeyDown(rl.KeyboardKey.LeftSuper) or rl.isKeyDown(
      rl.KeyboardKey.RightSuper)
  let shiftPressed = rl.isKeyDown(rl.KeyboardKey.LeftShift) or rl.isKeyDown(
      rl.KeyboardKey.RightShift)

  # Handle Ctrl+` (Windows/Linux) or Cmd+` (macOS) to toggle terminal
  if rl.isKeyPressed(rl.KeyboardKey.Grave) and (ctrlPressed or cmdPressed):
    if app.terminalIntegration != nil:
      app.terminalIntegration.toggleVisibility()
    return true

  # Handle Ctrl+P for command palette
  elif rl.isKeyPressed(rl.KeyboardKey.P) and ctrlPressed:
    if app.commandPalette != nil:
      app.commandPalette.show()
    return true

  # Handle Ctrl++ for zoom in
  elif rl.isKeyPressed(rl.KeyboardKey.Equal) and ctrlPressed:
    app.zoomIn()
    return true

  # Handle Ctrl+- for zoom out
  elif rl.isKeyPressed(rl.KeyboardKey.Minus) and ctrlPressed:
    app.zoomOut()
    return true

  # Handle Ctrl+0 for reset zoom
  elif rl.isKeyPressed(rl.KeyboardKey.Zero) and ctrlPressed:
    app.resetZoom()
    return true

  # Handle Ctrl+Shift+F for search in project
  if rl.isKeyPressed(rl.KeyboardKey.F) and ctrlPressed and shiftPressed:
    if app.sidebarWidth == 0:
      app.sidebarWidth = SIDEBAR_WIDTH.float32
      let layout = calculateLayout(app.windowWidth, app.windowHeight,
          app.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
      app.sidebarBounds = layout.sidebar
      app.editorBounds = layout.editor
    app.state.sidebarMode = smSearch
    if app.searchReplace != nil:
      app.searchReplace.show()
      app.searchReplace.setScope(ssProject)
    return true

  # Handle Ctrl+H for search and replace
  if rl.isKeyPressed(rl.KeyboardKey.H) and ctrlPressed:
    if app.sidebarWidth == 0:
      app.sidebarWidth = SIDEBAR_WIDTH.float32
      let layout = calculateLayout(app.windowWidth, app.windowHeight,
          app.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
      app.sidebarBounds = layout.sidebar
      app.editorBounds = layout.editor
    app.state.sidebarMode = smSearch
    if app.searchReplace != nil:
      app.searchReplace.show()
      app.searchReplace.setScope(ssCurrentFile)
    return true

  return handled

proc update(app: EditorApp) =
  if app.terminalIntegration != nil:
    app.terminalIntegration.update()

  if app.gitPanel != nil:
    asyncSpawn app.gitPanel.update()
  
  let deltaTime = rl.getFrameTime().float64
  app.statusBarService.update(deltaTime)

  if app.componentManager != nil:
    app.componentManager.update()

    if app.welcomeScreen != nil:
      app.welcomeScreen.update(deltaTime.float32)

    if app.inputDialog != nil:
      app.inputDialog.update(deltaTime.float32)

    if app.searchReplace != nil:
      app.searchReplace.update(deltaTime.float32)

    if app.notificationManager != nil:
      app.notificationManager.update(deltaTime.float32)

  app.explorerService.update(deltaTime.float32)

  if app.textEditor != nil:
    app.textEditor.update(deltaTime.float32)

  # Update status bar elements with current file information
  if app.statusBarService != nil:
    # Update file type
    var fileType = "Text"
    if app.currentFile.len > 0:
      let ext = app.currentFile.splitFile().ext.toLower()
      case ext
      of ".nim":
        fileType = "Nim"
      of ".ts", ".tsx":
        fileType = "TypeScript"
      of ".js", ".jsx":
        fileType = "JavaScript"
      of ".py":
        fileType = "Python"
      of ".rs":
        fileType = "Rust"
      of ".go":
        fileType = "Go"
      of ".cpp", ".cc", ".cxx":
        fileType = "C++"
      of ".c":
        fileType = "C"
      of ".md":
        fileType = "Markdown"
      else:
        fileType = "Text"
    
    discard app.statusBarService.addFileType(fileType, priority = 10)
    
    # Update Git branch information if Git panel is available
    if app.gitPanel != nil:
      try:
        let gitClient = app.gitPanel.getGitClient()
        if gitClient != nil:
            let branchResult = waitFor gitClient.getCurrentBranch(app.currentDir)
            let statusResult = waitFor gitClient.getStatus(app.currentDir)
            
            var currentBranch = ""
            var isDirty = false
            
            if branchResult.isOk:
              currentBranch = branchResult.get()
            
            if statusResult.isOk:
              let changes = statusResult.get()
              isDirty = changes.len > 0
            
            discard app.statusBarService.addGitBranch(currentBranch, isDirty = isDirty, priority = 100)
      except CatchableError:
        # If Git operations fail, show empty branch
        discard app.statusBarService.addGitBranch("", isDirty = false, priority = 100)

  if app.notificationService != nil:
    app.notificationService.update()

  if app.state.sidebarMode == smGit and app.gitPanel != nil:
    asyncSpawn app.gitPanel.update()

  if app.languageService != nil:
    app.languageService.pollLSPResponses()

proc renderWelcomeScreen(app: EditorApp) =
  if app.state.applicationState == asWelcome:
    if app.welcomeScreen != nil and app.welcomeScreen.isVisible:
      app.welcomeScreen.render()

    if app.componentManager != nil:
      app.componentManager.renderAllVisibleComponents()

proc renderSimplified(app: EditorApp) =
  app.renderer.beginFrame(app.themeManager.getUIColor(uiBackground))
  defer:
    app.renderer.endFrame()

  case app.state.applicationState:
  of asWelcome:
    renderWelcomeScreen(app)
  of asEditor, asLoading:
    app.renderer.drawThemedRectangle(
      rl.Rectangle(x: 0, y: 0, width: app.windowWidth,
          height: TITLEBAR_HEIGHT.float32),
      uiTitlebar
    )
    var titleText = "Drift Editor"
    if app.currentFile.len > 0:
      titleText = extractFilename(app.currentFile) & " - " & titleText
    app.renderer.drawThemedText(
      app.font, titleText, rl.Vector2(x: 10, y: 8), 16.0, uiText
    )

    if app.sidebarWidth > 0:
      case app.state.sidebarMode:
        of smExplorer:
          app.explorerService.setBounds(app.sidebarBounds)
        of smSearch:
          let searchBounds = rl.Rectangle(
            x: app.sidebarBounds.x,
            y: app.sidebarBounds.y,
            width: app.sidebarBounds.width,
            height: app.sidebarBounds.height
          )
          if app.searchReplace != nil:
            app.searchReplace.bounds = searchBounds
            app.searchReplace.updateLayout()
            app.searchReplace.render()
        of smGit:
          app.gitPanel.setBounds(app.sidebarBounds)
          app.gitPanel.render()
        else:
          discard

      # Draw resize handle
      let resizeZoneWidth = 4.0
      let handleRect = rl.Rectangle(
        x: app.sidebarWidth - resizeZoneWidth / 2,
        y: TITLEBAR_HEIGHT.float32,
        width: resizeZoneWidth,
        height: app.windowHeight - TITLEBAR_HEIGHT.float32 -
        STATUSBAR_HEIGHT.float32,
      )

      # Draw subtle resize indicator
      let mousePos = rl.getMousePosition()
      let inResizeZone =
        mousePos.x >= app.sidebarWidth - resizeZoneWidth and
        mousePos.x <= app.sidebarWidth + resizeZoneWidth and
        mousePos.y >= TITLEBAR_HEIGHT.float32

      if inResizeZone or app.state.isResizingSidebar:
        app.renderer.drawRectangle(
          handleRect,
          rl.Color(r: 100, g: 100, b: 100, a: 128)
        )

    # File tabs area
    if app.fileTabBar != nil and not app.fileTabBar.isEmpty():
        app.fileTabBar.render(app.font)

    # Editor area with line numbers
    app.renderer.drawThemedRectangle(app.editorBounds, uiBackground)

    # Line number gutter
    let lineNumberWidth = 60.0
    app.renderer.drawThemedRectangle(
      rl.Rectangle(x: app.editorBounds.x, y: app.editorBounds.y,
          width: lineNumberWidth, height: app.editorBounds.height),
      uiSidebar
    )

    # Render the TextEditor component in the editor area
    if app.textEditor != nil:
      app.textEditor.bounds = app.editorBounds
      let renderContext = renderer.RenderContext(
        bounds: app.editorBounds,
        clipRect: none(rl.Rectangle),
        transform: rl.Matrix(),
        tint: rl.WHITE,
        alpha: 1.0,
      )
      app.textEditor.render(
        renderContext, app.editorBounds.x, app.editorBounds.y,
        app.editorBounds.width, app.editorBounds.height
      )

    # Render the terminal panel if visible (before overlays to ensure proper layering)
    if app.terminalIntegration != nil and
        app.terminalIntegration.terminalPanel != nil and
        app.terminalIntegration.terminalPanel.isVisible:
      render(app.terminalIntegration.terminalPanel)

    # Render all ComponentManager components (including context menus)
    if app.componentManager != nil:
      echo "DEBUG: Rendering ComponentManager components"
      app.componentManager.renderAllVisibleComponents()
    else:
      echo "ERROR: ComponentManager is nil in render loop"

    # Enhanced Status Bar with service-based architecture
    let statusY = app.windowHeight - STATUSBAR_HEIGHT.float32
    let statusBounds = rl.Rectangle(
      x: 0, y: statusY, width: app.windowWidth, height: STATUSBAR_HEIGHT.float32
    )
    app.statusBarService.render(statusBounds)

  # Command palette overlay (rendered last to appear on top)
  if app.commandPalette != nil:
    app.commandPalette.render()

  # Render Input Dialog
  if app.inputDialog != nil:
    app.inputDialog.render()

  # Render notifications (rendered last to appear on top)
  if app.notificationService != nil:
    app.notificationService.render()
  else:
    discard # Notification service not available

proc handleWindowResize(app: EditorApp) =
  ## Handle window resize events and update all dependent components
  let newWidth = rl.getScreenWidth().float32
  let newHeight = rl.getScreenHeight().float32

  # Only process if window size actually changed
  if newWidth != app.windowWidth or newHeight != app.windowHeight:
    echo "Window resized from ", app.windowWidth, "x", app.windowHeight, " to ",
        newWidth, "x", newHeight

    # Update app dimensions
    app.windowWidth = newWidth
    app.windowHeight = newHeight

    # Recalculate layout with current terminal height
    let terminalHeight = if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0
    let layout = calculateLayout(app.windowWidth, app.windowHeight,
        app.sidebarWidth, terminalHeight)
    app.sidebarBounds = layout.sidebar
    app.editorBounds = layout.editor
    app.fileTabsBounds = layout.fileTabs

    # Update welcome screen bounds if it exists
    if app.welcomeScreen != nil:
      let welcomeBounds = rl.Rectangle(x: 0, y: 0, width: app.windowWidth,
          height: app.windowHeight)
      app.welcomeScreen.bounds = welcomeBounds

    # Update notification manager bounds if it exists
    if app.notificationManager != nil:
      let notificationBounds = rl.Rectangle(x: 0, y: 0, width: app.windowWidth,
          height: app.windowHeight)
      app.notificationManager.containerBounds = notificationBounds

    # Update text editor bounds if it exists
    if app.textEditor != nil:
      app.textEditor.bounds = app.editorBounds

    # Update explorer bounds if it's visible
    if app.explorerService != nil and app.state.sidebarMode == smExplorer and
        app.sidebarWidth > 0:
      app.explorerService.bounds = app.sidebarBounds

    # Update terminal integration bounds
    if app.terminalIntegration != nil:
      let maxTerminalHeight = app.windowHeight * 0.6
      let terminalBounds = rl.Rectangle(
        x: app.sidebarWidth,
        y: app.windowHeight - STATUSBAR_HEIGHT.float32 - maxTerminalHeight,
        width: app.windowWidth - app.sidebarWidth,
        height: maxTerminalHeight
      )
      app.terminalIntegration.bounds = terminalBounds

    # Status bar service handles resize internally

    # Update title bar buttons bounds
    if app.titleBarButtons != nil:
      let titleBarBounds = rl.Rectangle(x: 0, y: 0, width: 160,
          height: TITLEBAR_HEIGHT)
      app.titleBarButtons.bounds = titleBarBounds

    # Update file tab bar bounds
    if app.fileTabBar != nil:
      app.fileTabBar.bounds = app.fileTabsBounds

    # Update search and replace panel bounds if visible
    if app.searchReplace != nil and app.state.sidebarMode == smSearch and
        app.sidebarWidth > 0:
      app.searchReplace.bounds = app.sidebarBounds

    # Update git panel bounds if visible
    if app.gitPanel != nil and app.state.sidebarMode == smGit and
        app.sidebarWidth > 0:
      app.gitPanel.bounds = app.sidebarBounds

    # Mark components as dirty for re-rendering
    if app.componentManager != nil:
      # Mark all registered components as dirty since layout changed
      let componentIds = app.componentManager.getRegisteredComponents()
      for componentId in componentIds:
        app.componentManager.markComponentDirty(componentId)

    # Update renderer viewport to new window size
    if app.renderer != nil:
      app.renderer.setViewport(rl.Rectangle(x: 0, y: 0, width: app.windowWidth,
          height: app.windowHeight))

proc runMainLoop() =
  echo "Starting main loop..."

  while app.state.isRunning and not rl.windowShouldClose():
    # Check for window resize
    if rl.isWindowResized():
      handleWindowResize(app)

    discard handleInput(app)



    update(app)
    updateGlobalCursor() # Update cursor state after all input handling
    renderSimplified(app)

proc cleanup() =
  if app != nil:
    if app.componentManager != nil:
      app.componentManager.cleanup()

    if app.welcomeScreen != nil:
      app.welcomeScreen.cleanup()

    if app.inputDialog != nil:
      app.inputDialog.cleanup()

    if app.searchReplace != nil:
      app.searchReplace.cleanup()

    if app.notificationManager != nil:
      app.notificationManager.cleanup()

    if app.statusBarService != nil:
      app.statusBarService.cleanup()
    if app.renderer != nil:
      app.renderer.cleanup()

  cleanupIconCache()

  if rl.isWindowReady():
    rl.closeWindow()

proc createNewEmptyFile() =
  ## Create a new empty file
  # Use EditorService to create a new file
  let newResult = app.editorService.newFile()
  if newResult.isErr:
    echo "Failed to create new file: ", newResult.error.msg
    return
  
  app.currentFile = ""
  app.cursor = CursorPos(line: 0, col: 0)
  app.isModified = false
  app.state.applicationState = asEditor
  
  if app.textEditor != nil:
    app.textEditor.setDocument(app.editorService.document)

proc main() =
  let initResult = initializeApp()
  if initResult.isErr:
    echo "Initialization failed: ", initResult.error.getUserMessage()
    return

  let clipboardService = newClipboardService()
  app.textEditor =
    newTextEditor(app.uiService, app.componentManager, app.editorService,
        app.languageService, clipboardService, some(app.terminalIntegration))
  app.textEditor.bounds = app.editorBounds
  app.textEditor.font = app.font.addr

  if app.componentManager != nil:
    let registerResult = app.componentManager.registerComponent(
      app.textEditor.id,
      app.textEditor,
      proc(event: UnifiedInputEvent): bool =
        return app.textEditor.handleInput(event)
      ,
      proc(bounds: rl.Rectangle) =
        if app.state.applicationState != asWelcome:
          app.textEditor.bounds = bounds
    )

    if registerResult.isErr:
      echo "Warning: Failed to register text editor with ComponentManager: ",
          registerResult.error.msg

  # Register event handler for show_search and show_replace events
  app.uiService.registerEventHandler(app.textEditor.id, proc(event: UIEvent) =
    let action = event.data.getOrDefault("action", "")
    if action == "show_search":
      # Show the search/replace panel with focus on find input
      if app.searchReplace != nil:
        app.searchReplace.setVisible(true)
        app.searchReplace.focusedControl = ctFindInput
        echo "DEBUG: Activated search panel via show_search event"
    elif action == "show_replace":
      # Show the search/replace panel with focus on replace input
      if app.searchReplace != nil:
        app.searchReplace.setVisible(true)
        app.searchReplace.focusedControl = ctReplaceInput
        echo "DEBUG: Activated replace panel via show_replace event"
  )

  let statusBarHeight = 30.0
  let statusBarBounds = rl.Rectangle(
    x: 0,
    y: app.windowHeight - statusBarHeight,
    width: app.windowWidth,
    height: statusBarHeight
  )

  const TERMINAL_HEIGHT_RATIO = 0.6
  let maxTerminalHeight = app.windowHeight * TERMINAL_HEIGHT_RATIO
  let terminalIntegrationBounds = rl.Rectangle(
    x: app.sidebarWidth,
    y: statusBarBounds.y - maxTerminalHeight,
    width: app.windowWidth - app.sidebarWidth,
    height: maxTerminalHeight
  )

  let terminalConfig = TerminalIntegrationConfig(
    defaultTerminalHeight: maxTerminalHeight,
    minTerminalHeight: 100.0,
    maxTerminalHeight: maxTerminalHeight,
    enableKeyboardShortcuts: true,
    autoCreateFirstSession: false,
    defaultShell: getDefaultShell(),
    fontSize: 14.0
  )

  app.terminalIntegration = newTerminalIntegration(
    app.uiService, app.renderer, app.font.addr,
    terminalIntegrationBounds, statusBarBounds, app.componentManager, terminalConfig
  )

  if not app.terminalIntegration.initialize():
    echo "Failed to initialize terminal integration"
  else:
    app.terminalIntegration.setOnVisibilityChanged(proc(visible: bool) =
      try:
        let layout = calculateLayout(app.windowWidth, app.windowHeight,
            app.sidebarWidth, if app.terminalIntegration != nil: app.terminalIntegration.getEffectiveHeight() else: 0.0)
        app.editorBounds = layout.editor
        if app.textEditor != nil:
          app.textEditor.bounds = app.editorBounds
      except Exception as e:
        echo "Error updating layout after terminal visibility change: ", e.msg
    )

    app.terminalIntegration.setOnSessionChanged(proc(sessionId: int) =
      discard
    )

    app.terminalIntegration.setOnTerminalOutput(proc(output: string) =
      discard
    )

  app.fileTabBar = newFileTabBar(
    "main_file_tabs",
    app.componentManager,
    app.editorService,
    tabHeight = FILETAB_HEIGHT.float32
  )
  app.fileTabBar.bounds = app.fileTabsBounds
  app.fileTabBar.updateBounds(app.fileTabsBounds)

  # File tab bar registration
  let fileTabRegisterResult = app.componentManager.registerComponent(
    app.fileTabBar.id,
    app.fileTabBar,
    proc(event: UnifiedInputEvent): bool =
      # Only handle input if we have tabs, are in editor mode, and event is within our bounds
      if app.fileTabBar.tabs.len == 0 or app.state.applicationState != asEditor:
        return false

      case event.kind:
      of uiekMouse:
        let handled = app.fileTabBar.handleInput(event)
        if handled:
          echo "DEBUG: FileTabBar handled event successfully"
        else:
          echo "DEBUG: FileTabBar did not handle event"
        return handled
      of uiekKeyboard:
        # Only handle keyboard events for tab navigation when file tab bar is focused
        return app.fileTabBar.handleInput(event)
      else:
        return false,
    proc(bounds: rl.Rectangle) =
      # Only render file tabs in editor mode
      if app.state.applicationState == asEditor and app.fileTabBar.tabs.len > 0:
        echo "DEBUG: Rendering FileTabBar with bounds: ", bounds, ", tabs.len: ", app.fileTabBar.tabs.len
        app.fileTabBar.bounds = bounds
        app.fileTabBar.render(app.font)
      else:
        echo "DEBUG: Not rendering FileTabBar - state: ", app.state.applicationState, ", tabs.len: ", app.fileTabBar.tabs.len
  )

  if fileTabRegisterResult.isErr:
    echo "Warning: Failed to register FileTabBar with ComponentManager: ",
        fileTabRegisterResult.error.msg
  else:
    echo "DEBUG: FileTabBar registered successfully with ComponentManager"

  # Register event handler for document_saved events
  app.uiService.registerEventHandler(app.fileTabBar.id, proc(event: UIEvent) =
    if event.data.getOrDefault("action", "") == "document_saved":
      # Find the current file and update its modified state
      if app.editorService.currentFile.isSome:
        let filePath = app.editorService.currentFile.get()
        app.fileTabBar.updateTabModifiedState(filePath, false)
        echo "DEBUG: Updated tab modified state for saved file: ", filePath
  )

  app.fileTabBar.onTabActivated = proc(tabBar: FileTabBar, tabIndex: int) =
    if tabIndex < 0 or tabIndex >= tabBar.tabs.len:
      return

    let tab = tabBar.tabs[tabIndex]
    let filePath = tab.filePath

    # Only switch if it's a different file than currently open
    if app.editorService.currentFile.isNone or app.editorService.currentFile.get() != filePath:
      try:
        # Use EditorService to open the file
        let openResult = app.editorService.openFile(filePath)
        if openResult.isErr:
          echo "Failed to open file in EditorService: ", openResult.error.msg
          return

        # Update app-level state for compatibility
        app.currentFile = filePath
        app.cursor = CursorPos(line: 0, col: 0)
        app.isModified = false

        # Update text editor with the new document from EditorService
        if app.textEditor != nil and app.editorService.document != nil:
          app.textEditor.setDocumentWithPath(app.editorService.document, filePath)

        # Update language service
        if app.languageService != nil:
          let content = app.editorService.document.getFullText()
          discard app.languageService.openDocument(filePath, content)

        echo "Switched to tab: ", filePath
      except Exception as e:
        echo "Failed to switch to tab: ", filePath, " - Error: ", e.msg

  app.fileTabBar.onTabClosed = proc(tabBar: FileTabBar, tabIndex: int) =
    echo "DEBUG: Tab closed at index: ", tabIndex, ", remaining tabs: ", tabBar.tabs.len
    
    # If there are still tabs remaining, switch to the active tab
    if tabBar.tabs.len > 0:
      let activeIndex = tabBar.activeTabIndex
      echo "DEBUG: New active tab index: ", activeIndex
      if activeIndex >= 0 and activeIndex < tabBar.tabs.len:
        let activeTab = tabBar.tabs[activeIndex]
        let filePath = activeTab.filePath
        
        try:
          # Use EditorService to open the active tab's file
          let openResult = app.editorService.openFile(filePath)
          if openResult.isErr:
            echo "Failed to open active tab file in EditorService: ", openResult.error.msg
            return

          # Update app-level state for compatibility
          app.currentFile = filePath
          app.cursor = CursorPos(line: 0, col: 0)
          app.isModified = false

          # Update text editor with the document from EditorService
          if app.textEditor != nil and app.editorService.document != nil:
            app.textEditor.setDocumentWithPath(app.editorService.document, filePath)

          # Update language service
          if app.languageService != nil:
            let content = app.editorService.document.getFullText()
            discard app.languageService.openDocument(filePath, content)

          echo "Switched to active tab after close: ", filePath
        except Exception as e:
          echo "Failed to switch to active tab after close: ", filePath, " - Error: ", e.msg
    else:
      # No tabs remaining, create a new empty document
      echo "DEBUG: No tabs remaining, creating new empty document"
      try:
        let newFileResult = app.editorService.newFile()
        if newFileResult.isErr:
          echo "Failed to create new file in EditorService: ", newFileResult.error.msg
          return

        # Update app-level state
        app.currentFile = ""
        app.cursor = CursorPos(line: 0, col: 0)
        app.isModified = false

        # Update text editor with the new document from EditorService
        if app.textEditor != nil and app.editorService.document != nil:
          app.textEditor.setDocument(app.editorService.document)

        echo "Created new empty document after closing last tab"
      except Exception as e:
        echo "Failed to create new empty document: ", e.msg

  # Give the text editor focus by default
  app.textEditor.requestFocus()

  if app.editorService != nil and app.fileTabBar != nil:
    app.editorService.onDocumentChanged = proc(service: EditorService) =
      if service.currentFile.isSome:
        let filePath = service.currentFile.get()
        if app.fileTabBar.hasTab(filePath):
          app.fileTabBar.updateTabModifiedState(filePath, service.isModified)

  updateComponentVisibility(app)

  # Explorer registration is handled in registerExplorerService - ensure it's called
  if app.state.applicationState == asEditor and app.explorerService != nil:
    app.explorerService.bounds = app.sidebarBounds
    registerExplorerService(app)
    app.explorerService.setVisible(app.state.sidebarMode == smExplorer and
        app.sidebarWidth > 0)

  runMainLoop()
  cleanup()

when isMainModule:
  main()
