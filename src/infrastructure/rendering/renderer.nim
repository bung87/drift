## Renderer Infrastructure
## Provides high-level rendering abstraction over Raylib

import raylib as rl
import std/[tables, options]
import results
import ../../shared/errors
import theme

# Rendering state and configuration
type
  RenderMode* = enum
    rmNormal = "normal"
    rmDebug = "debug"
    rmWireframe = "wireframe"

  BlendMode* = enum
    bmAlpha = "alpha"
    bmAdditive = "additive"
    bmMultiplied = "multiplied"
    bmReplace = "replace"

  TextAlign* = enum
    taLeft = "left"
    taCenter = "center"
    taRight = "right"

  VerticalAlign* = enum
    vaTop = "top"
    vaMiddle = "middle"
    vaBottom = "bottom"

  RenderStats* = object
    drawCalls*: int
    verticesDrawn*: int
    texturesUsed*: int
    frameTime*: float32
    fps*: int

  RenderContext* = object
    bounds*: rl.Rectangle
    clipRect*: Option[rl.Rectangle]
    transform*: rl.Matrix
    tint*: rl.Color
    alpha*: float32

  RendererConfig* = ref object
    enableVSync*: bool
    targetFPS*: int
    multisampling*: int
    debugMode*: bool
    showFPS*: bool
    enableClipping*: bool
    defaultFont*: rl.Font

  Renderer* = ref object
    config*: RendererConfig
    themeManager*: ThemeManager
    contextStack*: seq[RenderContext]
    currentContext*: RenderContext
    stats*: RenderStats
    fonts*: Table[string, ptr rl.Font]
    textures*: Table[string, rl.Texture2D]
    renderMode*: RenderMode
    blendMode*: BlendMode

# Default configuration
proc defaultRendererConfig*(): RendererConfig =
  RendererConfig(
    enableVSync: true,
    targetFPS: 60,
    multisampling: 4,
    debugMode: false,
    showFPS: false,
    enableClipping: true,
  )

# Constructor
proc newRenderer*(
    themeManager: ThemeManager, config: RendererConfig = defaultRendererConfig()
): Renderer =
  result = Renderer(
    config: config,
    themeManager: themeManager,
    contextStack: @[],
    currentContext: RenderContext(
      bounds: rl.Rectangle(x: 0, y: 0, width: 1200, height: 800),
      clipRect: none(rl.Rectangle),
      transform: rl.Matrix(
        m0: 1.0,
        m4: 0.0,
        m8: 0.0,
        m12: 0.0,
        m1: 0.0,
        m5: 1.0,
        m9: 0.0,
        m13: 0.0,
        m2: 0.0,
        m6: 0.0,
        m10: 1.0,
        m14: 0.0,
        m3: 0.0,
        m7: 0.0,
        m11: 0.0,
        m15: 1.0,
    ),
    tint: rl.WHITE,
    alpha: 1.0,
  ),
    stats: RenderStats(),
    fonts: initTable[string, ptr rl.Font](),
    textures: initTable[string, rl.Texture2D](),
    renderMode: rmNormal,
    blendMode: bmAlpha,
  )

  # Set initial render state
  if config.enableVSync:
    rl.setTargetFPS(config.targetFPS.int32)

# Context management
proc pushContext*(renderer: Renderer) =
  ## Push current context onto stack
  renderer.contextStack.add(renderer.currentContext)

proc popContext*(renderer: Renderer) =
  ## Pop context from stack
  if renderer.contextStack.len > 0:
    renderer.currentContext = renderer.contextStack.pop()

proc withContext*(renderer: Renderer, context: RenderContext, body: proc()) =
  ## Execute code with temporary context
  renderer.pushContext()
  renderer.currentContext = context
  body()
  renderer.popContext()

# Coordinate system
proc setViewport*(renderer: Renderer, bounds: rl.Rectangle) =
  renderer.currentContext.bounds = bounds
  # rl.viewport(bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32)  # TODO: Fix raylib viewport function

proc setClipRect*(renderer: Renderer, rect: rl.Rectangle) =
  renderer.currentContext.clipRect = some(rect)
  rl.beginScissorMode(rect.x.int32, rect.y.int32, rect.width.int32,
      rect.height.int32)

