## Merged Theme System for Drift Editor
## This file combines theme.nim and infrastructure/rendering/theme.nim

import raylib as rl
import std/[tables]
import results
import ../../shared/[constants, errors]

# Export type for use in other modules
type ThemeError* = ConfigError

# Theme color categories
type UIColorType* = enum
  # Background colors
  uiBackground = "background"
  uiPanel = "panel"
  uiSidebar = "sidebar"
  uiTitlebar = "titlebar"
  uiStatusbar = "statusbar"
  uiPopup = "popup"

  # Border and separator colors
  uiBorder = "border"
  uiBorderActive = "border_active"
  uiSeparator = "separator"
  uiScrollbar = "scrollbar"

  # Text colors
  uiText = "text"
  uiTextMuted = "text_muted"
  uiTextDisabled = "text_disabled"
  uiTextHighlight = "text_highlight"

  # Interactive element colors
  uiAccent = "accent"
  uiAccentHover = "accent_hover"
  uiAccentActive = "accent_active"
  uiButton = "button"
  uiButtonHover = "button_hover"
  uiButtonActive = "button_active"
  uiIcon = "icon"

  # Editor specific colors
  uiSelection = "selection"
  uiSelectionInactive = "selection_inactive"
  uiCursor = "cursor"
  uiLineNumber = "line_number"
  uiLineNumberActive = "line_number_active"
  uiCurrentLine = "current_line"
  uiMatchingBracket = "matching_bracket"

  # Status colors
  uiSuccess = "success"
  uiWarning = "warning"
  uiError = "error"
  uiInfo = "info"

type SyntaxColorType* = enum
  # Language elements
  synKeyword = "keyword"
  synType = "type"
  synFunction = "function"
  synVariable = "variable"
  synParameter = "parameter"
  synProperty = "property"
  synConstant = "constant"
  synEnum = "enum"
  synInterface = "interface"
  synNamespace = "namespace"

  # Literals
  synString = "string"
  synNumber = "number"
  synBoolean = "boolean"
  synCharacter = "character"
  synRegex = "regex"

  # Comments and documentation
  synComment = "comment"
  synDocComment = "doc_comment"
  synDocKeyword = "doc_keyword"

  # Operators and punctuation
  synOperator = "operator"
  synPunctuation = "punctuation"
  synBracket = "bracket"
  synDelimiter = "delimiter"

  # Preprocessor and attributes
  synPreprocessor = "preprocessor"
  synAttribute = "attribute"
  synAnnotation = "annotation"

  # Special elements
  synTag = "tag"
  synLabel = "label"
  synEscape = "escape"
  synError = "error"
  synWarning = "warning"
  synDeprecated = "deprecated"

# Font configuration
type FontConfig* = object
  family*: string
  size*: int
  weight*: string # "normal", "bold", "light"
  style*: string # "normal", "italic"

# Theme definition
type Theme* = object
  name*: string
  description*: string
  author*: string
  version*: string
  isDark*: bool

  # Color mappings
  uiColors*: Table[UIColorType, rl.Color]
  syntaxColors*: Table[SyntaxColorType, rl.Color]

  # Font configuration
  editorFont*: FontConfig
  uiFont*: FontConfig
  titleFont*: FontConfig

  # Layout properties
  borderRadius*: float32
  shadowOpacity*: float32
  animationDuration*: float32

# Theme manager
type ThemeManager* = ref object
  currentTheme*: Theme
  availableThemes*: Table[string, Theme]
  customThemes*: Table[string, Theme]

