## Command Palette Component
## Provides a searchable command palette interface for the editor
## Uses ComponentManager for standardized component architecture

import std/[strutils, options, tables]
import raylib as rl
import ../infrastructure/rendering/theme
import ../services/component_manager
import ../services/ui_service  # For UIComponent type
import ../shared/errors
import ../infrastructure/input/[keyboard, input_handler]  # For UnifiedInputEvent
import results
# Command palette types
type
  CommandPaletteItem* = object
    name*: string
    description*: string
    category*: string
    keybinding*: string
    command*: string

  CommandPalette* = ref object of UIComponent
    # Core component manager integration
    componentManager*: ComponentManager
    
    # Command palette state
    searchText*: string
    filteredCommands*: seq[CommandPaletteItem]
    selectedIndex*: int
    maxVisibleItems*: int
    allCommands*: seq[CommandPaletteItem]
    
    # Layout configuration
    paletteWidth*: float32
    paletteHeight*: float32
    searchBoxHeight*: float32
    itemHeight*: float32
    
    # Visual configuration
    showKeybindings*: bool
    showCategories*: bool
    
    # Event callbacks
    onCommandSelected*: proc(palette: CommandPalette, command: CommandPaletteItem)
    onPaletteHidden*: proc(palette: CommandPalette)

# Forward declarations
proc handleInput*(palette: CommandPalette, event: UnifiedInputEvent): bool
proc render*(palette: CommandPalette)
proc initializeDefaultCommands*(palette: CommandPalette)
proc filterCommands*(palette: CommandPalette)
proc getSelectedCommand*(palette: CommandPalette): Option[CommandPaletteItem]
proc show*(palette: CommandPalette)
proc hide*(palette: CommandPalette)

# Constructor
proc newCommandPalette*(
  id: string,
  componentManager: ComponentManager,
  maxVisibleItems: int = 8
): CommandPalette =
  result = CommandPalette(
    componentManager: componentManager,
    searchText: "",
    filteredCommands: @[],
    selectedIndex: 0,
    maxVisibleItems: maxVisibleItems,
    allCommands: @[],
    paletteWidth: 600.0,
    paletteHeight: 400.0,
    searchBoxHeight: 40.0,
    itemHeight: 40.0,
    showKeybindings: true,
    showCategories: true
  )
  
  # Initialize UIComponent fields
  result.id = id
  result.name = "CommandPalette"
  result.state = csHidden
  result.bounds = rl.Rectangle(x: 0, y: 0, width: 600, height: 400)
  result.zIndex = 1000  # High z-index for modal overlay
  result.isVisible = false
  result.isEnabled = true
  result.isDirty = false
  result.parent = nil
  result.children = @[]
  result.data = initTable[string, string]()

# Initialize with ComponentManager integration
proc initialize*(palette: CommandPalette): Result[void, EditorError] =
  ## Initialize the command palette with ComponentManager integration
  
  # Register component with ComponentManager
  let registerResult = palette.componentManager.registerComponent(
    palette.id,
    palette,  # Now inherits from UIComponent
    proc(event: UnifiedInputEvent): bool = palette.handleInput(event),
    proc(bounds: rl.Rectangle) = palette.render()
  )
  
  if registerResult.isErr:
    return err(registerResult.error)
  
  # Register keyboard shortcuts using ComponentManager
  let shortcuts = {
    KeyCombination(key: ekEscape, modifiers: {}): "hide_palette",
    KeyCombination(key: ekEnter, modifiers: {}): "execute_command",
    KeyCombination(key: ekUp, modifiers: {}): "navigate_up",
    KeyCombination(key: ekDown, modifiers: {}): "navigate_down",
    KeyCombination(key: ekBackspace, modifiers: {}): "delete_char"
  }.toTable()
  
  let shortcutResult = palette.componentManager.registerKeyboardShortcuts(
    palette.id,
    shortcuts
  )
  
  if shortcutResult.isErr:
    return err(shortcutResult.error)
  
  # Initialize default commands
  palette.initializeDefaultCommands()
  
  return ok()

