import std/[streams, parsexml, strutils]
import raylib as rl
import stylus/parser
import svgtoraylib/[shapes, vector, styleparse, common]

export common

type
  SvgToRaylibError* = object of CatchableError
  ViewBox* = object
    point*: Vec2
    w*, h*: float64
  MetaData* = object
    viewBox*: ViewBox
    width*, height*: float64
    scale*: float64

func toViewBox(vbStr: string): ViewBox =
  let vbItems = vbStr.split(' ')
  ViewBox(
    point: Vec2(
      x: vbItems[0].parseFloat(),
      y: vbItems[1].parseFloat(),
    ),
    w: vbItems[2].parseFloat(),
    h: vbItems[3].parseFloat(),
  )

func deunitized(unitized: string): float64 =
  var val, unit: string
  for c in unitized:
    if (c >= '0' and c <= '9') or c == '.':
      val &= c
    else:
      unit &= c
  result = val.parseFloat()
  case unit:
    of "in":
      result *= 96
    of "px", "":  # Handle pixels or unitless values
      discard  # Keep as is
    else: discard

proc parseMetaData(p: var XmlParser): MetaData =
  var widthOrHeightGiven = false
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "viewBox":
            result.viewBox = toViewBox(p.attrValue)
          of "width":
            result.width = p.attrValue.deunitized
            widthOrHeightGiven = true
          of "height":
            result.height = p.attrValue.deunitized
            widthOrHeightGiven = true
          of "version":
            if p.attrValue != "1.1":
              raise newException(SvgToRaylibError, "Only SVG 1.1 is supported")
      of xmlElementClose:
        break
      else: discard
  if not widthOrHeightGiven:
    result.width = result.viewBox.w
    result.height = result.viewBox.h
  result.scale = result.width / result.viewBox.w

proc loadShape(p: var XmlParser, target: RenderTexture2D,
               classMap: ClassMap, scale: float64) =
  case p.elementName:
    of "rect": p.parseRect(classMap, scale).draw(target)
    of "circle": p.parseCircle(classMap, scale).draw(target)
    of "path": p.parsePath(classMap, scale).draw(target, scale)
    else: discard

proc loadShapes(p: var XmlParser, target: RenderTexture2D,
                classMap: ClassMap, scale: float64) =
  while true:
    # The token loadShapes starts with when called should be an xmlElementOpen.
    case p.kind:
      of xmlElementOpen:
        if p.elementName == "path" or p.elementName == "rect" or p.elementName == "circle":
          loadShape(p, target, classMap, scale)
      of xmlElementEnd:
        break
      of xmlAttribute, xmlWhitespace: discard
      else: raise newException(SvgToRaylibError, "Unexpected token when loading shapes")
    p.next()

template skipToKind(p: var XmlParser, targetKind: XmlEventKind) =
  ## Consumes and ignores tokens until hitting a token of `targetKind`. Using this
  ## by definition means ignoring potentially important information in the SVG data,
  ## which is a signal of incomplete SVG-to-Raylib implementation. Get away
  ## from using this eventually.
  p.next()
  while p.kind != targetKind: p.next()

proc parseDefs(p: var XmlParser, scale: float64): ClassMap =
  while true:
    p.next()
    case p.kind:
      of xmlElementOpen, xmlElementStart:
        if p.elementName == "style":
          p.skipToKind(xmlCharData)
          return parseStyleClasses(p.charData, scale)
      of xmlElementClose: break
      else: discard

type WithDimsResult* = tuple[texture: RenderTexture2D, width, height: float64]

proc svgToTexture*(s: var FileStream, inFile: string): WithDimsResult =
  var
    p: XmlParser
    metaData: MetaData
    classMap: ClassMap
    renderTexture: RenderTexture2D
    width, height: float64
  p.open(s, inFile)
  while true:
    p.next()
    case p.kind:
      of xmlElementOpen, xmlElementStart:
        case p.elementName:
          of "svg":
            metaData = parseMetaData(p)
            echo "DEBUG: metaData.width = ", metaData.width, ", metaData.height = ", metaData.height
            renderTexture = rl.loadRenderTexture(metaData.width.int32, metaData.height.int32)
            width = metaData.width
            height = metaData.height
            # Begin drawing to render texture
            rl.beginTextureMode(renderTexture)
            rl.clearBackground(rl.Color(r: 0, g: 0, b: 0, a: 0)) # Transparent background
          of "defs":
            classMap = parseDefs(p, metaData.scale)
          of "g":
            # Skip tokens until <g> attributes are over and hits first nested shape.
            p.skipToKind(xmlElementOpen)
            loadShapes(p, renderTexture, classMap, metaData.scale)
          of "path", "rect", "circle":
            loadShape(p, renderTexture, classMap, metaData.scale)
      of xmlEof:
        break
      else: discard
  rl.endTextureMode()
  p.close
  (texture: renderTexture, width: width, height: height)

proc svgToTexture*(inFile: string): RenderTexture2D =
  var s = newFileStream(inFile)
  if s.isNil:
    raise newException(SvgToRaylibError, "Failed to open SVG: " & inFile)
  let (texture, _, _) = s.svgToTexture(inFile)
  return texture

proc svgToTextureWithDims*(inFile: string): WithDimsResult =
  var s = newFileStream(inFile)
  if s.isNil:
    raise newException(SvgToRaylibError, "Failed to open SVG: " & inFile)
  s.svgToTexture(inFile)

# Convenience function to load SVG and get a Texture2D (non-render texture)
proc svgToTexture2D*(inFile: string): Texture2D =
  let renderTex = svgToTexture(inFile)
  result = renderTex.texture
  # rl.unloadTexture(renderTex)
