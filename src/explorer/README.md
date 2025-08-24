# Explorer Module

A service-based file explorer implementation for the Folx editor that provides clean separation of concerns and professional file management capabilities.

## Architecture

The explorer is built on a modular architecture using dependency injection with two main services:

- **UIService**: Manages UI components, layouts, events, and theming
- **FileService**: Handles file operations, project management, and file watching

```
┌─────────────────────────────────────────────────────────────┐
│                      Explorer                               │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   UIService     │    │        FileService              │ │
│  │                 │    │                                 │ │
│  │ • Components    │    │ • File Operations               │ │
│  │ • Layouts       │    │ • Directory Listing             │ │
│  │ • Events        │    │ • Project Management            │ │
│  │ • Theming       │    │ • File Watching                 │ │
│  │ • State Mgmt    │    │ • Git Integration               │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │    Types        │    │       Rendering                 │ │
│  │                 │    │                                 │ │
│  │ • ExplorerState │    │ • Tree Visualization            │ │
│  │ • Events        │    │ • Icons & Theming               │ │
│  │ • Config        │    │ • Layout Management             │ │
│  │ • FileInfo      │    │ • Input Handling                │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

```nim
import explorer/[types, explorer, rendering]
import services/[ui_service, file_service]

# Create services (you need to provide infrastructure implementations)
let uiService = newUIService(theme, renderer, inputHandler)
let fileService = newFileService(fileManager)

# Create explorer
var explorer = newExplorer(uiService, fileService, startDir = getCurrentDir())
explorer.initialize()

# Use in main loop
explorer.update(deltaTime)
explorer.handleKeyboard(keyCode)
explorer.handleMouse(mousePos, deltaTime, bounds)
explorer.render(renderContext, x, y, width, height)

# Process events
for event in explorer.getEvents():
  case event.kind
  of eeFileOpened:
    openFile(event.filePath)
  of eeSelectionChanged:
    updateSelection(event.filePath)
  # ... handle other events
```

## API Reference

### Core Types

#### Explorer
The main explorer object that coordinates between services.

```nim
type Explorer* = object
  uiService*: UIService
  fileService*: FileService
  componentId*: string
  state*: ExplorerState
  config*: ExplorerConfig
  events*: seq[ExplorerEvent]
```

#### ExplorerState
Holds the current state of the explorer.

```nim
type ExplorerState* = object
  currentDirectory*: string
  selectedIndex*: int
  files*: seq[ExplorerFileInfo]
  filteredFiles*: seq[ExplorerFileInfo]
  openDirs*: Table[string, bool]
  scrollY*: float32
  searchQuery*: string
  showHiddenFiles*: bool
  sortBy*: SortBy
  sortOrder*: SortOrder
```

#### ExplorerEvent
Events emitted by the explorer for UI integration.

```nim
type ExplorerEventKind* = enum
  eeSelectionChanged = "selection_changed"
  eeFileOpened = "file_opened"
  eeFileCreated = "file_created"
  eeDirectoryCreated = "directory_created"
  eeFileDeleted = "file_deleted"
  eeFileRenamed = "file_renamed"
  eeFileCopied = "file_copied"
  eeFileMoved = "file_moved"
  eeRenameRequested = "rename_requested"