# Initialize default commands
proc initializeDefaultCommands*(palette: CommandPalette) =
  ## Initialize the default set of commands
  palette.allCommands = @[]

  # File commands
  palette.allCommands.add(
    CommandPaletteItem(
      name: "Open File",
      description: "Open a file for editing",
      category: "File",
      keybinding: "Ctrl+O",
      command: "open_file",
    )
  )

  palette.allCommands.add(
    CommandPaletteItem(
      name: "New File",
      description: "Create a new file",
      category: "File",
      keybinding: "Ctrl+N",
      command: "new_file",
    )
  )

  # Theme commands
  palette.allCommands.add(
    CommandPaletteItem(
      name: "Switch Theme",
      description: "Toggle between dark and light themes",
      category: "View",
      keybinding: "F1",
      command: "switch_theme",
    )
  )

  # View commands
  palette.allCommands.add(
    CommandPaletteItem(
      name: "Show Welcome Screen",
      description: "Display the welcome screen",
      category: "View",
      keybinding: "",
      command: "show_welcome",
    )
  )

  palette.allCommands.add(
    CommandPaletteItem(
      name: "Toggle Sidebar",
      description: "Show or hide the file explorer sidebar",
      category: "View",
      keybinding: "Ctrl+B",
      command: "toggle_sidebar",
    )
  )

  # Git commands
  palette.allCommands.add(
    CommandPaletteItem(
      name: "Refresh Git Status",
      description: "Update git status information",
      category: "Git",
      keybinding: "",
      command: "refresh_git",
    )
  )

  # Explorer commands
  palette.allCommands.add(
    CommandPaletteItem(
      name: "Refresh Explorer",
      description: "Refresh file explorer contents",
      category: "File",
      keybinding: "F5",
      command: "refresh_explorer",
    )
  )

# Filter commands based on search text
proc filterCommands*(palette: CommandPalette) =
  palette.filteredCommands = @[]

  if palette.searchText.len == 0:
    palette.filteredCommands = palette.allCommands
  else:
    let searchLower = palette.searchText.toLower()
    for cmd in palette.allCommands:
      if searchLower in cmd.name.toLower() or 
         searchLower in cmd.description.toLower() or
         searchLower in cmd.category.toLower():
        palette.filteredCommands.add(cmd)

  # Reset selection if out of bounds
  if palette.selectedIndex >= palette.filteredCommands.len:
    palette.selectedIndex = 0
  
  # Mark as dirty for redraw
  palette.isDirty = true
  palette.componentManager.markComponentDirty(palette.id)

# Show the command palette using UIService
proc show*(palette: CommandPalette) =
  palette.searchText = ""
  palette.selectedIndex = 0
  palette.filterCommands()
  
  # Update component state using ComponentManager
  discard palette.componentManager.setComponentVisibility(palette.id, true)
  discard palette.componentManager.updateComponentState(palette.id, csFocused)
  
  # Set focus using UIService
  discard palette.componentManager.uiService.setFocus(palette.id)
  
  # Update local state after UIService calls
  palette.isVisible = true
  palette.state = csFocused
  
  # Update layout to center on screen
  let viewport = palette.componentManager.uiService.getViewport()
  let paletteX = (viewport.width - palette.paletteWidth) / 2
  let paletteY = (viewport.height - palette.paletteHeight) / 2
  
  let newBounds = rl.Rectangle(
    x: paletteX,
    y: paletteY,
    width: palette.paletteWidth,
    height: palette.paletteHeight
  )
  
  discard palette.componentManager.updateComponentBounds(palette.id, newBounds)

# Hide the command palette using UIService
proc hide*(palette: CommandPalette) =
  # Clear focus using UIService first
  palette.componentManager.uiService.clearFocus()
  
  # Update component state using ComponentManager
  discard palette.componentManager.setComponentVisibility(palette.id, false)
  discard palette.componentManager.updateComponentState(palette.id, csHidden)
  
  # Update local state after UIService calls
  palette.isVisible = false
  palette.state = csHidden
  
  # Reset state
  palette.searchText = ""
  palette.selectedIndex = 0
  
  # Call callback if set
  if palette.onPaletteHidden != nil:
    palette.onPaletteHidden(palette)

