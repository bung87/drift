## Explorer rendering module - Production-ready file explorer rendering
import std/[os, strutils, tables]
import raylib as rl
import types
import ../infrastructure/rendering/theme
import ../infrastructure/rendering/renderer
import ../icons

export types

# Rendering utilities
proc measureTextWidth*(font: rl.Font, text: string,
    fontSize: float32): float32 =
  ## Measure text width for layout calculations
  let textSize = rl.measureText(font, text, fontSize, 1.0)
  result = textSize.x

proc drawTextCentered*(
    font: rl.Font, text: string, x, y, fontSize: float32, color: rl.Color
) =
  ## Draw text centered at the given position
  let textSize = rl.measureText(font, text, fontSize, 1.0)
  let centeredX = x - textSize.x / 2.0
  let centeredY = y - textSize.y / 2.0
  rl.drawText(font, text, rl.Vector2(x: centeredX, y: centeredY), fontSize, 1.0, color)

proc drawTextRightAlign*(
    font: rl.Font, text: string, x, y, fontSize: float32, color: rl.Color
) =
  ## Draw text right-aligned at the given position
  let textSize = rl.measureText(font, text, fontSize, 1.0)
  let rightAlignedX = x - textSize.x
  rl.drawText(font, text, rl.Vector2(x: rightAlignedX, y: y), fontSize, 1.0, color)

# Utility functions
proc formatFileSize*(bytes: int64): string =
  ## Format file size in human-readable format
  const units = ["B", "KB", "MB", "GB", "TB"]
  var size = bytes.float64
  var unitIndex = 0

  while size >= 1024.0 and unitIndex < units.len - 1:
    size /= 1024.0
    unitIndex += 1

  if unitIndex == 0:
    result = $bytes & " " & units[unitIndex]
  else:
    result = formatFloat(size, ffDecimal, 1) & " " & units[unitIndex]

# Icon rendering
proc drawFileIcon*(bounds: rl.Rectangle, color: rl.Color,
    iconType: string = "", iconSize: float32) =
  ## Draw a file icon using the migrated icon system with fallback
  let centerX = bounds.x + bounds.width / 2.0
  let centerY = bounds.y + bounds.height / 2.0
  let halfIconSize = iconSize / 2.0

  # Try to use specific file type icon if iconType is provided
  if iconType.len > 0:
    let ext = iconType.toLower()
    case ext
    of ".nim":
      drawNimIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".py", ".pyw":
      drawPythonIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".js", ".mjs":
      drawJavaScriptIcon(centerX - halfIconSize, centerY - halfIconSize,
          iconSize, color)
      return
    of ".ts", ".tsx":
      drawTypeScriptIcon(centerX - halfIconSize, centerY - halfIconSize,
          iconSize, color)
      return
    of ".json":
      drawJsonIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".yml", ".yaml":
      drawYamlIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".toml":
      drawTomlIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".rs":
      drawRustIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".cpp", ".cxx", ".cc":
      drawCppIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".c", ".h":
      drawCIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".html", ".htm":
      drawHtmlIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".css", ".scss", ".sass":
      drawCssIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".go":
      drawGoIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".java":
      drawJavaIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    of ".md", ".markdown":
      drawMarkdownIcon(centerX - halfIconSize, centerY - halfIconSize, iconSize, color)
      return
    else:
      discard

  # Use main icon system for generic file icon
  drawFileIconRasterized(centerX - halfIconSize, centerY - halfIconSize, color)

proc drawFileIconFallback*(bounds: rl.Rectangle, color: rl.Color) =
  ## Fallback file icon drawing (original implementation)
  let centerX = bounds.x + bounds.width / 2.0
  let centerY = bounds.y + bounds.height / 2.0
  let size = min(bounds.width, bounds.height) * 0.8

  # Draw file icon (simple rectangle with corner)
  let iconRect = rl.Rectangle(
    x: centerX - size / 2.0, y: centerY - size / 2.0, width: size, height: size
  )

  # Main file body
  rl.drawRectangle(
    iconRect.x.int32, iconRect.y.int32, iconRect.width.int32,
    iconRect.height.int32,
    color,
  )
  rl.drawRectangleLines(
    iconRect.x.int32,
    iconRect.y.int32,
    iconRect.width.int32,
    iconRect.height.int32,
    rl.Color(r: color.r div 2, g: color.g div 2, b: color.b div 2, a: color.a),
  )

  # Corner fold
  let foldSize = size * 0.2
  let foldRect = rl.Rectangle(
    x: iconRect.x + iconRect.width - foldSize,
    y: iconRect.y,
    width: foldSize,
    height: foldSize,
  )
  rl.drawRectangle(
    foldRect.x.int32,
    foldRect.y.int32,
    foldRect.width.int32,
    foldRect.height.int32,
    rl.Color(r: color.r div 2, g: color.g div 2, b: color.b div 2, a: color.a),
  )

