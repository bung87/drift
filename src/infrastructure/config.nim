## Configuration management for Drift editor using new architecture
## Provides type-safe configuration loading, saving, and validation

import std/[tables, strutils, os, times, strformat]
import results
import ../shared/[types, constants, errors, utils]

# Configuration sections
type
  EditorConfig* = object
    fontSize*: int
    fontFamily*: string
    tabSize*: int
    insertSpaces*: bool
    wordWrap*: bool
    lineNumbers*: bool
    minimap*: bool
    autoSave*: bool
    autoSaveDelay*: float
    maxFileSize*: int
    encoding*: string
    lineEnding*: string

  UIConfig* = object
    theme*: string
    sidebarWidth*: int
    statusBarVisible*: bool
    menuBarVisible*: bool
    toolBarVisible*: bool
    animations*: bool
    transparency*: float32
    windowWidth*: int
    windowHeight*: int
    fullscreen*: bool

  LSPConfig* = object
    enabled*: bool
    timeout*: float
    completionDelay*: float
    diagnosticsEnabled*: bool
    formattingEnabled*: bool
    servers*: Table[string, LSPServerSettings]

  LSPServerSettings* = object
    command*: string
    args*: seq[string]
    languageIds*: seq[string]
    fileExtensions*: seq[string]
    initializationOptions*: Table[string, string]
    enabled*: bool

  GitConfig* = object
    enabled*: bool
    autoFetch*: bool
    fetchInterval*: float
    showBranch*: bool
    showChanges*: bool
    commitTemplate*: string
    defaultRemote*: string

  FileConfig* = object
    autoDetectEncoding*: bool
    preserveLineEndings*: bool
    trimTrailingWhitespace*: bool
    ensureFinalNewline*: bool
    backupEnabled*: bool
    backupDirectory*: string
    recentFiles*: seq[string]
    maxRecentFiles*: int
    excludePatterns*: seq[string]

  SearchConfig* = object
    caseSensitive*: bool
    wholeWord*: bool
    useRegex*: bool
    searchInFiles*: bool
    maxResults*: int
    excludePatterns*: seq[string]

  KeybindingConfig* = object
    bindings*: Table[string, string]
    customBindings*: Table[string, string]

# Main configuration structure
type Config* = object
  version*: string
  editor*: EditorConfig
  ui*: UIConfig
  lsp*: LSPConfig
  git*: GitConfig
  file*: FileConfig
  search*: SearchConfig
  keybindings*: KeybindingConfig
  custom*: Table[string, string] # For custom settings

# Configuration manager
type ConfigManager* = ref object
  config*: Config
  configPath*: string
  watchConfig*: bool
  lastModified*: float
  isLoaded*: bool
  defaultConfig*: Config

# Default configurations
proc getDefaultEditorConfig*(): EditorConfig =
  EditorConfig(
    fontSize: DEFAULT_FONT_SIZE,
    fontFamily: "Fira Code",
    tabSize: TAB_SIZE,
    insertSpaces: true,
    wordWrap: false,
    lineNumbers: true,
    minimap: true,
    autoSave: true,
    autoSaveDelay: AUTOSAVE_INTERVAL,
    maxFileSize: MAX_FILE_SIZE,
    encoding: "UTF-8",
    lineEnding: "LF",
  )

proc getDefaultUIConfig*(): UIConfig =
  UIConfig(
    theme: "Drift Dark",
    sidebarWidth: SIDEBAR_WIDTH,
    statusBarVisible: true,
    menuBarVisible: true,
    toolBarVisible: true,

    animations: true,
    transparency: 1.0,
    windowWidth: WINDOW_WIDTH,
    windowHeight: WINDOW_HEIGHT,
    fullscreen: false,
  )

proc getDefaultLSPConfig*(): LSPConfig =
  var servers = Table[string, LSPServerSettings]()

  # Nim LSP server
  servers["nim"] = LSPServerSettings(
    command: "nimlsp",
    args: @[],
    languageIds: @["nim"],
    fileExtensions: @[".nim", ".nims"],
    initializationOptions: Table[string, string](),
    enabled: true,
  )

  # Python LSP server
  servers["python"] = LSPServerSettings(
    command: "pylsp",
    args: @[],
    languageIds: @["python"],
    fileExtensions: @[".py", ".pyi"],
    initializationOptions: Table[string, string](),
    enabled: false,
  )

  LSPConfig(
    enabled: LSP_HOVER_ENABLED,
    timeout: LSP_REQUEST_TIMEOUT,
    completionDelay: 0.1,
    diagnosticsEnabled: LSP_DIAGNOSTICS_ENABLED,
    formattingEnabled: true,
    servers: servers,
  )