# Handle input events using standardized patterns
proc handleInput*(palette: CommandPalette, event: UnifiedInputEvent): bool =
  ## Handle command palette input using standardized input patterns
  if not palette.isVisible:
    return false

  case event.kind:
  of uiekKeyboard:
    let keyEvent = event.keyEvent
    
    case keyEvent.key:
    of ekEscape:
      if keyEvent.eventType == ietKeyPressed:
        palette.hide()
        return true
    
    of ekEnter:
      if keyEvent.eventType == ietKeyPressed:
        let selectedCommand = palette.getSelectedCommand()
        if selectedCommand.isSome and palette.onCommandSelected != nil:
          palette.onCommandSelected(palette, selectedCommand.get())
        palette.hide()
        return true
    
    of ekUp:
      if keyEvent.eventType == ietKeyPressed:
        if palette.selectedIndex > 0:
          palette.selectedIndex -= 1
          palette.isDirty = true
          palette.componentManager.markComponentDirty(palette.id)
        return true
    
    of ekDown:
      if keyEvent.eventType == ietKeyPressed:
        if palette.selectedIndex < palette.filteredCommands.len - 1:
          palette.selectedIndex += 1
          palette.isDirty = true
          palette.componentManager.markComponentDirty(palette.id)
        return true
    
    of ekBackspace:
      if keyEvent.eventType == ietKeyPressed:
        if palette.searchText.len > 0:
          palette.searchText = palette.searchText[0..^2]
          palette.filterCommands()
        return true
    
    else:
      # Handle character input
      if keyEvent.eventType == ietCharInput and keyEvent.character.ord >= 32 and keyEvent.character.ord <= 126:
        palette.searchText.add(char(keyEvent.character.ord))
        palette.filterCommands()
        return true
  
  of uiekMouse:
    # Handle mouse events if needed
    return false
  
  of uiekCombined:
    # Handle combined events if needed
    return false
  
  return false

# Get the currently selected command
proc getSelectedCommand*(palette: CommandPalette): Option[CommandPaletteItem] =
  if palette.selectedIndex < palette.filteredCommands.len:
    some(palette.filteredCommands[palette.selectedIndex])
  else:
    none(CommandPaletteItem)

# Update dimensions based on viewport
proc updateDimensions*(palette: CommandPalette) =
  let viewport = palette.componentManager.uiService.getViewport()
  palette.paletteWidth = min(600.0, viewport.width * 0.8)
  palette.paletteHeight = min(400.0, viewport.height * 0.6)
  
  # Update bounds if visible
  if palette.isVisible:
    let paletteX = (viewport.width - palette.paletteWidth) / 2
    let paletteY = (viewport.height - palette.paletteHeight) / 2
    
    let newBounds = rl.Rectangle(
      x: paletteX,
      y: paletteY,
      width: palette.paletteWidth,
      height: palette.paletteHeight
    )
    
    discard palette.componentManager.updateComponentBounds(palette.id, newBounds)