```

### Constructor

#### `newExplorer(uiService, fileService, startDir) -> Explorer`
Creates a new explorer instance with the provided services.

**Parameters:**
- `uiService: UIService` - UI service for component management
- `fileService: FileService` - File service for file operations
- `startDir: string = ""` - Starting directory (defaults to current directory)

### Core Methods

#### Navigation
```nim
proc setDirectory*(explorer: var Explorer, path: string)
proc navigateUp*(explorer: var Explorer)
proc navigateToSelected*(explorer: var Explorer)
proc navigateBack*(explorer: var Explorer)
proc navigateForward*(explorer: var Explorer)
```

#### Selection
```nim
proc selectFile*(explorer: var Explorer, index: int)
proc selectFileByPath*(explorer: var Explorer, path: string)
proc getSelectedFile*(explorer: Explorer): Option[ExplorerFileInfo]
```

#### File Operations
```nim
proc createNewFile*(explorer: var Explorer, name: string): FileOperationResult
proc createNewDirectory*(explorer: var Explorer, name: string): FileOperationResult
proc deleteSelected*(explorer: var Explorer): FileOperationResult
proc renameSelected*(explorer: var Explorer, newName: string): FileOperationResult
proc copySelected*(explorer: var Explorer, destPath: string): FileOperationResult
proc moveSelected*(explorer: var Explorer, destPath: string): FileOperationResult
```

#### Input Handling
```nim
proc handleKeyboard*(explorer: var Explorer, key: int32)
proc handleMouse*(explorer: var Explorer, mousePos: Vector2, deltaTime: float32, bounds: Rectangle)
proc handleDoubleClick*(explorer: var Explorer, filePath: string, currentTime: float32)
```

#### Rendering and Updates
```nim
proc update*(explorer: var Explorer, deltaTime: float32)
proc render*(explorer: var Explorer, context: RenderContext, x, y, width, height: float32)
```

#### Event Management
```nim
proc getEvents*(explorer: var Explorer): seq[ExplorerEvent]
proc hasEvents*(explorer: Explorer): bool
```

#### Configuration
```nim
proc getConfiguration*(explorer: Explorer): ExplorerConfig
proc setConfiguration*(explorer: var Explorer, config: ExplorerConfig)
proc toggleHidden*(explorer: var Explorer)
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` | Select previous file |
| `↓` | Select next file |
| `←` | Navigate to parent directory |
| `→` / `Enter` | Navigate into selected directory or open file |
| `F5` | Refresh directory |
| `Backspace` | Navigate back in history |
| `Delete` | Delete selected item |
| `F2` | Rename selected item |

## Service Dependencies

### UIService Requirements
The UIService must provide:
- Component creation and management
- Layout system
- Event handling
- Theme management
- State management

### FileService Requirements
The FileService must provide:
- File and directory operations (create, delete, move, copy)
- Directory listing with file information
- Project and workspace management
- File watching capabilities
- Git integration (optional)

## Benefits of Service Architecture

1. **Separation of Concerns**: UI logic is separate from file operations
2. **Testability**: Services can be mocked for unit testing
3. **Reusability**: Services can be used by other components
4. **Maintainability**: Changes to one service don't affect others
5. **Extensibility**: New features can be added through service interfaces
6. **Professional Features**: Built-in support for projects, workspaces, and git

## Migration from Old Explorer

The new explorer replaces the monolithic `side_explorer.nim` with a clean, service-based architecture:

**Before:**
```nim
import side_explorer
var explorer = newSideExplorerRaylib(startDir, x, y, width, height)
```

**After:**
```nim
import explorer/explorer
import services/[ui_service, file_service]

let uiService = newUIService(theme, renderer, inputHandler)
let fileService = newFileService(fileManager)
var explorer = newExplorer(uiService, fileService, startDir)
```

## Configuration

The explorer supports extensive configuration through `ExplorerConfig`:

```nim
type ExplorerConfig* = object
  # Display options
  showHiddenFiles*: bool
  showFileIcons*: bool
  showDirectoryIcons*: bool
  
  # Layout
  itemHeight*: float32
  indentSize*: float32
  
  # Behavior
  autoRefresh*: bool
  refreshInterval*: float32
  
  # Theme
  theme*: ExplorerTheme
```

## Example Implementation

See `explorer_example.nim` for a complete working example that demonstrates:
- Service setup with minimal implementations
- Explorer creation and initialization
- Input handling and event processing
- File operations and navigation
- Rendering integration

This example can serve as a template for integrating the explorer into your application.