proc getDefaultGitConfig*(): GitConfig =
  GitConfig(
    enabled: true,
    autoFetch: false,
    fetchInterval: 300.0, # 5 minutes
    showBranch: true,
    showChanges: true,
    commitTemplate: "",
    defaultRemote: "origin",
  )

proc getDefaultFileConfig*(): FileConfig =
  FileConfig(
    autoDetectEncoding: true,
    preserveLineEndings: true,
    trimTrailingWhitespace: false,
    ensureFinalNewline: true,
    backupEnabled: true,
    backupDirectory: "",
    recentFiles: @[],
    maxRecentFiles: 10,
    excludePatterns: @["*.tmp", "*.log", ".git/*", "node_modules/*"],
  )

proc getDefaultSearchConfig*(): SearchConfig =
  SearchConfig(
    caseSensitive: false,
    wholeWord: false,
    useRegex: false,
    searchInFiles: true,
    maxResults: MAX_SEARCH_RESULTS,
    excludePatterns: @[".git/*", "node_modules/*", "*.min.js"],
  )

proc getDefaultKeybindingConfig*(): KeybindingConfig =
  var bindings = Table[string, string]()

  # File operations
  bindings["file.new"] = "Ctrl+N"
  bindings["file.open"] = "Ctrl+O"
  bindings["file.save"] = "Ctrl+S"
  bindings["file.saveAs"] = "Ctrl+Shift+S"
  bindings["file.close"] = "Ctrl+W"
  bindings["file.quit"] = "Ctrl+Q"

  # Edit operations
  bindings["edit.undo"] = "Ctrl+Z"
  bindings["edit.redo"] = "Ctrl+Y"
  bindings["edit.cut"] = "Ctrl+X"
  bindings["edit.copy"] = "Ctrl+C"
  bindings["edit.paste"] = "Ctrl+V"
  bindings["edit.selectAll"] = "Ctrl+A"

  # Search operations
  bindings["search.find"] = "Ctrl+F"
  bindings["search.replace"] = "Ctrl+H"
  bindings["search.findNext"] = "F3"
  bindings["search.findPrevious"] = "Shift+F3"

  # View operations
  bindings["view.toggleSidebar"] = "Ctrl+B"
  bindings["view.toggleStatusBar"] = "Ctrl+/"
  bindings["view.zoomIn"] = "Ctrl+="
  bindings["view.zoomOut"] = "Ctrl+-"
  bindings["view.resetZoom"] = "Ctrl+0"

  KeybindingConfig(bindings: bindings, customBindings: Table[string, string]())

proc getDefaultConfig*(): Config =
  Config(
    version: APP_VERSION,
    editor: getDefaultEditorConfig(),
    ui: getDefaultUIConfig(),
    lsp: getDefaultLSPConfig(),
    git: getDefaultGitConfig(),
    file: getDefaultFileConfig(),
    search: getDefaultSearchConfig(),
    keybindings: getDefaultKeybindingConfig(),
    custom: Table[string, string](),
  )

# Configuration manager constructor
proc newConfigManager*(configPath: string = ""): ConfigManager =
  let finalConfigPath =
    if configPath.len > 0:
      configPath
    else:
      getConfigDir() / CONFIG_DIR_NAME / CONFIG_FILENAME

  result = ConfigManager(
    config: getDefaultConfig(),
    configPath: finalConfigPath,
    watchConfig: true,
    lastModified: 0.0,
    isLoaded: false,
    defaultConfig: getDefaultConfig(),
  )

# Configuration file operations
proc getConfigDir*(): string =
  ## Get user configuration directory
  when defined(windows):
    getEnv("APPDATA", getHomeDir() / "AppData" / "Roaming")
  elif defined(macosx):
    getHomeDir() / "Library" / "Application Support"
  else:
    getEnv("XDG_CONFIG_HOME", getHomeDir() / ".config")

