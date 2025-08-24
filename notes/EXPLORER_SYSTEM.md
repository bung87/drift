# Drift Editor - File Explorer System

## 🗂️ File Explorer Overview

The Drift editor features a sophisticated file explorer system that has been successfully refactored from a monolithic structure to a modular, clean architecture design.

## 🏗️ Architecture Comparison

### Original Explorer (`side_explorer.nim`)
```
┌─────────────────────────────────────────────────────────────┐
│                    side_explorer.nim                        │
│                     (~1600 lines)                          │
│                                                             │
│  • Types, logic, rendering, events all mixed together      │
│  • Hard to modify without affecting other parts            │
│  • Difficult to test individual components                 │
│  • Tight coupling between UI and business logic            │
└─────────────────────────────────────────────────────────────┘
```

### Modular Explorer
```
┌─────────────────────────────────────────────────────────────┐
│                side_explorer_raylib.nim                     │
│                   (Integration Layer)                       │
├─────────────────────────────────────────────────────────────┤
│                   explorer/explorer.nim                     │
│                   (Core Logic & State)                      │
├─────────────────────────────────────────────────────────────┤
│                   explorer/rendering.nim                    │
│                   (UI Components & Drawing)                 │
├─────────────────────────────────────────────────────────────┤
│                explorer/file_operations.nim                 │
│                (File System Operations)                     │
├─────────────────────────────────────────────────────────────┤
│                    explorer/types.nim                       │
│                 (Data Types & Structures)                   │
└─────────────────────────────────────────────────────────────┘
```

## ✅ Feature Comparison

| Feature | Original | Modular | Notes |
|---------|----------|---------|-------|
| **Basic Navigation** | ✅ | ✅ | Both support arrow key navigation |
| **File/Folder Opening** | ✅ | ✅ | Both support Enter/double-click |
| **Directory Expansion** | ✅ | ✅ | Both support folder tree expansion |
| **File Icons** | ✅ | ✅ | Modular has more file type icons |
| **Sorting** | ✅ | ✅ | Modular has more sorting options |
| **Context Menu** | ❌ | ✅ | Only in modular version |
| **Drag-to-Resize** | ❌ | ✅ | Only in modular version |
| **Themes** | ❌ | ✅ | Only in modular version |
| **File Operations** | ❌ | ✅ | Create/delete/rename in modular |
| **Hidden Files Toggle** | ❌ | ✅ | Only in modular version |
| **Virtual Scrolling** | ❌ | ✅ | Performance feature in modular |
| **File Filtering** | ❌ | ✅ | Advanced filtering in modular |
| **Event System** | ❌ | ✅ | Structured events in modular |
| **File Watching** | ❌ | ✅ | Auto-refresh in modular |
| **Tooltips** | ❌ | ✅ | File info tooltips in modular |
| **Keyboard Shortcuts** | ✅ | ✅ | Both support, modular has more |
| **Multiple Selection** | ❌ | 🔄 | Planned for modular |
| **Undo/Redo** | ❌ | 🔄 | Planned for modular |

Legend: ✅ Available, ❌ Not available, 🔄 Planned/In development

## 🎯 Successfully Implemented Features

### Enhanced File Explorer System
- **Sophisticated file tree view** replacing basic sidebar
- **Professional file and folder icons** with distinct visual representation
- **Mouse click interaction** to open files directly from explorer
- **Keyboard navigation** with Ctrl+Arrow keys for efficient file selection
- **Scrollable content** with proportional visual scrollbar for large directories
- **Selection highlighting** with theme-integrated selection colors
- **Tree structure visualization** with proper indentation and hierarchy lines
- **Refresh functionality** with F5 hotkey and command palette integration
- **Performance optimized** for directories with 50+ files
- **File type detection** with automatic syntax highlighting on open
- **Directory header** showing current project folder name
- **Professional styling** fully integrated with dark/light theme system
- **Sidebar toggle integration** preserving explorer state during hide/show
- **Error handling** for file access permissions and corrupted files
- **Visual feedback** with console logging for all file operations

### File Management
- **File explorer sidebar** with directory listing
- **Click-to-open files** from sidebar
- **CLI argument support**:
  ```bash
  ./main file.nim        # Open specific file
  ./main /path/to/dir    # Open directory as project
  ./main                 # Show welcome screen
  ```