# Default color definitions
const
  # Dark theme colors
  DarkThemeColors = {
    uiBackground: rl.Color(r: 22, g: 22, b: 22, a: 255),
    uiPanel: rl.Color(r: 28, g: 28, b: 28, a: 255),
    uiSidebar: rl.Color(r: 25, g: 25, b: 25, a: 255),
    uiTitlebar: rl.Color(r: 32, g: 32, b: 32, a: 255),
    uiStatusbar: rl.Color(r: 30, g: 30, b: 30, a: 255),
    uiPopup: rl.Color(r: 35, g: 35, b: 35, a: 255),
    uiBorder: rl.Color(r: 40, g: 40, b: 40, a: 255),
    uiBorderActive: rl.Color(r: 88, g: 134, b: 221, a: 255),
    uiSeparator: rl.Color(r: 35, g: 35, b: 35, a: 255),
    uiScrollbar: rl.Color(r: 45, g: 45, b: 45, a: 255),
    uiText: rl.Color(r: 230, g: 230, b: 230, a: 255),
    uiTextMuted: rl.Color(r: 140, g: 140, b: 140, a: 255),
    uiTextDisabled: rl.Color(r: 80, g: 80, b: 80, a: 255),
    uiTextHighlight: rl.Color(r: 255, g: 255, b: 255, a: 255),
    uiAccent: rl.Color(r: 88, g: 134, b: 221, a: 255),
    uiAccentHover: rl.Color(r: 108, g: 154, b: 241, a: 255),
    uiAccentActive: rl.Color(r: 68, g: 114, b: 201, a: 255),
    uiButton: rl.Color(r: 45, g: 45, b: 45, a: 255),
    uiButtonHover: rl.Color(r: 55, g: 55, b: 55, a: 255),
    uiButtonActive: rl.Color(r: 35, g: 35, b: 35, a: 255),
    uiIcon: rl.Color(r: 140, g: 140, b: 140, a: 255),
    uiSelection: rl.Color(r: 88, g: 134, b: 221, a: 60),
    uiSelectionInactive: rl.Color(r: 88, g: 134, b: 221, a: 30),
    uiCursor: rl.Color(r: 255, g: 255, b: 255, a: 255),
    uiLineNumber: rl.Color(r: 100, g: 100, b: 100, a: 255),
    uiLineNumberActive: rl.Color(r: 160, g: 160, b: 160, a: 255),
    uiCurrentLine: rl.Color(r: 32, g: 32, b: 32, a: 255),
    uiMatchingBracket: rl.Color(r: 88, g: 134, b: 221, a: 120),
    uiSuccess: rl.Color(r: 72, g: 187, b: 120, a: 255),
    uiWarning: rl.Color(r: 255, g: 184, b: 0, a: 255),
    uiError: rl.Color(r: 248, g: 81, b: 73, a: 255),
    uiInfo: rl.Color(r: 88, g: 134, b: 221, a: 255),
  }.toTable

  # Light theme colors
  LightThemeColors = {
    uiBackground: rl.Color(r: 255, g: 255, b: 255, a: 255),
    uiPanel: rl.Color(r: 248, g: 248, b: 248, a: 255),
    uiSidebar: rl.Color(r: 245, g: 245, b: 245, a: 255),
    uiTitlebar: rl.Color(r: 240, g: 240, b: 240, a: 255),
    uiStatusbar: rl.Color(r: 242, g: 242, b: 242, a: 255),
    uiPopup: rl.Color(r: 250, g: 250, b: 250, a: 255),
    uiBorder: rl.Color(r: 200, g: 200, b: 200, a: 255),
    uiBorderActive: rl.Color(r: 88, g: 134, b: 221, a: 255),
    uiSeparator: rl.Color(r: 220, g: 220, b: 220, a: 255),
    uiScrollbar: rl.Color(r: 180, g: 180, b: 180, a: 255),
    uiText: rl.Color(r: 30, g: 30, b: 30, a: 255),
    uiTextMuted: rl.Color(r: 120, g: 120, b: 120, a: 255),
    uiTextDisabled: rl.Color(r: 180, g: 180, b: 180, a: 255),
    uiTextHighlight: rl.Color(r: 0, g: 0, b: 0, a: 255),
    uiAccent: rl.Color(r: 88, g: 134, b: 221, a: 255),
    uiAccentHover: rl.Color(r: 68, g: 114, b: 201, a: 255),
    uiAccentActive: rl.Color(r: 108, g: 154, b: 241, a: 255),
    uiButton: rl.Color(r: 230, g: 230, b: 230, a: 255),
    uiButtonHover: rl.Color(r: 220, g: 220, b: 220, a: 255),
    uiButtonActive: rl.Color(r: 210, g: 210, b: 210, a: 255),
    uiIcon: rl.Color(r: 140, g: 140, b: 140, a: 255),
    uiSelection: rl.Color(r: 88, g: 134, b: 221, a: 100),
    uiSelectionInactive: rl.Color(r: 88, g: 134, b: 221, a: 50),
    uiCursor: rl.Color(r: 0, g: 0, b: 0, a: 255),
    uiLineNumber: rl.Color(r: 150, g: 150, b: 150, a: 255),
    uiLineNumberActive: rl.Color(r: 80, g: 80, b: 80, a: 255),
    uiCurrentLine: rl.Color(r: 248, g: 248, b: 248, a: 255),
    uiMatchingBracket: rl.Color(r: 88, g: 134, b: 221, a: 120),
    uiSuccess: rl.Color(r: 52, g: 167, b: 100, a: 255),
    uiWarning: rl.Color(r: 235, g: 164, b: 0, a: 255),
    uiError: rl.Color(r: 228, g: 61, b: 53, a: 255),
    uiInfo: rl.Color(r: 88, g: 134, b: 221, a: 255),
  }.toTable

  # Dark syntax colors
  DarkSyntaxColors = {
    synKeyword: rl.Color(r: 197, g: 134, b: 192, a: 255), # Purple
    synType: rl.Color(r: 78, g: 201, b: 176, a: 255), # Teal
    synFunction: rl.Color(r: 220, g: 220, b: 170, a: 255), # Yellow
    synVariable: rl.Color(r: 156, g: 220, b: 254, a: 255), # Light blue
    synParameter: rl.Color(r: 156, g: 220, b: 254, a: 255), # Light blue
    synProperty: rl.Color(r: 156, g: 220, b: 254, a: 255), # Light blue
    synConstant: rl.Color(r: 100, g: 171, b: 143, a: 255), # Green
    synEnum: rl.Color(r: 78, g: 201, b: 176, a: 255), # Teal
    synInterface: rl.Color(r: 78, g: 201, b: 176, a: 255), # Teal
    synNamespace: rl.Color(r: 204, g: 120, b: 50, a: 255), # Orange
    synString: rl.Color(r: 206, g: 145, b: 120, a: 255), # Peach
    synNumber: rl.Color(r: 181, g: 206, b: 168, a: 255), # Light green
    synBoolean: rl.Color(r: 86, g: 156, b: 214, a: 255), # Blue
    synCharacter: rl.Color(r: 206, g: 145, b: 120, a: 255), # Peach
    synRegex: rl.Color(r: 215, g: 186, b: 125, a: 255), # Gold
    synComment: rl.Color(r: 106, g: 153, b: 85, a: 255), # Green
    synDocComment: rl.Color(r: 106, g: 153, b: 85, a: 255), # Green
    synDocKeyword: rl.Color(r: 128, g: 128, b: 128, a: 255), # Gray
    synOperator: rl.Color(r: 212, g: 212, b: 212, a: 255), # Light gray
    synPunctuation: rl.Color(r: 212, g: 212, b: 212, a: 255), # Light gray
    synBracket: rl.Color(r: 255, g: 215, b: 0, a: 255), # Gold
    synDelimiter: rl.Color(r: 212, g: 212, b: 212, a: 255), # Light gray
    synPreprocessor: rl.Color(r: 155, g: 155, b: 155, a: 255), # Gray
    synAttribute: rl.Color(r: 155, g: 155, b: 155, a: 255), # Gray
    synAnnotation: rl.Color(r: 155, g: 155, b: 155, a: 255), # Gray
    synTag: rl.Color(r: 86, g: 156, b: 214, a: 255), # Blue
    synLabel: rl.Color(r: 220, g: 220, b: 170, a: 255), # Yellow
    synEscape: rl.Color(r: 215, g: 186, b: 125, a: 255), # Gold
    synError: rl.Color(r: 248, g: 81, b: 73, a: 255), # Red
    synWarning: rl.Color(r: 255, g: 184, b: 0, a: 255), # Amber
    synDeprecated: rl.Color(r: 128, g: 128, b: 128, a: 255), # Gray
  }.toTable

  # Light syntax colors
  LightSyntaxColors = {
    synKeyword: rl.Color(r: 175, g: 0, b: 219, a: 255), # Purple
    synType: rl.Color(r: 38, g: 127, b: 153, a: 255), # Teal
    synFunction: rl.Color(r: 121, g: 94, b: 38, a: 255), # Brown
    synVariable: rl.Color(r: 1, g: 84, b: 147, a: 255), # Blue
    synParameter: rl.Color(r: 1, g: 84, b: 147, a: 255), # Blue
    synProperty: rl.Color(r: 1, g: 84, b: 147, a: 255), # Blue
    synConstant: rl.Color(r: 9, g: 134, b: 88, a: 255), # Green
    synEnum: rl.Color(r: 38, g: 127, b: 153, a: 255), # Teal
    synInterface: rl.Color(r: 38, g: 127, b: 153, a: 255), # Teal
    synNamespace: rl.Color(r: 152, g: 104, b: 1, a: 255), # Orange
    synString: rl.Color(r: 163, g: 21, b: 21, a: 255), # Red
    synNumber: rl.Color(r: 9, g: 134, b: 88, a: 255), # Green
    synBoolean: rl.Color(r: 1, g: 84, b: 147, a: 255), # Blue
    synCharacter: rl.Color(r: 163, g: 21, b: 21, a: 255), # Red
    synRegex: rl.Color(r: 152, g: 104, b: 1, a: 255), # Orange
    synComment: rl.Color(r: 106, g: 153, b: 85, a: 255), # Green
    synDocComment: rl.Color(r: 106, g: 153, b: 85, a: 255), # Green
    synDocKeyword: rl.Color(r: 128, g: 128, b: 128, a: 255), # Gray
    synOperator: rl.Color(r: 104, g: 104, b: 104, a: 255), # Gray
    synPunctuation: rl.Color(r: 104, g: 104, b: 104, a: 255), # Gray
    synBracket: rl.Color(r: 104, g: 104, b: 104, a: 255), # Gray
    synDelimiter: rl.Color(r: 104, g: 104, b: 104, a: 255), # Gray
    synPreprocessor: rl.Color(r: 155, g: 155, b: 155, a: 255), # Gray
    synAttribute: rl.Color(r: 155, g: 155, b: 155, a: 255), # Gray
    synAnnotation: rl.Color(r: 155, g: 155, b: 155, a: 255), # Gray
    synTag: rl.Color(r: 1, g: 84, b: 147, a: 255), # Blue
    synLabel: rl.Color(r: 121, g: 94, b: 38, a: 255), # Brown
    synEscape: rl.Color(r: 152, g: 104, b: 1, a: 255), # Orange
    synError: rl.Color(r: 224, g: 108, b: 117, a: 255), # Red
    synWarning: rl.Color(r: 255, g: 184, b: 0, a: 255), # Amber
    synDeprecated: rl.Color(r: 128, g: 128, b: 128, a: 255), # Gray
  }.toTable