proc drawFolderIcon*(bounds: rl.Rectangle, color: rl.Color,
    isOpen: bool = false, iconSize: float32) =
  ## Draw a folder icon using the migrated icon system
  let centerX = bounds.x + bounds.width / 2.0
  let centerY = bounds.y + bounds.height / 2.0
  let halfIconSize = iconSize / 2.0

  # Use main icon system for folder icons
  if isOpen:
    drawRasterizedIcon("openfolder.svg", centerX - halfIconSize, centerY -
        halfIconSize, iconSize, color)
  else:
    drawFolderIconRasterized(centerX - halfIconSize, centerY - halfIconSize, color)

proc drawFolderIconFallback*(bounds: rl.Rectangle, color: rl.Color,
    isOpen: bool = false) =
  ## Fallback folder icon drawing (original implementation)
  let size = min(bounds.width, bounds.height) * 0.8
  let x = bounds.x + (bounds.width - size) / 2
  let y = bounds.y + (bounds.height - size) / 2
  # Main folder body
  rl.drawRectangleLines(
    x.int32, (y + size * 0.2).int32, size.int32, (size * 0.8).int32, color
  )
  # Folder tab
  rl.drawRectangleLines(x.int32, y.int32, (size * 0.4).int32, (size *
      0.3).int32, color)

proc drawExpandIcon*(bounds: rl.Rectangle, color: rl.Color, isExpanded: bool,
    iconSize: float32) =
  ## Draw expand/collapse triangle icon
  let centerX = bounds.x + bounds.width / 2.0
  let centerY = bounds.y + bounds.height / 2.0
  let size = iconSize * 0.75

  if isExpanded:
    # Down-pointing triangle
    let p1 = rl.Vector2(x: centerX - size / 2.0, y: centerY - size / 4.0)
    let p2 = rl.Vector2(x: centerX + size / 2.0, y: centerY - size / 4.0)
    let p3 = rl.Vector2(x: centerX, y: centerY + size / 4.0)
    rl.drawTriangle(p1, p2, p3, color)
  else:
    # Right-pointing triangle
    let p1 = rl.Vector2(x: centerX - size / 4.0, y: centerY - size / 2.0)
    let p2 = rl.Vector2(x: centerX - size / 4.0, y: centerY + size / 2.0)
    let p3 = rl.Vector2(x: centerX + size / 4.0, y: centerY)
    rl.drawTriangle(p1, p2, p3, color)

proc drawTooltip*(
    theme: Theme,
    text: string,
    position: rl.Vector2,
    font: rl.Font,
    fontSize: float32,
) =
  ## Draw a tooltip at the specified position
  if text.len == 0:
    return

  # Measure text size
  let textSize = rl.measureText(font, text, fontSize, 1.0)
  let padding = 8.0
  let tooltipWidth = textSize.x + padding * 2
  let tooltipHeight = textSize.y + padding * 2

  # Position tooltip above the mouse cursor
  let tooltipX = position.x
  let tooltipY = position.y - tooltipHeight - 10.0

  # Draw tooltip background
  let tooltipRect = rl.Rectangle(
    x: tooltipX,
    y: tooltipY,
    width: tooltipWidth,
    height: tooltipHeight
  )

  rl.drawRectangle(
    tooltipRect.x.int32,
    tooltipRect.y.int32,
    tooltipRect.width.int32,
    tooltipRect.height.int32,
    theme.uiColors[uiPopup]
  )

  # Draw tooltip border
  rl.drawRectangleLines(
    tooltipRect.x.int32,
    tooltipRect.y.int32,
    tooltipRect.width.int32,
    tooltipRect.height.int32,
    theme.uiColors[uiBorder]
  )

  # Draw tooltip text
  rl.drawText(
    font,
    text,
    rl.Vector2(x: tooltipX + padding, y: tooltipY + padding),
    fontSize,
    1.0,
    theme.uiColors[uiText]
  )