- **Smart README detection** (README.md, README.txt, etc.)
- **File/directory visual distinction** in explorer
- **Save operations** with Ctrl+S

## 🔧 Code Organization

### Original Explorer
```nim
# All in one file (~1600 lines)
type File* = object
  # File representation
  
type SideExplorer* = object  
  # Main explorer state
  
proc nameUpCmp*(...) = ...           # Sorting functions
proc folderUpCmp*(...) = ...
proc getIcon(...) = ...              # UI functions
proc newFiles(...) = ...             # File operations
proc updateDir*(...) = ...           # State management
proc onKeydown*(...) = ...           # Input handling
component Item {...}                 # UI components
component Title {...}
component SideExplorer {...}
```

### Modular Explorer
```nim
# types.nim (~180 lines)
type FileInfo* = object
type ExplorerFile* = object
type ExplorerState* = object
type ExplorerConfig* = object
type ExplorerTheme* = object
type ExplorerEvent* = object

# file_operations.nim (~400 lines)
proc scanDirectory*(...) = ...
proc sortFiles*(...) = ...
proc createFile*(...) = ...
proc deleteFile*(...) = ...
proc renameFile*(...) = ...

# rendering.nim (~500 lines)
proc drawIcon*(...) = ...
proc drawFileEntry*(...) = ...
proc drawScrollBar*(...) = ...
proc drawContextMenu*(...) = ...

# explorer.nim (~500 lines)
proc newExplorer*(...) = ...
proc update*(...) = ...
proc handleKeyboard*(...) = ...
proc handleMouse*(...) = ...

# side_explorer_raylib.nim (~300 lines)
proc newSideExplorerRaylib*(...) = ...
proc updateSideExplorerRaylib*(...) = ...
proc renderSideExplorerRaylib*(...) = ...
```

## 🔄 API Comparison

### Original Explorer Usage
```nim
# Create explorer
var explorer = SideExplorer(
  current_dir: getCurrentDir(),
  display: true,
  # ... other fields
)

# Update directory
updateDir(explorer, path)

# Handle input
onKeydown(explorer, keyEvent, path, onFileOpenCallback)

# Render (within component system)
SideExplorer explorer(bounds...):
  dir = explorer.dir
  onFileOpen = callback
```

### Modular Explorer Usage
```nim
# Create explorer
var explorer = newSideExplorerRaylib(
  startDir = getCurrentDir(),
  x = 0.0, y = 0.0,
  width = 300.0, height = 600.0
)

# Initialize
initSideExplorerRaylib(explorer, font, fontSize)

# Update and render
updateSideExplorerRaylib(explorer, deltaTime)
renderSideExplorerRaylib(explorer)

# Handle events
let events = getEventsSideExplorerRaylib(explorer)
for event in events:
  case event.kind:
  of eeFileOpened: openFile(event.filePath)
  # ... handle other events
```

## ⚡ Performance Comparison

### Original Explorer
- **Memory**: Loads entire directory structure into memory
- **Rendering**: Renders all items, even if not visible
- **Updates**: Full re-render on any change
- **Sorting**: Sorts entire file list on every render
- **Scrolling**: Basic scrolling without optimization

### Modular Explorer
- **Memory**: Efficient memory usage with virtual scrolling
- **Rendering**: Only renders visible items
- **Updates**: Incremental updates with smart invalidation
- **Sorting**: Cached sorting results
- **Scrolling**: Virtual scrolling for large directories
- **File Watching**: Automatic refresh only when needed

## 🎨 Customization Comparison

### Original Explorer
```nim
# Limited customization
# Colors hardcoded in component definitions
# No theme system
# Fixed icons and layout
```

### Modular Explorer
```nim
# Extensive customization
type ExplorerConfig* = object
  showHiddenFiles: bool
  sortOrder: SortOrder
  iconSize: float32
  theme: ExplorerTheme
  # ... many more options
```

## 🏆 Architecture Benefits

### ✅ Clean Separation of Concerns
- **UI Layer**: Pure rendering and input handling
- **Domain Layer**: Business logic without external dependencies
- **Infrastructure Layer**: External concerns and technology adapters
- **Services Layer**: Coordination between layers