proc ensureConfigDir*(configPath: string): Result[void, ConfigError] =
  ## Ensure configuration directory exists
  try:
    let dir = configPath.parentDir()
    if not dirExists(dir):
      createDir(dir)
    return ok()
  except OSError as e:
    return err(
      newConfigError(
        ERROR_CONFIG_WRITE_FAILED,
        "Failed to create config directory: " & e.msg,
        "configDir",
        manager.configPath.splitFile().dir,
      )
    )

proc toTomlString*(config: Config): string =
  ## Convert config to TOML format (simplified implementation)
  result =
    fmt"""# Drift Editor Configuration
# Version: {config.version}
# Generated: {formatDateTime(getCurrentTimestamp())}

[editor]
fontSize = {config.editor.fontSize}
fontFamily = "{config.editor.fontFamily}"
tabSize = {config.editor.tabSize}
insertSpaces = {config.editor.insertSpaces}
wordWrap = {config.editor.wordWrap}
lineNumbers = {config.editor.lineNumbers}
minimap = {config.editor.minimap}
autoSave = {config.editor.autoSave}
autoSaveDelay = {config.editor.autoSaveDelay}
maxFileSize = {config.editor.maxFileSize}
encoding = "{config.editor.encoding}"
lineEnding = "{config.editor.lineEnding}"

[ui]
theme = "{config.ui.theme}"
sidebarWidth = {config.ui.sidebarWidth}
statusBarVisible = {config.ui.statusBarVisible}
menuBarVisible = {config.ui.menuBarVisible}
toolBarVisible = {config.ui.toolBarVisible}
animations = {config.ui.animations}
transparency = {config.ui.transparency}
windowWidth = {config.ui.windowWidth}
windowHeight = {config.ui.windowHeight}
fullscreen = {config.ui.fullscreen}

[lsp]
enabled = {config.lsp.enabled}
timeout = {config.lsp.timeout}
completionDelay = {config.lsp.completionDelay}
diagnosticsEnabled = {config.lsp.diagnosticsEnabled}
formattingEnabled = {config.lsp.formattingEnabled}

[git]
enabled = {config.git.enabled}
autoFetch = {config.git.autoFetch}
fetchInterval = {config.git.fetchInterval}
showBranch = {config.git.showBranch}
showChanges = {config.git.showChanges}
commitTemplate = "{config.git.commitTemplate}"
defaultRemote = "{config.git.defaultRemote}"

[file]
autoDetectEncoding = {config.file.autoDetectEncoding}
preserveLineEndings = {config.file.preserveLineEndings}
trimTrailingWhitespace = {config.file.trimTrailingWhitespace}
ensureFinalNewline = {config.file.ensureFinalNewline}
backupEnabled = {config.file.backupEnabled}
backupDirectory = "{config.file.backupDirectory}"
maxRecentFiles = {config.file.maxRecentFiles}

[search]
caseSensitive = {config.search.caseSensitive}
wholeWord = {config.search.wholeWord}
useRegex = {config.search.useRegex}
searchInFiles = {config.search.searchInFiles}
maxResults = {config.search.maxResults}
"""

  # Add LSP servers
  for serverId, server in config.lsp.servers:
    result.add(
      fmt"""
[lsp.servers.{serverId}]
command = "{server.command}"
args = [{server.args.mapIt("\"" & it & "\"").join(", ")}]
languageIds = [{server.languageIds.mapIt("\"" & it & "\"").join(", ")}]
fileExtensions = [{server.fileExtensions.mapIt("\"" & it & "\"").join(", ")}]
enabled = {server.enabled}
"""
    )

  # Add keybindings
  result.add("\n[keybindings]\n")
  for action, binding in config.keybindings.bindings:
    result.add(fmt"""{action} = "{binding}"{'\n'}""")

  # Add custom settings
  if config.custom.len > 0:
    result.add("\n[custom]\n")
    for key, value in config.custom:
      result.add(fmt"""{key} = "{value}"{'\n'}""")

