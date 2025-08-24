import std/[parsexml, strutils, strformat, tables]
import raylib as rl
import ./[pathdata, vector, styleparse, common]

# Helper function for cubic bezier curve calculation
proc bezierCubic(p0, p1, p2, p3: Vec2, t: float64): Vec2 =
  let
    t2 = t * t
    t3 = t2 * t
    mt = 1.0 - t
    mt2 = mt * mt
    mt3 = mt2 * mt
  
  result = p0 * mt3 + p1 * (3.0 * mt2 * t) + p2 * (3.0 * mt * t2) + p3 * t3

# Helper to multiply two rl.Color values (component-wise)
proc colorMul(a, b: rl.Color): rl.Color =
  rl.Color(
    r: (a.r.uint16 * b.r.uint16 div 255).uint8,
    g: (a.g.uint16 * b.g.uint16 div 255).uint8,
    b: (a.b.uint16 * b.b.uint16 div 255).uint8,
    a: (a.a.uint16 * b.a.uint16 div 255).uint8
  )

type
  Shape* = object
    id*: string
    point*: Vec2
    style*: Style
  Rect* = object
    shape*: Shape
    width*, height*: float64
  Circle* = object
    shape*: Shape
    radius*: float64
  Ellipse* = object
    shape*: Shape
    rx*, ry*: float64
  Path* = object
    shape*: Shape
    data*: string
  Line* = object
    shape*: Shape
    x2*, y2*: float64
  Polyline* = object
    shape*: Shape
    points*: seq[Vec2]

  Polygon* = object
    shape*: Shape
    points*: seq[Vec2]

func `$`(s: Stroke): string = fmt"color=<{s.color}>, width=<{s.width}>"
func `$`(s: Style): string = fmt"fill=<{s.fill}>, stroke=<{s.stroke}>"
func `$`(s: Shape): string = fmt"id=<{s.id}>, pos=<{s.point.x},{s.point.y}>, style=<{s.style}>"
func `$`(r: Rect): string = fmt"Rect[size=<{r.width},{r.height}>, shape=<{r.shape}>]"
func `$`(c: Circle): string = fmt"Circle[radius=<{c.radius}>, shape=<{c.shape}>]"
func `$`(e: Ellipse): string = fmt"Ellipse[rx=<{e.rx}>, ry=<{e.ry}>, shape=<{e.shape}>]"
func `$`(p: Path): string = fmt"Path[data=<{p.data}>, shape=<{p.shape}>]"
func `$`(l: Line): string = fmt"Line[x2=<{l.x2}>, y2=<{l.y2}>, shape=<{l.shape}>]"
func `$`(pl: Polyline): string = fmt"Polyline[points=<{pl.points.len}>, shape=<{pl.shape}>]"
func `$`(pg: Polygon): string = fmt"Polygon[points=<{pg.points.len}>, shape=<{pg.shape}>]"

func initStyle(classMap: ClassMap, className, styleStr: string, scale: float64): Style =
  if className.len > 0:
    return classMap[className]
  parseStyle(styleStr, scale)

func initShape(id: string, point: Vec2, style: Style, scale: float64): Shape =
  Shape(id: id, point: point, style: style)

func initShape(id: string, point: Vec2, styleStr: string, scale: float64): Shape =
  initShape(id, point, parseStyle(styleStr, scale), scale)

