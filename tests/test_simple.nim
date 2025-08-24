## Simple test to verify markdown syntax highlighting positioning

import std/[strutils, options]
import src/markdown_code_blocks
import src/enhanced_syntax

# Very simple markdown content to test positioning
const simpleMarkdown = """# Test

Regular text before code block.

```nim
proc test() = echo "hello"
```

Text after code block should be positioned correctly.

More text here.
"""

proc testSimplePositioning() =
  echo "=== Simple Positioning Test ==="
  
  # First, show the actual text with character positions
  echo "=== Character-by-character analysis ==="
  for i, c in simpleMarkdown.pairs():
    if c == '\n':
      echo "pos ", i, ": \\n"
    else:
      echo "pos ", i, ": '", c, "'"
  echo "Total length: ", simpleMarkdown.len
  echo ""
  
  var renderer = newMarkdownCodeBlockRenderer(simpleMarkdown)
  renderer.parseCodeBlocks()
  
  echo "Found ", renderer.codeBlocks.len, " code blocks"
  
  # Generate tokens
  let tokens = renderer.renderMarkdownWithCodeBlocks()
  echo "Generated ", tokens.len, " tokens"
  
  # Check token positions are sequential and correct
  var expectedPos = 0
  var hasErrors = false
  
  for i, token in tokens.pairs():
    if token.start != expectedPos:
      echo "ERROR: Token ", i, " has wrong position. Expected: ", expectedPos, ", Got: ", token.start
      echo "  Token text: '", token.text, "'"
      hasErrors = true
    
    expectedPos = token.start + token.length
    
    # Add newline length if this token represents a full line
    if token.text.len > 0 and not token.text.contains('\n'):
      expectedPos += 1  # for newline character
  
  if hasErrors:
    echo "❌ Position errors found!"
    echo ""
    echo "Token details:"
    for i, token in tokens.pairs():
      echo "  Token ", i, ": start=", token.start, " len=", token.length, " type=", token.tokenType, " text='", token.text.replace("\n", "\\n"), "'"
  else:
    echo "✅ All token positions are correct!"
  
  echo ""
  
  # Test specific expectations
  echo "=== Content Verification ==="
  
  # Find the "Text after code block" token
  var foundAfterText = false
  for token in tokens:
    if "Text after code block" in token.text:
      foundAfterText = true
      echo "✅ Found 'Text after code block' at position ", token.start
      break
  
  if not foundAfterText:
    echo "❌ Could not find 'Text after code block' - positioning may be broken"
  
  echo ""

when isMainModule:
  testSimplePositioning()