# Render the command palette using standardized rendering
proc render*(palette: CommandPalette) =
  ## Render the command palette using ComponentManager's renderer and theme
  if not palette.isVisible:
    return

  # Using ComponentManager's renderer and theme directly
  
  # Get current bounds
  let bounds = palette.bounds
  let paletteX = bounds.x
  let paletteY = bounds.y
  let paletteWidth = bounds.width
  let paletteHeight = bounds.height

  # Draw semi-transparent overlay
  let viewport = palette.componentManager.uiService.getViewport()
  rl.drawRectangle(
    0,
    0,
    viewport.width.int32,
    viewport.height.int32,
    rl.Color(r: 0, g: 0, b: 0, a: 128),
  )

  # Draw palette background using theme colors
  rl.drawRectangleRounded(
    rl.Rectangle(x: paletteX, y: paletteY, width: paletteWidth, height: paletteHeight),
    0.1,
    16,
    palette.componentManager.getUIColor(uiSidebar),
  )

  # Draw border using theme colors
  rl.drawRectangleRoundedLines(
    rl.Rectangle(x: paletteX, y: paletteY, width: paletteWidth, height: paletteHeight),
    0.1,
    16,
    2.0,
    palette.componentManager.getUIColor(uiText),
  )

  # Draw search box
  let searchBoxY = paletteY + 20
  rl.drawRectangleRounded(
    rl.Rectangle(
      x: paletteX + 20, 
      y: searchBoxY, 
      width: paletteWidth - 40, 
      height: palette.searchBoxHeight
    ),
    0.1,
    8,
    palette.componentManager.getUIColor(uiBackground),
  )

  # Draw search text with placeholder
  let searchText =
    if palette.searchText.len > 0:
      palette.searchText
    else:
      "Type to search commands..."
  
  let textColor =
    if palette.searchText.len > 0:
      palette.componentManager.getUIColor(uiText)
    else:
      palette.componentManager.themeManager.getSyntaxColor(synComment)

  # Use renderer's font system
  rl.drawText(
    searchText,
    (paletteX + 30).int32,
    (searchBoxY + 12).int32,
    16,
    textColor,
  )

  # Draw cursor in search box
  if palette.searchText.len > 0:
    let textWidth = rl.measureText(palette.searchText, 16)
    rl.drawRectangle(
      (paletteX + 30 + textWidth.float32).int32,
      (searchBoxY + 10).int32,
      2,
      20,
      palette.componentManager.getUIColor(uiCursor),
    )

  # Draw command list
  let listY = searchBoxY + palette.searchBoxHeight + 20
  let maxItems = min(
    palette.maxVisibleItems,
    ((paletteHeight - (listY - paletteY) - 20) / palette.itemHeight).int,
  )

  for i in 0 ..< min(maxItems, palette.filteredCommands.len):
    let cmd = palette.filteredCommands[i]
    let itemY = listY + i.float32 * palette.itemHeight
    let isSelected = i == palette.selectedIndex

    # Draw selection background using theme colors
    if isSelected:
      rl.drawRectangleRounded(
        rl.Rectangle(
          x: paletteX + 10, 
          y: itemY, 
          width: paletteWidth - 20, 
          height: palette.itemHeight
        ),
        0.1,
        8,
        palette.componentManager.getUIColor(uiSelection),
      )

    # Draw command name using theme colors
    rl.drawText(
      cmd.name, 
      (paletteX + 20).int32, 
      (itemY + 5).int32, 
      16, 
      palette.componentManager.getUIColor(uiText)
    )

    # Draw command description using theme colors
    rl.drawText(
      cmd.description,
      (paletteX + 20).int32,
      (itemY + 22).int32,
      12,
      palette.componentManager.themeManager.getSyntaxColor(synComment),
    )

    # Draw keybinding if available and enabled
    if palette.showKeybindings and cmd.keybinding.len > 0:
      let keybindingWidth = rl.measureText(cmd.keybinding, 12)
      rl.drawText(
        cmd.keybinding,
        (paletteX + paletteWidth - 20 - keybindingWidth.float32).int32,
        (itemY + 15).int32,
        12,
        palette.componentManager.themeManager.getSyntaxColor(synOperator),
      )

  # Mark as clean after rendering
  palette.isDirty = false

# Command management
proc addCommand*(palette: CommandPalette, command: CommandPaletteItem) =
  palette.allCommands.add(command)
  palette.filterCommands()

proc removeCommand*(palette: CommandPalette, commandName: string) =
  for i in countdown(palette.allCommands.high, 0):
    if palette.allCommands[i].name == commandName:
      palette.allCommands.delete(i)
      break
  palette.filterCommands()

proc clearCommands*(palette: CommandPalette) =
  palette.allCommands = @[]
  palette.filteredCommands = @[]
  palette.selectedIndex = 0
  palette.filterCommands()

# Cleanup
proc cleanup*(palette: CommandPalette) =
  ## Clean up resources and unregister from ComponentManager
  discard palette.componentManager.unregisterComponent(palette.id)
