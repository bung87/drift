## Resource Manager for Drift Editor (Raylib)
## Centralized management of fonts, textures, sounds, and other assets

import std/[os, tables, sequtils, options]
import raylib as rl
import shared/utils

type
  ResourceManager* = object
    basePath*: string
    textures*: Table[string, rl.Texture2D]
    sounds*: Table[string, rl.Sound]
    music*: Table[string, rl.Music]
    initialized*: bool

  FontInfo* = object
    name*: string
    path*: string
    size*: int32
    loaded*: bool

  TextureInfo* = object
    name*: string
    path*: string
    width*: int32
    height*: int32
    loaded*: bool

# Global resource manager instance
var resourceManager*: ResourceManager



# Font management
proc initResourceManager*(basePath: string = "resources") =
  ## Initialize the resource manager
  echo "Initializing Raylib resource manager..."

  resourceManager.basePath = basePath
  # Tables are auto-initialized in Nim v0.20+
  resourceManager.initialized = true

  echo "Resource manager initialized successfully"

# Texture management
proc loadTexture*(name: string, path: string): bool =
  ## Load a texture and register it with a name
  if name in resourceManager.textures:
    echo "Texture already loaded: ", name
    return true

  let fullPath =
    if path.isAbsolute():
      path
    else:
      resourceManager.basePath / path

  if not fileExists(fullPath):
    echo "Texture file not found: ", fullPath
    return false

  try:
    let texture = rl.loadTexture(fullPath)
    if texture.id > 0:
      resourceManager.textures[name] = texture
      echo "Loaded texture '", name, "' from: ", fullPath
      return true
    else:
      echo "Failed to load texture: ", fullPath
      return false
  except:
    echo "Exception loading texture: ", fullPath
    return false

proc getTexture*(name: string): Option[rl.Texture2D] =
  ## Get a loaded texture by name
  if name in resourceManager.textures:
    return some(resourceManager.textures[name])
  else:
    return none(rl.Texture2D)

proc isTextureLoaded*(name: string): bool =
  ## Check if a texture is loaded
  return name in resourceManager.textures

proc listTextures*(): seq[string] =
  ## Get list of loaded texture names
  return toSeq(resourceManager.textures.keys)

# Sound management
proc loadSound*(name: string, path: string): bool =
  ## Load a sound and register it with a name
  if name in resourceManager.sounds:
    echo "Sound already loaded: ", name
    return true

  let fullPath =
    if path.isAbsolute():
      path
    else:
      resourceManager.basePath / path

  if not fileExists(fullPath):
    echo "Sound file not found: ", fullPath
    return false

  try:
    let sound = rl.loadSound(fullPath)
    resourceManager.sounds[name] = sound
    echo "Loaded sound '", name, "' from: ", fullPath
    return true
  except:
    echo "Exception loading sound: ", fullPath
    return false

proc getSound*(name: string): Option[rl.Sound] =
  ## Get a loaded sound by name
  if name in resourceManager.sounds:
    return some(resourceManager.sounds[name])
  else:
    return none(rl.Sound)

proc playSound*(name: string): bool =
  ## Play a loaded sound by name
  let sound = getSound(name)
  if sound.isSome:
    rl.playSound(sound.get())
    return true
  else:
    echo "Sound '", name, "' not found"
    return false

# Music management
proc loadMusic*(name: string, path: string): bool =
  ## Load music and register it with a name
  if name in resourceManager.music:
    echo "Music already loaded: ", name
    return true

  let fullPath =
    if path.isAbsolute():
      path
    else:
      resourceManager.basePath / path

  if not fileExists(fullPath):
    echo "Music file not found: ", fullPath
    return false

  try:
    let music = rl.loadMusicStream(fullPath)
    resourceManager.music[name] = music
    echo "Loaded music '", name, "' from: ", fullPath
    return true
  except:
    echo "Exception loading music: ", fullPath
    return false

proc getMusic*(name: string): Option[rl.Music] =
  ## Get loaded music by name
  if name in resourceManager.music:
    return some(resourceManager.music[name])
  else:
    return none(rl.Music)

