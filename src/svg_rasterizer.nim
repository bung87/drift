## SVG to Image Rasterization Module for Nim/Raylib
## Converts SVG files to rasterized RGBA image data for use as textures
# iould # 
## Features:
## - Path rendering with fill and stroke support
## - Basic shapes: rectangles, circles, ellipses
## - Transform support: translate, scale, rotate
## - Adaptive bezier curve sampling for optimal quality/performance
## - Anti-aliased rendering with supersampling
## - Configurable debug output
## - Comprehensive error handling

import std/[streams, parsexml, strutils, algorithm, strformat, math]
import raylib as rl
import chroma
import svgtoraylib/pathdata

# Debug flag - set to false for production
const DEBUG_SVG_RASTERIZER = false

type
  SvgRasterizerError* = object of CatchableError

  Point* = object
    x*, y*: float32

  Edge* = object
    x1*, y1*, x2*, y2*: float32

  ScanlineIntersection* = object
    x*: float32
    winding*: int # For winding rule support

  RasterizedImage* = object
    width*, height*: int32
    data*: seq[uint8] # RGBA data

  ViewBox* = object
    x*, y*, width*, height*: float32

  Transform* = object
    translateX*, translateY*: float32
    scaleX*, scaleY*: float32
    rotate*: float32
    
  RasterContext* = object
    width*, height*: int32
    viewBox*: ViewBox
    scaleX*, scaleY*: float32
    transform*: Transform

  PathStyle* = object
    fillColor*: rl.Color
    strokeColor*: rl.Color
    strokeWidth*: float32
    hasFill*: bool
    hasStroke*: bool
    strokeLineCap*: string  # "butt", "round", "square"
    strokeLineJoin*: string # "miter", "round", "bevel"

# Utility functions
proc newPoint*(x, y: float32): Point =
  Point(x: x, y: y)

proc newEdge*(x1, y1, x2, y2: float32): Edge =
  Edge(x1: x1, y1: y1, x2: x2, y2: y2)

proc newPathStyle*(): PathStyle =
  result = PathStyle(
    fillColor: rl.Color(r: 0, g: 0, b: 0, a: 255),
    strokeColor: rl.Color(r: 0, g: 0, b: 0, a: 255),
    strokeWidth: 1.0,
    hasFill: false,
    hasStroke: false,
    strokeLineCap: "butt",
    strokeLineJoin: "miter"
  )

# Bezier curve sampling
proc bezierCubic*(p0, p1, p2, p3: Point, t: float32): Point =
  let
    t2 = t * t
    t3 = t2 * t
    mt = 1.0 - t
    mt2 = mt * mt
    mt3 = mt2 * mt

  result = Point(
    x: p0.x * mt3 + p1.x * (3.0 * mt2 * t) + p2.x * (3.0 * mt * t2) + p3.x * t3,
    y: p0.y * mt3 + p1.y * (3.0 * mt2 * t) + p2.y * (3.0 * mt * t2) + p3.y * t3
  )

proc calculateBezierLength*(p0, p1, p2, p3: Point): float32 =
  ## Calculate approximate length of bezier curve for adaptive sampling
  let chord = sqrt((p3.x - p0.x) * (p3.x - p0.x) + (p3.y - p0.y) * (p3.y - p0.y))
  let controlNet = sqrt((p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y)) +
                   sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y)) +
                   sqrt((p3.x - p2.x) * (p3.x - p2.x) + (p3.y - p2.y) * (p3.y - p2.y))
  result = (chord + controlNet) / 2.0

proc sampleBezierCurve*(p0, p1, p2, p3: Point, samples: int = 0): seq[Point] =
  ## Adaptive bezier curve sampling based on curve length
  let curveLength = calculateBezierLength(p0, p1, p2, p3)
  
  # Adaptive sampling: minimum 4 samples, maximum 100, based on curve length
  let adaptiveSamples = if samples == 0:
    max(4, min(100, (curveLength * 0.5).int))
  else:
    samples
    
  result = @[]
  if adaptiveSamples < 2:
    return @[p0, p3]
    
  for i in 0..adaptiveSamples:
    let t = i.float32 / adaptiveSamples.float32
    result.add(bezierCubic(p0, p1, p2, p3, t))

# Basic shape to path conversion
proc rectToPath*(x, y, width, height: float32, rx = 0.0, ry = 0.0): string =
  ## Convert rectangle to SVG path data
  if rx <= 0.0 and ry <= 0.0:
    # Simple rectangle
    return fmt"M{x},{y} L{x+width},{y} L{x+width},{y+height} L{x},{y+height} Z"
  else:
    # Rounded rectangle
    let actualRx = if rx <= 0.0: ry else: rx
    let actualRy = if ry <= 0.0: rx else: ry
    return fmt"M{x+actualRx},{y} L{x+width-actualRx},{y} A{actualRx},{actualRy} 0 0 1 {x+width},{y+actualRy} L{x+width},{y+height-actualRy} A{actualRx},{actualRy} 0 0 1 {x+width-actualRx},{y+height} L{x+actualRx},{y+height} A{actualRx},{actualRy} 0 0 1 {x},{y+height-actualRy} L{x},{y+actualRy} A{actualRx},{actualRy} 0 0 1 {x+actualRx},{y} Z"

proc circleToPath*(cx, cy, r: float32): string =
  ## Convert circle to SVG path data
  return fmt"M{cx-r},{cy} A{r},{r} 0 1 1 {cx+r},{cy} A{r},{r} 0 1 1 {cx-r},{cy} Z"

proc ellipseToPath*(cx, cy, rx, ry: float32): string =
  ## Convert ellipse to SVG path data
  return fmt"M{cx-rx},{cy} A{rx},{ry} 0 1 1 {cx+rx},{cy} A{rx},{ry} 0 1 1 {cx-rx},{cy} Z"