# Default font configurations
const
  DefaultEditorFont =
    FontConfig(family: "Fira Code", size: 14, weight: "normal", style: "normal")

  DefaultUIFont =
    FontConfig(family: "Inter", size: 13, weight: "normal", style: "normal")

  DefaultTitleFont =
    FontConfig(family: "Inter", size: 13, weight: "medium", style: "normal")

# Built-in theme definitions
proc createDarkTheme*(): Theme =
  Theme(
    name: "Drift Dark",
    description: "Default dark theme for Drift editor",
    author: "Drift Team",
    version: "1.0.0",
    isDark: true,
    uiColors: DarkThemeColors,
    syntaxColors: DarkSyntaxColors,
    editorFont: DefaultEditorFont,
    uiFont: DefaultUIFont,
    titleFont: DefaultTitleFont,
    borderRadius: 4.0,
    shadowOpacity: 0.3,
    animationDuration: 0.2,
  )

proc createLightTheme*(): Theme =
  Theme(
    name: "Drift Light",
    description: "Light theme for Drift editor",
    author: "Drift Team",
    version: "1.0.0",
    isDark: false,
    uiColors: LightThemeColors,
    syntaxColors: LightSyntaxColors,
    editorFont: DefaultEditorFont,
    uiFont: DefaultUIFont,
    titleFont: DefaultTitleFont,
    borderRadius: 4.0,
    shadowOpacity: 0.1,
    animationDuration: 0.2,
  )

