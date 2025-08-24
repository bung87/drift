# Drift Editor - Architecture Overview

## 🏗️ Architecture Summary

The Drift editor follows a clean, domain-driven architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Application Layer (Phase 5)                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Application    │  │  Event          │  │  Command                    │  │
│  │  Controller     │  │  Coordinator    │  │  Dispatcher                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Service Layer (Phase 4)                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Editor         │  │  File           │  │  Language                   │  │
│  │  Service        │  │  Service        │  │  Service                    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  UI             │  │  Layout         │  │  Notification               │  │
│  │  Service        │  │  Service        │  │  Service                    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Domain Layer (Phase 3)                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Document       │  │  Selection      │  │  Syntax                     │  │
│  │  Model          │  │  Model          │  │  Model                      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Project        │  │  LSP            │  │  Git                        │  │
│  │  Model          │  │  Model          │  │  Model                      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ✅ Infrastructure Layer (Complete)                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Rendering      │  │  Input          │  │  File System                │  │
│  │  Engine         │  │  Handler        │  │  Adapter                    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Config         │  │  Resources      │  │  External APIs              │  │
│  │  Manager        │  │  Manager        │  │  (Git, LSP)                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ✅ Shared Foundation (Complete)                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  Types &        │  │  Constants &    │  │  Error Handling &           │  │
│  │  Results        │  │  Configuration  │  │  Utilities                  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
src/
├── main.nim                          # Clean entry point
├── shared/                           # ✅ Foundation layer
│   ├── types.nim                     # Domain types & Result pattern
│   ├── constants.nim                 # Application constants
│   ├── errors.nim                    # Error handling system
│   └── utils.nim                     # Pure utility functions
├── infrastructure/                   # ✅ External dependencies
│   ├── rendering/
│   │   └── theme.nim                 # Theme & color management
│   ├── input/
│   │   ├── keyboard.nim              # Keyboard abstraction
│   │   ├── mouse.nim                 # Mouse abstraction
│   │   └── input_handler.nim         # Unified input coordination
│   ├── filesystem/
│   │   ├── file_watcher.nim          # Async file operations
│   │   └── path_utils.nim            # Cross-platform paths
│   ├── external/
│   │   ├── lsp_client.nim            # LSP protocol client
│   │   └── git_client.nim            # Git operations
│   └── config.nim                    # Configuration management
├── domain/                           # 🚧 Business logic (Phase 3)
├── services/                         # 📋 Coordination layer (Phase 4)
├── app/                              # 📋 Application layer (Phase 5)
└── legacy/                           # 🔄 Legacy modules being migrated
    ├── drift.nim                     # Old entry point
    ├── core.nim                      # Legacy types
    ├── ui.nim                        # Legacy UI
    └── editor.nim                    # Legacy editor