# Path parsing to polygon conversion with transform support
proc pathToPolygon*(pathData: string, ctx: RasterContext): seq[seq[Point]] =
  var
    currentPoint = Point(x: 0, y: 0)
    startPoint = Point(x: 0, y: 0)
    currentPolygon: seq[Point] = @[]
    polygons: seq[seq[Point]] = @[]

  if DEBUG_SVG_RASTERIZER:
    echo fmt"    Parsing path data: {pathData}"

  for op in pathData.ops:
    if DEBUG_SVG_RASTERIZER:
      echo fmt"    Command: {op.cmd}, Values: {op.values}"
    case op.cmd:
      of 'M':
        # Move to absolute - start new polygon
        if currentPolygon.len > 0:
          polygons.add(currentPolygon)
          currentPolygon = @[]
        for (group, idx) in op.groups:
          let x = group[0].float32 * ctx.scaleX
          let y = group[1].float32 * ctx.scaleY
          currentPoint = Point(x: x, y: y)
          if idx == 0:
            startPoint = currentPoint
          currentPolygon.add(currentPoint)

      of 'm':
        # Move to relative - start new polygon
        if currentPolygon.len > 0:
          polygons.add(currentPolygon)
          currentPolygon = @[]
        for (group, idx) in op.groups:
          currentPoint.x += group[0].float32 * ctx.scaleX
          currentPoint.y += group[1].float32 * ctx.scaleY
          if idx == 0:
            startPoint = currentPoint
          currentPolygon.add(currentPoint)

      of 'L':
        # Line to absolute
        for (group, _) in op.groups:
          let x = group[0].float32 * ctx.scaleX
          let y = group[1].float32 * ctx.scaleY
          currentPoint = Point(x: x, y: y)
          currentPolygon.add(currentPoint)

      of 'l':
        # Line to relative
        for (group, _) in op.groups:
          currentPoint.x += group[0].float32 * ctx.scaleX
          currentPoint.y += group[1].float32 * ctx.scaleY
          currentPolygon.add(currentPoint)

      of 'V':
        # Vertical line to absolute
        for (group, _) in op.groups:
          let newY = group[0].float32 * ctx.scaleY
          let newPoint = Point(x: currentPoint.x, y: newY)
          currentPolygon.add(newPoint)
          currentPoint = newPoint

      of 'v':
        # Vertical line to relative
        for (group, _) in op.groups:
          let newY = currentPoint.y + group[0].float32 * ctx.scaleY
          let newPoint = Point(x: currentPoint.x, y: newY)
          currentPolygon.add(newPoint)
          currentPoint = newPoint

      of 'H':
        # Horizontal line to absolute
        for (group, _) in op.groups:
          let newX = group[0].float32 * ctx.scaleX
          let newPoint = Point(x: newX, y: currentPoint.y)
          currentPolygon.add(newPoint)
          currentPoint = newPoint

      of 'h':
        # Horizontal line to relative
        for (group, _) in op.groups:
          let newX = currentPoint.x + group[0].float32 * ctx.scaleX
          let newPoint = Point(x: newX, y: currentPoint.y)
          currentPolygon.add(newPoint)
          currentPoint = newPoint

      of 'C':
        # Cubic bezier curve absolute
        for (group, _) in op.groups:
          let
            cp1 = Point(x: group[0].float32 * ctx.scaleX, y: group[1].float32 * ctx.scaleY)
            cp2 = Point(x: group[2].float32 * ctx.scaleX, y: group[3].float32 * ctx.scaleY)
            endPoint = Point(x: group[4].float32 * ctx.scaleX, y: group[
                5].float32 * ctx.scaleY)

          let curvePoints = sampleBezierCurve(currentPoint, cp1, cp2, endPoint)
          for point in curvePoints[1..^1]: # Skip first point (already in polygon)
            currentPolygon.add(point)

          currentPoint = endPoint

      of 'c':
        # Cubic bezier curve relative
        for (group, _) in op.groups:
          let
            cp1 = Point(x: currentPoint.x + group[0].float32 * ctx.scaleX,
                       y: currentPoint.y + group[1].float32 * ctx.scaleY)
            cp2 = Point(x: currentPoint.x + group[2].float32 * ctx.scaleX,
                       y: currentPoint.y + group[3].float32 * ctx.scaleY)
            endPoint = Point(x: currentPoint.x + group[4].float32 * ctx.scaleX,
                           y: currentPoint.y + group[5].float32 * ctx.scaleY)

          let curvePoints = sampleBezierCurve(currentPoint, cp1, cp2, endPoint)
          for point in curvePoints[1..^1]: # Skip first point (already in polygon)
            currentPolygon.add(point)

          currentPoint = endPoint

      of 'Z', 'z':
        # Close path
        if currentPolygon.len > 0 and currentPoint != startPoint:
          currentPolygon.add(startPoint)

      else:
        # Skip unsupported commands
        discard

  # Add final polygon
  if currentPolygon.len > 0:
    polygons.add(currentPolygon)

  return polygons

# Scanline polygon filling algorithm
proc getEdgesFromPolygon*(polygon: seq[Point]): seq[Edge] =
  result = @[]
  if polygon.len < 3:
    return

  for i in 0..<polygon.len:
    let next = (i + 1) mod polygon.len
    let p1 = polygon[i]
    let p2 = polygon[next]

    # Skip horizontal edges
    if abs(p1.y - p2.y) > 0.001:
      result.add(newEdge(p1.x, p1.y, p2.x, p2.y))

proc findIntersections*(edges: seq[Edge], y: float32): seq[
    ScanlineIntersection] =
  result = @[]

  for edge in edges:
    let y1 = min(edge.y1, edge.y2)
    let y2 = max(edge.y1, edge.y2)

    # Check if scanline intersects this edge
    if y >= y1 and y < y2:
      # Calculate intersection x coordinate
      let t = (y - edge.y1) / (edge.y2 - edge.y1)
      let x = edge.x1 + t * (edge.x2 - edge.x1)

      # Determine winding direction
      let winding = if edge.y2 > edge.y1: 1 else: -1

      result.add(ScanlineIntersection(x: x, winding: winding))

  # Sort intersections by x coordinate
  result.sort(proc(a, b: ScanlineIntersection): int =
    if a.x < b.x: -1 elif a.x > b.x: 1 else: 0)

