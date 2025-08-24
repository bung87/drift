## Merged Icon Drawing and Integration Functions for Drift Editor
## This file combines icon_integration.nim and icons.nim

import raylib as rl
from raylib import drawTexture, Rectangle, Vector2, White
import svg_rasterizer
import pixie
import std/[os, tables, options]

# Texture cache for loaded SVG icons - following naylib best practices
var textureCache = initTable[string, (ref Texture2D, int32, int32)]()

# Private helper for consistent icon scaling
type IconMetrics = object
  x, y, size: int32
  thickness: float32

proc getIconMetrics(x, y: float32): IconMetrics =
  let baseSize = 12.0
  # Use logical coordinates directly - Raylib handles DPI scaling automatically
  return IconMetrics(
    x: x.int32, y: y.int32, size: baseSize.int32, thickness: max(1.0, baseSize * 0.1)
  )

const ResourcesDir = currentSourcePath.parentDir.parentDir / "resources"

proc getCachedRasterizedTexture(filepath: string, size: int32 = ICON_SIZE_SMALL,
    tint: rl.Color = rl.WHITE): Option[(ref Texture2D, int32, int32)] =
  ## Get rasterized texture from cache or create and cache it
  let cacheKey = filepath & "_raster_" & $size & "_" & $tint.r & "_" & $tint.g &
      "_" & $tint.b & "_" & $tint.a

  if cacheKey in textureCache:
    return some(textureCache[cacheKey])
  else:
    if not fileExists(filepath):
      echo "Warning: Icon file not found: ", filepath
      return none((ref Texture2D, int32, int32))

    try:
      let textureValue = if tint == rl.WHITE:
        svgToTexture2D(filepath, size, size)
      else:
        svgToTexture2DWithTint(filepath, tint, size, size)

      # Create reference following naylib best practices
      var textureRef: ref Texture2D
      new(textureRef)
      textureRef[] = textureValue

      let cacheEntry = (textureRef, size, size)
      textureCache[cacheKey] = cacheEntry
      return some(cacheEntry)
    except:
      echo "Error rasterizing icon: ", filepath, " - ", getCurrentExceptionMsg()
      return none((ref Texture2D, int32, int32))

proc drawRasterizedIcon*(
    filename: string,
    x: float32,
    y: float32,
    size: float32 = 16.0,
    tint: rl.Color = rl.WHITE,
) =
  ## Draw an icon using the new rasterizer for better complex shape handling
  let iconsDir = ResourcesDir / "icons"
  let file = iconsDir / filename
  let textureOpt = getCachedRasterizedTexture(file, size.int32, tint)

  if textureOpt.isNone:
    # Fallback to regular icon drawing
    # drawIcon(filename, x, y, size, tint)
    return

  let (texture, width, height) = textureOpt.get()

  let sourceRec = Rectangle(
    x: 0,
    y: 0,
    width: width.float32,
    height: -height.float32 # Negative height to flip Y
  )
  let destRec = Rectangle(
    x: x,
    y: y,
    width: size,
    height: size
  )
  let origin = Vector2(x: 0, y: 0)

  drawTexture(texture[], sourceRec, destRec, origin, 0.0,
      White) # Tint already applied during rasterization

proc drawFileIcon*(x: float32, y: float32, color: rl.Color) =
  let m = getIconMetrics(x, y)
  drawRasterizedIcon("file.svg", x, y, m.size.float32, color)

proc drawFolderIcon*(x: float32, y: float32, color: rl.Color) =
  let m = getIconMetrics(x, y)
  drawRasterizedIcon("folder.svg", x, y, m.size.float32, color)

# Alias for backward compatibility
proc drawFileIconRasterized*(x: float32, y: float32, color: rl.Color) =
  drawFileIcon(x, y, color)

proc drawFolderIconRasterized*(x: float32, y: float32, color: rl.Color) =
  drawFolderIcon(x, y, color)

