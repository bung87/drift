## Explorer types module - Production-ready file explorer type definitions
import std/[tables, times, options]
import raylib as rl
import ../infrastructure/rendering/theme

type
  FileKind* = enum
    fkFile = "file"
    fkDirectory = "directory"
    fkSymlink = "symlink"
    fkSpecial = "special"

  ExplorerFileInfo* = object
    name*: string
    path*: string
    kind*: FileKind
    size*: int64
    modTime*: Time
    permissions*: set[ExplorerFilePermission]
    isHidden*: bool
    extension*: string
    isExpanded*: bool # For directories in tree view
    level*: int # Indentation level in tree

  ExplorerFilePermission* = enum
    fpRead = "read"
    fpWrite = "write"
    fpExecute = "execute"

  ExplorerEventKind* = enum
    eeSelectionChanged = "selection_changed"
    eeFileOpened = "file_opened"
    eeFileCreated = "file_created"
    eeDirectoryCreated = "directory_created"
    eeFileDeleted = "file_deleted"
    eeFileRenamed = "file_renamed"
    eeFileCopied = "file_copied"
    eeFileMoved = "file_moved"
    eeRenameRequested = "rename_requested"

  ExplorerEvent* = object
    kind*: ExplorerEventKind
    filePath*: string
    oldPath*: Option[string] # For rename/move operations
    timestamp*: Time

  FileOperationResult* = object
    success*: bool
    error*: string
    affectedFiles*: seq[string]

  # Use infrastructure theme instead of custom ExplorerTheme
  ExplorerTheme* = Theme

  ExplorerSortOrder* = enum
    soAscending = "ascending"
    soDescending = "descending"

  SortBy* = enum
    sbName = "name"
    sbSize = "size"
    sbModified = "modified"
    sbType = "type"

  ExplorerConfig* = object # Display options
    showHiddenFiles*: bool
    showFileExtensions*: bool
    showFileSizes*: bool
    showModifiedDates*: bool
    showFileIcons*: bool
    showLineNumbers*: bool

    # Sorting options
    sortBy*: SortBy
    sortOrder*: ExplorerSortOrder
    directoriesFirst*: bool

    # View options
    itemHeight*: float32
    iconSize*: float32
    indentSize*: float32

    # Behavior options
    singleClickOpen*: bool
    doubleClickTime*: float32
    autoExpandDirectories*: bool
    followSymlinks*: bool
    confirmDelete*: bool
    confirmOverwrite*: bool

    # Performance options
    maxFilesPerDirectory*: int
    asyncFileLoading*: bool
    cacheFileInfo*: bool
    watchFileChanges*: bool

    # File filtering options
    hideBinaryFiles*: bool
    hideExecutableFiles*: bool

    # Theme
    theme*: Theme

  SortOrder* = enum
    soAscending = "ascending"
    soDescending = "descending"

  ExplorerState* = object # Current state
    currentDirectory*: string
    selectedIndex*: int
    files*: seq[ExplorerFileInfo]
    filteredFiles*: seq[ExplorerFileInfo]

    # Tree view state
    openDirs*: Table[string, bool] # Directory path -> expanded state
    rootCollapsed*: bool # Whether the project root folder is collapsed

    # Scrolling
    scrollY*: float32
    scrollMaxY*: float32

    # Search and filter
    searchQuery*: string
    isVisible*: bool
    showHiddenFiles*: bool
    sortBy*: SortBy
    sortOrder*: SortOrder

    # State management
    refreshing*: bool
    errorMessage*: string
    lastRefreshTime*: Time

    # Navigation history
    history*: seq[string]
    historyIndex*: int

    # UI/interaction status (moved from ExplorerRenderStatus)
    mousePos*: rl.Vector2
    deltaTime*: float32
    frameCount*: int
    isKeyboardFocused*: bool
    
    # Click tracking for debouncing
    lastClickTime*: float64
    lastClickedPath*: string
    
    # Tooltip system
    hoveredItem*: Option[int]  # Index of currently hovered item
    tooltipText*: string       # Text to show in tooltip
    tooltipVisible*: bool      # Whether tooltip should be shown
    tooltipPosition*: rl.Vector2  # Position for tooltip

  # Explorer type is now defined in explorer.nim to avoid circular imports

# Constants for layout
const
  HEADER_HEIGHT* = 32.0
  DIRECTORY_BAR_HEIGHT* = 0.0
  SCROLLBAR_WIDTH* = 16.0
  RESIZE_HANDLE_WIDTH* = 4.0
  MIN_ITEM_HEIGHT* = 16.0
  MAX_ITEM_HEIGHT* = 48.0
  DEFAULT_ITEM_HEIGHT* = 20.0
  DEFAULT_INDENT_SIZE* = 12.0
  DEFAULT_ICON_SIZE* = 12.0
  DEFAULT_DOUBLE_CLICK_TIME* = 500.0 # milliseconds

# Default theme

# Default configuration
proc defaultExplorerConfig*(theme: Theme, zoomLevel: float32 = 1.0): ExplorerConfig =
  ExplorerConfig(
    showHiddenFiles: false,
    showFileExtensions: true,
    showFileSizes: true,
    showModifiedDates: false,
    showFileIcons: true,
    showLineNumbers: false,
    sortBy: sbName,
    sortOrder: soAscending,
    directoriesFirst: true,
    itemHeight: DEFAULT_ITEM_HEIGHT * zoomLevel,
    iconSize: DEFAULT_ICON_SIZE * zoomLevel,
    indentSize: DEFAULT_INDENT_SIZE * zoomLevel,
    singleClickOpen: false,
    doubleClickTime: DEFAULT_DOUBLE_CLICK_TIME,
    autoExpandDirectories: false,
    followSymlinks: false,
    confirmDelete: true,
    confirmOverwrite: true,
    maxFilesPerDirectory: 10000,
    asyncFileLoading: true,
    cacheFileInfo: true,
    watchFileChanges: true,
    hideBinaryFiles: true,
    hideExecutableFiles: true,
    theme: theme,
  )
