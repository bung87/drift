## Application Types Module
## Core types and enums for the Drift Editor application

import std/times
import raylib as rl
import ../shared/types
import ../services/terminal_integration
import ../services/component_manager
import ../infrastructure/rendering/renderer
import ../infrastructure/rendering/theme
import ../explorer/explorer
import ../services/language_service
import ../services/editor_service
import ../services/notification_service
import ../services/diagnostic_service
import ../services/ui_service
import ../status_bar_service
import ../components/text_editor_types
import ../components/welcome_screen_component
import ../components/file_tabs
import ../components/search_replace
import ../components/git_panel
import ../components/simple_notification
import ../components/input_dialog
import ../components/context_menu
import ../components/command_palette
import ../button_group

# Forward type declarations for services
type
  ExplorerService* = ref object of RootObj

# Application State Enum
type
  ApplicationState* = enum
    asWelcome = "Welcome"
    asEditor = "Editor"
    asLoading = "Loading"

  # Sidebar Modes
  SidebarMode* = enum
    smExplorer = "Explorer"
    smSearch = "Search"
    smGit = "Git"
    smNone = "None"

  # Layout Configuration
  LayoutConfig* = object
    sidebarWidth*: float32
    minSidebarWidth*: float32
    maxSidebarWidth*: float32
    statusBarHeight*: float32
    titleBarHeight*: float32
    fileTabsHeight*: float32
    terminalPanelHeight*: float32
    minTerminalHeight*: float32
    maxTerminalHeight*: float32

  # Component Bounds
  ComponentBounds* = object
    sidebar*: rl.Rectangle
    editor*: rl.Rectangle
    fileTabs*: rl.Rectangle
    statusBar*: rl.Rectangle
    titleBar*: rl.Rectangle
    terminal*: rl.Rectangle

  # Editor Configuration
  EditorConfig* = object
    font*: rl.Font
    fontSize*: int
    lineHeight*: float32
    zoomLevel*: float32
    minZoomLevel*: float32
    maxZoomLevel*: float32
    zoomStep*: float32

  # Application Configuration
  AppConfig* = object
    windowTitle*: string
    windowWidth*: int
    windowHeight*: int
    targetFPS*: int
    layout*: LayoutConfig
    editor*: EditorConfig

  # Git File Status
  GitFileStatus* = object
    path*: string
    status*: string
    staged*: bool

  # Git Integration State
  GitState* = object
    currentBranch*: string
    statusFiles*: seq[GitFileStatus]
    lastUpdate*: float64
    updateInterval*: float64

  # Status Bar Elements
  StatusBarElement* = object
    text*: string
    icon*: string
    tooltip*: string
    clickHandler*: proc()

  # Cursor and Scroll State
  CursorState* = object
    position*: int
    selectionStart*: int
    selectionEnd*: int

  ScrollState* = object
    x*: float32
    y*: float32

  # File Information
  FileInfo* = object
    path*: string
    name*: string
    isDirectory*: bool
    size*: int64
    modified*: Time

  # Application State Container
  AppState* = ref object
    # Core state
    applicationState*: ApplicationState
    isRunning*: bool
    appStartTime*: float64
    
    # Document state
    document*: Document
    currentFile*: string
    isModified*: bool
    
    # File system state
    currentDir*: string
    files*: seq[FileInfo]
    
    # UI state
    cursor*: CursorState
    scrollOffset*: ScrollState
    sidebarMode*: SidebarMode
    isResizingSidebar*: bool
    resizeStartX*: float32
    resizingTerminalPanel*: bool
    delayedNotificationSent*: bool
    
    # Git state
    gitState*: GitState
    
    # Status bar
    statusBarElements*: seq[StatusBarElement]
    
    # Component visibility flags
    explorerVisible*: bool
    searchVisible*: bool
    gitPanelVisible*: bool
    terminalVisible*: bool
    commandPaletteVisible*: bool



  # Main Application Object
  EditorApp* = ref object
    # Configuration
    config*: AppConfig
    
    # Application state
    state*: AppState
    document*: Document
    currentFile*: string
    currentDir*: string
    cursor*: CursorPos
    isModified*: bool
    gitIsAvailable*: bool
    
    # Layout bounds
    bounds*: ComponentBounds
    sidebarBounds*: rl.Rectangle
    editorBounds*: rl.Rectangle
    fileTabsBounds*: rl.Rectangle
    
    # UI Components (simplified for now)
    welcomeScreen*: WelcomeScreenComponent
    textEditor*: TextEditor
    fileTabBar*: FileTabBar
    commandPalette*: CommandPalette
    searchReplace*: SearchReplacePanel
    gitPanel*: GitPanel
    terminalIntegration*: TerminalIntegration  # Fixed type to match actual implementation
    inputDialog*: InputDialog
    contextMenu*: ContextMenu
    notificationManager*: NotificationManager
    
    # Services and managers
    componentManager*: ComponentManager
    explorerService*: Explorer
    renderer*: Renderer
    themeManager*: ThemeManager
    uiService*: UIService
    languageService*: LanguageService
    editorService*: EditorService
    notificationService*: NotificationService
    diagnosticService*: DiagnosticService
    statusBarService*: StatusBarService
    font*: rl.Font
    windowWidth*: float32
    windowHeight*: float32
    sidebarWidth*: float32
    
    # Title bar components
    titleBarButtons*: ButtonGroup

# Default configurations
proc defaultLayoutConfig*(): LayoutConfig =
  LayoutConfig(
    sidebarWidth: 300,
    minSidebarWidth: 200,
    maxSidebarWidth: 600,
    statusBarHeight: 25,
    titleBarHeight: 40,
    fileTabsHeight: 35,
    terminalPanelHeight: 200,
    minTerminalHeight: 100,
    maxTerminalHeight: 600
  )

proc defaultEditorConfig*(): EditorConfig =
  EditorConfig(
    fontSize: 14,
    lineHeight: 1.5,
    zoomLevel: 1.0,
    minZoomLevel: 0.5,
    maxZoomLevel: 3.0,
    zoomStep: 0.1
  )

proc defaultAppConfig*(): AppConfig =
  AppConfig(
    windowTitle: "Drift Editor",
    windowWidth: 1400,
    windowHeight: 800,
    targetFPS: 60,
    layout: defaultLayoutConfig(),
    editor: defaultEditorConfig()
  )

# Export all types
export ApplicationState, SidebarMode, LayoutConfig, ComponentBounds,
       EditorConfig, AppConfig, GitState, GitFileStatus, StatusBarElement, 
       CursorState, ScrollState, FileInfo, AppState, EditorApp, UIComponent,
       defaultLayoutConfig, defaultEditorConfig, defaultAppConfig