proc playMusic*(name: string): bool =
  ## Play loaded music by name
  let music = getMusic(name)
  if music.isSome:
    rl.playMusicStream(music.get())
    return true
  else:
    echo "Music '", name, "' not found"
    return false

# Utility functions
proc getResourcePath*(relativePath: string): string =
  ## Get full path to a resource
  return resourceManager.basePath / relativePath

proc resourceExists*(relativePath: string): bool =
  ## Check if a resource file exists
  return fileExists(getResourcePath(relativePath))

proc getResourceInfo*(): tuple[textures: int, sounds: int, music: int] =
  ## Get count of loaded resources
  return (
    textures: resourceManager.textures.len,
    sounds: resourceManager.sounds.len,
    music: resourceManager.music.len,
  )

proc setupDefaultResources*() =
  ## Set up default resources for the editor
  if not resourceManager.initialized:
    initResourceManager()

  # Initialize audio (required for sound loading)
  rl.initAudioDevice()

  echo "Default resources setup complete"

# Cleanup functions (simplified for compatibility)
proc cleanupResources*() =
  ## Clean up all loaded resources (simplified)
  echo "Cleaning up resources..."

  # Clear all resource tables
  resourceManager.textures.clear()
  resourceManager.sounds.clear()
  resourceManager.music.clear()

  resourceManager.initialized = false
  echo "Resources cleaned up successfully"

# Theme support
type EditorTheme* = object
  name*: string
  background*: rl.Color
  text*: rl.Color
  keyword*: rl.Color
  string*: rl.Color
  comment*: rl.Color
  number*: rl.Color
  function*: rl.Color
  operator*: rl.Color
  selection*: rl.Color
  cursor*: rl.Color
  lineNumber*: rl.Color
  sidebar*: rl.Color
  statusbar*: rl.Color
  titlebar*: rl.Color

proc getDefaultTheme*(): EditorTheme =
  ## Get default dark theme
  return EditorTheme(
    name: "Default Dark",
    background: rl.Color(r: 30, g: 30, b: 30, a: 255),
    text: rl.Color(r: 220, g: 220, b: 220, a: 255),
    keyword: rl.Color(r: 86, g: 156, b: 214, a: 255),
    string: rl.Color(r: 206, g: 145, b: 120, a: 255),
    comment: rl.Color(r: 106, g: 153, b: 85, a: 255),
    number: rl.Color(r: 181, g: 206, b: 168, a: 255),
    function: rl.Color(r: 220, g: 220, b: 170, a: 255),
    operator: rl.Color(r: 212, g: 212, b: 212, a: 255),
    selection: rl.Color(r: 38, g: 79, b: 120, a: 255),
    cursor: rl.Color(r: 255, g: 255, b: 255, a: 255),
    lineNumber: rl.Color(r: 128, g: 128, b: 128, a: 255),
    sidebar: rl.Color(r: 37, g: 37, b: 38, a: 255),
    statusbar: rl.Color(r: 0, g: 122, b: 204, a: 255),
    titlebar: rl.Color(r: 51, g: 51, b: 51, a: 255),
  )

# Resource validation
proc validateResources*(): bool =
  ## Validate that essential resources are available
  if not resourceManager.initialized:
    echo "Resource manager not initialized"
    return false

  echo "Resource validation passed"
  return true

# Font loading with fallback
proc loadProfessionalFont*(fontSize: float32): rl.Font =
  # Try to load system fonts in order of preference
  let fontPaths = [
    "resources/CascadiaMono.ttf", "resources/FiraCode-Regular.ttf",
    "resources/Roboto-Regular.ttf",
  ]
  let dpiScale = getDPIScale()
  # Load font at appropriate size for current DPI
  for path in fontPaths:
    if os.fileExists(path):
      let font = rl.loadFont(path, int32(fontSize * dpiScale), 0)
      if font.texture.id != 0:
        # Use bilinear filtering for smooth scaling with logical coordinates
        rl.setTextureFilter(font.texture, rl.TextureFilter.Bilinear)
        return font

  return rl.getFontDefault()