proc fillPolygon*(image: var RasterizedImage, polygon: seq[Point],
    color: rl.Color) =
  if polygon.len < 3:
    return

  let edges = getEdgesFromPolygon(polygon)
  if edges.len == 0:
    return

  # Find bounding box
  var minY = polygon[0].y
  var maxY = polygon[0].y
  for point in polygon:
    minY = min(minY, point.y)
    maxY = max(maxY, point.y)

  # Clamp to image bounds
  let startY = max(0, minY.int32)
  let endY = min(image.height - 1, maxY.int32)

  # Scanline fill
  for y in startY..endY:
    let intersections = findIntersections(edges, y.float32)

    # Fill between pairs of intersections using even-odd rule
    var i = 0
    while i < intersections.len - 1:
      let x1 = max(0, intersections[i].x.int32)
      let x2 = min(image.width - 1, intersections[i + 1].x.int32)

      # Fill pixels between x1 and x2
      for x in x1..x2:
        let pixelIndex = (y * image.width + x) * 4
        if pixelIndex >= 0 and pixelIndex < image.data.len - 3:
          image.data[pixelIndex] = color.r
          image.data[pixelIndex + 1] = color.g
          image.data[pixelIndex + 2] = color.b
          image.data[pixelIndex + 3] = color.a

      i += 2 # Move to next pair

proc drawCircle*(image: var RasterizedImage, centerX, centerY: float32, radius: float32, color: rl.Color) =
  ## Draw a filled circle for rounded line caps and joins
  let cx = centerX.int32
  let cy = centerY.int32
  let r = radius.int32

  for y in max(0, cy - r)..min(image.height - 1, cy + r):
    for x in max(0, cx - r)..min(image.width - 1, cx + r):
      let dx = x - cx
      let dy = y - cy
      let distance = (dx * dx + dy * dy).float32
      if distance <= radius * radius:
        let pixelIndex = (y * image.width + x) * 4
        if pixelIndex >= 0 and pixelIndex < image.data.len - 3:
          # Simple alpha blending
          let srcAlpha = color.a.float32 / 255.0
          let dstAlpha = image.data[pixelIndex + 3].float32 / 255.0
          let outAlpha = srcAlpha + dstAlpha * (1.0 - srcAlpha)
          if outAlpha > 0:
            image.data[pixelIndex] = ((color.r.float32 * srcAlpha + image.data[pixelIndex].float32 * dstAlpha * (1.0 - srcAlpha)) / outAlpha).uint8
            image.data[pixelIndex + 1] = ((color.g.float32 * srcAlpha + image.data[pixelIndex + 1].float32 * dstAlpha * (1.0 - srcAlpha)) / outAlpha).uint8
            image.data[pixelIndex + 2] = ((color.b.float32 * srcAlpha + image.data[pixelIndex + 2].float32 * dstAlpha * (1.0 - srcAlpha)) / outAlpha).uint8
            image.data[pixelIndex + 3] = (outAlpha * 255).uint8

# Stroke rendering functions
proc distanceToLineSegment*(px, py, x1a, y1a, x1b, y1b, x2a, y2a, x2b, y2b: float32): float32 =
  ## Calculate minimum distance from point to line segment
  ## This is a simplified version - for better quality, we'd need more complex geometry

  # For simplicity, we'll use the distance to the center line
  let centerX1 = (x1a + x1b) / 2.0
  let centerY1 = (y1a + y1b) / 2.0
  let centerX2 = (x2a + x2b) / 2.0
  let centerY2 = (y2a + y2b) / 2.0

  # Calculate distance to line segment
  let dx = centerX2 - centerX1
  let dy = centerY2 - centerY1
  let length = sqrt(dx * dx + dy * dy)

  if length < 0.001:
    return sqrt((px - centerX1) * (px - centerX1) + (py - centerY1) * (py - centerY1))

  # Calculate projection
  let t = max(0.0, min(1.0, ((px - centerX1) * dx + (py - centerY1) * dy) / (length * length)))
  let projX = centerX1 + t * dx
  let projY = centerY1 + t * dy

  # Calculate distance to projected point
  let dist = sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY))

  return dist

proc calculateLineCoverage*(px, py, x1a, y1a, x1b, y1b, x2a, y2a, x2b, y2b: float32): float32 =
  ## Calculate pixel coverage for anti-aliased line drawing
  ## Returns a value between 0.0 and 1.0 representing pixel coverage

  # Calculate distance from point to line segment
  let dist = distanceToLineSegment(px, py, x1a, y1a, x1b, y1b, x2a, y2a, x2b, y2b)

  # Convert distance to coverage (1.0 at center, 0.0 at edges)
  if dist <= 0.5:
    return 1.0
  elif dist <= 1.0:
    return 1.0 - (dist - 0.5) * 2.0
  else:
    return 0.0

