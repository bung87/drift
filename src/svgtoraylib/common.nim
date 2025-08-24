import std/tables
import raylib as rl
import chroma

type
  Stroke* = object
    width*: float64 = 1.0
    color*: rl.Color
  Style* = object
    fill*: rl.Color
    stroke*: Stroke
  ClassMap* = Table[string, Style]

const Dpi300* = 300.0/96.0

# Utility function to convert chroma Color to Raylib Color
func toRaylibColor*(c: chroma.Color): rl.Color =
  rl.Color(
    r: uint8(c.r * 255),
    g: uint8(c.g * 255), 
    b: uint8(c.b * 255),
    a: uint8(c.a * 255)
  )

# Default transparent color
func transparentColor*(): rl.Color =
  rl.Color(r: 0, g: 0, b: 0, a: 0)

# Default black color
func blackColor*(): rl.Color =
  rl.Color(r: 0, g: 0, b: 0, a: 255)