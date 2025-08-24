## Text Editor Types
## Extracted from text_editor.nim

import std/[options]
import raylib as rl
import ../services/ui_service
import ../services/editor_service
import ../services/language_service
import ../services/component_manager
import ../services/file_service
import ../services/terminal_integration
import ../infrastructure/clipboard
import ../shared/types
import ../infrastructure/input/input_handler
import ../infrastructure/rendering/[renderer, theme]
import ../enhanced_syntax
import ../markdown_code_blocks

# Hover timing constants
# HOVER_REQUEST_DEBOUNCE_MS moved to shared/constants.nim

# Text editor specific types
type
  TextEditorConfig* = object
    fontSize*: float32
    lineHeight*: float32
    charWidth*: float32
    showLineNumbers*: bool
    lineNumberWidth*: float32
    showScrollbar*: bool
    scrollbarWidth*: float32
    padding*: float32
    tabSize*: int
    useSpaces*: bool
    wordWrap*: bool
    syntaxHighlighting*: bool
    autoIndent*: bool
    bracketMatching*: bool

  TextEditor* = ref object of UIComponent
    ## Text editor component that inherits from UIComponent for infrastructure integration.
    ## Provides text editing, syntax highlighting, and cursor management with full UI service integration.
    uiService*: UIService # Reference to UI service for component management
    componentManager*: ComponentManager # Component manager for unified input handling
    editorService*: EditorService # Editor operations service
    languageService*: LanguageService # Language service for LSP features
    config*: TextEditorConfig # Display and behavior configuration
    terminalIntegration*: Option[TerminalIntegration] # Optional reference to terminal integration for hover exclusion
    editorState*: TextEditorState # Internal editor state
    syntaxHighlighter*: SyntaxHighlighter # Syntax highlighting
    font*: ptr rl.Font # Use a pointer to the font
    lastUpdateTime*: float64 # Last update timestamp for animations/timing
    allTokens*: seq[enhanced_syntax.Token] # Cached tokens for entire document
    tokensValid*: bool # Whether the cached tokens are valid
    lastTokenizedVersion*: int # Last document version that was tokenized
    currentLanguage*: enhanced_syntax.Language # Current language for syntax highlighting
    markdownParser*: Option[MarkdownCodeBlockRenderer] # Markdown code block renderer
    renderer*: Renderer # Renderer service
    themeManager*: ThemeManager # Theme manager service  
    fileService*: FileService # File service for file operations
    inputHandler*: InputHandler # Input handler service
    clipboardService*: ClipboardService # Clipboard operations service
    pendingHoverSymbol: string
    pendingHoverLine: int
    pendingHoverCol: int
    # Hover timing fields
    hoverStartTime*: float
    lastHoverRequestTime*: float
    # Mouse tracking for hover optimization
    lastMousePos*: rl.Vector2
    lastMouseMoveTime*: float
    lastModifierState*: bool  # Track Ctrl/Cmd modifier state
    lastScrollWheelMove*: float32  # Track scroll wheel movement
    # Cursor blinking support
    cursorBlinkTime*: float64
    cursorVisible*: bool
    # Multi-cursor support
    isMultiCursorMode*: bool
    multiCursors*: seq[CursorPos]
    # Click tracking for double/triple click
    clickCount*: int
    lastClickTime*: float64
    lastClickPos*: CursorPos
    # Ctrl+D multi-selection tracking
    lastSelectedWord*: string
    ctrlDSelections*: seq[Selection]
  
    # Ctrl+hover state for Go to Definition
    isCtrlHovering*: bool
    ctrlHoverSymbol*: string
    ctrlHoverPosition*: CursorPos

# Default configuration
proc defaultTextEditorConfig*(): TextEditorConfig =
  TextEditorConfig(
    fontSize: 14.0,
    lineHeight: 20.0,
    charWidth: 8.0,
    showLineNumbers: true,
    lineNumberWidth: 60.0,
    showScrollbar: true,
    scrollbarWidth: 12.0,
    padding: 8.0,
    tabSize: 2,
    useSpaces: true,
    wordWrap: false,
    syntaxHighlighting: true,
    autoIndent: true,
    bracketMatching: true,
  )