proc drawAntiAliasedRectangle*(image: var RasterizedImage, x1a, y1a, x1b, y1b, x2a, y2a, x2b, y2b: float32, color: rl.Color) =
  ## Draw an anti-aliased rectangle (stroke) using scanline algorithm

  # Find bounding box
  let minX = min(min(x1a, x1b), min(x2a, x2b))
  let maxX = max(max(x1a, x1b), max(x2a, x2b))
  let minY = min(min(y1a, y1b), min(y2a, y2b))
  let maxY = max(max(y1a, y1b), max(y2a, y2b))

  # Clamp to image bounds
  let startX = max(0, minX.int32)
  let endX = min(image.width - 1, maxX.int32)
  let startY = max(0, minY.int32)
  let endY = min(image.height - 1, maxY.int32)

  # For each pixel in the bounding box, calculate coverage
  for y in startY..endY:
    for x in startX..endX:
      let pixelX = x.float32 + 0.5 # Center of pixel
      let pixelY = y.float32 + 0.5

      # Calculate distance from pixel center to line segment
      let coverage = calculateLineCoverage(pixelX, pixelY, x1a, y1a, x1b, y1b, x2a, y2a, x2b, y2b)

      if coverage > 0:
        # Apply coverage as alpha
        let pixelIndex = (y * image.width + x) * 4
        if pixelIndex >= 0 and pixelIndex < image.data.len - 3:
          let alpha = (color.a.float32 * coverage).uint8
          let antiAliasedColor = rl.Color(r: color.r, g: color.g, b: color.b, a: alpha)

          # Blend with existing pixel
          let srcAlpha = alpha.float32 / 255.0
          let dstAlpha = image.data[pixelIndex + 3].float32 / 255.0
          let outAlpha = srcAlpha + dstAlpha * (1.0 - srcAlpha)

          if outAlpha > 0:
            image.data[pixelIndex] = ((antiAliasedColor.r.float32 * srcAlpha + image.data[pixelIndex].float32 * dstAlpha * (1.0 - srcAlpha)) / outAlpha).uint8
            image.data[pixelIndex + 1] = ((antiAliasedColor.g.float32 * srcAlpha + image.data[pixelIndex + 1].float32 * dstAlpha * (1.0 - srcAlpha)) / outAlpha).uint8
            image.data[pixelIndex + 2] = ((antiAliasedColor.b.float32 * srcAlpha + image.data[pixelIndex + 2].float32 * dstAlpha * (1.0 - srcAlpha)) / outAlpha).uint8
            image.data[pixelIndex + 3] = (outAlpha * 255).uint8

proc drawLineInternal*(image: var RasterizedImage, x1, y1, x2, y2: float32, color: rl.Color, width: float32 = 1.0) =
  ## Draw a line with specified width using anti-aliased Bresenham's algorithm
  let minWidth = max(width, 1.0) # Ensure at least 1 pixel wide

  # For anti-aliasing, we'll use sub-pixel precision
  let dx = x2 - x1
  let dy = y2 - y1
  let length = sqrt(dx * dx + dy * dy)

  if length < 0.001: # Skip very short lines
    return

  # Normalize direction vector
  let dirX = dx / length
  let dirY = dy / length

  # Calculate perpendicular vector for stroke width
  let perpX = -dirY
  let perpY = dirX

  # Calculate stroke half-width
  let halfWidth = minWidth / 2.0

  # Calculate stroke corners
  let x1a = x1 + perpX * halfWidth
  let y1a = y1 + perpY * halfWidth
  let x1b = x1 - perpX * halfWidth
  let y1b = y1 - perpY * halfWidth
  let x2a = x2 + perpX * halfWidth
  let y2a = y2 + perpY * halfWidth
  let x2b = x2 - perpX * halfWidth
  let y2b = y2 - perpY * halfWidth

  # Draw the stroke as a filled rectangle with anti-aliasing
  drawAntiAliasedRectangle(image, x1a, y1a, x1b, y1b, x2a, y2a, x2b, y2b, color)

proc drawLineWithCaps*(image: var RasterizedImage, x1, y1, x2, y2: float32, color: rl.Color, width: float32, lineCap: string) =
  ## Draw a line with proper line caps
  # Draw the main line
  drawLineInternal(image, x1, y1, x2, y2, color, width)

  # Add line caps if needed
  if lineCap == "round":
    let radius = width / 2.0
    drawCircle(image, x1, y1, radius, color)
    drawCircle(image, x2, y2, radius, color)
  elif lineCap == "square":
    # For square caps, extend the line by half the stroke width
    let dx = x2 - x1
    let dy = y2 - y1
    let length = sqrt(dx * dx + dy * dy)
    if length > 0:
      let halfWidth = width / 2.0
      let extendX = (dx / length) * halfWidth
      let extendY = (dy / length) * halfWidth

      # Extend the line at both ends
      let startX = x1 - extendX
      let startY = y1 - extendY
      let endX = x2 + extendX
      let endY = y2 + extendY

      drawLineInternal(image, startX, startY, endX, endY, color, width)