proc fromTomlString*(tomlContent: string): Result[Config, ConfigError] =
  ## Parse TOML content to config (simplified implementation)
  # This is a simplified parser - in practice you'd use a proper TOML library
  try:
    var config = getDefaultConfig()

    # Basic parsing logic (would be much more robust in practice)
    let lines = tomlContent.split('\n')
    var currentSection = ""

    for line in lines:
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed.startsWith('#'):
        continue

      if trimmed.startsWith('[') and trimmed.endsWith(']'):
        currentSection = trimmed[1 ..^ 2]
        continue

      if '=' in trimmed:
        let parts = trimmed.split('=', 1)
        if parts.len == 2:
          let key = parts[0].strip()
          var value = parts[1].strip()
          if value.len >= 2 and value[0] == '"' and value[^1] == '"':
            value = value[1 ..^ 2]

          # Apply configuration based on section
          case currentSection
          of "editor":
            case key
    of "fontSize":
      config.editor.fontSize = parseInt(value)
    of "fontFamily":
      config.editor.fontFamily = value
    of "tabSize":
      config.editor.tabSize = parseInt(value)
    of "insertSpaces":
      config.editor.insertSpaces = parseBool(value)
    of "wordWrap":
      config.editor.wordWrap = parseBool(value)
    of "lineNumbers":
      config.editor.lineNumbers = parseBool(value)
    of "autoSave":
      config.editor.autoSave = parseBool(value)
    of "autoSaveDelay":
      config.editor.autoSaveDelay = parseFloat(value)
    else:
      discard
          of "ui":
            case key
            of "theme":
              config.ui.theme = value
            of "sidebarWidth":
              config.ui.sidebarWidth = parseInt(value)
            of "statusBarVisible":
              config.ui.statusBarVisible = parseBool(value)
            of "menuBarVisible":
              config.ui.menuBarVisible = parseBool(value)
            of "toolBarVisible":
              config.ui.toolBarVisible = parseBool(value)
            of "animations":
              config.ui.animations = parseBool(value)
            of "transparency":
              config.ui.transparency = parseFloat(value)
            of "windowWidth":
              config.ui.windowWidth = parseInt(value)
            of "windowHeight":
              config.ui.windowHeight = parseInt(value)
            of "fullscreen":
              config.ui.fullscreen = parseBool(value)
            else:
              discard
          of "lsp":
            case key
            of "enabled":
              config.lsp.enabled = parseBool(value)
            of "timeout":
              config.lsp.timeout = parseFloat(value)
            of "completionDelay":
              config.lsp.completionDelay = parseFloat(value)
            of "diagnosticsEnabled":
              config.lsp.diagnosticsEnabled = parseBool(value)
            of "formattingEnabled":
              config.lsp.formattingEnabled = parseBool(value)
            else:
              discard
          of "git":
            case key
            of "enabled":
              config.git.enabled = parseBool(value)
            of "autoFetch":
              config.git.autoFetch = parseBool(value)
            of "fetchInterval":
              config.git.fetchInterval = parseFloat(value)
            of "showBranch":
              config.git.showBranch = parseBool(value)
            of "showChanges":
              config.git.showChanges = parseBool(value)
            of "commitTemplate":
              config.git.commitTemplate = value
            of "defaultRemote":
              config.git.defaultRemote = value
            else:
              discard
          of "file":
            case key
            of "autoDetectEncoding":
              config.file.autoDetectEncoding = parseBool(value)
            of "preserveLineEndings":
              config.file.preserveLineEndings = parseBool(value)
            of "trimTrailingWhitespace":
              config.file.trimTrailingWhitespace = parseBool(value)
            of "ensureFinalNewline":
              config.file.ensureFinalNewline = parseBool(value)
            of "backupEnabled":
              config.file.backupEnabled = parseBool(value)
            of "backupDirectory":
              config.file.backupDirectory = value
            of "maxRecentFiles":
              config.file.maxRecentFiles = parseInt(value)
            else:
              discard
          of "search":
            case key
            of "caseSensitive":
              config.search.caseSensitive = parseBool(value)
            of "wholeWord":
              config.search.wholeWord = parseBool(value)
            of "useRegex":
              config.search.useRegex = parseBool(value)
            of "searchInFiles":
              config.search.searchInFiles = parseBool(value)
            of "maxResults":
              config.search.maxResults = parseInt(value)
            else:
              discard
          else:
            # Add to custom settings
            config.custom[currentSection & "." & key] = value

    return ok(config)
  except Exception as e:
    return err(
      newConfigError(
        ERROR_CONFIG_INVALID_FORMAT,
        "Failed to parse configuration: " & e.msg,
        "parsing",
      )
    )