# Main rendering functions
proc drawExplorerHeader*(
    rendererContext: renderer.RenderContext,
    theme: Theme,
    x, y, width: float32,
    currentDir: string,
    state: ExplorerState,
    font: rl.Font,
    fontSize: float32,
) =
  ## Draw the explorer header with current directory
  let headerRect = rl.Rectangle(x: x, y: y, width: width, height: HEADER_HEIGHT)

  # Draw header background
  rl.drawRectangle(
    headerRect.x.int32,
    headerRect.y.int32,
    headerRect.width.int32,
    headerRect.height.int32,
    theme.uiColors[uiTitlebar],
  )
  rl.drawRectangleLines(
    headerRect.x.int32,
    headerRect.y.int32,
    headerRect.width.int32,
    headerRect.height.int32,
    theme.uiColors[uiBorder],
  )

  # Draw collapse/expand triangle
  let triangleX = x + 8
  let triangleY = y + (HEADER_HEIGHT - 8) / 2.0
  let triangleSize = 6.0

  # Check if mouse is over triangle area - but only within the header bounds
  let mousePos = state.mousePos
  let triangleRect = rl.Rectangle(x: triangleX - 8, y: triangleY - 8, width: 20, height: 20)
  let isTriangleHovered = rl.checkCollisionPointRec(mousePos, triangleRect) and
                         rl.checkCollisionPointRec(mousePos, headerRect)

  # Triangle color
  let triangleColor =
    if isTriangleHovered:
      theme.uiColors[uiText]
    else:
      theme.uiColors[uiTextMuted]

  # Draw hover background for better visual feedback
  if isTriangleHovered:
    rl.drawRectangle(
      (triangleRect.x + 2).int32,
      (triangleRect.y + 2).int32,
      (triangleRect.width - 4).int32,
      (triangleRect.height - 4).int32,
      rl.Color(r: 128, g: 128, b: 128, a: 32)
    )

  # Left-side collapse icon removed per new design

  # Note: Triangle click handling is done by the explorer's input system
  # This rendering function only provides visual feedback

  # Draw directory name (moved right to make room for triangle)
  let dirName =
    if currentDir.len > 0:
      os.extractFilename(currentDir)
    else:
      "Explorer"
  let textY = y + (HEADER_HEIGHT - fontSize) / 2.0
  rl.drawText(
    font,
    dirName,
    rl.Vector2(x: x + 8, y: textY),
    fontSize,
    1.0,
    theme.uiColors[uiText],
  )

  # Draw up arrow if there's a parent directory
  if currentDir.len > 0 and currentDir != "/":
    let arrowX = x + width - 20
    let arrowY = y + (HEADER_HEIGHT - 12) / 2.0

    # Check if mouse is over arrow area - but only within the header bounds
    let mousePos = state.mousePos
    let arrowRect = rl.Rectangle(x: arrowX - 8, y: arrowY - 6, width: 16, height: 12)
    let isHovered = rl.checkCollisionPointRec(mousePos, arrowRect) and
                   rl.checkCollisionPointRec(mousePos, headerRect)

    # Draw simple arrow (no background)
    let arrowColor =
      if isHovered:
        theme.uiColors[uiText]
      else:
        theme.uiColors[uiTextMuted]

        # Draw arrow as two lines indicating root collapsed/expanded
    let centerX = arrowX
    let centerY = arrowY
    let arrowSize = 6.0

    if state.rootCollapsed:
      # Draw right-pointing arrow '>'
      rl.drawLine(
        (centerX - arrowSize / 2.0).int32,
        (centerY - arrowSize / 2.0).int32,
        (centerX + arrowSize / 2.0).int32,
        centerY.int32,
        arrowColor,
      )
      rl.drawLine(
        (centerX - arrowSize / 2.0).int32,
        (centerY + arrowSize / 2.0).int32,
        (centerX + arrowSize / 2.0).int32,
        centerY.int32,
        arrowColor,
      )
    else:
      # Draw down-pointing arrow 'v'
      rl.drawLine(
        (centerX - arrowSize / 2.0).int32,
        (centerY - arrowSize / 2.0).int32,
        centerX.int32,
        (centerY + arrowSize / 2.0).int32,
        arrowColor,
      )
      rl.drawLine(
        centerX.int32,
        (centerY + arrowSize / 2.0).int32,
        (centerX + arrowSize / 2.0).int32,
        (centerY - arrowSize / 2.0).int32,
        arrowColor,
      )

    # Note: Arrow click handling is done by the explorer's input system
    # This rendering function only provides visual feedback



