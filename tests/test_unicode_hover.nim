## Test Unicode handling in hover system
import std/[unicode, strutils]
import src/components/text_editor

# Test Unicode helper functions
proc testUnicodeHelpers() =
  echo "Testing Unicode helper functions..."
  
  # Test with ASCII text
  let asciiText = "hello_world"
  echo "ASCII text: '", asciiText, "'"
  echo "  Rune length: ", asciiText.runeLen
  echo "  Byte length: ", asciiText.len
  
  # Test with Unicode text
  let unicodeText = "héllo_wörld"
  echo "Unicode text: '", unicodeText, "'"
  echo "  Rune length: ", unicodeText.runeLen
  echo "  Byte length: ", unicodeText.len
  
  # Test rune conversion functions
  echo "Testing rune conversion..."
  let testLine = "héllo_wörld"
  for runePos in 0..testLine.runeLen:
    let bytePos = runeColumnToByte(testLine, runePos)
    let backToRune = byteColumnToRune(testLine, bytePos)
    echo "  Rune pos ", runePos, " -> byte pos ", bytePos, " -> rune pos ", backToRune
  
  echo "Unicode helper tests completed!"

when isMainModule:
  testUnicodeHelpers()