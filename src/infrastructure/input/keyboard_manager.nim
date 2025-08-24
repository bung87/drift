## Keyboard Manager
## Handles keyboard shortcuts and focus management for the application

import std/[tables, options, hashes]
import std/strutils
import raylib as rl
# import ../../shared/types  # Unused import

type
  KeyModifier* = enum
    kmNone = 0,
    kmShift = 1,
    kmCtrl = 2,
    kmAlt = 4,
    kmSuper = 8  # Windows/Cmd key

  KeyCombination* = object
    key*: int32
    modifiers*: set[KeyModifier]

  ShortcutAction* = enum
    saToggleTerminal,
    saFocusEditor,
    saFocusTerminal,
    saNewTerminalSession,
    saCloseTerminalSession,
    saSwitchToNextSession,
    saSwitchToPrevSession,
    saClearTerminal,
    saScrollTerminalUp,
    saScrollTerminalDown,
    saCustom

  ShortcutEvent* = object
    action*: ShortcutAction
    combination*: KeyCombination
    customData*: string

  FocusableComponent* = enum
    fcNone,
    fcEditor,
    fcTerminal,
    fcExplorer,
    fcSearchPanel,
    fcStatusBar

  FocusManager* = ref object
    currentFocus*: FocusableComponent
    previousFocus*: FocusableComponent
    focusHistory*: seq[FocusableComponent]
    maxHistorySize*: int
    onFocusChanged*: proc(fromComponent: FocusableComponent, toComponent: FocusableComponent) {.closure.}

  KeyboardManager* = ref object
    shortcuts*: Table[KeyCombination, ShortcutAction]
    customShortcuts*: Table[KeyCombination, string]
    focusManager*: FocusManager
    onShortcut*: proc(event: ShortcutEvent) {.closure.}
    enabled*: bool
    captureMode*: bool  # When true, captures all input for shortcut recording

# Key combination utilities
proc `==`*(a, b: KeyCombination): bool =
  a.key == b.key and a.modifiers == b.modifiers

proc hash*(combo: KeyCombination): Hash =
  var h: Hash = 0
  h = h !& hash(combo.key)
  h = h !& hash(cast[int](combo.modifiers))
  result = !$h

proc newKeyCombination*(key: int32, modifiers: set[KeyModifier] = {}): KeyCombination =
  KeyCombination(key: key, modifiers: modifiers)

proc toString*(combo: KeyCombination): string =
  var parts: seq[string] = @[]
  
  if kmCtrl in combo.modifiers:
    parts.add("Ctrl")
  if kmShift in combo.modifiers:
    parts.add("Shift")
  if kmAlt in combo.modifiers:
    parts.add("Alt")
  if kmSuper in combo.modifiers:
    when defined(macosx):
      parts.add("Cmd")
    else:
      parts.add("Super")
  
  # Convert key code to readable string
  let keyName = case combo.key:
    of rl.KeyboardKey.Space.int32: "Space"
    of rl.KeyboardKey.Enter.int32: "Enter"
    of rl.KeyboardKey.Tab.int32: "Tab"
    of rl.KeyboardKey.Backspace.int32: "Backspace"
    of rl.KeyboardKey.Delete.int32: "Delete"
    of rl.KeyboardKey.Up.int32: "Up"
    of rl.KeyboardKey.Down.int32: "Down"
    of rl.KeyboardKey.Left.int32: "Left"
    of rl.KeyboardKey.Right.int32: "Right"
    of rl.KeyboardKey.Home.int32: "Home"
    of rl.KeyboardKey.End.int32: "End"
    of rl.KeyboardKey.PageUp.int32: "PageUp"
    of rl.KeyboardKey.PageDown.int32: "PageDown"
    of rl.KeyboardKey.Escape.int32: "Escape"
    of rl.KeyboardKey.F1.int32..rl.KeyboardKey.F12.int32: "F" & $(combo.key - rl.KeyboardKey.F1.int32 + 1)
    of 33..126: $char(combo.key)  # Printable ASCII (excluding Space, which is handled above)
    else: "Key" & $combo.key
  
  parts.add(keyName)
  return parts.join("+")

# Focus Manager
proc newFocusManager*(maxHistorySize: int = 10): FocusManager =
  FocusManager(
    currentFocus: fcNone,
    previousFocus: fcNone,
    focusHistory: @[],
    maxHistorySize: maxHistorySize,
    onFocusChanged: nil
  )