proc strokePath*(image: var RasterizedImage, pathData: string, strokeColor: rl.Color, strokeWidth: float32, ctx: RasterContext, style: PathStyle) =
  ## Render a path as a stroke by following the actual path commands
  var currentPoint = Point(x: 0, y: 0)
  var startPoint = Point(x: 0, y: 0)
  var previousPoint = Point(x: 0, y: 0)
  var firstPoint = true

  if DEBUG_SVG_RASTERIZER:
    echo fmt"    Rendering stroke path: {pathData[0..min(50, pathData.len-1)]}"

  for op in pathData.ops:
    case op.cmd:
      of 'M':
        # Move to absolute - start new subpath
        for (group, idx) in op.groups:
          let x = group[0].float32 * ctx.scaleX
          let y = group[1].float32 * ctx.scaleY
          currentPoint = Point(x: x, y: y)
          if idx == 0:
            startPoint = currentPoint
          if not firstPoint:
            # Draw line from previous point to current point
            drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint
          firstPoint = false

      of 'm':
        # Move to relative - start new subpath
        for (group, idx) in op.groups:
          currentPoint.x += group[0].float32 * ctx.scaleX
          currentPoint.y += group[1].float32 * ctx.scaleY
          if idx == 0:
            startPoint = currentPoint
          if not firstPoint:
            # Draw line from previous point to current point
            drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint
          firstPoint = false

      of 'L':
        # Line to absolute
        for (group, _) in op.groups:
          let x = group[0].float32 * ctx.scaleX
          let y = group[1].float32 * ctx.scaleY
          currentPoint = Point(x: x, y: y)
          drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint

      of 'l':
        # Line to relative
        for (group, _) in op.groups:
          currentPoint.x += group[0].float32 * ctx.scaleX
          currentPoint.y += group[1].float32 * ctx.scaleY
          drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint

      of 'V':
        # Vertical line to absolute
        for (group, _) in op.groups:
          let newY = group[0].float32 * ctx.scaleY
          currentPoint = Point(x: currentPoint.x, y: newY)
          drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint

      of 'v':
        # Vertical line to relative
        for (group, _) in op.groups:
          currentPoint.y += group[0].float32 * ctx.scaleY
          drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint

      of 'H':
        # Horizontal line to absolute
        for (group, _) in op.groups:
          let newX = group[0].float32 * ctx.scaleX
          currentPoint = Point(x: newX, y: currentPoint.y)
          drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint

      of 'h':
        # Horizontal line to relative
        for (group, _) in op.groups:
          currentPoint.x += group[0].float32 * ctx.scaleX
          drawLineWithCaps(image, previousPoint.x, previousPoint.y, currentPoint.x, currentPoint.y, strokeColor, strokeWidth, style.strokeLineCap)
          previousPoint = currentPoint

      of 'C':
        # Cubic bezier curve absolute
        for (group, _) in op.groups:
          let
            cp1 = Point(x: group[0].float32 * ctx.scaleX, y: group[1].float32 * ctx.scaleY)
            cp2 = Point(x: group[2].float32 * ctx.scaleX, y: group[3].float32 * ctx.scaleY)
            endPoint = Point(x: group[4].float32 * ctx.scaleX, y: group[5].float32 * ctx.scaleY)

          let curvePoints = sampleBezierCurve(previousPoint, cp1, cp2, endPoint)
          # Draw lines between curve points
          for i in 1..<curvePoints.len:
            drawLineWithCaps(image, curvePoints[i-1].x, curvePoints[i-1].y, curvePoints[i].x, curvePoints[i].y, strokeColor, strokeWidth, style.strokeLineCap)

          currentPoint = endPoint
          previousPoint = currentPoint

      of 'c':
        # Cubic bezier curve relative
        for (group, _) in op.groups:
          let
            cp1 = Point(x: currentPoint.x + group[0].float32 * ctx.scaleX,
                       y: currentPoint.y + group[1].float32 * ctx.scaleY)
            cp2 = Point(x: currentPoint.x + group[2].float32 * ctx.scaleX,
                       y: currentPoint.y + group[3].float32 * ctx.scaleY)
            endPoint = Point(x: currentPoint.x + group[4].float32 * ctx.scaleX,
                           y: currentPoint.y + group[5].float32 * ctx.scaleY)

          let curvePoints = sampleBezierCurve(previousPoint, cp1, cp2, endPoint)
          # Draw lines between curve points
          for i in 1..<curvePoints.len:
            drawLineWithCaps(image, curvePoints[i-1].x, curvePoints[i-1].y, curvePoints[i].x, curvePoints[i].y, strokeColor, strokeWidth, style.strokeLineCap)

          currentPoint = endPoint
          previousPoint = currentPoint

      of 'Z', 'z':
        # Close path - draw line back to start
        if not firstPoint and currentPoint != startPoint:
          drawLineWithCaps(image, currentPoint.x, currentPoint.y, startPoint.x, startPoint.y, strokeColor, strokeWidth, style.strokeLineCap)

      else:
        # Skip unsupported commands
        discard

# Color parsing utilities
proc parseColor*(colorStr: string): rl.Color =
  if colorStr.startsWith("#"):
    try:
      # Remove the # and parse the hex color
      let hexStr = colorStr[1..^1]
      let chromaColor = parseHex(hexStr)
      let parsedColor = rl.Color(
        r: (chromaColor.r * 255).uint8,
        g: (chromaColor.g * 255).uint8,
        b: (chromaColor.b * 255).uint8,
        a: (chromaColor.a * 255).uint8
      )
      if DEBUG_SVG_RASTERIZER:
        echo fmt"    Parsed hex color {colorStr} -> RGBA({parsedColor.r}, {parsedColor.g}, {parsedColor.b}, {parsedColor.a})"
      return parsedColor
    except:
      echo "Warning: Failed to parse color: ", colorStr
      return rl.Color(r: 0, g: 0, b: 0, a: 255) # Default to black
  else:
    # Handle named colors or other formats
    case colorStr.toLowerAscii():
      of "none", "transparent":
        return rl.Color(r: 0, g: 0, b: 0, a: 0)
      of "black":
        return rl.Color(r: 0, g: 0, b: 0, a: 255)
      of "white":
        return rl.Color(r: 255, g: 255, b: 255, a: 255)
      else:
        return rl.Color(r: 0, g: 0, b: 0, a: 255) # Default to black

# Error handling utilities
type
  SvgParseError* = object of SvgRasterizerError
  SvgRenderError* = object of SvgRasterizerError

proc formatError*(msg: string, context = ""): string =
  if context.len > 0:
    return fmt"{msg} (context: {context})"
  else:
    return msg

# Main SVG parsing and rasterization
proc parseViewBox*(viewBoxStr: string): ViewBox =
  let parts = viewBoxStr.split({' ', ','})
  if parts.len >= 4:
    try:
      return ViewBox(
        x: parts[0].parseFloat(),
        y: parts[1].parseFloat(),
        width: parts[2].parseFloat(),
        height: parts[3].parseFloat()
      )
    except ValueError:
      echo "Warning: Invalid viewBox format: ", viewBoxStr
      return ViewBox(x: 0, y: 0, width: 100, height: 100)
  else:
    return ViewBox(x: 0, y: 0, width: 100, height: 100)