proc loadConfig*(manager: ConfigManager): Result[void, ConfigError] =
  ## Load configuration from file
  try:
    if not fileExists(manager.configPath):
      # Create default config file
      let saveResult = saveConfig(manager)
      if saveResult.isErr:
        return err(saveResult.getError())
      manager.config = getDefaultConfig()
      manager.isLoaded = true
      return ok()

    let content = readFile(manager.configPath)
    let configResult = fromTomlString(content)
    if configResult.isErr:
      return err(configResult.getError())

    manager.config = configResult.get()
    manager.lastModified = getFileInfo(manager.configPath).lastWriteTime.toUnixFloat()
    manager.isLoaded = true

    return ok()
  except IOError as e:
    return err(
      newConfigError(
        ERROR_CONFIG_NOT_FOUND,
        "Failed to load config file: " & e.msg,
        "configFile",
        manager.configPath,
      )
    )

proc saveConfig*(manager: ConfigManager): Result[void, ConfigError] =
  ## Save configuration to file
  try:
    let ensureResult = ensureConfigDir(manager.configPath)
    if ensureResult.isErr:
      return err(ensureResult.getError())

    let tomlContent = toTomlString(manager.config)
    writeFile(manager.configPath, tomlContent)

    manager.lastModified = getCurrentTimestamp()
    return ok()
  except IOError as e:
    return err(
      newConfigError(
        ERROR_CONFIG_WRITE_FAILED,
        "Failed to save config file: " & e.msg,
        "configFile",
        manager.configPath,
      )
    )

proc validateConfig*(config: Config): Result[void, ValidationError] =
  ## Validate configuration values
  # Editor validation
  if config.editor.fontSize < MIN_FONT_SIZE or config.editor.fontSize > MAX_FONT_SIZE:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE,
        fmt"Font size {config.editor.fontSize} is out of range",
        "editor.fontSize",
        fmt"{MIN_FONT_SIZE}-{MAX_FONT_SIZE}",
      )
    )

  if config.editor.tabSize < 1 or config.editor.tabSize > 16:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE,
        fmt"Tab size {config.editor.tabSize} is out of range",
        "editor.tabSize",
        "1-16",
      )
    )

  # UI validation
  if config.ui.sidebarWidth < SIDEBAR_MIN_WIDTH or
      config.ui.sidebarWidth > SIDEBAR_MAX_WIDTH:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE,
        fmt"Sidebar width {config.ui.sidebarWidth} is out of range",
        "ui.sidebarWidth",
        fmt"{SIDEBAR_MIN_WIDTH}-{SIDEBAR_MAX_WIDTH}",
      )
    )

  if config.ui.transparency < 0.0 or config.ui.transparency > 1.0:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE,
        fmt"Transparency {config.ui.transparency} is out of range",
        "ui.transparency",
        "0.0-1.0",
      )
    )

  # LSP validation
  if config.lsp.timeout <= 0.0:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE, "LSP timeout must be positive", "lsp.timeout",
        "> 0.0",
      )
    )

  return ok()

proc checkForConfigChanges*(manager: ConfigManager): bool =
  ## Check if config file has been modified externally
  if not manager.watchConfig or not fileExists(manager.configPath):
    return false

  try:
    let currentModified = getFileInfo(manager.configPath).lastWriteTime.toUnixFloat()
    return currentModified > manager.lastModified
  except:
    return false

proc reloadConfig*(manager: ConfigManager): Result[void, ConfigError] =
  ## Reload configuration from file
  manager.loadConfig()

# Configuration access helpers
proc get*[T](manager: ConfigManager, path: string): T =
  ## Get configuration value by dot-separated path
  # This would be implemented with proper path parsing in practice
  default(T)

proc set*[T](
    manager: ConfigManager, path: string, value: T
): Result[void, ConfigError] =
  ## Set configuration value by dot-separated path
  # This would be implemented with proper path parsing in practice
  ok()