proc parseCommonAttributes(p: var XmlParser, classMap: ClassMap, scale: float64): tuple[
    id: string, point: Vec2, style: Style, className: string] =
  var
    id, styleStr: string
    point = Vec2(x: 0.0, y: 0.0)
    className = ""
  
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "id": id = p.attrValue
          of "x": point.x = p.attrValue.parseFloat() * scale
          of "y": point.y = p.attrValue.parseFloat() * scale
          of "style": styleStr = p.attrValue
          of "class": className = p.attrValue
          of "fill": 
            # Handle inline fill attribute
            if styleStr.len == 0:
              styleStr = "fill: " & p.attrValue
            else:
              styleStr &= "; fill: " & p.attrValue
          of "stroke": 
            # Handle inline stroke attribute
            if styleStr.len == 0:
              styleStr = "stroke: " & p.attrValue
            else:
              styleStr &= "; stroke: " & p.attrValue
          of "stroke-width": 
            # Handle inline stroke-width attribute
            if styleStr.len == 0:
              styleStr = "stroke-width: " & p.attrValue
            else:
              styleStr &= "; stroke-width: " & p.attrValue
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  let style = initStyle(classMap, className, styleStr, scale)
  (id, point, style, className)

proc parseRect*(p: var XmlParser, classMap: ClassMap, scale: float64): Rect =
  var width, height: float64
  let (id, point, style, _) = parseCommonAttributes(p, classMap, scale)
  
  # Parse rect-specific attributes
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "width": width = p.attrValue.parseFloat() * scale
          of "height": height = p.attrValue.parseFloat() * scale
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  Rect(
    shape: initShape(id, point, style, scale),
    width: width,
    height: height,
  )

proc parseCircle*(p: var XmlParser, classMap: ClassMap, scale: float64): Circle =
  var radius: float64
  let (id, point, style, _) = parseCommonAttributes(p, classMap, scale)
  
  # Parse circle-specific attributes
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "r": radius = p.attrValue.parseFloat() * scale
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  Circle(
    shape: initShape(id, point, style, scale),
    radius: radius,
  )

proc parsePath*(p: var XmlParser, classMap: ClassMap, scale: float64): Path =
  var
    id, styleStr, data: string
    point: Vec2
    className = ""
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "id": id = p.attrValue
          of "x": point.x = p.attrValue.parseFloat() * scale
          of "y": point.y = p.attrValue.parseFloat() * scale
          of "style": styleStr = p.attrValue
          of "d": data = p.attrValue
          of "class": className = p.attrValue
          of "fill": 
            # Handle inline fill attribute
            if styleStr.len == 0:
              styleStr = "fill: " & p.attrValue
            else:
              styleStr &= "; fill: " & p.attrValue
          of "stroke": 
            # Handle inline stroke attribute
            if styleStr.len == 0:
              styleStr = "stroke: " & p.attrValue
            else:
              styleStr &= "; stroke: " & p.attrValue
          of "stroke-width": 
            # Handle inline stroke-width attribute
            if styleStr.len == 0:
              styleStr = "stroke-width: " & p.attrValue
            else:
              styleStr &= "; stroke-width: " & p.attrValue
      of xmlElementClose:
        p.next()
        break
      else: discard
  let style = initStyle(classMap, className, styleStr, scale)
  Path(
    shape: initShape(id, point, style, scale),
    data: data,
  )

proc drawStroke(stroke: Stroke, rect: rl.Rectangle) =
  if stroke.width > 0.0:
    rl.drawRectangleLines(rect, stroke.width.float32, stroke.color)

proc drawStroke(stroke: Stroke, center: rl.Vector2, radius: float32) =
  if stroke.width > 0.0:
    rl.drawCircleLines(center.x.int32, center.y.int32, radius, stroke.color)

proc draw*(r: Rect, target: RenderTexture2D) =
  let rect = rl.Rectangle(
    x: r.shape.point.x.float32,
    y: r.shape.point.y.float32,
    width: r.width.float32,
    height: r.height.float32
  )

  # Draw fill if not transparent
  if r.shape.style.fill.a > 0:
    rl.drawRectangle(rect, r.shape.style.fill)

  # Draw stroke if width > 0 and not transparent
  if r.shape.style.stroke.width > 0.0 and r.shape.style.stroke.color.a > 0:
    drawStroke(r.shape.style.stroke, rect)