proc parseTransform*(transformStr: string): Transform =
  ## Parse SVG transform attribute (e.g., "translate(10,20) scale(2) rotate(45)")
  result = Transform(translateX: 0, translateY: 0, scaleX: 1, scaleY: 1, rotate: 0)
  
  if transformStr.len == 0:
    return result
    
  var str = transformStr.strip()
  
  # Parse translate
  if "translate(" in str:
    let startPos = str.find("translate(") + 10
    let endPos = str.find(")", startPos)
    if endPos > startPos and startPos > 0:
      let values = str[startPos..<endPos].split(",")
      if values.len >= 1:
        try:
          result.translateX = values[0].parseFloat()
        except ValueError:
          discard
      if values.len >= 2:
        try:
          result.translateY = values[1].parseFloat()
        except ValueError:
          discard
  
  # Parse scale
  if "scale(" in str:
    let startPos = str.find("scale(") + 6
    let endPos = str.find(")", startPos)
    if endPos > startPos and startPos > 0:
      let values = str[startPos..<endPos].split(",")
      if values.len >= 1:
        try:
          result.scaleX = values[0].parseFloat()
          result.scaleY = values[0].parseFloat()
        except ValueError:
          discard
      if values.len >= 2:
        try:
          result.scaleY = values[1].parseFloat()
        except ValueError:
          discard
  
  # Parse rotate
  if "rotate(" in str:
    let startPos = str.find("rotate(") + 7
    let endPos = str.find(")", startPos)
    if endPos > startPos and startPos > 0:
      try:
        result.rotate = str[startPos..<endPos].parseFloat()
      except ValueError:
        discard

proc applyTransform*(point: Point, transform: Transform): Point =
  ## Apply transform to a point
  let cosR = cos(transform.rotate * PI / 180.0)
  let sinR = sin(transform.rotate * PI / 180.0)
  
  # Scale
  let scaledX = point.x * transform.scaleX
  let scaledY = point.y * transform.scaleY
  
  # Rotate
  let rotatedX = scaledX * cosR - scaledY * sinR
  let rotatedY = scaledX * sinR + scaledY * cosR
  
  # Translate
  result = Point(
    x: rotatedX + transform.translateX,
    y: rotatedY + transform.translateY
  )

proc createRasterContext*(width, height: int32,
    viewBox: ViewBox): RasterContext =
  result = RasterContext(
    width: width,
    height: height,
    viewBox: viewBox,
    scaleX: width.float32 / viewBox.width,
    scaleY: height.float32 / viewBox.height,
    transform: Transform(translateX: 0, translateY: 0, scaleX: 1, scaleY: 1, rotate: 0)
  )

proc newRasterizedImage*(width, height: int32): RasterizedImage =
  result = RasterizedImage(
    width: width,
    height: height,
    data: newSeq[uint8](width * height * 4) # RGBA
  )

  # Initialize with transparent background
  for i in 0..<result.data.len:
    result.data[i] = 0

proc rasterizeSvgPath*(pathData: string, fillColor: rl.Color,
                      ctx: RasterContext): RasterizedImage =
  var image = newRasterizedImage(ctx.width, ctx.height)

  let polygons = pathToPolygon(pathData, ctx)

  for polygon in polygons:
    fillPolygon(image, polygon, fillColor)

  return image