### ✅ Testability
- **Unit Testing**: Each component can be tested independently
- **Mock Dependencies**: Infrastructure can be mocked for testing
- **Pure Functions**: Business logic is pure and easily testable

### ✅ Maintainability
- **Clear Dependencies**: Dependencies flow in one direction
- **Modular Design**: Changes in one component don't affect others
- **Type Safety**: Strong typing prevents runtime errors

### ✅ Extensibility
- **Plugin Architecture**: Easy to add new features
- **Theme System**: Easy to add new themes and color schemes
- **Component System**: Easy to add new UI elements

## 🔧 Technical Implementation Details

### Component Architecture
```nim
# Example component structure
type ExplorerApp = ref object
  # Core components
  explorer: FileExplorer
  theme: ExplorerTheme
  inputHandler: InputHandler
  
  # State management
  currentDirectory: string
  selectedFile: string
  expandedFolders: HashSet[string]
  
  # UI bounds
  explorerBounds: Rectangle
  scrollBarBounds: Rectangle
```

### Rendering Pipeline
```nim
proc renderExplorer(app: ExplorerApp) =
  # 1. Calculate layout bounds
  calculateExplorerLayout(app)
  
  # 2. Render components in order
  drawExplorerHeader(app)
  drawFileTree(app)
  drawScrollBar(app)
  
  # 3. Handle overlays
  if app.contextMenu.isVisible:
    drawContextMenu(app)
```

### Input Handling
```nim
proc handleExplorerInput(app: ExplorerApp) =
  # 1. Process mouse events
  let mouseEvents = app.inputHandler.getMouseEvents()
  for event in mouseEvents:
    handleExplorerMouseEvent(app, event)
  
  # 2. Process keyboard events
  let keyEvents = app.inputHandler.getKeyEvents()
  for event in keyEvents:
    handleExplorerKeyEvent(app, event)
```

## 🎨 Visual Design System

### File Type Icons
- **Enhanced File Type Detection**: 20+ programming languages with specific colors
- **Category-Based Icons**: Code, Config, Data, Document, Image, Archive, Executable
- **Visual Enhancements**: Type-specific visual indicators (code brackets, gear icons, etc.)
- **Theme Integration**: Full compatibility with existing color theme system
- **Professional Colors**: VS Code-inspired color scheme for file types

### File Type Detection Matrix

| Extension | Color | Category | Special Icon |
|-----------|-------|----------|--------------|
| `.nim` | Yellow | Code | Nim-specific |
| `.py` | Blue | Code | Standard code |
| `.js/.ts` | Yellow | Code | Code brackets |
| `.rs` | Orange | Code | Code brackets |
| `.json/.yml` | Yellow/Pink | Config | Gear indicator |
| `.md/.txt` | Gray | Document | Text lines |
| `.git*` | Orange | Config | Git styling |
| `.png/.jpg` | Purple | Image | Mountain/sun |
| `.zip/.tar` | Orange | Archive | Archive box |

## 🔮 Future Enhancements

### Advanced Explorer Features
- **Multiple Selection**: Select multiple files for batch operations
- **Drag and Drop**: Drag files between directories
- **Context Menus**: Right-click context menus with file operations
- **Search Integration**: In-explorer search functionality
- **Bookmarks**: Save frequently accessed directories
- **Recent Files**: Quick access to recently opened files

### Performance Enhancements
- **Virtual Scrolling**: Only render visible items for large directories
- **Lazy Loading**: Load directory contents on demand
- **Caching**: Cache directory structures for faster navigation
- **Background Scanning**: Scan directories in background threads

### Integration Enhancements
- **LSP Integration**: Show LSP status in file icons
- **Git Integration**: Show git status in file explorer
- **Build System**: Show build status and errors
- **Plugin System**: Allow plugins to extend explorer functionality

## 📚 Related Documentation

- **[UI_COMPONENTS.md](UI_COMPONENTS.md)** - UI component implementation details
- **[ICON_SYSTEM.md](ICON_SYSTEM.md)** - Icon system and SVG rasterization
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Overall architecture overview
- **[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)** - Current implementation status