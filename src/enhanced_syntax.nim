import std/[strutils, os, sets, unicode]
import raylib as rl
import std/algorithm

# Token types for syntax highlighting
type
  TokenType* = enum
    ttText
    ttIdentifier
    ttKeyword
    ttControlFlow
    ttOperator
    ttStringLit
    ttNumberLit
    ttComment
    ttTodoComment
    ttFunction
    ttType
    ttBuiltin
    ttLineNumber
    ttExportMark
    ttProcName
    ttMarkdownFence
    ttMarkdownLanguage

  Token* = object
    tokenType*: TokenType
    start*: int
    length*: int
    text*: string

  Language* = enum
    langNim = "nim"
    langPython = "python"
    langJavaScript = "javascript"
    langRust = "rust"
    langC = "c"
    langCpp = "cpp"
    langMarkdown = "markdown"
    langPlainText = "plaintext"

# Color constants for syntax highlighting
const
  SYNTAX_KEYWORD_COLOR* = rl.Color(r: 86, g: 156, b: 214, a: 255)          # Blue
  SYNTAX_STRING_COLOR* = rl.Color(r: 206, g: 145, b: 120, a: 255)          # Orange
  SYNTAX_COMMENT_COLOR* = rl.Color(r: 106, g: 153, b: 85, a: 255)          # Green
  SYNTAX_NUMBER_COLOR* = rl.Color(r: 181, g: 206, b: 168, a: 255)          # Light Green
  SYNTAX_FUNCTION_COLOR* = rl.Color(r: 220, g: 220, b: 170, a: 255)        # Yellow
  SYNTAX_OPERATOR_COLOR* = rl.Color(r: 212, g: 212, b: 212, a: 255)        # Light Gray
  SYNTAX_TYPE_COLOR* = rl.Color(r: 78, g: 201, b: 176, a: 255)             # Teal
  SYNTAX_CONTROL_FLOW_COLOR* = rl.Color(r: 195, g: 110, b: 181, a: 255)    # Magenta
  SYNTAX_TEXT_COLOR* = rl.Color(r: 220, g: 220, b: 220, a: 255)            # Light Gray
  SYNTAX_LINENUMBER_COLOR* = rl.Color(r: 128, g: 128, b: 128, a: 255)      # Gray
  SYNTAX_ERROR_COLOR* = rl.Color(r: 255, g: 0, b: 0, a: 255)               # Red
  SYNTAX_PUNCTUATION_COLOR* = rl.Color(r: 255, g: 203, b: 107, a: 255)     # Orange-Yellow
  SYNTAX_PREPROCESSOR_COLOR* = rl.Color(r: 199, g: 146, b: 234, a: 255)    # Purple
  SYNTAX_ESCAPE_COLOR* = rl.Color(r: 255, g: 128, b: 0, a: 255)            # Orange
  SYNTAX_MARKDOWN_FENCE_COLOR* = rl.Color(r: 128, g: 128, b: 128,
      a: 255) # Muted gray for fence characters
  SYNTAX_MARKDOWN_LANGUAGE_COLOR* = rl.Color(r: 86, g: 156, b: 214,
      a: 255) # Blue for language names

type LanguageDefinition = object
  keywords: HashSet[string]
  controlFlow: HashSet[string]
  builtinTypes: HashSet[string]
  operators: seq[string]
  singleLineComment: string
  multiLineCommentStart: string
  multiLineCommentEnd: string

proc initLanguageDefinition(): LanguageDefinition =
  result.keywords = initHashSet[string]()
  result.controlFlow = initHashSet[string]()
  result.builtinTypes = initHashSet[string]()
  result.operators = @[]