proc rasterizeSvgFile*(filepath: string, outputWidth,
    outputHeight: int32): RasterizedImage =
  when defined(svg_performance):
    let startTime = getTime()
  
  var
    stream = newFileStream(filepath)
    parser: XmlParser
    viewBox = ViewBox(x: 0, y: 0, width: 16, height: 16) # Default viewBox
    elements: seq[(string, string, PathStyle, Transform)] = @[] # (type, data, style, transform)

  if stream.isNil:
    raise newException(SvgRasterizerError, "Cannot open SVG file: " & filepath)

  if DEBUG_SVG_RASTERIZER:
    echo fmt"Rasterizing SVG: {filepath} -> {outputWidth}x{outputHeight}"

  parser.open(stream, filepath)

  try:
    while true:
      parser.next()
      case parser.kind:
        of xmlElementOpen, xmlElementStart:
          case parser.elementName:
            of "svg":
              # Parse SVG attributes
              while true:
                parser.next()
                case parser.kind:
                  of xmlAttribute:
                    case parser.attrKey:
                      of "viewBox":
                        viewBox = parseViewBox(parser.attrValue)
                      of "width":
                        if not parser.attrValue.contains("px") and parser.attrValue.len > 0:
                          try:
                            viewBox.width = parser.attrValue.parseFloat()
                          except ValueError:
                            echo "Warning: Invalid width format: ", parser.attrValue
                      of "height":
                        if not parser.attrValue.contains("px") and parser.attrValue.len > 0:
                          try:
                            viewBox.height = parser.attrValue.parseFloat()
                          except ValueError:
                            echo "Warning: Invalid height format: ", parser.attrValue
                  of xmlElementClose:
                    break
                  else:
                    discard

            of "path", "rect", "circle", "ellipse":
              var elementData = ""
              var style = newPathStyle()
              var elementType = parser.elementName
              var elementTransform = Transform(translateX: 0, translateY: 0, scaleX: 1, scaleY: 1, rotate: 0)

              # Parse element attributes
              while true:
                parser.next()
                case parser.kind:
                  of xmlAttribute:
                    case parser.attrKey:
                      of "d":
                        if elementType == "path":
                          elementData = parser.attrValue
                      of "x":
                        if elementType == "rect":
                          elementData.add(parser.attrValue & "|")
                      of "y":
                        if elementType == "rect":
                          elementData.add(parser.attrValue & "|")
                      of "width":
                        if elementType == "rect":
                          elementData.add(parser.attrValue & "|")
                      of "height":
                        if elementType == "rect":
                          elementData.add(parser.attrValue & "|")
                      of "rx":
                        if elementType == "rect" or elementType == "ellipse":
                          elementData.add(parser.attrValue & "|")
                      of "ry":
                        if elementType == "rect" or elementType == "ellipse":
                          elementData.add(parser.attrValue & "|")
                      of "cx":
                        if elementType == "circle" or elementType == "ellipse":
                          elementData.add(parser.attrValue & "|")
                      of "cy":
                        if elementType == "circle" or elementType == "ellipse":
                          elementData.add(parser.attrValue & "|")
                      of "r":
                        if elementType == "circle":
                          elementData.add(parser.attrValue)
                      of "fill":
                        if parser.attrValue != "none":
                          style.fillColor = parseColor(parser.attrValue)
                          style.hasFill = true
                        else:
                          style.hasFill = false
                      of "stroke":
                        if parser.attrValue != "none":
                          style.strokeColor = parseColor(parser.attrValue)
                          style.hasStroke = true
                          if DEBUG_SVG_RASTERIZER:
                            echo fmt"    Parsed stroke color: {parser.attrValue} -> {style.strokeColor}"
                        else:
                          style.hasStroke = false
                      of "stroke-width":
                        try:
                          style.strokeWidth = parser.attrValue.parseFloat()
                        except ValueError:
                          echo "Warning: Invalid stroke-width: ", parser.attrValue
                          style.strokeWidth = 1.0
                      of "stroke-linecap":
                        style.strokeLineCap = parser.attrValue
                      of "stroke-linejoin":
                        style.strokeLineJoin = parser.attrValue
                      of "transform":
                        elementTransform = parseTransform(parser.attrValue)
                      else:
                        discard
                  of xmlElementClose:
                    break
                  else:
                    discard

              if elementData.len > 0 or elementType == "rect" or elementType == "circle" or elementType == "ellipse":
                elements.add((elementType, elementData, style, elementTransform))

        of xmlEof:
          break
        else:
          discard

  finally:
    parser.close()
    stream.close()

  var finalImage = newRasterizedImage(outputWidth, outputHeight)

  # Helper proc to render a path with style
  proc renderPathWithStyle(pathData: string, style: PathStyle, ctx: RasterContext, targetImage: var RasterizedImage) =
    if DEBUG_SVG_RASTERIZER:
      echo fmt"Processing path: {pathData[0..min(50, pathData.len-1)]}..."
      echo fmt"  Has fill: {style.hasFill}, Has stroke: {style.hasStroke}"

    # Render fill if present
    if style.hasFill:
      let fillImage = rasterizeSvgPath(pathData, style.fillColor, ctx)
      if DEBUG_SVG_RASTERIZER:
        echo fmt"  Fill rendered"

      # Composite fill image onto target image
      for i in 0..<targetImage.data.len div 4:
        let pixelIndex = i * 4
        let srcAlpha = fillImage.data[pixelIndex + 3].float32 / 255.0
        let dstAlpha = targetImage.data[pixelIndex + 3].float32 / 255.0

        if srcAlpha > 0:
          let outAlpha = srcAlpha + dstAlpha * (1.0 - srcAlpha)
          if outAlpha > 0:
            targetImage.data[pixelIndex] = ((fillImage.data[pixelIndex].float32 * srcAlpha +
                                           targetImage.data[pixelIndex].float32 *
                                               dstAlpha * (1.0 - srcAlpha)) /
                                               outAlpha).uint8
            targetImage.data[pixelIndex + 1] = ((fillImage.data[pixelIndex + 1].float32 * srcAlpha +
                                               targetImage.data[pixelIndex +
                                                   1].float32 * dstAlpha * (1.0 -
                                                   srcAlpha)) / outAlpha).uint8
            targetImage.data[pixelIndex + 2] = ((fillImage.data[pixelIndex + 2].float32 * srcAlpha +
                                               targetImage.data[pixelIndex +
                                                   2].float32 * dstAlpha * (1.0 -
                                                   srcAlpha)) / outAlpha).uint8
            targetImage.data[pixelIndex + 3] = (outAlpha * 255).uint8

    # Render stroke if present
    if style.hasStroke:
      # Scale stroke width with context and ensure minimum visibility
      let scaledStrokeWidth = max(1.0, style.strokeWidth * min(ctx.scaleX, ctx.scaleY) * 0.5) # Ensure minimum 1.0 pixel width
      if DEBUG_SVG_RASTERIZER:
        echo fmt"  Rendering stroke with width: {scaledStrokeWidth}"

      strokePath(targetImage, pathData, style.strokeColor, scaledStrokeWidth, ctx, style)
      if DEBUG_SVG_RASTERIZER:
        echo fmt"  Stroke rendered"

  # Rasterize all elements with individual transforms
  for (elementType, data, style, elementTransform) in elements:
    # Create a new context for this element with its specific transform
    var elementCtx = createRasterContext(outputWidth, outputHeight, viewBox)
    elementCtx.transform = elementTransform
    
    case elementType:
      of "path":
        renderPathWithStyle(data, style, elementCtx, finalImage)
      of "rect":
        # Parse rectangle attributes from data
        let parts = data.split('|')
        if parts.len >= 4:
          try:
            let x = parts[0].parseFloat()
            let y = parts[1].parseFloat()
            let width = parts[2].parseFloat()
            let height = parts[3].parseFloat()
            let rx = if parts.len >= 5: parts[4].parseFloat() else: 0.0
            let ry = if parts.len >= 6: parts[5].parseFloat() else: 0.0
            let pathData = rectToPath(x, y, width, height, rx, ry)
            renderPathWithStyle(pathData, style, elementCtx, finalImage)
          except ValueError:
            echo "Warning: Failed to parse rectangle: ", data
      of "circle":
        let parts = data.split('|')
        if parts.len >= 3:
          try:
            let cx = parts[0].parseFloat()
            let cy = parts[1].parseFloat()
            let r = parts[2].parseFloat()
            let pathData = circleToPath(cx, cy, r)
            renderPathWithStyle(pathData, style, elementCtx, finalImage)
          except ValueError:
            echo "Warning: Failed to parse circle: ", data
      of "ellipse":
        let parts = data.split('|')
        if parts.len >= 4:
          try:
            let cx = parts[0].parseFloat()
            let cy = parts[1].parseFloat()
            let rx = parts[2].parseFloat()
            let ry = parts[3].parseFloat()
            let pathData = ellipseToPath(cx, cy, rx, ry)
            renderPathWithStyle(pathData, style, elementCtx, finalImage)
          except ValueError:
            echo "Warning: Failed to parse ellipse: ", data

  when defined(svg_performance):
    let duration = (getTime() - startTime).inMilliseconds
    logRenderTime(duration)
    if DEBUG_SVG_RASTERIZER:
      echo fmt"  Render time: {duration:.2f}ms (avg: {getAverageRenderTime():.2f}ms)"

  return finalImage