proc clearClipRect*(renderer: Renderer) =
  renderer.currentContext.clipRect = none(rl.Rectangle)
  rl.endScissorMode()

proc setTransform*(renderer: Renderer, transform: rl.Matrix) =
  renderer.currentContext.transform = transform
  # rl.pushMatrix()  # TODO: Fix raylib matrix function names
  # rl.multMatrixf(cast[ptr float32](addr transform))

proc resetTransform*(renderer: Renderer) =
  renderer.currentContext.transform = rl.Matrix(
    m0: 1.0,
    m4: 0.0,
    m8: 0.0,
    m12: 0.0,
    m1: 0.0,
    m5: 1.0,
    m9: 0.0,
    m13: 0.0,
    m2: 0.0,
    m6: 0.0,
    m10: 1.0,
    m14: 0.0,
    m3: 0.0,
    m7: 0.0,
    m11: 0.0,
    m15: 1.0,
  )
  # rl.popMatrix()  # TODO: Fix raylib matrix function names

# Color and blending
proc setTint*(renderer: Renderer, color: rl.Color) =
  renderer.currentContext.tint = color

proc setAlpha*(renderer: Renderer, alpha: float32) =
  renderer.currentContext.alpha = clamp(alpha, 0.0, 1.0)

proc getCurrentColor*(renderer: Renderer, baseColor: rl.Color): rl.Color =
  result = baseColor
  result.r = uint8(float32(result.r) * float32(renderer.currentContext.tint.r) / 255.0)
  result.g = uint8(float32(result.g) * float32(renderer.currentContext.tint.g) / 255.0)
  result.b = uint8(float32(result.b) * float32(renderer.currentContext.tint.b) / 255.0)
  result.a = uint8(float32(result.a) * renderer.currentContext.alpha)

# Basic drawing primitives
proc drawPixel*(renderer: Renderer, x, y: int32, color: rl.Color) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawPixel(x, y, finalColor)
  inc renderer.stats.drawCalls

proc drawLine*(renderer: Renderer, start, endPoint: rl.Vector2,
    color: rl.Color) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawLine(
    start.x.int32, start.y.int32, endPoint.x.int32, endPoint.y.int32, finalColor
  )
  inc renderer.stats.drawCalls

proc drawRectangle*(renderer: Renderer, rect: rl.Rectangle, color: rl.Color) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawRectangle(
    rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32, finalColor
  )
  inc renderer.stats.drawCalls

proc drawRectangleOutline*(renderer: Renderer, rect: rl.Rectangle,
    color: rl.Color) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawRectangleLines(
    rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32, finalColor
  )
  inc renderer.stats.drawCalls

proc drawRoundedRectangle*(
    renderer: Renderer, rect: rl.Rectangle, roundness: float32, color: rl.Color
) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawRectangleRounded(rect, roundness, 8, finalColor)
  inc renderer.stats.drawCalls

proc drawCircle*(
    renderer: Renderer, center: rl.Vector2, radius: float32, color: rl.Color
) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawCircle(center.x.int32, center.y.int32, radius, finalColor)
  inc renderer.stats.drawCalls

proc drawEllipse*(
    renderer: Renderer, center: rl.Vector2, radiusH, radiusV: float32,
        color: rl.Color
) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawEllipse(center.x.int32, center.y.int32, radiusH, radiusV, finalColor)
  inc renderer.stats.drawCalls

# Text rendering
proc drawText*(
    renderer: Renderer,
    font: rl.Font,
    text: string,
    position: rl.Vector2,
    fontSize: float32,
    spacing: float32,
    color: rl.Color,
) =
  let finalColor = renderer.getCurrentColor(color)
  rl.drawText(font, text, position, fontSize, spacing, finalColor)
  inc renderer.stats.drawCalls

proc drawTextAligned*(
    renderer: Renderer,
    font: rl.Font,
    text: string,
    bounds: rl.Rectangle,
    fontSize: float32,
    spacing: float32,
    color: rl.Color,
    hAlign: TextAlign = taLeft,
    vAlign: VerticalAlign = vaTop,
) =
  let textSize = rl.measureText(font, text, fontSize, spacing)

  var x = bounds.x
  case hAlign
  of taCenter:
    x = bounds.x + (bounds.width - textSize.x) / 2.0
  of taRight:
    x = bounds.x + bounds.width - textSize.x
  of taLeft:
    x = bounds.x

  var y = bounds.y
  case vAlign
  of vaMiddle:
    y = bounds.y + (bounds.height - textSize.y) / 2.0
  of vaBottom:
    y = bounds.y + bounds.height - textSize.y
  of vaTop:
    y = bounds.y

  renderer.drawText(font, text, rl.Vector2(x: x, y: y), fontSize, spacing, color)