proc setFocus*(manager: FocusManager, component: FocusableComponent) =
  if manager.currentFocus == component:
    return
  
  let oldFocus = manager.currentFocus
  manager.previousFocus = manager.currentFocus
  manager.currentFocus = component
  
  # Update focus history
  if component != fcNone:
    # Remove component from history if it exists
    for i in countdown(manager.focusHistory.len - 1, 0):
      if manager.focusHistory[i] == component:
        manager.focusHistory.delete(i)
        break
    
    # Add to front of history
    manager.focusHistory.insert(component, 0)
    
    # Trim history if needed
    if manager.focusHistory.len > manager.maxHistorySize:
      manager.focusHistory.setLen(manager.maxHistorySize)
  
  # Notify callback
  if manager.onFocusChanged != nil:
    manager.onFocusChanged(oldFocus, component)

proc getCurrentFocus*(manager: FocusManager): FocusableComponent =
  manager.currentFocus

proc getPreviousFocus*(manager: FocusManager): FocusableComponent =
  manager.previousFocus

proc switchToPrevious*(manager: FocusManager) =
  if manager.previousFocus != fcNone:
    manager.setFocus(manager.previousFocus)

proc cycleFocus*(manager: FocusManager, components: seq[FocusableComponent]) =
  if components.len == 0:
    return
  
  let currentIndex = components.find(manager.currentFocus)
  let nextIndex = if currentIndex == -1: 0 else: (currentIndex + 1) mod components.len
  manager.setFocus(components[nextIndex])

# Keyboard Manager
proc registerDefaultShortcuts*(manager: KeyboardManager) =
  # Platform-specific modifier key
  when defined(macosx):
    let primaryModifier = kmSuper  # Use Cmd on macOS
  else:
    let primaryModifier = kmCtrl   # Use Ctrl on other platforms
  
  # Terminal shortcuts
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.Grave.int32, {primaryModifier})] = saToggleTerminal
  
  # Session management
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.T.int32, {primaryModifier, kmShift})] = saNewTerminalSession
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.W.int32, {primaryModifier, kmShift})] = saCloseTerminalSession
  
  # Navigation
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.Tab.int32, {primaryModifier})] = saSwitchToNextSession
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.Tab.int32, {primaryModifier, kmShift})] = saSwitchToPrevSession
  
  # Terminal actions
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.K.int32, {primaryModifier})] = saClearTerminal
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.PageUp.int32, {kmShift})] = saScrollTerminalUp
  manager.shortcuts[newKeyCombination(rl.KeyboardKey.PageDown.int32, {kmShift})] = saScrollTerminalDown

proc newKeyboardManager*(focusManager: FocusManager = nil): KeyboardManager =
  let fm = if focusManager != nil: focusManager else: newFocusManager()
  
  result = KeyboardManager(
    shortcuts: initTable[KeyCombination, ShortcutAction](),
    customShortcuts: initTable[KeyCombination, string](),
    focusManager: fm,
    onShortcut: nil,
    enabled: true,
    captureMode: false
  )
  
  # Register default shortcuts
  result.registerDefaultShortcuts()

proc registerShortcut*(manager: KeyboardManager, combination: KeyCombination, action: ShortcutAction) =
  manager.shortcuts[combination] = action

proc registerCustomShortcut*(manager: KeyboardManager, combination: KeyCombination, customData: string) =
  manager.customShortcuts[combination] = customData

proc unregisterShortcut*(manager: KeyboardManager, combination: KeyCombination) =
  manager.shortcuts.del(combination)
  manager.customShortcuts.del(combination)

proc getShortcut*(manager: KeyboardManager, action: ShortcutAction): Option[KeyCombination] =
  for combo, act in manager.shortcuts.pairs:
    if act == action:
      return some(combo)
  return none(KeyCombination)

proc getCurrentModifiers*(): set[KeyModifier] =
  result = {}
  if rl.isKeyDown(rl.KeyboardKey.LeftControl) or rl.isKeyDown(rl.KeyboardKey.RightControl):
    result.incl(kmCtrl)
  if rl.isKeyDown(rl.KeyboardKey.LeftShift) or rl.isKeyDown(rl.KeyboardKey.RightShift):
    result.incl(kmShift)
  if rl.isKeyDown(rl.KeyboardKey.LeftAlt) or rl.isKeyDown(rl.KeyboardKey.RightAlt):
    result.incl(kmAlt)
  if rl.isKeyDown(rl.KeyboardKey.LeftSuper) or rl.isKeyDown(rl.KeyboardKey.RightSuper):
    result.incl(kmSuper)