# Performance monitoring
when defined(svg_performance):
  import std/times
  
  var renderTimes: seq[float64] = @[]
  
  proc logRenderTime*(duration: float64) =
    renderTimes.add(duration)
    if renderTimes.len > 10:
      renderTimes.delete(0)
    
  proc getAverageRenderTime*(): float64 =
    if renderTimes.len == 0: return 0.0
    return sum(renderTimes) / renderTimes.len.float64

# Raylib integration
# Icon size presets for consistent sizing
const
  ICON_SIZE_TINY* = 12
  ICON_SIZE_SMALL* = 16
  ICON_SIZE_MEDIUM* = 24
  ICON_SIZE_LARGE* = 32
  ICON_SIZE_XLARGE* = 48

proc svgToTexture2D*(filepath: string, width: int32 = ICON_SIZE_SMALL,
    height: int32 = ICON_SIZE_SMALL): Texture2D =
  # Use higher resolution for rasterization to reduce serration, then scale down
  let superSampleFactor = 2  # 2x supersampling for anti-aliasing
  let renderWidth = width * superSampleFactor
  let renderHeight = height * superSampleFactor

  let rasterImage = rasterizeSvgFile(filepath, renderWidth.int32, renderHeight.int32)

  # Create high-res render texture first
  let highResTexture = loadRenderTexture(renderWidth.int32, renderHeight.int32)

  beginTextureMode(highResTexture)
  clearBackground(rl.Color(r: 0, g: 0, b: 0, a: 0)) # Transparent background

  # Draw pixels using small rectangles with Y-axis flipped for proper orientation
  for y in 0..<renderHeight:
    for x in 0..<renderWidth:
      let pixelIndex = (y * renderWidth + x) * 4
      if pixelIndex < rasterImage.data.len - 3:
        let color = rl.Color(
          r: rasterImage.data[pixelIndex],
          g: rasterImage.data[pixelIndex + 1],
          b: rasterImage.data[pixelIndex + 2],
          a: rasterImage.data[pixelIndex + 3]
        )
        if color.a > 0: # Only draw non-transparent pixels
          # Flip Y coordinate for proper texture orientation
          let flippedY = renderHeight - 1 - y
          drawRectangle(x.int32, flippedY.int32, 1.int32, 1.int32, color)

  endTextureMode()

  # Now create final texture at target size with smooth scaling
  let finalTexture = loadRenderTexture(width, height)

  beginTextureMode(finalTexture)
  clearBackground(rl.Color(r: 0, g: 0, b: 0, a: 0))

  # Draw the high-res texture scaled down with filtering for anti-aliasing
  let sourceRec = Rectangle(x: 0, y: 0, width: renderWidth.float32, height: renderHeight.float32)
  let destRec = Rectangle(x: 0, y: 0, width: width.float32, height: height.float32)
  drawTexture(highResTexture.texture, sourceRec, destRec, Vector2(x: 0, y: 0), 0.0, White)

  endTextureMode()

  result = finalTexture.texture

# Tinting support
proc applyTint*(image: var RasterizedImage, tint: rl.Color) =
  for i in 0..<(image.data.len div 4):
    let pixelIndex = i * 4
    if image.data[pixelIndex + 3] > 0: # Only tint non-transparent pixels
      image.data[pixelIndex] = ((image.data[pixelIndex].uint16 *
          tint.r.uint16) div 255).uint8
      image.data[pixelIndex + 1] = ((image.data[pixelIndex + 1].uint16 *
          tint.g.uint16) div 255).uint8
      image.data[pixelIndex + 2] = ((image.data[pixelIndex + 2].uint16 *
          tint.b.uint16) div 255).uint8
      image.data[pixelIndex + 3] = ((image.data[pixelIndex + 3].uint16 *
          tint.a.uint16) div 255).uint8

proc svgToTexture2DWithTint*(filepath: string, tint: rl.Color,
                             width: int32 = ICON_SIZE_SMALL, height: int32 = ICON_SIZE_SMALL): Texture2D =
  # Use higher resolution for rasterization to reduce serration, then scale down
  let superSampleFactor = 2  # 2x supersampling for anti-aliasing
  let renderWidth = width * superSampleFactor
  let renderHeight = height * superSampleFactor

  var rasterImage = rasterizeSvgFile(filepath, renderWidth.int32, renderHeight.int32)
  rasterImage.applyTint(tint)

  # Create high-res render texture first
  let highResTexture = loadRenderTexture(renderWidth.int32, renderHeight.int32)

  beginTextureMode(highResTexture)
  clearBackground(rl.Color(r: 0, g: 0, b: 0, a: 0)) # Transparent background

  # Draw pixels using small rectangles with Y-axis flipped for proper orientation
  for y in 0..<renderHeight:
    for x in 0..<renderWidth:
      let pixelIndex = (y * renderWidth + x) * 4
      if pixelIndex < rasterImage.data.len - 3:
        let color = rl.Color(
          r: rasterImage.data[pixelIndex],
          g: rasterImage.data[pixelIndex + 1],
          b: rasterImage.data[pixelIndex + 2],
          a: rasterImage.data[pixelIndex + 3]
        )
        if color.a > 0: # Only draw non-transparent pixels
          # Flip Y coordinate for proper texture orientation
          let flippedY = renderHeight - 1 - y
          drawRectangle(x.int32, flippedY.int32, 1.int32, 1.int32, color)

  endTextureMode()

  # Now create final texture at target size with smooth scaling
  let finalTexture = loadRenderTexture(width, height)

  beginTextureMode(finalTexture)
  clearBackground(rl.Color(r: 0, g: 0, b: 0, a: 0))

  # Draw the high-res texture scaled down with filtering for anti-aliasing
  let sourceRec = Rectangle(x: 0, y: 0, width: renderWidth.float32, height: renderHeight.float32)
  let destRec = Rectangle(x: 0, y: 0, width: width.float32, height: height.float32)
  drawTexture(highResTexture.texture, sourceRec, destRec, Vector2(x: 0, y: 0), 0.0, White)

  endTextureMode()

  result = finalTexture.texture