proc drawFileEntry*(
    rendererContext: renderer.RenderContext,
    theme: Theme,
    config: ExplorerConfig,
    file: ExplorerFileInfo,
    bounds: rl.Rectangle,
    isSelected: bool,
    isHovered: bool,
    showExpandIcon: bool = false,
    state: ExplorerState,
    font: rl.Font,
    fontSize: float32,
) =
  ## Draw a single file entry
  # Get icon size from config
  let iconSize = config.iconSize

  # Draw background
  let bgColor =
    if isSelected:
      theme.uiColors[uiSelection]
    elif isHovered:
      theme.uiColors[uiPanel].lighten(0.1)
    else:
      theme.uiColors[uiBackground]

  rl.drawRectangle(
    bounds.x.int32, bounds.y.int32, bounds.width.int32, bounds.height.int32, bgColor
  )

  # Draw selection border
  if isSelected:
    rl.drawRectangleLines(
      bounds.x.int32,
      bounds.y.int32,
      bounds.width.int32,
      bounds.height.int32,
      theme.uiColors[uiBorderActive],
    )

  var currentX = bounds.x + 4.0
  let textY = bounds.y + (bounds.height - fontSize) / 2.0

  # Draw tree indentation
  if file.level > 0:
    currentX += file.level.float32 * config.indentSize

    # Draw tree lines
    for level in 0 ..< file.level:
      let lineX =
        bounds.x + 4.0 + level.float32 * config.indentSize + config.indentSize / 2.0
      let lineColor = theme.uiColors[uiSeparator]
      rl.drawLine(
        lineX.int32,
        bounds.y.int32,
        lineX.int32,
        (bounds.y + bounds.height).int32,
        lineColor,
      )

  # No expand icon - just use indentation to show hierarchy

  # Draw file/folder icon
  if config.showFileIcons:
    let iconRect = rl.Rectangle(
      x: currentX,
      y: bounds.y + (bounds.height - iconSize) / 2.0,
      width: iconSize,
      height: iconSize,
    )

    if file.kind == fkDirectory:
      drawFolderIcon(iconRect, theme.uiColors[uiAccent], file.isExpanded, iconSize)
    else:
      drawFileIcon(iconRect, theme.uiColors[uiText], file.extension, iconSize)

    currentX += iconSize + 8.0

  # Draw file name
  let textColor =
    if isSelected:
      theme.uiColors[uiTextHighlight]
    elif file.kind == fkDirectory:
      theme.uiColors[uiAccent]
    elif file.isHidden:
      theme.uiColors[uiTextMuted]
    else:
      theme.uiColors[uiText]

  let displayName =
    if config.showFileExtensions or file.kind == fkDirectory:
      file.name
    else:
      file.name.splitFile().name

  # Calculate available width for text (subtract some padding for right margin)
  let availableWidth = bounds.x + bounds.width - currentX - 8.0

  # Measure text width and truncate if necessary
  let textSize = rl.measureText(font, displayName, fontSize, 1.0)
  let (finalDisplayName, isTextTruncated) =
    if textSize.x > availableWidth and availableWidth > 0:
      # Text is too long, need to truncate with ellipsis
      let ellipsis = "…"
      let ellipsisSize = rl.measureText(font, ellipsis, fontSize, 1.0)
      let maxTextWidth = availableWidth - ellipsisSize.x

      if maxTextWidth > 0:
        # Find the longest substring that fits
        var truncatedName = displayName
        var truncatedSize = textSize.x

        # Binary search for optimal length
        var left = 0
        var right = displayName.len
        while left < right:
          let mid = (left + right + 1) div 2
          let testName = displayName[0..<mid]
          let testSize = rl.measureText(font, testName, fontSize, 1.0)
          if testSize.x <= maxTextWidth:
            left = mid
          else:
            right = mid - 1

        if left > 0:
          truncatedName = displayName[0..<left] & ellipsis
        else:
          truncatedName = ellipsis

        (truncatedName, true)
      else:
        ("…", true)
    else:
      (displayName, false)

  # Set tooltip information if text is truncated and mouse is hovering
  if isTextTruncated and isHovered:
    # Note: We can't modify state here directly since it's passed as immutable
    # The tooltip logic will need to be handled in the calling function
    discard

  rl.drawText(
    font,
    finalDisplayName,
    rl.Vector2(x: currentX, y: textY),
    fontSize,
    1.0,
    textColor,
  )

  # No file sizes displayed

