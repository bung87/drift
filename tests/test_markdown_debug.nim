import std/[strutils, options]
import src/markdown_code_blocks
import src/enhanced_syntax

# Test markdown content
let testMarkdown = """# Test Markdown

This is regular text.

```nim
proc hello() =
  echo "Hello World"
```

More regular text here.

```python
def greet(name):
    print(f"Hello, {name}!")
```

Final text.
"""

echo "=== Testing Markdown Code Block Renderer ==="
echo "Input text length: ", testMarkdown.len
echo "Input lines: ", testMarkdown.splitLines().len
echo ""

var renderer = newMarkdownCodeBlockRenderer(testMarkdown)
echo "Created renderer with ", renderer.lines.len, " lines"

renderer.parseCodeBlocks()
echo "Found ", renderer.codeBlocks.len, " code blocks"

for i, codeBlock in renderer.codeBlocks.pairs():
  echo "Block ", i + 1, ":"
  echo "  Type: ", codeBlock.blockType
  echo "  Language: ", codeBlock.language
  echo "  Lines: ", codeBlock.startLine, " to ", codeBlock.endLine
  echo "  Content lines: ", codeBlock.content.len
  if codeBlock.content.len > 0:
    echo "  First content line: '", codeBlock.content[0], "'"

echo ""
echo "=== Testing Token Generation ==="
let tokens = renderer.renderMarkdownWithCodeBlocks()
echo "Generated ", tokens.len, " tokens"

for i, token in tokens.pairs():
  if i < 20: # Show first 20 tokens
    echo "Token ", i + 1, ": type=", token.tokenType, " start=", token.start,
        " len=", token.length, " text='", token.text.replace("\n", "\\n"), "'"
  elif i == 20:
    echo "... (showing first 20 tokens only)"
    break

echo ""
echo "=== Checking Token Positions ==="
var totalExpectedLength = testMarkdown.len
echo "Expected total length: ", totalExpectedLength

var maxTokenEnd = 0
for token in tokens:
  let tokenEnd = token.start + token.length
  if tokenEnd > maxTokenEnd:
    maxTokenEnd = tokenEnd

echo "Max token end position: ", maxTokenEnd
echo "Position difference: ", maxTokenEnd - totalExpectedLength

# Check for overlapping tokens
echo ""
echo "=== Checking for Token Overlaps ==="
for i in 0..<tokens.len-1:
  let current = tokens[i]
  let next = tokens[i+1]
  let currentEnd = current.start + current.length

  if currentEnd > next.start:
    echo "OVERLAP DETECTED:"
    echo "  Token ", i, ": start=", current.start, " end=", currentEnd,
        " text='", current.text.replace("\n", "\\n"), "'"
    echo "  Token ", i+1, ": start=", next.start, " end=", next.start +
        next.length, " text='", next.text.replace("\n", "\\n"), "'"
    echo ""
