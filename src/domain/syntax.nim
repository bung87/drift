## Syntax Domain Model
## Simple re-export of enhanced syntax functionality

import ../enhanced_syntax

# Re-export core types and functions from enhanced_syntax
export TokenType, Token, Language, SyntaxHighlighter
export newSyntaxHighlighter, tokenize, getTokenColor, getTokenText, detectLanguage

# Compatibility aliases for any code that might expect different names
type
  LanguageDefinition* = Language
  TokenStream* = seq[Token]

# Simple helper functions that might be expected by domain layer
proc createTokenStream*(tokens: seq[Token], language: Language): TokenStream =
  ## Create a token stream from a sequence of tokens
  tokens

proc getLanguageFromExtension*(extension: string): Language =
  ## Get language from file extension
  detectLanguage("file" & extension)

proc highlightText*(text: string, language: Language): seq[Token] =
  ## Simple function to highlight text and return tokens
  var highlighter = newSyntaxHighlighter(language)
  highlighter.tokenize(text)
