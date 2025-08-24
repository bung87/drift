# Drift Editor - UI Components

## 🎨 UI Component Overview

The Drift editor features a sophisticated UI system with professional components that have been successfully ported from the original monolithic structure to the new clean architecture.

## ✅ Successfully Ported Components

### Core Text Editor
- **Basic text editing** with insert/delete operations
- **Cursor movement** (arrow keys, home/end)
- **Line-based editing** with proper cursor positioning
- **Text rendering** with proper font handling
- **Scroll management** to keep cursor visible

### Syntax Highlighting
- **Full syntax highlighting system** using `enhanced_syntax.nim`
- **Language detection** based on file extensions
- **Token-based highlighting** with proper color coding
- **Support for multiple languages**:
  - Nim (keywords, types, functions, comments, strings, numbers)
  - Python, JavaScript, Rust, C, C++
  - Plaintext fallback
- **Real-time syntax updates** when text is modified
- **Professional color scheme** with VS Code-inspired colors

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

### Window and Layout Management
- **High-DPI support** with proper scaling
- **Resizable window** with dynamic layout recalculation
- **Professional layout system**:
  - Title bar with file/directory info
  - Sidebar for file explorer (300px width)
  - Main editor area with line numbers
  - Status bar with comprehensive information
- **Proper bounds calculation** for all UI elements

### Git Integration
- **Real-time Git branch display** in status bar
- **Git status monitoring** (number of changed files)
- **Automatic Git repository detection**
- **Periodic updates** (every 2 seconds)
- **Non-blocking Git operations** using file-based detection

### Status Bar Enhancement
- **Cursor position** (line, column)
- **Document statistics** (lines, characters, words)
- **Git information** (branch name, change count)
- **File modification indicator**
- **Professional styling** with dark theme

### Notification System
- **Color-coded notifications** (success, error, warning, info)
- **Timed notifications** with auto-removal
- **Alpha-blended fade-out** effect
- **Operation feedback** for file operations

### Professional UI Theme
- **Dark theme** with carefully chosen colors
- **Syntax highlighting colors** matching modern editors
- **Proper contrast ratios** for readability
- **Line number styling** with background distinction
- **Cursor visualization** with bright yellow indicator

### Command Palette System
- **Modal command palette** with Ctrl+P activation
- **Fuzzy search functionality** for quick command discovery
- **Keyboard navigation** with arrow keys and Enter to execute
- **Command categories** (File, View, Git) for organization
- **Keybinding display** showing shortcuts for each command
- **Available commands**:
  - **Open File** (Ctrl+O) - File opening dialog
  - **New File** (Ctrl+N) - Create new document
  - **Switch Theme** (F1) - Toggle dark/light themes
  - **Show Welcome Screen** - Return to welcome view
  - **Toggle Sidebar** (Ctrl+B) - Hide/show file explorer
  - **Refresh Git Status** - Force update Git information
- **Professional styling** with semi-transparent overlay
- **Theme integration** using current color scheme
- **Escape to close** for quick dismissal
- **String-based command dispatch** for maintainable execution

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

### Button Group System
- **Professional title bar buttons** with Zed-style flat design
- **Four interactive buttons**: Explorer, Search, Git, Settings
- **Mouse interaction states** (normal, hover, active) with smooth transitions
- **Professional icon system** with centered 16x16 pixel icons for each function
- **Grid-based layout** automatically positioning buttons in 160px title bar area
- **Theme integration** with adaptive colors for all button states
- **Click functionality**:
  - **Explorer Button**: Toggle file explorer sidebar visibility
  - **Search Button**: Open command palette (same as Ctrl+P)
  - **Git Button**: Refresh git status information
  - **Settings Button**: Switch between dark/light themes (same as F1)
- **State management** with proper active/inactive button tracking
- **Window resize support** maintaining button layout during window changes
- **Performance optimized** with 60fps hover and click response
- **Professional styling** matching modern desktop application standards
- **Integration coordination** with all existing systems (themes, explorer, command palette, git)

