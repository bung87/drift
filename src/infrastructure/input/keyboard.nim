## Keyboard input abstraction for Drift editor
## Provides clean interface for keyboard handling without Raylib dependencies

import raylib as rl
import std/[tables, strutils, unicode]
import ../../shared/[constants, utils]

# Key enumeration for editor operations
type EditorKey* = enum
  # Special keys
  ekNone = "none"
  ekEscape = "escape"
  ekEnter = "enter"
  ekTab = "tab"
  ekBackspace = "backspace"
  ekDelete = "delete"
  ekSpace = "space"

  # Navigation keys
  ekLeft = "left"
  ekRight = "right"
  ekUp = "up"
  ekDown = "down"
  ekHome = "home"
  ekEnd = "end"
  ekPageUp = "page_up"
  ekPageDown = "page_down"

  # Function keys
  ekF1 = "f1"
  ekF2 = "f2"
  ekF3 = "f3"
  ekF4 = "f4"
  ekF5 = "f5"
  ekF6 = "f6"
  ekF7 = "f7"
  ekF8 = "f8"
  ekF9 = "f9"
  ekF10 = "f10"
  ekF11 = "f11"
  ekF12 = "f12"

  # Number keys
  ekNum0 = "0"
  ekNum1 = "1"
  ekNum2 = "2"
  ekNum3 = "3"
  ekNum4 = "4"
  ekNum5 = "5"
  ekNum6 = "6"
  ekNum7 = "7"
  ekNum8 = "8"
  ekNum9 = "9"

  # Letter keys
  ekA = "a"
  ekB = "b"
  ekC = "c"
  ekD = "d"
  ekE = "e"
  ekF = "f"
  ekG = "g"
  ekH = "h"
  ekI = "i"
  ekJ = "j"
  ekK = "k"
  ekL = "l"
  ekM = "m"
  ekN = "n"
  ekO = "o"
  ekP = "p"
  ekQ = "q"
  ekR = "r"
  ekS = "s"
  ekT = "t"
  ekU = "u"
  ekV = "v"
  ekW = "w"
  ekX = "x"
  ekY = "y"
  ekZ = "z"

  # Symbol keys
  ekMinus = "minus"
  ekEquals = "equals"
  ekLeftBracket = "left_bracket"
  ekRightBracket = "right_bracket"
  ekBackslash = "backslash"
  ekSemicolon = "semicolon"
  ekQuote = "quote"
  ekComma = "comma"
  ekPeriod = "period"
  ekSlash = "slash"
  ekGrave = "grave"

# Modifier keys
type ModifierKey* = enum
  mkNone = "none"
  mkShift = "shift"
  mkCtrl = "ctrl"
  mkAlt = "alt"
  mkSuper = "super" # Windows/Cmd key

# Key combination
type KeyCombination* = object
  key*: EditorKey
  modifiers*: set[ModifierKey]

# Input event types
type InputEventType* = enum
  ietKeyPressed = "key_pressed"
  ietKeyReleased = "key_released"
  ietCharInput = "char_input"
  ietKeyRepeat = "key_repeat"

# Input event
type InputEvent* = object
  eventType*: InputEventType
  key*: EditorKey
  modifiers*: set[ModifierKey]
  character*: Rune
  timestamp*: float

# Key state tracking
type KeyState* = object
  isPressed*: bool
  pressTime*: float
  lastRepeatTime*: float
  repeatCount*: int

# Keyboard handler
type KeyboardHandler* = ref object
  keyStates*: Table[EditorKey, KeyState]
  pressedKeys*: set[EditorKey]
  activeModifiers*: set[ModifierKey]
  eventQueue*: seq[InputEvent]
  lastInputTime*: float
  keyRepeatEnabled*: bool
  keyRepeatDelay*: float
  keyRepeatRate*: float