proc measureText*(
    renderer: Renderer, font: rl.Font, text: string, fontSize: float32,
        spacing: float32
): rl.Vector2 =
  rl.measureText(font, text, fontSize, spacing)

# Theme-aware drawing
proc drawThemedRectangle*(
    renderer: Renderer, rect: rl.Rectangle, colorType: UIColorType
) =
  let color = renderer.themeManager.getUIColor(colorType)
  renderer.drawRectangle(rect, color)

proc drawThemedText*(
    renderer: Renderer,
    font: rl.Font,
    text: string,
    position: rl.Vector2,
    fontSize: float32,
    colorType: UIColorType,
) =
  let color = renderer.themeManager.getUIColor(colorType)
  renderer.drawText(font, text, position, fontSize, 1.0, color)

# Advanced drawing functions
proc drawGradient*(
    renderer: Renderer,
    rect: rl.Rectangle,
    color1, color2: rl.Color,
    direction: float32 = 0.0, # 0 = horizontal, 90 = vertical
) =
  let finalColor1 = renderer.getCurrentColor(color1)
  let finalColor2 = renderer.getCurrentColor(color2)

  if abs(direction - 90.0) < 0.1: # Vertical gradient
    rl.drawRectangleGradientV(
      rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32,
      finalColor1,
      finalColor2,
    )
  else: # Horizontal gradient
    rl.drawRectangleGradientH(
      rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32,
      finalColor1,
      finalColor2,
    )
  inc renderer.stats.drawCalls

proc drawShadow*(
    renderer: Renderer,
    rect: rl.Rectangle,
    offset: rl.Vector2,
    blur: float32,
    color: rl.Color,
) =
  # Simple shadow approximation using multiple rectangles
  let shadowColor = renderer.getCurrentColor(color)
  let shadowRect = rl.Rectangle(
    x: rect.x + offset.x, y: rect.y + offset.y, width: rect.width,
    height: rect.height
  )

  for i in 0 ..< blur.int:
    let alpha = uint8((255.0 * (1.0 - float32(i) / blur)) / 4.0)
    var blurColor = shadowColor
    blurColor.a = alpha

    let blurRect = rl.Rectangle(
      x: shadowRect.x - float32(i),
      y: shadowRect.y - float32(i),
      width: shadowRect.width + float32(i * 2),
      height: shadowRect.height + float32(i * 2),
    )
    rl.drawRectangle(
      blurRect.x.int32, blurRect.y.int32, blurRect.width.int32,
      blurRect.height.int32,
      blurColor,
    )

  renderer.stats.drawCalls += blur.int

# Asset management
proc loadFont*(
    renderer: Renderer, name: string, path: string
): Result[void, EditorError] =
  try:
    let loadedFont = rl.loadFont(path)
    if loadedFont.baseSize == 0:
      return
        err(EditorError(msg: "Failed to load font: " & path,
            code: "FONT_LOAD_ERROR"))


    renderer.fonts[name] = loadedFont.addr
    return ok()
  except:
    return
      err(EditorError(msg: "Failed to load font: " & path,
          code: "FONT_LOAD_ERROR"))

proc registerFont*(renderer: Renderer, name: string, font: ptr rl.Font) =
  ## Register an already loaded font with the renderer
  renderer.fonts[name] = font

proc getFont*(renderer: Renderer, name: string): ptr rl.Font =
  if name in renderer.fonts:
    return renderer.fonts[name]

proc loadTexture*(
    renderer: Renderer, name: string, path: string
): Result[void, EditorError] =
  try:
    let texture = rl.loadTexture(path)
    if texture.width == 0 or texture.height == 0:
      return err(
        EditorError(msg: "Failed to load texture: " & path,
            code: "TEXTURE_LOAD_ERROR")
      )

    renderer.textures[name] = texture
    return ok()
  except:
    return err(
      EditorError(msg: "Failed to load texture: " & path,
          code: "TEXTURE_LOAD_ERROR")
    )

