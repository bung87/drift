## Simplified Markdown Code Block Renderer
## Focuses only on detecting and highlighting code blocks within markdown files
## Does not treat markdown as a programming language

import std/[strutils, options]
import enhanced_syntax

# Types for code block detection
type
  CodeBlockType* = enum
    cbFenced     ## Fenced code block (``` or ~~~)
    cbIndented   ## Indented code block (4+ spaces)

  CodeBlockInfo* = object
    blockType*: CodeBlockType
    language*: string           ## Language identifier (e.g., "nim", "python")
    startLine*: int             ## 0-based line number where block starts
    endLine*: int               ## 0-based line number where block ends
    content*: seq[string]       ## Lines of code inside the block
    fence*: string              ## The fence characters used (``` or ~~~)
    
  MarkdownCodeBlockRenderer* = object
    lines*: seq[string]         ## Document lines
    codeBlocks*: seq[CodeBlockInfo]  ## Detected code blocks

# Language detection for code blocks
proc detectCodeLanguage(langId: string): Language =
  ## Convert language identifier to Language enum
  if langId.len == 0:
    return langPlainText
  
  case langId.toLowerAscii()
  of "nim", "nimrod":
    return langNim
  of "python", "py":
    return langPython
  of "javascript", "js", "node":
    return langJavaScript
  of "rust", "rs":
    return langRust
  of "c":
    return langC
  of "cpp", "c++", "cxx":
    return langCpp
  else:
    return langPlainText

# Core parsing functions
proc newMarkdownCodeBlockRenderer*(content: string): MarkdownCodeBlockRenderer =
  ## Create a new markdown code block renderer
  result = MarkdownCodeBlockRenderer()
  result.lines = content.splitLines()
  result.codeBlocks = @[]

proc isFenceLine(line: string): tuple[isFence: bool, fence: string, lang: string] =
  ## Check if line is a fence line (``` or ~~~)
  let trimmed = line.strip()
  
  # Check for ``` fences
  if trimmed.startsWith("```"):
    var fenceLen = 0
    for c in trimmed:
      if c == '`':
        fenceLen += 1
      else:
        break
    
    if fenceLen >= 3:
      # Extract language (remaining non-whitespace text)
      let rest = trimmed[fenceLen..^1].strip()
      let lang = if rest.len > 0: rest.split(' ')[0] else: ""
      return (true, repeat('`', fenceLen), lang)
  
  # Check for ~~~ fences
  elif trimmed.startsWith("~~~"):
    var fenceLen = 0
    for c in trimmed:
      if c == '~':
        fenceLen += 1
      else:
        break
    
    if fenceLen >= 3:
      # Extract language (remaining non-whitespace text)
      let rest = trimmed[fenceLen..^1].strip()
      let lang = if rest.len > 0: rest.split(' ')[0] else: ""
      return (true, repeat('~', fenceLen), lang)
  
  return (false, "", "")

proc isIndentedCodeLine(line: string): tuple[isIndented: bool, content: string] =
  ## Check if line is an indented code line (4+ spaces or 1+ tabs)
  if line.strip().len == 0:
    return (true, "")  # Empty lines are part of indented blocks
  
  var indentLevel = 0
  var i = 0
  
  # Count leading whitespace
  while i < line.len:
    if line[i] == ' ':
      indentLevel += 1
      i += 1
    elif line[i] == '\t':
      indentLevel += 4  # Tab counts as 4 spaces
      i += 1
    else:
      break
  
  # Code blocks need at least 4 spaces of indentation
  if indentLevel >= 4:
    return (true, line[i..^1])
  
  return (false, "")

