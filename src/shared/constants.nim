## Shared constants for the Drift editor
## All application constants in one place

# Window and layout constants
const
  # Default window dimensions
  WINDOW_WIDTH* = 1200
  WINDOW_HEIGHT* = 800

  # UI component heights
  TITLEBAR_HEIGHT* = 32
  STATUSBAR_HEIGHT* = 28
  FILETAB_HEIGHT* = 32

  # Layout dimensions
  SIDEBAR_WIDTH* = 300
  SIDEBAR_MIN_WIDTH* = 200
  SIDEBAR_MAX_WIDTH* = 600
  SPLITTER_WIDTH* = 4
  SCROLLBAR_WIDTH* = 12

  # Editor layout
  EDITOR_PADDING* = 8
  LINE_HEIGHT* = 20
  LINE_NUMBER_WIDTH* = 50

# Text editor constants
const
  # Text formatting
  TAB_SIZE* = 4
  MAX_LINE_LENGTH* = 10000
  MAX_LINES* = 100000

  # Font sizes
  DEFAULT_FONT_SIZE* = 14
  MIN_FONT_SIZE* = 8
  MAX_FONT_SIZE* = 72

  # Cursor and selection
  CURSOR_BLINK_RATE* = 1.0 # seconds
  SELECTION_ALPHA* = 60 # alpha value for selection highlight

# File system constants
const
  # File limits
  MAX_FILE_SIZE* = 10 * 1024 * 1024 # 10MB
  MAX_FILES_IN_PROJECT* = 10000
  MAX_PATH_LENGTH* = 4096

  # File path validation
  INVALID_PATH_CHARS* = {'\0', '<', '>', '|', '"', '*', '?'}

  # Auto-save
  AUTOSAVE_INTERVAL* = 30.0 # seconds
  BACKUP_EXTENSION* = ".drift-backup"

  # File watching
  FILE_WATCH_DEBOUNCE* = 100 # milliseconds

# Language Server Protocol constants
const
  # LSP timeouts
  LSP_INITIALIZATION_TIMEOUT* = 10.0 # seconds
  LSP_REQUEST_TIMEOUT* = 5.0 # seconds
  LSP_SHUTDOWN_TIMEOUT* = 3.0 # seconds

  # LSP capabilities
  LSP_HOVER_ENABLED* = true
  LSP_COMPLETION_ENABLED* = true
  LSP_DIAGNOSTICS_ENABLED* = true

# Notification system constants
const
  # Notification timing
  NOTIFICATION_DEFAULT_DURATION* = 3.0 # seconds
  NOTIFICATION_ERROR_DURATION* = 5.0 # seconds
  NOTIFICATION_FADE_DURATION* = 0.5 # seconds

  # Notification limits
  MAX_NOTIFICATIONS* = 10
  NOTIFICATION_HEIGHT* = 40
  NOTIFICATION_SPACING* = 8

# Git integration constants
const
  # Git status update intervals
  GIT_STATUS_UPDATE_INTERVAL* = 2.0 # seconds
  GIT_BRANCH_UPDATE_INTERVAL* = 10.0 # seconds

  # Git command timeouts
  GIT_COMMAND_TIMEOUT* = 5.0 # seconds

# Syntax highlighting constants
const
  # Token limits
  MAX_TOKENS_PER_LINE* = 1000
  SYNTAX_UPDATE_DEBOUNCE* = 200 # milliseconds

  # TreeSitter constants
  TREESITTER_TIMEOUT* = 100 # milliseconds per parse

# UI interaction constants
const
  # Mouse interaction
  DOUBLE_CLICK_TIME* = 0.5 # seconds
  TRIPLE_CLICK_TIME* = 1.0 # seconds
  MOUSE_WHEEL_SPEED* = 3 # lines per wheel tick
  HOVER_REQUEST_DEBOUNCE_MS* = 25.0 # milliseconds - reduced for responsive hover

  # Keyboard repeat
  KEY_REPEAT_DELAY* = 0.5 # seconds
  KEY_REPEAT_RATE* = 0.05 # seconds between repeats

# Performance constants
const
  # Rendering limits
  MAX_VISIBLE_LINES* = 1000
  RENDER_BATCH_SIZE* = 100

  # Update frequencies
  TARGET_FPS* = 60
  UI_UPDATE_INTERVAL* = 1.0 / 60.0 # seconds

# Search and replace constants
const
  # Search limits
  MAX_SEARCH_RESULTS* = 1000
  SEARCH_CONTEXT_LINES* = 2

  # Regular expressions
  REGEX_TIMEOUT* = 1.0 # seconds

# Configuration constants
const
  # Config file names
  CONFIG_FILENAME* = "drift.toml"
  KEYBINDINGS_FILENAME* = "keybindings.toml"
  THEME_FILENAME* = "theme.toml"

  # Config directories
  CONFIG_DIR_NAME* = ".drift"
  THEMES_DIR_NAME* = "themes"
  PLUGINS_DIR_NAME* = "plugins"

# Resource constants
const
  # Resource directories
  RESOURCES_DIR* = "resources"
  FONTS_DIR* = "fonts"
  ICONS_DIR* = "icons"
  THEMES_DIR* = "themes"

  # Default resource files
  DEFAULT_FONT* = "fonts/FiraCode-Regular.ttf"
  DEFAULT_ICON_FONT* = "fonts/FiraCode-Regular.ttf"

# Application metadata
const
  APP_NAME* = "Drift Editor"
  APP_VERSION* = "0.1.0"
  APP_AUTHOR* = "Drift Team"
  APP_DESCRIPTION* = "A lightweight, fast text editor"

# Debug and logging
const
  # Debug flags
  DEBUG_LSP* = false
  DEBUG_RENDERING* = false
  DEBUG_INPUT* = false
  DEBUG_FILE_OPERATIONS* = false

  # Log levels
  LOG_LEVEL_TRACE* = 0
  LOG_LEVEL_DEBUG* = 1
  LOG_LEVEL_INFO* = 2
  LOG_LEVEL_WARN* = 3
  LOG_LEVEL_ERROR* = 4