proc getLanguageDefinition(language: Language): LanguageDefinition =
  result = initLanguageDefinition()
  case language
  of langNim:
    # Nim keywords
    for keyword in ["addr", "and", "as", "asm", "bind", "block", "break",
        "case", "cast", "concept", "const", "continue", "converter", "defer",
        "discard", "distinct", "div", "elif", "else", "end", "enum", "except",
        "export", "finally", "for", "from", "func", "if", "import", "in",
        "include", "interface", "is", "isnot", "iterator", "let", "macro",
        "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or",
        "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static",
        "template", "try", "tuple", "type", "using", "var", "when", "while",
        "xor", "yield"]:
      result.keywords.incl(keyword)
    for flow in ["if", "elif", "else", "case", "of", "when", "while", "for",
        "break", "continue", "block", "return", "yield", "raise", "try",
        "except", "finally", "defer"]:
      result.controlFlow.incl(flow)
    for builtin in ["int", "int8", "int16", "int32", "int64", "uint", "uint8",
        "uint16", "uint32", "uint64", "float", "float32", "float64", "bool",
        "char", "string", "cstring", "pointer", "void", "auto", "any", "typed",
        "typedesc", "untyped", "untypedesc", "static", "enum", "object",
        "tuple", "seq", "array", "set", "openarray", "varargs", "opt", "lent",
        "owned", "sink", "lent", "proc", "func", "iterator", "converter",
        "template", "macro", "method", "concept", "distinct", "ref", "ptr",
        "addr", "nil", "true", "false"]:
      result.builtinTypes.incl(builtin)
    result.operators = @["==", "<=", ">=", "!=", "->", "=>", "::", "..", ".[",
        ".]", ".{", ".}", ".(", ".)"]
    result.singleLineComment = "#"
    result.multiLineCommentStart = "#["
    result.multiLineCommentEnd = "]"
  of langPython:
    for keyword in ["False", "None", "True", "and", "as", "assert", "async",
        "await", "break", "class", "continue", "def", "del", "elif", "else",
        "except", "finally", "for", "from", "global", "if", "import", "in",
        "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
        "try", "while", "with", "yield"]:
      result.keywords.incl(keyword)
    for flow in ["if", "elif", "else", "for", "while", "break", "continue",
        "try", "except", "finally", "with", "return", "yield", "raise"]:
      result.controlFlow.incl(flow)
    result.operators = @["==", "!=", "<=", ">=", "**", "//", "->", "+=", "-=",
        "*=", "/="]
    result.singleLineComment = "#"
  of langJavaScript:
    for keyword in ["break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "export", "extends",
        "finally", "for", "function", "if", "import", "in", "instanceof", "let",
        "new", "return", "super", "switch", "this", "throw", "try", "typeof",
        "var", "void", "while", "with", "yield"]:
      result.keywords.incl(keyword)
    for flow in ["if", "else", "for", "while", "break", "continue", "return",
        "switch", "case", "default", "try", "catch", "finally", "throw"]:
      result.controlFlow.incl(flow)
    result.operators = @["==", "!=", "===", "!==", "<=", ">=", "&&", "||", "++", "--"]
    result.singleLineComment = "//"
    result.multiLineCommentStart = "/*"
    result.multiLineCommentEnd = "*/"
  of langRust:
    for keyword in ["as", "break", "const", "continue", "crate", "else", "enum",
        "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
        "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self",
        "static", "struct", "super", "trait", "true", "type", "unsafe", "use",
        "where", "while"]:
      result.keywords.incl(keyword)
    for flow in ["if", "else", "for", "while", "loop", "break", "continue",
        "return", "match"]:
      result.controlFlow.incl(flow)
    result.operators = @["==", "!=", "<=", ">=", "->", "=>", "::", ".."]
    result.singleLineComment = "//"
    result.multiLineCommentStart = "/*"
    result.multiLineCommentEnd = "*/"
  of langC:
    for keyword in ["auto", "break", "case", "char", "const", "continue",
        "default", "do", "double", "else", "enum", "extern", "float", "for",
        "goto", "if", "int", "long", "register", "return", "short", "signed",
        "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
        "void", "volatile", "while"]:
      result.keywords.incl(keyword)
    for flow in ["if", "else", "for", "while", "break", "continue", "return",
        "switch", "case", "default", "goto"]:
      result.controlFlow.incl(flow)
    result.operators = @["==", "!=", "<=", ">=", "->", "++", "--", "&&", "||"]
    result.singleLineComment = "//"
    result.multiLineCommentStart = "/*"
    result.multiLineCommentEnd = "*/"
  of langCpp:
    for keyword in ["auto", "break", "case", "catch", "char", "class", "const",
        "continue", "default", "delete", "do", "double", "else", "enum",
        "explicit", "export", "extern", "false", "float", "for", "friend",
        "goto", "if", "inline", "int", "long", "mutable", "namespace", "new",
        "operator", "private", "protected", "public", "register", "return",
        "short", "signed", "sizeof", "static", "struct", "switch", "template",
        "this", "throw", "true", "try", "typedef", "typename", "union",
        "unsigned", "using", "virtual", "void", "volatile", "while"]:
      result.keywords.incl(keyword)
    for flow in ["if", "else", "switch", "case", "default", "for", "while",
        "do", "break", "continue", "return", "goto", "try", "catch", "throw"]:
      result.controlFlow.incl(flow)
    result.operators = @["<<", ">>", "::", "->", "++", "--", "==", "!=", "<=",
        ">=", "&&", "||"]
    result.singleLineComment = "//"
    result.multiLineCommentStart = "/*"
    result.multiLineCommentEnd = "*/"
  else:
    # PlainText has no special rules
    discard
  for op in ["=", "+", "-", "*", "/", "<", ">", "!", "&", "|", "^", "~", "%",
      ".", ":", ",", ";", "(", ")", "[", "]", "{", "}"]:
    result.operators.add(op)
  result.operators.sort(proc(a, b: string): int = cmp(a.len, b.len))
  result.operators.reverse()