proc draw*(c: Circle, target: RenderTexture2D) =
  let center = rl.Vector2(
    x: c.shape.point.x.float32,
    y: c.shape.point.y.float32
  )
  let radius = c.radius.float32

  # Draw fill if not transparent
  if c.shape.style.fill.a > 0:
    rl.drawCircle(center, radius, c.shape.style.fill)

  # Draw stroke if width > 0 and not transparent
  if c.shape.style.stroke.width > 0.0 and c.shape.style.stroke.color.a > 0:
    drawStroke(c.shape.style.stroke, center, radius)

proc parseEllipse*(p: var XmlParser, classMap: ClassMap, scale: float64): Ellipse =
  var rx, ry: float64
  let (id, point, style, _) = parseCommonAttributes(p, classMap, scale)
  
  # Parse ellipse-specific attributes
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "rx": rx = p.attrValue.parseFloat() * scale
          of "ry": ry = p.attrValue.parseFloat() * scale
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  Ellipse(
    shape: initShape(id, point, style, scale),
    rx: rx,
    ry: ry,
  )

proc parseLine*(p: var XmlParser, classMap: ClassMap, scale: float64): Line =
  var x2, y2: float64
  let (id, point, style, _) = parseCommonAttributes(p, classMap, scale)
  
  # Parse line-specific attributes
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "x2": x2 = p.attrValue.parseFloat() * scale
          of "y2": y2 = p.attrValue.parseFloat() * scale
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  Line(
    shape: initShape(id, point, style, scale),
    x2: x2,
    y2: y2,
  )

proc parsePolyline*(p: var XmlParser, classMap: ClassMap, scale: float64): Polyline =
  var pointsStr = ""
  let (id, point, style, _) = parseCommonAttributes(p, classMap, scale)
  
  # Parse polyline-specific attributes
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "points": pointsStr = p.attrValue
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  # Parse points from "x1,y1 x2,y2 x3,y3" format
  var points: seq[Vec2] = @[]
  if pointsStr.len > 0:
    let pointPairs = pointsStr.split(' ')
    for pair in pointPairs:
      if pair.len > 0:
        let coords = pair.split(',')
        if coords.len >= 2:
          try:
            let x = parseFloat(coords[0]) * scale
            let y = parseFloat(coords[1]) * scale
            points.add(Vec2(x: x, y: y))
          except ValueError:
            discard
  
  Polyline(
    shape: initShape(id, point, style, scale),
    points: points,
  )

proc draw*(e: Ellipse, target: RenderTexture2D) =
  let center = rl.Vector2(
    x: e.shape.point.x.float32,
    y: e.shape.point.y.float32
  )
  let rx = e.rx.float32
  let ry = e.ry.float32

  # Draw fill if not transparent
  if e.shape.style.fill.a > 0:
    rl.drawEllipse(center.x.int32, center.y.int32, rx, ry, e.shape.style.fill)

  # Draw stroke if width > 0 and not transparent
  if e.shape.style.stroke.width > 0.0 and e.shape.style.stroke.color.a > 0:
    # Note: Raylib doesn't have ellipse stroke, so we'll approximate with scaled circle
    # For now, use the average radius
    let avgRadius = (rx + ry) / 2.0
    rl.drawCircleLines(center.x.int32, center.y.int32, avgRadius, e.shape.style.stroke.color)

type UnimplementedPathCmdError* = object of CatchableError