# Raylib to EditorKey mapping
const RaylibKeyMap = {
  rl.KeyboardKey.Null: ekNone,
  rl.KeyboardKey.Escape: ekEscape,
  rl.KeyboardKey.Enter: ekEnter,
  rl.KeyboardKey.Tab: ekTab,
  rl.KeyboardKey.Backspace: ekBackspace,
  rl.KeyboardKey.Delete: ekDelete,
  rl.KeyboardKey.Space: ekSpace,
  rl.KeyboardKey.Left: ekLeft,
  rl.KeyboardKey.Right: ekRight,
  rl.KeyboardKey.Up: ekUp,
  rl.KeyboardKey.Down: ekDown,
  rl.KeyboardKey.Home: ekHome,
  rl.KeyboardKey.End: ekEnd,
  rl.KeyboardKey.PageUp: ekPageUp,
  rl.KeyboardKey.PageDown: ekPageDown,
  rl.KeyboardKey.F1: ekF1,
  rl.KeyboardKey.F2: ekF2,
  rl.KeyboardKey.F3: ekF3,
  rl.KeyboardKey.F4: ekF4,
  rl.KeyboardKey.F5: ekF5,
  rl.KeyboardKey.F6: ekF6,
  rl.KeyboardKey.F7: ekF7,
  rl.KeyboardKey.F8: ekF8,
  rl.KeyboardKey.F9: ekF9,
  rl.KeyboardKey.F10: ekF10,
  rl.KeyboardKey.F11: ekF11,
  rl.KeyboardKey.F12: ekF12,
  rl.KeyboardKey.Zero: ekNum0,
  rl.KeyboardKey.One: ekNum1,
  rl.KeyboardKey.Two: ekNum2,
  rl.KeyboardKey.Three: ekNum3,
  rl.KeyboardKey.Four: ekNum4,
  rl.KeyboardKey.Five: ekNum5,
  rl.KeyboardKey.Six: ekNum6,
  rl.KeyboardKey.Seven: ekNum7,
  rl.KeyboardKey.Eight: ekNum8,
  rl.KeyboardKey.Nine: ekNum9,
  rl.KeyboardKey.A: ekA,
  rl.KeyboardKey.B: ekB,
  rl.KeyboardKey.C: ekC,
  rl.KeyboardKey.D: ekD,
  rl.KeyboardKey.E: ekE,
  rl.KeyboardKey.F: ekF,
  rl.KeyboardKey.G: ekG,
  rl.KeyboardKey.H: ekH,
  rl.KeyboardKey.I: ekI,
  rl.KeyboardKey.J: ekJ,
  rl.KeyboardKey.K: ekK,
  rl.KeyboardKey.L: ekL,
  rl.KeyboardKey.M: ekM,
  rl.KeyboardKey.N: ekN,
  rl.KeyboardKey.O: ekO,
  rl.KeyboardKey.P: ekP,
  rl.KeyboardKey.Q: ekQ,
  rl.KeyboardKey.R: ekR,
  rl.KeyboardKey.S: ekS,
  rl.KeyboardKey.T: ekT,
  rl.KeyboardKey.U: ekU,
  rl.KeyboardKey.V: ekV,
  rl.KeyboardKey.W: ekW,
  rl.KeyboardKey.X: ekX,
  rl.KeyboardKey.Y: ekY,
  rl.KeyboardKey.Z: ekZ,
  rl.KeyboardKey.Minus: ekMinus,
  rl.KeyboardKey.Equal: ekEquals,
  rl.KeyboardKey.LeftBracket: ekLeftBracket,
  rl.KeyboardKey.RightBracket: ekRightBracket,
  rl.KeyboardKey.Backslash: ekBackslash,
  rl.KeyboardKey.Semicolon: ekSemicolon,
  rl.KeyboardKey.Apostrophe: ekQuote,
  rl.KeyboardKey.Comma: ekComma,
  rl.KeyboardKey.Period: ekPeriod,
  rl.KeyboardKey.Slash: ekSlash,
  rl.KeyboardKey.Grave: ekGrave,
}.toTable

# Constructor
proc newKeyboardHandler*(): KeyboardHandler =
  result = KeyboardHandler(
    keyStates: initTable[EditorKey, KeyState](),
    pressedKeys: {},
    activeModifiers: {},
    eventQueue: @[],
    lastInputTime: 0.0,
    keyRepeatEnabled: true,
    keyRepeatDelay: KEY_REPEAT_DELAY,
    keyRepeatRate: KEY_REPEAT_RATE,
  )