proc parseCodeBlocks*(renderer: var MarkdownCodeBlockRenderer) =
  ## Parse the document and extract all code blocks
  renderer.codeBlocks = @[]
  var i = 0
  
  while i < renderer.lines.len:
    let line = renderer.lines[i]
    
    # Check for fenced code block
    let fenceInfo = isFenceLine(line)
    if fenceInfo.isFence:
      var codeBlock = CodeBlockInfo()
      codeBlock.blockType = cbFenced
      codeBlock.language = fenceInfo.lang
      codeBlock.startLine = i
      codeBlock.fence = fenceInfo.fence
      codeBlock.content = @[]
      
      # Look for closing fence
      i += 1
      var foundClosing = false
      
      while i < renderer.lines.len:
        let currentLine = renderer.lines[i]
        let currentFence = isFenceLine(currentLine)
        
        # Check if this is a closing fence of the same type
        if currentFence.isFence and currentFence.fence.startsWith(codeBlock.fence[0]):
          codeBlock.endLine = i
          foundClosing = true
          break
        else:
          # Add content line
          codeBlock.content.add(currentLine)
        
        i += 1
      
      # Handle unclosed fence (treat rest of document as code)
      if not foundClosing:
        codeBlock.endLine = renderer.lines.len - 1
      

      renderer.codeBlocks.add(codeBlock)
    
    # Check for indented code block (only if not already in a fence)
    else:
      let indentInfo = isIndentedCodeLine(line)
      if indentInfo.isIndented and indentInfo.content.len > 0:
        var codeBlock = CodeBlockInfo()
        codeBlock.blockType = cbIndented
        codeBlock.language = ""  # No language for indented blocks
        codeBlock.startLine = i
        codeBlock.content = @[indentInfo.content]
        
        # Continue collecting indented lines
        i += 1
        while i < renderer.lines.len:
          let currentIndent = isIndentedCodeLine(renderer.lines[i])
          if currentIndent.isIndented:
            codeBlock.content.add(currentIndent.content)
            i += 1
          else:
            break
        
        codeBlock.endLine = i - 1
        renderer.codeBlocks.add(codeBlock)

        continue  # Don't increment i again
    
    i += 1

proc getCodeBlockAt*(renderer: MarkdownCodeBlockRenderer, lineNum: int): Option[CodeBlockInfo] =
  ## Get the code block that contains the specified line number
  for codeBlock in renderer.codeBlocks:
    if lineNum >= codeBlock.startLine and lineNum <= codeBlock.endLine:
      return some(codeBlock)
  return none(CodeBlockInfo)

proc isInsideCodeBlock*(renderer: MarkdownCodeBlockRenderer, lineNum: int): bool =
  ## Check if the specified line is inside any code block
  renderer.getCodeBlockAt(lineNum).isSome

proc getLanguageAtLine*(renderer: MarkdownCodeBlockRenderer, lineNum: int): Language =
  ## Get the programming language for syntax highlighting at the specified line
  let blockOpt = renderer.getCodeBlockAt(lineNum)
  if blockOpt.isSome:
    let codeBlock = blockOpt.get()
    return detectCodeLanguage(codeBlock.language)
  return langPlainText  # Outside code blocks, treat as plain text

proc renderCodeBlockTokens*(renderer: MarkdownCodeBlockRenderer, codeBlock: CodeBlockInfo): seq[enhanced_syntax.Token] =
  ## Generate syntax-highlighted tokens for a code block
  if codeBlock.content.len == 0:
    return @[]
  
  let language = detectCodeLanguage(codeBlock.language)
  var highlighter = newSyntaxHighlighter(language)
  let codeText = codeBlock.content.join("\n")
  
  let tokens = highlighter.tokenize(codeText)
  return tokens