type SyntaxHighlighter* = object
  langDef: LanguageDefinition
  text*: string

proc newSyntaxHighlighter*(language: Language): SyntaxHighlighter =
  result.langDef = getLanguageDefinition(language)

proc isIdentChar(c: char): bool =
  c.isAlphaNumeric() or c == '_'

proc isIdentCharUnicode(rune: Rune): bool =
  ## Unicode-aware identifier character check
  rune.isAlpha() or rune == '_'.Rune or ('0'.Rune <=% rune and rune <=% '9'.Rune)

proc tokenize*(highlighter: var SyntaxHighlighter, text: string): seq[Token] =
  highlighter.text = text

  # Special handling for markdown - treat as plain text in tokenizer
  # Actual markdown code block highlighting is handled separately
  if highlighter.langDef == getLanguageDefinition(langMarkdown):
    # For markdown, just return the text as plain text tokens
    # The markdown code block highlighting is handled in the text editor
    return @[Token(tokenType: ttText, start: 0, length: text.len, text: text)]

  var pos = 0

  while pos < text.len:
    let c = text[pos]

    # 1. Whitespace (create tokens for them instead of skipping)
    if c == ' ' or c == '\t' or c == '\n' or c == '\r':
      let startPos = pos
      # Consume consecutive whitespace characters
      while pos < text.len and (text[pos] == ' ' or text[pos] == '\t' or text[
          pos] == '\n' or text[pos] == '\r'):
        pos += 1
      let whitespaceText = text.substr(startPos, pos - 1)
      result.add(Token(tokenType: ttText, start: startPos, length: pos -
          startPos, text: whitespaceText))
      continue

    # 2. Comments
    let lang = highlighter.langDef
    var matched = false

    # Multi-line comments
    if lang.multiLineCommentStart.len > 0 and pos +
        lang.multiLineCommentStart.len <= text.len and
       text.substr(pos, pos + lang.multiLineCommentStart.len - 1) ==
           lang.multiLineCommentStart:
      let startPos = pos
      pos += lang.multiLineCommentStart.len
      let endPos = text.find(lang.multiLineCommentEnd, pos)
      if endPos > -1:
        pos = endPos + lang.multiLineCommentEnd.len
      else:
        pos = text.len

      let commentText = text.substr(startPos, pos - 1)
      let tokenType = if "todo" in commentText.toLowerAscii() or "fixme" in
          commentText.toLowerAscii(): ttTodoComment else: ttComment
      result.add(Token(tokenType: tokenType, start: startPos, length: pos -
          startPos, text: commentText))
      matched = true

    # Single-line comments
    elif lang.singleLineComment.len > 0 and pos + lang.singleLineComment.len <= text.len and
         text.substr(pos, pos + lang.singleLineComment.len - 1) ==
             lang.singleLineComment:
      let startPos = pos
      while pos < text.len and text[pos] != '\n':
        pos += 1

      let commentText = text.substr(startPos, pos - 1)
      let tokenType = if "todo" in commentText.toLowerAscii() or "fixme" in
          commentText.toLowerAscii(): ttTodoComment else: ttComment
      result.add(Token(tokenType: tokenType, start: startPos, length: pos -
          startPos, text: commentText))
      matched = true

    if matched:
      continue

    # 3. String literals
    if c == '"' or c == '\'':
      let startPos = pos
      let quoteChar = c
      pos += 1
      while pos < text.len and text[pos] != quoteChar:
        if text[pos] == '\\' and pos + 1 < text.len:
          pos += 2 # Skip escaped character
        else:
          pos += 1

      if pos < text.len:
        pos += 1 # Skip closing quote

      let stringText = text.substr(startPos, pos - 1)
      result.add(Token(tokenType: ttStringLit, start: startPos, length: pos -
          startPos, text: stringText))
      continue

    # 4. Numbers
    if c.isDigit():
      let startPos = pos
      while pos < text.len and (text[pos].isDigit() or text[pos] == '.'):
        pos += 1
      let numberText = text.substr(startPos, pos - 1)
      result.add(Token(tokenType: ttNumberLit, start: startPos, length: pos -
          startPos, text: numberText))
      continue

    # 5. Identifiers and keywords
    if c.isAlphaAscii() or c == '_':
      let startPos = pos
      while pos < text.len and isIdentChar(text[pos]):
        pos += 1

      let ident = text.substr(startPos, pos - 1)
      var tokenType = ttIdentifier

      if lang.controlFlow.contains(ident):
        tokenType = ttControlFlow
      elif lang.keywords.contains(ident):
        tokenType = ttKeyword
      elif lang.builtinTypes.contains(ident):
        tokenType = ttBuiltin
      elif ident == "result":
        tokenType = ttControlFlow # Special color for result (same as control flow)
      elif ident.len > 0 and ident[0].isUpperAscii():
        tokenType = ttType
      # Check if this looks like a procedure name (simple heuristic)
      elif ident.len > 0 and ident[0].isLowerAscii() and
          not lang.keywords.contains(ident) and not lang.builtinTypes.contains(ident):
        # Look ahead to see if this is followed by '(' or '*'
        var lookAhead = pos
        while lookAhead < text.len and (text[lookAhead] == ' ' or text[
            lookAhead] == '\t'):
          lookAhead += 1
        if lookAhead < text.len and (text[lookAhead] == '(' or text[
            lookAhead] == '*'):
          tokenType = ttProcName # This looks like a procedure name
        # Field names in type definitions are always ttIdentifier (normal text color)
        # They are lowercase identifiers that are not keywords or builtin types

      result.add(Token(tokenType: tokenType, start: startPos, length: pos -
          startPos, text: ident))
      continue

    # 6. Export marks (asterisks in Nim)
    if c == '*' and highlighter.langDef.singleLineComment ==
        "#": # This indicates Nim language
      result.add(Token(tokenType: ttExportMark, start: pos, length: 1, text: "*"))
      pos += 1
      continue

    # 6. Operators
    matched = false
    for op in lang.operators:
      if pos + op.len <= text.len and text.substr(pos, pos + op.len - 1) == op:
        result.add(Token(tokenType: ttOperator, start: pos, length: op.len, text: op))
        pos += op.len
        matched = true
        break
    if matched:
      continue

    # 7. Fallback
    result.add(Token(tokenType: ttText, start: pos, length: 1, text: $c))
    pos += 1