# Language-specific icon functions using rasterizer
proc drawNimIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated Nim icon first
  let iconsDir = ResourcesDir / "icons"
  let nimIconPath = iconsDir / "nim.svg"
  if fileExists(nimIconPath):
    drawRasterizedIcon("nim.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawPythonIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated Python icon first
  let iconsDir = ResourcesDir / "icons"
  let pythonIconPath = iconsDir / "python.svg"
  if fileExists(pythonIconPath):
    drawRasterizedIcon("python.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawJavaScriptIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated JavaScript icon first
  let iconsDir = ResourcesDir / "icons"
  let jsIconPath = iconsDir / "javascript.svg"
  if fileExists(jsIconPath):
    drawRasterizedIcon("javascript.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawTypeScriptIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated TypeScript icon first
  let iconsDir = ResourcesDir / "icons"
  let tsIconPath = iconsDir / "typescript.svg"
  if fileExists(tsIconPath):
    drawRasterizedIcon("typescript.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawMarkdownIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated Markdown icon first
  let iconsDir = ResourcesDir / "icons"
  let mdIconPath = iconsDir / "markdown.svg"
  if fileExists(mdIconPath):
    drawRasterizedIcon("markdown.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawJsonIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated JSON icon first
  let iconsDir = ResourcesDir / "icons"
  let jsonIconPath = iconsDir / "json.svg"
  if fileExists(jsonIconPath):
    drawRasterizedIcon("json.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawYamlIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated YAML icon first
  let iconsDir = ResourcesDir / "icons"
  let yamlIconPath = iconsDir / "yaml.svg"
  if fileExists(yamlIconPath):
    drawRasterizedIcon("yaml.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawTomlIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated TOML icon first
  let iconsDir = ResourcesDir / "icons"
  let tomlIconPath = iconsDir / "toml.svg"
  if fileExists(tomlIconPath):
    drawRasterizedIcon("toml.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawRustIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated Rust icon first
  let iconsDir = ResourcesDir / "icons"
  let rustIconPath = iconsDir / "rust.svg"
  if fileExists(rustIconPath):
    drawRasterizedIcon("rust.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawCppIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated C++ icon first
  let iconsDir = ResourcesDir / "icons"
  let cppIconPath = iconsDir / "cpp.svg"
  if fileExists(cppIconPath):
    drawRasterizedIcon("cpp.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawCIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated C icon first
  let iconsDir = ResourcesDir / "icons"
  let cIconPath = iconsDir / "c.svg"
  if fileExists(cIconPath):
    drawRasterizedIcon("c.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawHtmlIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated HTML icon first
  let iconsDir = ResourcesDir / "icons"
  let htmlIconPath = iconsDir / "html.svg"
  if fileExists(htmlIconPath):
    drawRasterizedIcon("html.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawCssIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated CSS icon first
  let iconsDir = ResourcesDir / "icons"
  let cssIconPath = iconsDir / "css.svg"
  if fileExists(cssIconPath):
    drawRasterizedIcon("css.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawGoIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated Go icon first
  let iconsDir = ResourcesDir / "icons"
  let goIconPath = iconsDir / "go.svg"
  if fileExists(goIconPath):
    drawRasterizedIcon("go.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawJavaIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  # Try to use dedicated Java icon first
  let iconsDir = ResourcesDir / "icons"
  let javaIconPath = iconsDir / "java.svg"
  if fileExists(javaIconPath):
    drawRasterizedIcon("java.svg", x, y, size, tint)
  else:
    # Fallback to generic file icon
    drawRasterizedIcon("file.svg", x, y, size, tint)

proc drawOpenFolderIcon*(
    x: float32, y: float32, size: float32 = 16.0, tint: rl.Color = rl.WHITE
) =
  drawRasterizedIcon("openfolder.svg", x, y, size, tint)


proc preloadCommonIcons*() =
  ## Preload commonly used icons for better performance
  let iconsDir = ResourcesDir / "icons"
  let commonIcons = [
    "gitbranch.svg",
    "file.svg",
    "folder.svg",
    "openfolder.svg",
    "nim.svg",
    "python.svg",
    "javascript.svg",
    "typescript.svg",
    "markdown.svg",
    "json.svg",
    "yaml.svg",
    "toml.svg",
    "rust.svg",
    "cpp.svg",
    "c.svg",
    "html.svg",
    "css.svg",
    "go.svg",
    "java.svg",
    "git.svg",
    "close.svg",
    "minimize.svg",
    "maximize.svg"
  ]

  echo "Preloading common icons..."
  var loadedCount = 0
  for iconFile in commonIcons:
    let filepath = iconsDir / iconFile
    if fileExists(filepath):
      let result = getCachedRasterizedTexture(filepath)
      if result.isSome:
        loadedCount += 1
        echo "  Loaded: ", iconFile
      else:
        echo "  Failed to load: ", iconFile
    else:
      echo "  Not found: ", iconFile

  echo "Icon preloading complete: ", loadedCount, "/", commonIcons.len, " icons loaded"

proc clearCachedTexture*(filepath: string) =
  ## Clear a specific texture from cache
  if filepath in textureCache:
    let (_, _, _) = textureCache[filepath]
    # TODO: rl.unloadTexture(texture) when raylib function name is fixed
    textureCache.del(filepath)

proc cleanupIconCache*() =
  ## Cleanup all cached textures - call this when shutting down
  for (_, _, _) in textureCache.values:
    # TODO: rl.unloadTexture(texture) when raylib function name is fixed
    discard
  textureCache.clear()