# Key mapping utilities
proc toEditorKey*(raylibKey: rl.KeyboardKey): EditorKey =
  if raylibKey in RaylibKeyMap:
    return RaylibKeyMap[raylibKey]
  return ekNone

proc getCurrentModifiers*(): set[ModifierKey] =
  result = {}
  if rl.isKeyDown(rl.KeyboardKey.LeftShift) or rl.isKeyDown(rl.KeyboardKey.RightShift):
    result.incl(mkShift)
  if rl.isKeyDown(rl.KeyboardKey.LeftControl) or
      rl.isKeyDown(rl.KeyboardKey.RightControl):
    result.incl(mkCtrl)
  if rl.isKeyDown(rl.KeyboardKey.LeftAlt) or rl.isKeyDown(rl.KeyboardKey.RightAlt):
    result.incl(mkAlt)
  if rl.isKeyDown(rl.KeyboardKey.LeftSuper) or rl.isKeyDown(rl.KeyboardKey.RightSuper):
    result.incl(mkSuper)

# Key combination utilities
proc newKeyCombination*(
    key: EditorKey, modifiers: set[ModifierKey] = {}
): KeyCombination =
  KeyCombination(key: key, modifiers: modifiers)

proc `$`*(combo: KeyCombination): string =
  var parts: seq[string] = @[]

  if mkCtrl in combo.modifiers:
    parts.add("Ctrl")
  if mkAlt in combo.modifiers:
    parts.add("Alt")
  if mkShift in combo.modifiers:
    parts.add("Shift")
  if mkSuper in combo.modifiers:
    when defined(macosx):
      parts.add("Cmd")
    else:
      parts.add("Super")

  parts.add($combo.key)
  return parts.join("+")

proc `==`*(a, b: KeyCombination): bool =
  a.key == b.key and a.modifiers == b.modifiers

proc matches*(
    combo: KeyCombination, key: EditorKey, modifiers: set[ModifierKey]
): bool =
  combo.key == key and combo.modifiers == modifiers

# Input event creation
proc newInputEvent*(
    eventType: InputEventType,
    key: EditorKey,
    modifiers: set[ModifierKey] = {},
    character: Rune = Rune(0),
): InputEvent =
  InputEvent(
    eventType: eventType,
    key: key,
    modifiers: modifiers,
    character: character,
    timestamp: getCurrentTimestamp(),
  )

# Handler state management
proc updateKeyState*(
    handler: KeyboardHandler, key: EditorKey, isPressed: bool, currentTime: float
) =
  if key notin handler.keyStates:
    handler.keyStates[key] = KeyState()

  var state = handler.keyStates[key]
  let wasPressed = state.isPressed

  state.isPressed = isPressed

  if isPressed and not wasPressed:
    # Key just pressed
    state.pressTime = currentTime
    state.lastRepeatTime = currentTime
    state.repeatCount = 0
    handler.pressedKeys.incl(key)
  elif not isPressed and wasPressed:
    # Key just released
    state.repeatCount = 0
    handler.pressedKeys.excl(key)

  handler.keyStates[key] = state