proc getTokenColor*(tokenType: TokenType): rl.Color =
  case tokenType
  of ttKeyword: SYNTAX_KEYWORD_COLOR
  of ttControlFlow: SYNTAX_CONTROL_FLOW_COLOR
  of ttType: SYNTAX_TYPE_COLOR
  of ttBuiltin: SYNTAX_TYPE_COLOR
  of ttFunction: SYNTAX_FUNCTION_COLOR
  of ttStringLit: SYNTAX_STRING_COLOR
  of ttNumberLit: SYNTAX_NUMBER_COLOR
  of ttComment, ttTodoComment: SYNTAX_COMMENT_COLOR
  of ttOperator: SYNTAX_OPERATOR_COLOR
  of ttLineNumber: SYNTAX_LINENUMBER_COLOR
  of ttIdentifier: SYNTAX_TEXT_COLOR # Regular identifiers are white
  of ttProcName: SYNTAX_FUNCTION_COLOR # Procedure names are yellow
  of ttExportMark: SYNTAX_PREPROCESSOR_COLOR # Make export marks purple
  of ttMarkdownFence: SYNTAX_MARKDOWN_FENCE_COLOR  # Muted gray for fence characters
  of ttMarkdownLanguage: SYNTAX_MARKDOWN_LANGUAGE_COLOR  # Blue for language names
  else: SYNTAX_TEXT_COLOR

proc getTokenText*(highlighter: SyntaxHighlighter, token: Token): string =
  highlighter.text.substr(token.start, token.length - 1)

proc detectLanguage*(filename: string): Language =
  let ext = filename.splitFile().ext.toLowerAscii()
  case ext
  of ".nim", ".nims", ".nimble": langNim
  of ".py", ".pyw": langPython
  of ".js", ".mjs", ".cjs": langJavaScript
  of ".rs": langRust
  of ".c", ".h": langC
  of ".cpp", ".cxx", ".cc", ".hpp": langCpp
  of ".md", ".markdown": langMarkdown
  else: langPlainText