proc draw*(p: Path, target: RenderTexture2D, scale: float64, tint: rl.Color = rl.WHITE) =
  ## All other shapes have scaling pre-calculated when the shape object is created,
  ## but paths are different because their line commands need to know scaling at draw
  ## time, not just at path object creation time. That is why `scale` is only an
  ## argument in this draw function.

  var
    currentPoint: Vec2
    pathPoints: seq[rl.Vector2]
    segments: seq[seq[rl.Vector2]]
    startPoint: Vec2  # For close path command
    totalPoints = 0

  # Parse path data and convert to line segments for Raylib
  for op in p.data.ops:
    case op.cmd:
      of 'M':
        # Move to - start new segment
        if pathPoints.len > 0:
          segments.add(pathPoints)
          pathPoints = @[]
        for (group, idx) in op.groups:
          currentPoint = Vec2(x: group[0], y: group[1]) * scale
          if idx == 0:
            startPoint = currentPoint  # Remember start point for close path
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'm':
        # Move to relative - start new segment
        if pathPoints.len > 0:
          segments.add(pathPoints)
          pathPoints = @[]
        for (group, idx) in op.groups:
          currentPoint += Vec2(x: group[0], y: group[1]) * scale
          if idx == 0:
            startPoint = currentPoint  # Remember start point for close path
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'L':
        # Line to absolute
        for (group, _) in op.groups:
          currentPoint = Vec2(x: group[0], y: group[1]) * scale
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'l':
        # Line to relative
        for (group, _) in op.groups:
          currentPoint += Vec2(x: group[0], y: group[1]) * scale
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'H':
        # Horizontal line to absolute
        for (group, _) in op.groups:
          currentPoint.x = group[0] * scale
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'h':
        # Horizontal line to relative
        for (group, _) in op.groups:
          currentPoint.x += group[0] * scale
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'V':
        # Vertical line to absolute
        for (group, _) in op.groups:
          currentPoint.y = group[0] * scale
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'v':
        # Vertical line to relative
        for (group, _) in op.groups:
          currentPoint.y += group[0] * scale
          pathPoints.add(rl.Vector2(x: currentPoint.x.float32, y: currentPoint.y.float32))
          totalPoints += 1
      of 'C':
        # Cubic bezier curve absolute - sample points along the curve
        for (group, _) in op.groups:
          let
            cp1 = Vec2(x: group[0], y: group[1]) * scale  # Control point 1
            cp2 = Vec2(x: group[2], y: group[3]) * scale  # Control point 2
            endPoint = Vec2(x: group[4], y: group[5]) * scale  # End point
          
          # Adaptive sampling based on curve complexity
          let curveLength = (currentPoint - cp1).length() + (cp1 - cp2).length() + (cp2 - endPoint).length()
          let segments = max(8, int(curveLength / 8.0))  # More segments for complex curves
          
          for i in 0..segments:
            let tNorm = i.float64 / segments.float64
            let point = bezierCubic(currentPoint, cp1, cp2, endPoint, tNorm)
            pathPoints.add(rl.Vector2(x: point.x.float32, y: point.y.float32))
            totalPoints += 1
          
          currentPoint = endPoint
      of 'c':
        # Cubic bezier curve relative - sample points along the curve
        for (group, _) in op.groups:
          let
            cp1 = currentPoint + (Vec2(x: group[0], y: group[1]) * scale)  # Control point 1
            cp2 = currentPoint + (Vec2(x: group[2], y: group[3]) * scale)  # Control point 2
            endPoint = currentPoint + (Vec2(x: group[4], y: group[5]) * scale)  # End point
          
          # Adaptive sampling based on curve complexity
          let curveLength = (currentPoint - cp1).length() + (cp1 - cp2).length() + (cp2 - endPoint).length()
          let segments = max(8, int(curveLength / 8.0))  # More segments for complex curves
          
          for i in 0..segments:
            let tNorm = i.float64 / segments.float64
            let point = bezierCubic(currentPoint, cp1, cp2, endPoint, tNorm)
            pathPoints.add(rl.Vector2(x: point.x.float32, y: point.y.float32))
            totalPoints += 1
          
          currentPoint = endPoint
      of 'Z', 'z':
        # Close path - connect back to start point
        if pathPoints.len > 0 and startPoint != currentPoint:
          pathPoints.add(rl.Vector2(x: startPoint.x.float32, y: startPoint.y.float32))
          totalPoints += 1
      of 'Q':
        # Quadratic bezier curve absolute
        for (group, _) in op.groups:
          let
            cp = Vec2(x: group[0], y: group[1]) * scale  # Control point
            endPoint = Vec2(x: group[2], y: group[3]) * scale  # End point
          
          # Adaptive sampling based on curve complexity
          let curveLength = (currentPoint - cp).length() + (cp - endPoint).length()
          let segments = max(8, int(curveLength / 5.0))  # More segments for complex curves
          
          for i in 0..segments:
            let tNorm = i.float64 / segments.float64
            let mt = 1.0 - tNorm
            let point = currentPoint * (mt * mt) + cp * (2.0 * mt * tNorm) + endPoint * (tNorm * tNorm)
            pathPoints.add(rl.Vector2(x: point.x.float32, y: point.y.float32))
            totalPoints += 1
          
          currentPoint = endPoint
      of 'q':
        # Quadratic bezier curve relative
        for (group, _) in op.groups:
          let
            cp = currentPoint + (Vec2(x: group[0], y: group[1]) * scale)  # Control point
            endPoint = currentPoint + (Vec2(x: group[2], y: group[3]) * scale)  # End point
          
          # Adaptive sampling based on curve complexity
          let curveLength = (currentPoint - cp).length() + (cp - endPoint).length()
          let segments = max(8, int(curveLength / 5.0))  # More segments for complex curves
          
          for i in 0..segments:
            let tNorm = i.float64 / segments.float64
            let mt = 1.0 - tNorm
            let point = currentPoint * (mt * mt) + cp * (2.0 * mt * tNorm) + endPoint * (tNorm * tNorm)
            pathPoints.add(rl.Vector2(x: point.x.float32, y: point.y.float32))
            totalPoints += 1
          
          currentPoint = endPoint
      of 'T':
        # Smooth quadratic bezier curve absolute
        for (group, _) in op.groups:
          let endPoint = Vec2(x: group[0], y: group[1]) * scale
          
          # For smooth quadratic, control point is reflection of previous control point
          # For now, use a simple line approximation
          let point = currentPoint + (endPoint - currentPoint) * 0.5
          pathPoints.add(rl.Vector2(x: point.x.float32, y: point.y.float32))
          totalPoints += 1
          
          pathPoints.add(rl.Vector2(x: endPoint.x.float32, y: endPoint.y.float32))
          totalPoints += 1
          
          currentPoint = endPoint
      of 't':
        # Smooth quadratic bezier curve relative
        for (group, _) in op.groups:
          let endPoint = currentPoint + (Vec2(x: group[0], y: group[1]) * scale)
          
          # For smooth quadratic, control point is reflection of previous control point
          # For now, use a simple line approximation
          let point = currentPoint + (endPoint - currentPoint) * 0.5
          pathPoints.add(rl.Vector2(x: point.x.float32, y: point.y.float32))
          totalPoints += 1
          
          pathPoints.add(rl.Vector2(x: endPoint.x.float32, y: endPoint.y.float32))
          totalPoints += 1
          
          currentPoint = endPoint
      else:
        raise newException(UnimplementedPathCmdError, "Unimplemented path command: " & op.cmd)

  # Add final segment
  if pathPoints.len > 0:
    segments.add(pathPoints)

  # Draw all segments
  for segment in segments:
    if segment.len > 1:
      # Draw lines between consecutive points
      for i in 0..<(segment.len - 1):
        if p.shape.style.stroke.width > 0.0 and p.shape.style.stroke.color.a > 0:
          rl.drawLine(segment[i], segment[i + 1], p.shape.style.stroke.width.float32, colorMul(p.shape.style.stroke.color, tint))

      # For filled paths, use polygon fill
      if p.shape.style.fill.a > 0 and segment.len >= 3:
        let fillColor = colorMul(p.shape.style.fill, tint)
        
        # Draw the polygon outline first
        for i in 0..<segment.len:
          let next = (i + 1) mod segment.len
          rl.drawLine(segment[i], segment[next], 2.0, fillColor)
        
        # For complex shapes, just draw the outline and let the stroke handle the fill
        # The stroke color should be the same as fill for filled shapes
        if p.shape.style.stroke.width > 0.0:
          for i in 0..<segment.len:
            let next = (i + 1) mod segment.len
            rl.drawLine(segment[i], segment[next], p.shape.style.stroke.width.float32, colorMul(p.shape.style.stroke.color, tint))