proc renderMarkdownWithCodeBlocks*(renderer: MarkdownCodeBlockRenderer): seq[enhanced_syntax.Token] =
  ## Render entire markdown document with code blocks highlighted
  var tokens: seq[enhanced_syntax.Token] = @[]
  var currentPos = 0
  
  for lineNum, line in renderer.lines.pairs():
    let lineStart = currentPos
    let blockOpt = renderer.getCodeBlockAt(lineNum)
    
    if blockOpt.isSome:
      let codeBlock = blockOpt.get()
      
      if codeBlock.blockType == cbFenced:
        if lineNum == codeBlock.startLine:
          # Opening fence line - parse fence and language separately
          let fenceInfo = isFenceLine(line)
          if fenceInfo.isFence:
            # Add fence characters (``` or ~~~)
            tokens.add(enhanced_syntax.Token(
              tokenType: ttMarkdownFence,
              start: lineStart,
              length: fenceInfo.fence.len,
              text: fenceInfo.fence
            ))
            
            # Add language identifier if present
            if fenceInfo.lang.len > 0:
              let langStart = lineStart + fenceInfo.fence.len
              let trimmedLine = line.strip()
              let langStartInLine = trimmedLine.find(fenceInfo.lang)
              if langStartInLine >= 0:
                # Add any whitespace between fence and language
                let actualLangStart = lineStart + line.find(fenceInfo.lang)
                if actualLangStart > langStart:
                  tokens.add(enhanced_syntax.Token(
                    tokenType: ttText,
                    start: langStart,
                    length: actualLangStart - langStart,
                    text: line[fenceInfo.fence.len..<(actualLangStart - lineStart)]
                  ))
                
                # Add the language identifier
                tokens.add(enhanced_syntax.Token(
                  tokenType: ttMarkdownLanguage,
                  start: actualLangStart,
                  length: fenceInfo.lang.len,
                  text: fenceInfo.lang
                ))
                
                # Add any remaining text on the line
                let remainingStart = actualLangStart + fenceInfo.lang.len
                if remainingStart < lineStart + line.len:
                  tokens.add(enhanced_syntax.Token(
                    tokenType: ttText,
                    start: remainingStart,
                    length: (lineStart + line.len) - remainingStart,
                    text: line[(remainingStart - lineStart)..<line.len]
                  ))
          else:
            # Fallback if fence parsing fails
            tokens.add(enhanced_syntax.Token(
              tokenType: ttMarkdownFence,
              start: lineStart,
              length: line.len,
              text: line
            ))
        elif lineNum == codeBlock.endLine:
          # Closing fence line
          tokens.add(enhanced_syntax.Token(
            tokenType: ttMarkdownFence,
            start: lineStart,
            length: line.len,
            text: line
          ))
        else:
          # Content line inside code block
          if line.len > 0:
            let language = detectCodeLanguage(codeBlock.language)
            var highlighter = newSyntaxHighlighter(language)
            let lineTokens = highlighter.tokenize(line)
            
            # Add tokens for this content line with correct positions
            for token in lineTokens:
              var adjustedToken = token
              adjustedToken.start += lineStart
              tokens.add(adjustedToken)
          else:
            # Empty line in code block
            tokens.add(enhanced_syntax.Token(
              tokenType: ttText,
              start: lineStart,
              length: 0,
              text: ""
            ))
      
      elif codeBlock.blockType == cbIndented:
        # Handle indented code blocks
        let indentInfo = isIndentedCodeLine(line)
        if indentInfo.isIndented:
          let codeContent = indentInfo.content
          let indentSize = line.len - codeContent.len
          
          # Add indentation as plain text
          if indentSize > 0:
            tokens.add(enhanced_syntax.Token(
              tokenType: ttText,
              start: lineStart,
              length: indentSize,
              text: line[0 ..< indentSize]
            ))
          
          # Add the code content as plain text (could be enhanced with syntax highlighting)
          if codeContent.len > 0:
            tokens.add(enhanced_syntax.Token(
              tokenType: ttText,
              start: lineStart + indentSize,
              length: codeContent.len,
              text: codeContent
            ))
        else:
          # Non-indented line (empty or end of block)
          tokens.add(enhanced_syntax.Token(
            tokenType: ttText,
            start: lineStart,
            length: line.len,
            text: line
          ))
    
    else:
      # Regular markdown text - treat as plain text
      tokens.add(enhanced_syntax.Token(
        tokenType: ttText,
        start: lineStart,
        length: line.len,
        text: line
      ))
    
    currentPos += line.len + 1  # +1 for newline
  
  return tokens

# Utility functions for integration
proc hasCodeBlocks*(renderer: MarkdownCodeBlockRenderer): bool =
  ## Check if the document has any code blocks
  renderer.codeBlocks.len > 0

proc getCodeBlockCount*(renderer: MarkdownCodeBlockRenderer): int =
  ## Get the total number of code blocks
  renderer.codeBlocks.len

proc getCodeBlocksInRange*(renderer: MarkdownCodeBlockRenderer, startLine: int, endLine: int): seq[CodeBlockInfo] =
  ## Get all code blocks that intersect with the specified line range
  result = @[]
  for codeBlock in renderer.codeBlocks:
    if not (codeBlock.endLine < startLine or codeBlock.startLine > endLine):
      result.add(codeBlock)

# Performance optimization for large files
proc parseCodeBlocksInRange*(renderer: var MarkdownCodeBlockRenderer, startLine: int, endLine: int) =
  ## Parse code blocks only in a specific range (for large files)
  # For now, just parse everything - can be optimized later for very large files
  renderer.parseCodeBlocks()

# Debug function
proc debugPrint*(renderer: MarkdownCodeBlockRenderer) =
  ## Print debug information about detected code blocks
  echo "=== Markdown Code Blocks Debug ==="
  echo "Total lines: ", renderer.lines.len
  echo "Code blocks found: ", renderer.codeBlocks.len
  echo ""
  
  for i, codeBlock in renderer.codeBlocks.pairs():
    echo "Block ", i + 1, ":"
    echo "  Type: ", codeBlock.blockType
    echo "  Language: ", if codeBlock.language.len > 0: codeBlock.language else: "(none)"
    echo "  Lines: ", codeBlock.startLine + 1, " - ", codeBlock.endLine + 1
    echo "  Content lines: ", codeBlock.content.len
    if codeBlock.content.len > 0:
      let preview = codeBlock.content[0]
      echo "  First line: ", preview[0 ..< min(50, preview.len)]
    if codeBlock.blockType == cbFenced:
      echo "  Fence: ", codeBlock.fence
    echo ""