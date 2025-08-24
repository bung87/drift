import raylib as rl
import std/[os, strformat]
import ../src/svg_rasterizer

const ResourcesDir = currentSourcePath.parentDir.parentDir / "resources"

proc main() =
  rl.setConfigFlags(
    rl.flags(rl.ConfigFlags.WindowResizable, rl.ConfigFlags.WindowHighdpi)
  )
  rl.initWindow(800, 600, "SVG Rasterizer Test")
  rl.setTargetFPS(60)
  
  # Test loading both stroke-only and fill-only SVGs
  let gitBranchPath = ResourcesDir / "icons" / "gitbranch.svg"
  let gitPath = ResourcesDir / "icons" / "git.svg"
  echo "Testing improved SVG rasterizer with: ", gitBranchPath
  echo "Testing fill-only SVG with: ", gitPath
  
  var gitBranchTexture: rl.Texture2D
  var gitTexture: rl.Texture2D
  
  try:
    # Test the improved rasterizer with stroke-only SVG
    gitBranchTexture = svgToTexture2D(gitBranchPath, 64, 64)
    echo "Successfully loaded gitbranch texture with stroke support!"
    
    # Test with fill-only SVG
    gitTexture = svgToTexture2D(gitPath, 64, 64)
    echo "Successfully loaded git texture with fill support!"
    
    while not rl.windowShouldClose():
      rl.beginDrawing()
      rl.clearBackground(rl.RAYWHITE)
      
      # Draw the gitbranch texture (stroke-only)
      rl.drawTexture(gitBranchTexture, 100, 100, rl.WHITE)
      rl.drawText("Git Branch (Stroke-only)", 100, 170, 16, rl.BLACK)
      
      # Draw the git texture (fill-only)
      rl.drawTexture(gitTexture, 200, 100, rl.WHITE)
      rl.drawText("Git (Fill-only)", 200, 170, 16, rl.BLACK)
      
      # Draw some text
      rl.drawText("Improved SVG Rasterizer Test", 10, 10, 20, rl.BLACK)
      rl.drawText("Left: gitbranch.svg (stroke-only)", 10, 40, 16, rl.GRAY)
      rl.drawText("Right: git.svg (fill-only)", 10, 70, 16, rl.GRAY)
      rl.drawText("Both should render correctly", 10, 100, 14, rl.DARKGRAY)
      
      rl.endDrawing()
    
  except Exception as e:
    echo fmt"Error: {e.msg}"
  
  rl.closeWindow()

when isMainModule:
  main() 