# Theme manager implementation
proc newThemeManager*(): ThemeManager =
  result = ThemeManager(
    availableThemes: Table[string, Theme](),
    customThemes: Table[string, Theme](),
  )

  # Add built-in themes
  let darkTheme = createDarkTheme()
  let lightTheme = createLightTheme()

  result.availableThemes[darkTheme.name] = darkTheme
  result.availableThemes[lightTheme.name] = lightTheme

  # Set default theme
  result.currentTheme = darkTheme

proc setTheme*(manager: ThemeManager, themeName: string): Result[void, ThemeError] =
  if themeName in manager.availableThemes:
    manager.currentTheme = manager.availableThemes[themeName]
    return ok()
  elif themeName in manager.customThemes:
    manager.currentTheme = manager.customThemes[themeName]
    return ok()
  else:
    return err(
      newConfigError(
        ERROR_CONFIG_INVALID_VALUE, "Theme not found: " & themeName, "theme", themeName
      )
    )

proc getUIColor*(manager: ThemeManager, colorType: UIColorType): rl.Color =
  if colorType in manager.currentTheme.uiColors:
    return manager.currentTheme.uiColors[colorType]
  else:
    # Fallback to a default color
    return rl.Color(r: 128, g: 128, b: 128, a: 255)

proc getSyntaxColor*(manager: ThemeManager, colorType: SyntaxColorType): rl.Color =
  if colorType in manager.currentTheme.syntaxColors:
    return manager.currentTheme.syntaxColors[colorType]
  else:
    # Fallback to text color
    return manager.getUIColor(uiText)

