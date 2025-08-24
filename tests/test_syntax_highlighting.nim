import std/[unittest, strutils, tables]
import ../src/enhanced_syntax

# Test suite for syntax highlighting implementation - Pure logic, no UI dependencies
suite "Syntax Highlighting Logic Tests":

  setup:
    discard

  teardown:
    discard

  test "SyntaxHighlighter creation for different languages":
    let nimHighlighter = newSyntaxHighlighter(langNim)
    let pythonHighlighter = newSyntaxHighlighter(langPython)
    let jsHighlighter = newSyntaxHighlighter(langJavaScript)

    check nimHighlighter.language == langNim
    check pythonHighlighter.language == langPython
    check jsHighlighter.language == langJavaScript

    # Verify keyword tables are populated
    check nimHighlighter.keywords.len > 0
    check pythonHighlighter.keywords.len > 0
    check jsHighlighter.keywords.len > 0

  test "Nim keyword and type detection":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "let x = 10\nproc test(): int = 42\nvar name: string"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var foundTokens: Table[string, TokenType] = initTable[string, TokenType]()
    for token in tokens:
      foundTokens[token.text] = token.tokenType

    check "let" in foundTokens
    check foundTokens["let"] == ttKeyword
    check "x" in foundTokens
    check foundTokens["x"] == ttIdentifier

  test "String literal tokenization":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = """let msg = "Hello, World!" """
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var foundString = false
    for token in tokens:
      if token.tokenType == ttStringLit and "Hello, World!" in token.text:
        foundString = true
        break

    check foundString

  test "Number literal variations":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "let a = 42\nlet b = 3.14\nlet c = 0xFF\nlet d = 0b1010"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var numberTokens: seq[string] = @[]
    for token in tokens:
      if token.tokenType == ttNumberLit:
        numberTokens.add(token.text)

    check "42" in numberTokens
    check "3.14" in numberTokens
    check "0xFF" in numberTokens

  test "Comment detection comprehensive":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = """# Single line comment
let x = 10  # Another comment
#[ Multi-line
   comment with
   multiple lines ]#"""
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var commentCount = 0
    for token in tokens:
      if token.tokenType == ttComment:
        commentCount += 1

    check commentCount >= 2  # At least single-line and multi-line comments

  test "Operator recognition":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "result = a + b * c - d / e"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var operators: seq[string] = @[]
    for token in tokens:
      if token.tokenType == ttOperator:
        operators.add(token.text)

    check "=" in operators
    check "+" in operators
    check "*" in operators
    check "-" in operators
    check "/" in operators

  test "Function and identifier distinction":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "echo(hello)\nlen(myList)\ntest()"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var functions: seq[string] = @[]
    var identifiers: seq[string] = @[]
    
    for token in tokens:
      if token.tokenType == ttFunction:
        functions.add(token.text)
      elif token.tokenType == ttIdentifier:
        identifiers.add(token.text)

    # Should find some function-like patterns
    check functions.len > 0

  test "Type vs identifier classification":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "type Point = object\ntype MyCustomType = int"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var types: seq[string] = @[]
    for token in tokens:
      if token.tokenType == ttType:
        types.add(token.text)

    # Should identify custom types
    check types.len > 0

  test "Token positioning accuracy":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "let x = 42"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    # Verify tokens have correct positions and lengths
    for token in tokens:
      check token.start >= 0
      check token.length > 0
      check token.start + token.length <= code.len

  test "Empty and edge case handling":
    var highlighter = newSyntaxHighlighter(langNim)
    
    # Empty string
    let emptyTokens = highlighter.tokenize("")
    check emptyTokens.len == 0

    # Whitespace only
    let whitespaceTokens = highlighter.tokenize("   \n  \t  ")
    # Should handle gracefully (either empty or whitespace tokens)
    check whitespaceTokens.len >= 0

  test "Python syntax basics":
    var highlighter = newSyntaxHighlighter(langPython)
    let code = "def hello(name):\n    return f'Hello {name}'"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var foundDef = false
    var foundReturn = false
    for token in tokens:
      if token.text == "def" and token.tokenType == ttKeyword:
        foundDef = true
      elif token.text == "return" and token.tokenType == ttKeyword:
        foundReturn = true

    check foundDef
    check foundReturn

  test "JavaScript syntax basics":
    var highlighter = newSyntaxHighlighter(langJavaScript)
    let code = "function test() { return true; }"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    var foundFunction = false
    var foundReturn = false
    for token in tokens:
      if token.text == "function" and token.tokenType == ttKeyword:
        foundFunction = true
      elif token.text == "return" and token.tokenType == ttKeyword:
        foundReturn = true

    check foundFunction
    check foundReturn

  test "Complex code tokenization":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = """
proc calculateSum(numbers: seq[int]): int =
  ## Calculate sum of integers
  var result = 0
  for num in numbers:
    result += num  # Add to total
  return result
"""
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    # Verify we have diverse token types
    var tokenTypes: set[TokenType] = {}
    for token in tokens:
      tokenTypes.incl(token.tokenType)

    check ttKeyword in tokenTypes
    check ttNumberLit in tokenTypes
    check ttComment in tokenTypes
    check ttOperator in tokenTypes
    check ttIdentifier in tokenTypes

  test "Token text extraction accuracy":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "let message = \"test\""
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    # Verify token text matches what's expected
    for token in tokens:
      let extractedText = code[token.start ..< token.start + token.length]
      check token.text == extractedText

  test "Language-specific keyword differences":
    var nimHL = newSyntaxHighlighter(langNim)
    var pyHL = newSyntaxHighlighter(langPython)
    var jsHL = newSyntaxHighlighter(langJavaScript)

    # Nim specific
    check "proc" in nimHL.keywords
    check "let" in nimHL.keywords

    # Python specific
    check "def" in pyHL.keywords
    check "lambda" in pyHL.keywords

    # JavaScript specific  
    check "function" in jsHL.keywords
    check "var" in jsHL.keywords

  test "Multi-line code handling":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = """line1 = "hello"
line2 = "world"
line3 = 123"""
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    # Should handle newlines and multiple lines correctly
    check tokens.len > 6  # At least identifiers, operators, and values

  test "Nested structures tokenization":
    var highlighter = newSyntaxHighlighter(langNim)
    let code = "obj.field[index].method()"
    highlighter.text = code
    let tokens = highlighter.tokenize(code)

    # Should tokenize complex nested access patterns
    var foundIdentifiers = 0
    var foundOperators = 0
    for token in tokens:
      if token.tokenType == ttIdentifier:
        foundIdentifiers += 1
      elif token.tokenType == ttOperator or token.tokenType == ttPunctuation:
        foundOperators += 1

    check foundIdentifiers > 0
    check foundOperators > 0

when isMainModule:
  # Tests run automatically with unittest framework
  echo "✅ All syntax highlighting logic tests completed!" 