```

## 🎯 Layer Responsibilities

### 1. Shared Layer (`src/shared/`)
**Purpose**: Foundation types and utilities used across all layers.

**Components**:
- `types.nim`: Core domain types (CursorPos, Selection, EditorMode, etc.)
- `errors.nim`: Error handling with Result types
- `constants.nim`: Application-wide constants
- `utils.nim`: Pure utility functions

**Key Features**:
- No external dependencies
- Type-safe error handling with Result[T, E]
- Position utilities and selection operations
- LSP type conversions

### 2. Infrastructure Layer (`src/infrastructure/`)
**Purpose**: External concerns and technology-specific implementations.

**Components**:
- **Rendering**: Theme system and rendering abstraction
- **Input**: Input event handling and key binding system
- **Filesystem**: File system operations and cross-platform paths
- **External APIs**: LSP client and Git integration

### 3. Domain Layer (`src/domain/`) - Phase 3
**Purpose**: Pure business logic without external dependencies.

**Planned Components**:
- **Document Model**: Text manipulation and undo/redo
- **Selection Model**: Multi-cursor and text selection
- **Syntax Model**: Language-agnostic syntax highlighting
- **Project Model**: Project and workspace management

### 4. Services Layer (`src/services/`) - Phase 4
**Purpose**: Application business logic coordinating domain models and infrastructure.

**Planned Components**:
- **Editor Service**: Document editing coordination
- **File Service**: File and project management
- **Language Service**: LSP server management
- **UI Service**: UI component management

### 5. Application Layer (`src/app/`) - Phase 5
**Purpose**: High-level application orchestration and entry points.

**Planned Components**:
- **App Coordinator**: Service coordination
- **Event Coordinator**: Event routing and handling
- **Command Dispatcher**: Command execution and routing

## 🔄 Migration Status

### ✅ Completed Layers
- **Shared Foundation**: Complete with type-safe error handling
- **Infrastructure**: Complete with input, rendering, and external APIs

### 🔄 In Progress
- **Domain Layer**: Core business models being implemented
- **Services Layer**: Service coordination being designed
- **Application Layer**: Application orchestration planned

### 📋 Legacy Migration
- **Legacy Modules**: Being gradually migrated to new architecture
- **UI Components**: Successfully ported to new architecture
- **File Operations**: Enhanced with new infrastructure

## 🎨 UI Layout Architecture

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

## 🔄 Main Logic Flow

### 1. Initialization
```
main() → initializeApplication() → {
  - Initialize Raylib window
  - Load default font
  - Initialize editor state
  - Setup UI components
  - Handle command line arguments
}
```

### 2. Main Loop
```
runMainLoop() → {
  while not shouldClose:
    - Handle window resize
    - Calculate layout bounds
    - Process input events
    - Update editor state
    - Update syntax highlighting
    - Update git info
    - Check auto-save
    - Render frame
}
```

### 3. Input Flow
```
handleInput() → {
  Mouse Input → {
    - Button clicks (sidebar panels)
    - Sidebar resizing
    - File explorer navigation
    - Text editor positioning
    - Scrolling
  }

  Keyboard Input → {
    - Character input → insertChar()
    - Special keys → {
      - Enter → insertLine()
      - Backspace → deleteChar()
      - Arrows → cursor movement
      - Ctrl+S → saveFile()
      - Ctrl+O → openFile()
      - Ctrl+N → newFile()
    }
  }
}
```

### 4. Rendering Pipeline
```
render() → {
  calculateLayout() → {
    - Title bar bounds
    - Sidebar bounds
    - Editor bounds
    - Status bar bounds
  }

  Draw Components → {
    - drawTitleBar()
    - drawSidebar() (Explorer/Search/Git/Extensions)
    - drawEditor()
    - drawStatusBar()
  }
}
```

## 🏆 Architecture Benefits

### ✅ Clean Separation of Concerns
- **UI Layer**: Pure rendering and input handling
- **Domain Layer**: Business logic without external dependencies
- **Infrastructure Layer**: External concerns and technology adapters
- **Services Layer**: Coordination between layers

### ✅ Testability
- **Unit Testing**: Each layer can be tested independently
- **Mock Dependencies**: Infrastructure can be mocked for domain testing
- **Pure Functions**: Domain logic is pure and easily testable

### ✅ Maintainability
- **Clear Dependencies**: Dependencies flow in one direction
- **Modular Design**: Changes in one layer don't affect others
- **Type Safety**: Strong typing prevents runtime errors

### ✅ Extensibility
- **Plugin Architecture**: Easy to add new features
- **Language Support**: Easy to add new syntax highlighting
- **UI Components**: Easy to add new UI elements

## 🔮 Future Enhancements

### Phase 3: Domain Layer Implementation
- **Document Model**: Complete text manipulation system
- **Selection Model**: Multi-cursor and advanced selection
- **Syntax Model**: Enhanced language support
- **Project Model**: Workspace management

### Phase 4: Services Layer
- **Editor Service**: Complete editing coordination
- **File Service**: Advanced file operations
- **Language Service**: Full LSP integration
- **UI Service**: Advanced UI management

### Phase 5: Application Layer
- **Command System**: Full command palette integration
- **Event System**: Sophisticated event routing
- **Plugin System**: Extensible plugin architecture

## 📚 Related Documentation

- **[REFACTORING_GUIDE.md](REFACTORING_GUIDE.md)** - Detailed refactoring process
- **[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)** - Current implementation status
- **[UI_COMPONENTS.md](UI_COMPONENTS.md)** - UI component architecture