## 🎯 UI Layout Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│ [Explorer] [Search] [Git] [Ext] │ ▓ main.nim ▓ utils.nim ✕ │ Drift Editor                                                  │
├────────────────────────────────────────────────────────────────────────────┤
│ dir_base_name             │ main.nim                                                                                         │
│ ┌─ src/                  │───────────────────────────────────────────────────────────│
│ │  ├─ main.nim          │  1 │ func main() =                            ││                                               │
│ │  └─ ui/               │  2 │   echo "Hello"                           ││                                               │
│ │                        │  3 │   return 0                               ││                                                │
│ │                        │  4 │                                          ││                                                │
│ │                        │  5 │                                          ││                                                │
│ │                        │    │                                          ││                                                │
│                           │    │                                          ││                                                │
├──────────────────────────┴─────────────────────────────────────────────────┤
│ ● Modified     ⎇ main                                                                            Ln 1, Col 1    UTF-8 LF  Nim│
└────────────────────────────────────────────────────────────────────────────┘
```

## 🔄 Component Integration

### Theme System Coordination
- **Color Harmony**: All components respect current theme colors
- **Dark/Light Support**: Adaptive colors for both theme variants
- **Consistency**: Unified color palette across all UI elements

### Input System Integration
- **Sophisticated Events**: Mouse events with drag, hover, multi-click detection
- **Keyboard Handling**: Key combinations, repeat handling, modifier detection
- **Command System**: Foundation for registering editor commands with contexts
- **Type Safety**: Clean interfaces without direct Raylib dependencies

### File Explorer Enhancement
- **Visual Hierarchy**: Clear parent/child relationships
- **Interactive Elements**: Clickable expand/collapse indicators
- **Keyboard Navigation**: Arrow key navigation with Ctrl modifiers
- **Selection Feedback**: Visual feedback for current selection

## 🏆 Architecture Benefits

### ✅ Clean Separation of Concerns
- **UI Layer**: Pure rendering and input handling
- **Domain Layer**: Business logic without external dependencies
- **Infrastructure Layer**: External concerns and technology adapters
- **Services Layer**: Coordination between layers

### ✅ Testability
- **Unit Testing**: Each component can be tested independently
- **Mock Dependencies**: Infrastructure can be mocked for UI testing
- **Pure Functions**: UI logic is pure and easily testable

### ✅ Maintainability
- **Clear Dependencies**: Dependencies flow in one direction
- **Modular Design**: Changes in one component don't affect others
- **Type Safety**: Strong typing prevents runtime errors

### ✅ Extensibility
- **Plugin Architecture**: Easy to add new UI components
- **Theme System**: Easy to add new themes and color schemes
- **Component System**: Easy to add new UI elements

## 🔧 Technical Implementation Details

### Component Architecture
```nim
# Example component structure
type EditorApp = ref object
  # Core components
  theme: ColorTheme
  inputHandler: InputHandler
  fileExplorer: FileExplorer
  commandPalette: CommandPalette
  statusBar: StatusBar
  
  # State management
  currentFile: string
  cursorPos: CursorPos
  selection: Selection
  
  # UI bounds
  titleBarBounds: Rectangle
  sidebarBounds: Rectangle
  editorBounds: Rectangle
  statusBarBounds: Rectangle
```

### Rendering Pipeline
```nim
proc render(app: EditorApp) =
  # 1. Calculate layout bounds
  calculateLayout(app)
  
  # 2. Render components in order
  drawTitleBar(app)
  drawSidebar(app)
  drawEditor(app)
  drawStatusBar(app)
  drawNotifications(app)
  
  # 3. Handle overlays
  if app.commandPalette.isVisible:
    drawCommandPalette(app)
```

### Input Handling
```nim
proc handleInput(app: EditorApp) =
  # 1. Process mouse events
  let mouseEvents = app.inputHandler.getMouseEvents()
  for event in mouseEvents:
    handleMouseEvent(app, event)
  
  # 2. Process keyboard events
  let keyEvents = app.inputHandler.getKeyEvents()
  for event in keyEvents:
    handleKeyEvent(app, event)
```

## 🎨 Visual Design System

### Color Palette
- **Primary Colors**: Professional dark theme with carefully chosen colors
- **Syntax Colors**: VS Code-inspired syntax highlighting
- **UI Colors**: Consistent color scheme across all components
- **Status Colors**: Color-coded notifications and status indicators

### Typography
- **Font System**: Professional font loading with fallback system
- **Line Numbers**: Distinct styling with background distinction
- **UI Text**: Consistent font sizes and weights
- **Code Font**: Monospace font for code display

### Layout System
- **Grid System**: Consistent spacing and alignment
- **Responsive Design**: Adapts to different window sizes
- **High-DPI Support**: Crisp rendering on high-resolution displays
- **Professional Margins**: Proper spacing between elements

## 🔮 Future Enhancements

### Advanced UI Features
- **Multiple Tabs**: Tab-based file management
- **Split Views**: Multiple editor panes
- **Minimap**: Code overview sidebar
- **Code Folding**: Collapsible code sections
- **Bracket Matching**: Visual bracket highlighting
- **Auto-completion**: Inline completion suggestions

### Enhanced Interactions
- **Drag and Drop**: File drag and drop support
- **Context Menus**: Right-click context menus
- **Tooltips**: Hover information tooltips
- **Keyboard Shortcuts**: Customizable shortcuts
- **Mouse Gestures**: Advanced mouse interactions

### Visual Enhancements
- **Animations**: Smooth transitions and animations
- **Custom Themes**: User-defined color schemes
- **Icon Customization**: Custom file type icons
- **Layout Customization**: User-defined layouts

## 📚 Related Documentation

- **[EXPLORER_SYSTEM.md](EXPLORER_SYSTEM.md)** - File explorer implementation details
- **[ICON_SYSTEM.md](ICON_SYSTEM.md)** - Icon system and SVG rasterization
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Overall architecture overview
- **[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)** - Current implementation status