proc processInput*(handler: KeyboardHandler): seq[InputEvent] =
  ## Process all keyboard input and return events
  result = @[]
  let currentTime = getCurrentTimestamp()
  let currentModifiers = getCurrentModifiers()
  handler.activeModifiers = currentModifiers

  # Check for newly pressed keys
  # Iterate through common keyboard keys we care about
  let keysToCheck = [
    rl.KeyboardKey.A, rl.KeyboardKey.B, rl.KeyboardKey.C, rl.KeyboardKey.D,
    rl.KeyboardKey.E, rl.KeyboardKey.F, rl.KeyboardKey.G, rl.KeyboardKey.H,
    rl.KeyboardKey.I, rl.KeyboardKey.J, rl.KeyboardKey.K, rl.KeyboardKey.L,
    rl.KeyboardKey.M, rl.KeyboardKey.N, rl.KeyboardKey.O, rl.KeyboardKey.P,
    rl.KeyboardKey.Q, rl.KeyboardKey.R, rl.KeyboardKey.S, rl.KeyboardKey.T,
    rl.KeyboardKey.U, rl.KeyboardKey.V, rl.KeyboardKey.W, rl.KeyboardKey.X,
    rl.KeyboardKey.Y, rl.KeyboardKey.Z, rl.KeyboardKey.Zero, rl.KeyboardKey.One,
    rl.KeyboardKey.Two, rl.KeyboardKey.Three, rl.KeyboardKey.Four, rl.KeyboardKey.Five,
    rl.KeyboardKey.Six, rl.KeyboardKey.Seven, rl.KeyboardKey.Eight, rl.KeyboardKey.Nine,
    rl.KeyboardKey.Space, rl.KeyboardKey.Enter, rl.KeyboardKey.Tab,
    rl.KeyboardKey.Backspace, rl.KeyboardKey.Delete, rl.KeyboardKey.Right,
    rl.KeyboardKey.Left, rl.KeyboardKey.Down, rl.KeyboardKey.Up, rl.KeyboardKey.PageUp,
    rl.KeyboardKey.PageDown, rl.KeyboardKey.Home, rl.KeyboardKey.End,
    rl.KeyboardKey.CapsLock, rl.KeyboardKey.ScrollLock, rl.KeyboardKey.NumLock,
    rl.KeyboardKey.PrintScreen, rl.KeyboardKey.Pause, rl.KeyboardKey.F1,
    rl.KeyboardKey.F2, rl.KeyboardKey.F3, rl.KeyboardKey.F4, rl.KeyboardKey.F5,
    rl.KeyboardKey.F6, rl.KeyboardKey.F7, rl.KeyboardKey.F8, rl.KeyboardKey.F9,
    rl.KeyboardKey.F10, rl.KeyboardKey.F11, rl.KeyboardKey.F12,
    rl.KeyboardKey.LeftShift, rl.KeyboardKey.LeftControl, rl.KeyboardKey.LeftAlt,
    rl.KeyboardKey.LeftSuper, rl.KeyboardKey.RightShift, rl.KeyboardKey.RightControl,
    rl.KeyboardKey.RightAlt, rl.KeyboardKey.RightSuper, rl.KeyboardKey.Escape,
  ]

  for raylibKey in keysToCheck:
    if rl.isKeyPressed(raylibKey):
      let editorKey = toEditorKey(raylibKey)
      if editorKey != ekNone:
        handler.updateKeyState(editorKey, true, currentTime)
        result.add(newInputEvent(ietKeyPressed, editorKey, currentModifiers))
        handler.lastInputTime = currentTime

  # Check for newly released keys
  for raylibKey in keysToCheck:
    if rl.isKeyReleased(raylibKey):
      let editorKey = toEditorKey(raylibKey)
      if editorKey != ekNone:
        handler.updateKeyState(editorKey, false, currentTime)
        result.add(newInputEvent(ietKeyReleased, editorKey, currentModifiers))

  # Handle key repeats
  if handler.keyRepeatEnabled:
    for key in handler.pressedKeys:
      if key in handler.keyStates:
        var state = handler.keyStates[key]
        let timeSincePress = currentTime - state.pressTime
        let timeSinceLastRepeat = currentTime - state.lastRepeatTime

        if timeSincePress >= handler.keyRepeatDelay:
          if timeSinceLastRepeat >= handler.keyRepeatRate:
            state.lastRepeatTime = currentTime
            state.repeatCount += 1
            handler.keyStates[key] = state
            result.add(newInputEvent(ietKeyRepeat, key, currentModifiers))

  # Handle character input
  let charPressed = rl.getCharPressed()
  if charPressed != 0:
    let character = Rune(charPressed)
    if charPressed >= 32 and charPressed <= 126: # Basic ASCII printable characters
      result.add(newInputEvent(ietCharInput, ekNone, currentModifiers, character))
      handler.lastInputTime = currentTime

proc isKeyPressed*(handler: KeyboardHandler, key: EditorKey): bool =
  key in handler.pressedKeys