proc parsePolygon*(p: var XmlParser, classMap: ClassMap, scale: float64): Polygon =
  var pointsStr = ""
  let (id, point, style, _) = parseCommonAttributes(p, classMap, scale)
  
  # Parse polygon-specific attributes
  while true:
    p.next()
    case p.kind:
      of xmlAttribute:
        case p.attrKey:
          of "points": pointsStr = p.attrValue
      of xmlElementClose:
        p.next()
        break
      else: discard
  
  # Parse points from "x1,y1 x2,y2 x3,y3" format (same as polyline)
  var points: seq[Vec2] = @[]
  if pointsStr.len > 0:
    let pointPairs = pointsStr.split(' ')
    for pair in pointPairs:
      if pair.len > 0:
        let coords = pair.split(',')
        if coords.len >= 2:
          try:
            let x = parseFloat(coords[0]) * scale
            let y = parseFloat(coords[1]) * scale
            points.add(Vec2(x: x, y: y))
          except ValueError:
            discard
  
  Polygon(
    shape: initShape(id, point, style, scale),
    points: points,
  )

proc draw*(l: Line, target: RenderTexture2D) =
  let start = rl.Vector2(
    x: l.shape.point.x.float32,
    y: l.shape.point.y.float32
  )
  let endPoint = rl.Vector2(
    x: l.x2.float32,
    y: l.y2.float32
  )

  # Draw line
  if l.shape.style.stroke.width > 0.0 and l.shape.style.stroke.color.a > 0:
    rl.drawLine(start, endPoint, l.shape.style.stroke.width.float32, l.shape.style.stroke.color)