proc isDarkTheme*(manager: ThemeManager): bool =
  manager.currentTheme.isDark

proc getThemeNames*(manager: ThemeManager): seq[string] =
  result = @[]
  for name in manager.availableThemes.keys:
    result.add(name)
  for name in manager.customThemes.keys:
    result.add(name)

proc getCurrentThemeName*(manager: ThemeManager): string =
  manager.currentTheme.name

# Color manipulation utilities
proc withAlpha*(color: rl.Color, alpha: uint8): rl.Color =
  result = color
  result.a = alpha

proc darken*(color: rl.Color, factor: float32): rl.Color =
  result.r = uint8(float32(color.r) * (1.0 - factor))
  result.g = uint8(float32(color.g) * (1.0 - factor))
  result.b = uint8(float32(color.b) * (1.0 - factor))
  result.a = color.a

proc lighten*(color: rl.Color, factor: float32): rl.Color =
  result.r = uint8(min(255.0, float32(color.r) + (255.0 - float32(color.r)) * factor))
  result.g = uint8(min(255.0, float32(color.g) + (255.0 - float32(color.g)) * factor))
  result.b = uint8(min(255.0, float32(color.b) + (255.0 - float32(color.b)) * factor))
  result.a = color.a

proc blend*(color1: rl.Color, color2: rl.Color, factor: float32): rl.Color =
  result.r = uint8(float32(color1.r) * (1.0 - factor) + float32(color2.r) * factor)
  result.g = uint8(float32(color1.g) * (1.0 - factor) + float32(color2.g) * factor)
  result.b = uint8(float32(color1.b) * (1.0 - factor) + float32(color2.b) * factor)
  result.a = uint8(float32(color1.a) * (1.0 - factor) + float32(color2.a) * factor)

# Theme validation
proc validateTheme*(theme: Theme): Result[void, ValidationError] =
  if theme.name.len == 0:
    return err(
      newValidationError(ERROR_VALIDATION_REQUIRED, "Theme name is required", "name")
    )

  if theme.editorFont.size < MIN_FONT_SIZE or theme.editorFont.size > MAX_FONT_SIZE:
    return err(
      newValidationError(
        ERROR_VALIDATION_OUT_OF_RANGE,
        "Editor font size out of range",
        "editorFont.size",
        $MIN_FONT_SIZE & "-" & $MAX_FONT_SIZE,
      )
    )

  # Validate that all required colors are present
  for colorType in UIColorType:
    if colorType notin theme.uiColors:
      return err(
        newValidationError(
          ERROR_VALIDATION_REQUIRED, "Missing UI color: " & $colorType, "uiColors"
        )
      )

  return ok()

# Zoom/scale utility functions
proc getScaledFontSize*(baseFontSize: float32, zoomLevel: float32): float32 =
  ## Get font size scaled by zoom level
  result = baseFontSize * zoomLevel

proc getScaledIconSize*(baseIconSize: float32, zoomLevel: float32): float32 =
  ## Get icon size scaled by zoom level
  result = baseIconSize * zoomLevel

proc getScaledUIFontSize*(theme: Theme, zoomLevel: float32): float32 =
  ## Get UI font size scaled by zoom level
  result = theme.uiFont.size.float32 * zoomLevel

proc getScaledEditorFontSize*(theme: Theme, zoomLevel: float32): float32 =
  ## Get editor font size scaled by zoom level
  result = theme.editorFont.size.float32 * zoomLevel

proc getScaledTitleFontSize*(theme: Theme, zoomLevel: float32): float32 =
  ## Get title font size scaled by zoom level
  result = theme.titleFont.size.float32 * zoomLevel