proc drawScrollbar*(
    rendererContext: renderer.RenderContext,
    theme: Theme,
    x, y, width, height: float32,
    scrollY, maxScrollY: float32,
    onScroll: proc(newScrollY: float32) = nil,
    state: ExplorerState,
    font: rl.Font,
    fontSize: float32,
) =
  ## Draw vertical scrollbar
  if maxScrollY <= 0:
    return

  let scrollbarRect = rl.Rectangle(x: x, y: y, width: width, height: height)

  # Draw scrollbar background
  rl.drawRectangle(
    scrollbarRect.x.int32,
    scrollbarRect.y.int32,
    scrollbarRect.width.int32,
    scrollbarRect.height.int32,
    theme.uiColors[uiScrollbar],
  )

  # Calculate thumb size and position
  let thumbRatio = height / (height + maxScrollY)
  let thumbHeight = max(20.0, height * thumbRatio)
  let thumbY = y + (scrollY / maxScrollY) * (height - thumbHeight)

  let thumbRect = rl.Rectangle(x: x, y: thumbY, width: width,
      height: thumbHeight)

  # Check if mouse is over thumb
  let mousePos = state.mousePos
  let isHovered = rl.checkCollisionPointRec(mousePos, thumbRect)

  let thumbColor =
    if isHovered:
      theme.uiColors[uiScrollbar].lighten(0.3)
    else:
      theme.uiColors[uiScrollbar].lighten(0.1)
  rl.drawRectangle(
    thumbRect.x.int32, thumbRect.y.int32, thumbRect.width.int32,
    thumbRect.height.int32,
    thumbColor,
  )

  # Note: Scrollbar interaction is handled by the explorer's input system
  # This rendering function only draws the scrollbar visual elements

proc drawFileList*(
    rendererContext: renderer.RenderContext,
    theme: Theme,
    config: ExplorerConfig,
    state: ExplorerState,
    x, y, width, height: float32,
    font: rl.Font,
    fontSize: float32,
) =
  ## Draw the main file list
  let listRect = rl.Rectangle(x: x, y: y, width: width, height: height)

  # Draw list background
  rl.drawRectangle(
    listRect.x.int32,
    listRect.y.int32,
    listRect.width.int32,
    listRect.height.int32,
    theme.uiColors[uiBackground],
  )

  # If root is collapsed, don't draw any files
  if state.rootCollapsed:
    return

  # Calculate visible range
  let itemHeight = config.itemHeight
  let visibleCount = (height / itemHeight).int + 1
  let startIndex = max(0, (state.scrollY / itemHeight).int)
  let endIndex = min(state.filteredFiles.len - 1, startIndex + visibleCount)

  # Draw visible files
  for i in startIndex .. endIndex:
    if i >= state.filteredFiles.len:
      break

    let file = state.filteredFiles[i]
    let itemY = y + (i.float32 * itemHeight) - state.scrollY

    # Skip if item is outside visible area
    if itemY + itemHeight < y or itemY > y + height:
      continue

    let itemRect = rl.Rectangle(
      x: x,
      y: itemY,
      width: width - (if state.scrollMaxY > 0: 12.0 else: 0.0),
      height: itemHeight,
    )

    let isSelected = i == state.selectedIndex

    # Check if mouse is hovering over this item
    let mousePos = state.mousePos
    let isHovered = rl.checkCollisionPointRec(mousePos, itemRect)

    drawFileEntry(
      rendererContext,
      theme,
      config,
      file,
      itemRect,
      isSelected,
      isHovered,
      file.kind == fkDirectory,
      state,
      font,
      fontSize,
    )

    # Note: Mouse interaction is handled by the explorer's input system
    # Click handling is done in explorer.nim through handleMouseLeftClick
    # This rendering function only draws the visual representation

  # Draw scrollbar if needed
  if state.scrollMaxY > 0:
    let scrollbarX = x + width - 12.0
    let scrollbarRect = rl.Rectangle(x: scrollbarX, y: y, width: 12.0,
        height: height)

    # Draw scrollbar background
    rl.drawRectangle(
      scrollbarRect.x.int32,
      scrollbarRect.y.int32,
      scrollbarRect.width.int32,
      scrollbarRect.height.int32,
      theme.uiColors[uiScrollbar],
    )

    # Calculate thumb size and position
    let thumbRatio = height / (height + state.scrollMaxY)
    let thumbHeight = max(20.0, height * thumbRatio)
    let thumbY = y + (state.scrollY / state.scrollMaxY) * (height - thumbHeight)

    # Draw scrollbar thumb
    rl.drawRectangle(
      scrollbarX.int32,
      thumbY.int32,
      12.0.int32,
      thumbHeight.int32,
      theme.uiColors[uiScrollbar].lighten(0.2),
    )

