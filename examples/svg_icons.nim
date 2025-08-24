## SVG Icons Grid Displa
## This example displays all SVG icons from resources/icons directory in a grid layout

import raylib as rl
import std/[os, strformat, strutils]
import ../src/svgtoraylib

const
  SCREEN_WIDTH = 1000
  SCREEN_HEIGHT = 800
  GRID_COLS = 4
  CELL_WIDTH = 200
  CELL_HEIGHT = 150
  ICON_SIZE = 64
  MARGIN = 20

type
  IconData = object
    texture: RenderTexture2D
    width: float64
    height: float64
    filename: string
    loaded: bool

proc main() =
  rl.setConfigFlags(
    rl.flags(rl.ConfigFlags.WindowResizable, rl.ConfigFlags.WindowHighdpi)
  )
  # Initialize Raylib
  rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "SVG Icons Grid")
  rl.setTargetFPS(60)

  var icons: seq[IconData]
  let iconsDir = "resources/icons"

  # Load all SVG files from the icons directory
  if dirExists(iconsDir):
    for file in walkFiles(iconsDir / "*.svg"):
      let filename = extractFilename(file)
      var iconData = IconData(filename: filename, loaded: false)

      try:
        let result = svgToTextureWithDims(file)
        iconData.texture = result.texture
        iconData.width = result.width
        iconData.height = result.height
        iconData.loaded = true
        echo fmt"Successfully loaded: {filename} ({iconData.width}x{iconData.height})"
      except SvgToRaylibError as e:
        echo fmt"Failed to load {filename}: {e.msg}"
      except Exception as e:
        echo fmt"Error loading {filename}: {e.msg}"

      icons.add(iconData)
  else:
    echo fmt"Icons directory not found: {iconsDir}"

  # Calculate grid layout
  let totalIcons = icons.len
  let totalRows = (totalIcons + GRID_COLS - 1) div GRID_COLS
  let startX = (SCREEN_WIDTH - (GRID_COLS * CELL_WIDTH)) div 2
  let startY = (SCREEN_HEIGHT - (totalRows * CELL_HEIGHT)) div 2

  # Main game loop
  while not rl.windowShouldClose():
    # Update
    # Nothing to update in this example

    # Draw
    rl.beginDrawing()
    rl.clearBackground(rl.RAYWHITE)

    # Draw title
    let titleText = fmt"SVG Icons Grid ({totalIcons} icons)"
    let titleWidth = rl.measureText(titleText, 24)
    rl.drawText(titleText, (SCREEN_WIDTH - titleWidth) div 2, 20, 24, rl.DARKGRAY)

    # Draw grid of icons
    for i in 0..<icons.len:
      let
        col = i mod GRID_COLS
        row = i div GRID_COLS
        cellX = startX + col * CELL_WIDTH
        cellY = startY + row * CELL_HEIGHT + 60  # Offset for title

      # Draw cell border (optional)
      let cellRect = rl.Rectangle(
        x: cellX.float32,
        y: cellY.float32,
        width: CELL_WIDTH.float32,
        height: CELL_HEIGHT.float32
      )
      rl.drawRectangleLines(cellRect, 1.0, rl.LIGHTGRAY)

      if icons[i].loaded:
        # Calculate icon position (centered in cell, upper part)
        let
          iconDisplaySize = ICON_SIZE.float32
          scale = min(iconDisplaySize / icons[i].width.float32, iconDisplaySize / icons[i].height.float32)
          scaledWidth = icons[i].width.float32 * scale
          scaledHeight = icons[i].height.float32 * scale
          iconX = cellX.float32 + (CELL_WIDTH.float32 - scaledWidth) / 2
          iconY = cellY.float32 + MARGIN.float32

          sourceRec = rl.Rectangle(
            x: 0,
            y: 0,
            width: icons[i].width.float32,
            height: -icons[i].height.float32  # Negative height to flip Y
          )
          destRec = rl.Rectangle(
            x: iconX,
            y: iconY,
            width: scaledWidth,
            height: scaledHeight
          )
          origin = rl.Vector2(x: 0, y: 0)

        # Draw the icon
        rl.drawTexture(icons[i].texture.texture, sourceRec, destRec, origin, 0.0, rl.WHITE)

        # Draw filename below icon
        let
          filenameWithoutExt = icons[i].filename.replace(".svg", "")
          textWidth = rl.measureText(filenameWithoutExt, 16)
          textX = cellX + (CELL_WIDTH - textWidth) div 2
          textY = cellY + ICON_SIZE + MARGIN * 2

        rl.drawText(filenameWithoutExt, textX.int32, textY.int32, 16, rl.DARKGRAY)
      else:
        # Draw error placeholder
        let
          errorX = cellX + CELL_WIDTH div 2
          errorY = cellY + CELL_HEIGHT div 2
          errorText = "Failed to load"
          textWidth = rl.measureText(errorText, 12)

        rl.drawText(errorText, (errorX - textWidth div 2).int32, errorY.int32, 12, rl.RED)
        rl.drawText(icons[i].filename, (cellX + 10).int32, (cellY + 10).int32, 10, rl.DARKGRAY)

    # Draw instructions
    rl.drawText("Press ESC to exit", 10, SCREEN_HEIGHT - 30, 16, rl.DARKGRAY)

    rl.endDrawing()

  # Cleanup
  for i in 0..<icons.len:
    if icons[i].loaded:
      # Note: Cleanup is handled automatically by Raylib
      discard

  rl.closeWindow()

when isMainModule:
  echo "SVG Icons Grid Display"
  echo "Loading all SVG icons from resources/icons/ directory..."
  main()