proc processKeyInput*(manager: KeyboardManager, key: int32): bool =
  if not manager.enabled:
    return false
  
  let modifiers = getCurrentModifiers()
  let combination = newKeyCombination(key, modifiers)
  
  # Check for registered shortcuts
  if combination in manager.shortcuts:
    let action = manager.shortcuts[combination]
    let event = ShortcutEvent(
      action: action,
      combination: combination,
      customData: ""
    )
    
    if manager.onShortcut != nil:
      manager.onShortcut(event)
    
    return true
  
  # Check for custom shortcuts
  if combination in manager.customShortcuts:
    let customData = manager.customShortcuts[combination]
    let event = ShortcutEvent(
      action: saCustom,
      combination: combination,
      customData: customData
    )
    
    if manager.onShortcut != nil:
      manager.onShortcut(event)
    
    return true
  
  return false

proc update*(manager: KeyboardManager) =
  if not manager.enabled:
    return
  
  # Process all pressed keys
  var key = rl.getKeyPressed()
  while key != rl.KeyboardKey.Null:
    discard manager.processKeyInput(key.int32)
    key = rl.getKeyPressed()

proc enable*(manager: KeyboardManager) =
  manager.enabled = true

proc disable*(manager: KeyboardManager) =
  manager.enabled = false

proc isEnabled*(manager: KeyboardManager): bool =
  manager.enabled

proc setCaptureMode*(manager: KeyboardManager, enabled: bool) =
  manager.captureMode = enabled

proc isCaptureMode*(manager: KeyboardManager): bool =
  manager.captureMode

# Focus management shortcuts
proc handleFocusShortcuts*(manager: KeyboardManager, key: int32): bool =
  let modifiers = getCurrentModifiers()
  
  # Platform-specific modifier key
  when defined(macosx):
    let primaryModifier = kmSuper  # Use Cmd on macOS
  else:
    let primaryModifier = kmCtrl   # Use Ctrl on other platforms
  
  # Handle common focus shortcuts
  case key:
  of rl.KeyboardKey.Tab.int32:
    if primaryModifier in modifiers:
      if kmShift in modifiers:
        # Cmd/Ctrl+Shift+Tab - Previous focus
        manager.focusManager.switchToPrevious()
      else:
        # Cmd/Ctrl+Tab - Cycle focus
        let components = @[fcEditor, fcTerminal, fcExplorer]
        manager.focusManager.cycleFocus(components)
      return true
  of rl.KeyboardKey.Escape.int32:
    # Escape - Return to editor
    manager.focusManager.setFocus(fcEditor)
    return true
  else:
    discard
  
  return false

# Shortcut description and help
proc getShortcutDescription*(action: ShortcutAction): string =
  case action:
  of saToggleTerminal: "Toggle terminal panel visibility"
  of saFocusEditor: "Focus the editor"
  of saFocusTerminal: "Focus the terminal"
  of saNewTerminalSession: "Create new terminal session"
  of saCloseTerminalSession: "Close current terminal session"
  of saSwitchToNextSession: "Switch to next terminal session"
  of saSwitchToPrevSession: "Switch to previous terminal session"
  of saClearTerminal: "Clear terminal output"
  of saScrollTerminalUp: "Scroll terminal up"
  of saScrollTerminalDown: "Scroll terminal down"
  of saCustom: "Custom shortcut"

proc getAllShortcuts*(manager: KeyboardManager): seq[(KeyCombination, ShortcutAction, string)] =
  result = @[]
  for combo, action in manager.shortcuts.pairs:
    result.add((combo, action, getShortcutDescription(action)))

proc getShortcutsForComponent*(manager: KeyboardManager, component: FocusableComponent): seq[(KeyCombination, ShortcutAction, string)] =
  result = @[]
  for combo, action in manager.shortcuts.pairs:
    case component:
    of fcTerminal:
      if action in [saToggleTerminal, saNewTerminalSession, saCloseTerminalSession, 
                    saSwitchToNextSession, saSwitchToPrevSession, saClearTerminal,
                    saScrollTerminalUp, saScrollTerminalDown]:
        result.add((combo, action, getShortcutDescription(action)))
    of fcEditor:
      if action in [saToggleTerminal, saFocusTerminal]:
        result.add((combo, action, getShortcutDescription(action)))
    else:
      if action in [saToggleTerminal, saFocusEditor, saFocusTerminal]:
        result.add((combo, action, getShortcutDescription(action)))

# Utility functions for component name conversion
proc toString*(component: FocusableComponent): string =
  case component:
  of fcNone: "None"
  of fcEditor: "Editor"
  of fcTerminal: "Terminal"
  of fcExplorer: "Explorer"
  of fcSearchPanel: "Search Panel"
  of fcStatusBar: "Status Bar"

proc fromString*(s: string): FocusableComponent =
  case s.toLower():
  of "editor": fcEditor
  of "terminal": fcTerminal
  of "explorer": fcExplorer
  of "search panel", "searchpanel": fcSearchPanel
  of "status bar", "statusbar": fcStatusBar
  else: fcNone