proc drawExplorerPanel*(
    rendererContext: renderer.RenderContext,
    theme: Theme,
    state: ExplorerState,
    x, y, width, height: float32,
    events: var seq[ExplorerEvent],
    font: rl.Font,
    fontSize: float32,
    zoomLevel: float32 = 1.0,
) =
  ## Draw the complete explorer panel
  let panelRect = rl.Rectangle(x: x, y: y, width: width, height: height)

  # Draw panel background
  rl.drawRectangle(
    panelRect.x.int32,
    panelRect.y.int32,
    panelRect.width.int32,
    panelRect.height.int32,
    theme.uiColors[uiPanel],
  )
  rl.drawRectangleLines(
    panelRect.x.int32,
    panelRect.y.int32,
    panelRect.width.int32,
    panelRect.height.int32,
    theme.uiColors[uiBorder],
  )

  var currentY = y

  # Draw header
  drawExplorerHeader(
    rendererContext,
    theme,
    x,
    currentY,
    width,
    state.currentDirectory,
    state,
    font,
    fontSize,
  )
  currentY += HEADER_HEIGHT

  # Draw file list
  let listHeight = height - (currentY - y)
  if listHeight > 0:
    drawFileList(
      rendererContext,
      theme,
      defaultExplorerConfig(theme, zoomLevel),
      state,
      x,
      currentY,
      width,
      listHeight,
      font,
      fontSize,
    )

  # Draw loading indicator if needed
  if state.refreshing:
    let loadingRect = rl.Rectangle(
      x: x + width / 2.0 - 50, y: y + height / 2.0 - 10, width: 100, height: 20
    )
    rl.drawRectangle(
      loadingRect.x.int32,
      loadingRect.y.int32,
      loadingRect.width.int32,
      loadingRect.height.int32,
      rl.Color(r: 0, g: 0, b: 0, a: 128),
    )
    rl.drawText(
      font,
      "Loading...",
      rl.Vector2(
        x: loadingRect.x + loadingRect.width / 2.0,
        y: loadingRect.y + loadingRect.height / 2.0,
      ),
      fontSize,
      1.0,
      theme.uiColors[uiText],
    )

  # Draw tooltip if visible
  if state.tooltipVisible and state.tooltipText.len > 0:
    drawTooltip(theme, state.tooltipText, state.tooltipPosition, font, fontSize)

# Other utility functions

proc calculateScrollLimits*(
    files: seq[ExplorerFileInfo], itemHeight, viewportHeight: float32
): float32 =
  ## Calculate maximum scroll position
  let totalHeight = files.len.float32 * itemHeight
  result = max(0.0, totalHeight - viewportHeight)

proc getFileAtPosition*(
    files: seq[ExplorerFileInfo],
    mousePos: rl.Vector2,
    listRect: rl.Rectangle,
    itemHeight, scrollY: float32,
): int =
  ## Get file index at mouse position
  if not rl.checkCollisionPointRec(mousePos, listRect):
    return -1

  let relativeY = mousePos.y - listRect.y + scrollY
  let index = (relativeY / itemHeight).int

  if index >= 0 and index < files.len:
    return index
  else:
    return -1

proc isExpandIconClicked*(
    file: ExplorerFileInfo,
    mousePos: rl.Vector2,
    itemRect: rl.Rectangle,
    indentSize: float32,
    iconSize: float32,
): bool =
  ## Check if the expand icon was clicked
  if file.kind != fkDirectory:
    return false

  let iconX = itemRect.x + file.level.float32 * indentSize
  let iconRect = rl.Rectangle(
    x: iconX,
    y: itemRect.y + (itemRect.height - iconSize) / 2.0,
    width: iconSize,
    height: iconSize,
  )

  return rl.checkCollisionPointRec(mousePos, iconRect)

# Main rendering interface for explorer
proc renderExplorer*(
    state: ExplorerState,
    config: ExplorerConfig,
    rendererContext: renderer.RenderContext,
    bounds: rl.Rectangle,
    font: rl.Font,
    fontSize: float32,
    zoomLevel: float32 = 1.0,
) =
  ## Main render function called by Explorer
  var events: seq[ExplorerEvent] = @[]
  drawExplorerPanel(
    rendererContext,
    config.theme,
    state,
    bounds.x,
    bounds.y,
    bounds.width,
    bounds.height,
    events,
    font,
    fontSize,
    zoomLevel,
  )