proc isKeyJustPressed*(handler: KeyboardHandler, key: EditorKey): bool =
  if key in handler.keyStates:
    let state = handler.keyStates[key]
    return state.isPressed and state.repeatCount == 0
  return false

proc isKeyJustReleased*(handler: KeyboardHandler, key: EditorKey): bool =
  if key in handler.keyStates:
    let state = handler.keyStates[key]
    return not state.isPressed
  return false

proc getKeyRepeatCount*(handler: KeyboardHandler, key: EditorKey): int =
  if key in handler.keyStates:
    return handler.keyStates[key].repeatCount
  return 0

proc hasModifier*(handler: KeyboardHandler, modifier: ModifierKey): bool =
  modifier in handler.activeModifiers

proc hasAnyModifier*(handler: KeyboardHandler): bool =
  handler.activeModifiers.len > 0

proc getActiveModifiers*(handler: KeyboardHandler): set[ModifierKey] =
  handler.activeModifiers

# Key combination checking
proc checkKeyCombination*(handler: KeyboardHandler, combo: KeyCombination): bool =
  ## Check if a specific key combination is currently active
  if not handler.isKeyPressed(combo.key):
    return false

  # Check that all required modifiers are active
  for modifier in combo.modifiers:
    if modifier notin handler.activeModifiers:
      return false

  # Check that no extra modifiers are active (exact match)
  for modifier in handler.activeModifiers:
    if modifier notin combo.modifiers:
      return false

  return true

proc checkKeyCombinationJustPressed*(
    handler: KeyboardHandler, combo: KeyCombination
): bool =
  ## Check if a key combination was just pressed
  if not handler.isKeyJustPressed(combo.key):
    return false

  return combo.modifiers == handler.activeModifiers

# Input validation
proc isTextInputKey*(key: EditorKey): bool =
  ## Check if key produces text input
  case key
  of ekA .. ekZ, ekNum0 .. ekNum9, ekSpace, ekMinus .. ekGrave: true
  else: false

proc isNavigationKey*(key: EditorKey): bool =
  ## Check if key is used for navigation
  case key
  of ekLeft, ekRight, ekUp, ekDown, ekHome, ekEnd, ekPageUp, ekPageDown: true
  else: false

proc isModifierKey*(key: EditorKey): bool =
  ## Check if key is a modifier (handled separately)
  false # Modifiers are handled via getCurrentModifiers()

proc isFunctionKey*(key: EditorKey): bool =
  ## Check if key is a function key
  case key
  of ekF1 .. ekF12: true
  else: false

# Character utilities
proc isValidTextCharacter*(character: Rune): bool =
  ## Check if character is valid for text input
  let codepoint = character.int32
  if codepoint <= 0 or codepoint > 0x10FFFF:
    return false

  # Reject control characters except tab and newline
  if codepoint < 32 and codepoint != 9 and codepoint != 10:
    return false

  # Reject DEL character
  if codepoint == 127:
    return false

  return true

proc isPrintableCharacter*(character: Rune): bool =
  ## Check if character is printable
  let codepoint = character.int32
  if codepoint <= 0 or codepoint > 0x10FFFF:
    return false

  return codepoint >= 32 and codepoint != 127

# Debug utilities
proc getKeyStateDebug*(handler: KeyboardHandler): string =
  ## Get debug string of current key states
  var parts: seq[string] = @[]

  if handler.pressedKeys.len > 0:
    parts.add("Pressed: " & $handler.pressedKeys)

  if handler.activeModifiers.len > 0:
    parts.add("Modifiers: " & $handler.activeModifiers)

  if parts.len == 0:
    return "No keys pressed"

  return parts.join(", ")

# Configuration
proc setKeyRepeatEnabled*(handler: KeyboardHandler, enabled: bool) =
  handler.keyRepeatEnabled = enabled

proc setKeyRepeatTiming*(handler: KeyboardHandler, delay: float, rate: float) =
  handler.keyRepeatDelay = delay
  handler.keyRepeatRate = rate

proc clearKeyStates*(handler: KeyboardHandler) =
  ## Clear all key states (useful when window loses focus)
  handler.keyStates.clear()
  handler.pressedKeys = {}
  handler.activeModifiers = {}