proc draw*(pl: Polyline, target: RenderTexture2D) =
  if pl.points.len < 2:
    return

  # Draw polyline segments
  if pl.shape.style.stroke.width > 0.0 and pl.shape.style.stroke.color.a > 0:
    for i in 0..<(pl.points.len - 1):
      let start = rl.Vector2(
        x: pl.points[i].x.float32,
        y: pl.points[i].y.float32
      )
      let endPoint = rl.Vector2(
        x: pl.points[i + 1].x.float32,
        y: pl.points[i + 1].y.float32
      )
      rl.drawLine(start, endPoint, pl.shape.style.stroke.width.float32, pl.shape.style.stroke.color)

proc draw*(pg: Polygon, target: RenderTexture2D) =
  if pg.points.len < 3:
    return

  var points = newSeq[rl.Vector2](pg.points.len)
  for i in 0..<pg.points.len:
    points[i] = rl.Vector2(
      x: pg.points[i].x.float32,
      y: pg.points[i].y.float32
    )

  # Draw fill if not transparent
  if pg.shape.style.fill.a > 0:
    # Raylib doesn't have polygon fill, draw outline with fill color
    for i in 0..<pg.points.len:
      let next = (i + 1) mod pg.points.len
      rl.drawLine(points[i], points[next], 2.0, pg.shape.style.fill)

  # Draw stroke if width > 0 and not transparent
  if pg.shape.style.stroke.width > 0.0 and pg.shape.style.stroke.color.a > 0:
    for i in 0..<pg.points.len:
      let next = (i + 1) mod pg.points.len
      rl.drawLine(points[i], points[next], pg.shape.style.stroke.width.float32, pg.shape.style.stroke.color)

# Helper function for linear interpolation
func lerp(a, b: Vec2, t: float64): Vec2 =
  Vec2(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