proc resetToDefault*(
    manager: ConfigManager, section: string = ""
): Result[void, ConfigError] =
  ## Reset configuration section to defaults
  if section.len == 0:
    manager.config = getDefaultConfig()
  else:
    case section
    of "editor":
      manager.config.editor = getDefaultEditorConfig()
    of "ui":
      manager.config.ui = getDefaultUIConfig()
    of "lsp":
      manager.config.lsp = getDefaultLSPConfig()
    of "git":
      manager.config.git = getDefaultGitConfig()
    of "file":
      manager.config.file = getDefaultFileConfig()
    of "search":
      manager.config.search = getDefaultSearchConfig()
    of "keybindings":
      manager.config.keybindings = getDefaultKeybindingConfig()
    else:
      return err(
        newConfigError(
          ERROR_CONFIG_INVALID_VALUE,
          "Unknown configuration section: " & section,
          "section",
          section,
        )
      )

  return manager.saveConfig()

# Recent files management
proc addRecentFile*(manager: ConfigManager, filePath: string) =
  ## Add file to recent files list
  let normalizedPath = normalizePath(filePath)

  # Remove if already exists
  manager.config.file.recentFiles =
    manager.config.file.recentFiles.filterIt(it != normalizedPath)

  # Add to front
  manager.config.file.recentFiles.insert(normalizedPath, 0)

  # Trim to max size
  if manager.config.file.recentFiles.len > manager.config.file.maxRecentFiles:
    manager.config.file.recentFiles =
      manager.config.file.recentFiles[0 ..< manager.config.file.maxRecentFiles]

proc getRecentFiles*(manager: ConfigManager): seq[string] =
  ## Get recent files list
  manager.config.file.recentFiles

proc clearRecentFiles*(manager: ConfigManager) =
  ## Clear recent files list
  manager.config.file.recentFiles = @[]

# Theme management
proc getAvailableThemes*(manager: ConfigManager): seq[string] =
  ## Get list of available themes
  @["Drift Dark", "Drift Light"] # Would scan theme directory in practice

proc setTheme*(manager: ConfigManager, themeName: string): Result[void, ConfigError] =
  ## Set active theme
  let availableThemes = manager.getAvailableThemes()
  if themeName notin availableThemes:
    return err(
      newConfigError(
        ERROR_CONFIG_INVALID_VALUE, "Unknown theme: " & themeName, "ui.theme", themeName
      )
    )

  manager.config.ui.theme = themeName
  return ok()

# Environment variable overrides
proc applyEnvironmentOverrides*(manager: ConfigManager) =
  ## Apply configuration overrides from environment variables
  let envPrefix = "DRIFT_"

  # Check for common overrides
  let debugLSP = getEnv(envPrefix & "DEBUG_LSP")
  if debugLSP.len > 0:
    try:
      if debugLSP.parseBool():
        manager.config.custom["debug.lsp"] = "true"
    except:
      discard

  let configFile = getEnv(envPrefix & "CONFIG")
  if configFile.len > 0 and fileExists(configFile):
    manager.configPath = configFile

# Export current configuration
proc exportConfig*(
    manager: ConfigManager, filePath: string
): Result[void, ConfigError] =
  ## Export current configuration to file
  try:
    let content = toTomlString(manager.config)
    writeFile(filePath, content)
    return ok()
  except IOError as e:
    return err(
      newConfigError(
        ERROR_CONFIG_WRITE_FAILED,
        "Failed to export config: " & e.msg,
        "export",
        filePath,
      )
    )

# Import configuration
proc importConfig*(
    manager: ConfigManager, filePath: string
): Result[void, ConfigError] =
  ## Import configuration from file
  try:
    let content = readFile(filePath)
    let configResult = fromTomlString(content)
    if configResult.isErr:
      return err(configResult.getError())

    let config = configResult.get()
    let validationResult = validateConfig(config)
    if validationResult.isErr:
      return err(
        newConfigError(
          ERROR_CONFIG_INVALID_VALUE,
          "Invalid imported configuration: " & validationResult.getError().msg,
          "import",
        )
      )

    manager.config = config
    return manager.saveConfig()
  except IOError as e:
    return err(
      newConfigError(
        ERROR_CONFIG_NOT_FOUND, "Failed to import config: " & e.msg, "import", filePath
      )
    )