proc getTexture*(renderer: Renderer, name: string): Option[rl.Texture2D] =
  if name in renderer.textures:
    return some(renderer.textures[name])
  else:
    return none(rl.Texture2D)

# Frame management
proc beginFrame*(renderer: Renderer, clearColor: rl.Color) =
  rl.beginDrawing()
  let finalClearColor = renderer.getCurrentColor(clearColor)
  rl.clearBackground(finalClearColor)

  # Reset stats
  renderer.stats.drawCalls = 0
  renderer.stats.verticesDrawn = 0
  renderer.stats.texturesUsed = 0

proc endFrame*(renderer: Renderer) =
  # Update stats
  renderer.stats.frameTime = rl.getFrameTime()
  renderer.stats.fps = rl.getFPS()

  # Draw debug info if enabled
  if renderer.config.debugMode:
    # drawDebugInfo(renderer)  # TODO: Fix forward declaration issue
    discard

  # Show FPS if enabled
  if renderer.config.showFPS:
    let fpsText = "FPS: " & $renderer.stats.fps
    let defaultFont = rl.getFontDefault()
    rl.drawText(defaultFont, fpsText, rl.Vector2(x: 10, y: 10), 20, 1.0, rl.LIME)

  rl.endDrawing()

proc drawDebugInfo*(renderer: Renderer) =
  let debugRect = rl.Rectangle(x: 10, y: 40, width: 200, height: 120)
  rl.drawRectangle(
    debugRect.x.int32,
    debugRect.y.int32,
    debugRect.width.int32,
    debugRect.height.int32,
    rl.Color(r: 0, g: 0, b: 0, a: 180),
  )

  let defaultFont = rl.getFontDefault()
  var y = debugRect.y + 5

  rl.drawText(defaultFont, "Draw Calls: " & $renderer.stats.drawCalls,
      rl.Vector2(x: 15, y: y), 16, 1.0, rl.WHITE)
  y += 20
  rl.drawText(defaultFont, "Frame Time: " & $renderer.stats.frameTime,
      rl.Vector2(x: 15, y: y), 16, 1.0, rl.WHITE)
  y += 20
  rl.drawText(defaultFont, "Fonts: " & $renderer.fonts.len, rl.Vector2(x: 15,
      y: y), 16, 1.0, rl.WHITE)
  y += 20
  rl.drawText(defaultFont, "Textures: " & $renderer.textures.len, rl.Vector2(
      x: 15, y: y), 16, 1.0, rl.WHITE)

# Utility functions
proc isPointInBounds*(renderer: Renderer, point: rl.Vector2): bool =
  let bounds = renderer.currentContext.bounds
  return
    point.x >= bounds.x and point.x <= bounds.x + bounds.width and point.y >=
        bounds.y and
    point.y <= bounds.y + bounds.height

proc screenToLocal*(renderer: Renderer, screenPos: rl.Vector2): rl.Vector2 =
  # Transform screen coordinates to local context coordinates
  result.x = screenPos.x - renderer.currentContext.bounds.x
  result.y = screenPos.y - renderer.currentContext.bounds.y

proc localToScreen*(renderer: Renderer, localPos: rl.Vector2): rl.Vector2 =
  # Transform local coordinates to screen coordinates
  result.x = localPos.x + renderer.currentContext.bounds.x
  result.y = localPos.y + renderer.currentContext.bounds.y

# Configuration
proc setConfig*(renderer: Renderer, config: RendererConfig) =
  renderer.config = config
  if config.enableVSync:
    rl.setTargetFPS(config.targetFPS.int32)

proc getStats*(renderer: Renderer): RenderStats =
  renderer.stats

# Cleanup
proc cleanup*(renderer: Renderer) =
  # Unload fonts
  for font in renderer.fonts.mvalues:
    if font.baseSize > 0: # Check if font is valid
      # rl.unloadFont(font[])  # TODO: Fix raylib function name
      discard
  renderer.fonts.clear()

  # Unload textures
  for texture in renderer.textures.mvalues:
    if texture.width > 0: # Check if texture is valid
      # rl.unloadTexture(texture)  # TODO: Fix raylib function name
      discard
  renderer.textures.clear()
