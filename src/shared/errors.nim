## Shared error handling utilities for the Drift editor
## Provides consistent error types and handling across the application

import std/[strformat, strutils]

# Base error types
type
  EditorError* = object of CatchableError
    code*: string
    context*: string

  # Domain-specific error types
  FileError* = object of EditorError
    filepath*: string
    operation*: string

  LSPError* = object of EditorError
    methodName*: string
    serverId*: string

  SyntaxError* = object of EditorError
    line*: int
    column*: int
    language*: string

  ConfigError* = object of EditorError
    setting*: string
    value*: string

  GitError* = object of EditorError
    command*: string
    workingDir*: string

  RenderError* = object of EditorError
    component*: string

  InputError* = object of EditorError
    inputType*: string

  ValidationError* = object of EditorError
    field*: string
    constraint*: string



# Error code constants
const
  # File operation errors
  ERROR_FILE_NOT_FOUND* = "FILE_NOT_FOUND"
  ERROR_FILE_ACCESS_DENIED* = "FILE_ACCESS_DENIED"
  ERROR_FILE_TOO_LARGE* = "FILE_TOO_LARGE"
  ERROR_FILE_BINARY* = "FILE_BINARY"
  ERROR_FILE_CORRUPTED* = "FILE_CORRUPTED"
  ERROR_FILE_LOCKED* = "FILE_LOCKED"

  # LSP errors
  ERROR_LSP_NOT_INITIALIZED* = "LSP_NOT_INITIALIZED"
  ERROR_LSP_CONNECTION_FAILED* = "LSP_CONNECTION_FAILED"
  ERROR_LSP_TIMEOUT* = "LSP_TIMEOUT"
  ERROR_LSP_INVALID_RESPONSE* = "LSP_INVALID_RESPONSE"
  ERROR_LSP_SERVER_ERROR* = "LSP_SERVER_ERROR"

  # Syntax errors
  ERROR_SYNTAX_PARSE_FAILED* = "SYNTAX_PARSE_FAILED"
  ERROR_SYNTAX_UNKNOWN_LANGUAGE* = "SYNTAX_UNKNOWN_LANGUAGE"
  ERROR_SYNTAX_INVALID_TOKEN* = "SYNTAX_INVALID_TOKEN"

  # Configuration errors
  ERROR_CONFIG_NOT_FOUND* = "CONFIG_NOT_FOUND"
  ERROR_CONFIG_INVALID_FORMAT* = "CONFIG_INVALID_FORMAT"
  ERROR_CONFIG_INVALID_VALUE* = "CONFIG_INVALID_VALUE"
  ERROR_CONFIG_WRITE_FAILED* = "CONFIG_WRITE_FAILED"

  # Git errors
  ERROR_GIT_NOT_REPOSITORY* = "GIT_NOT_REPOSITORY"
  ERROR_GIT_COMMAND_FAILED* = "GIT_COMMAND_FAILED"
  ERROR_GIT_NOT_INSTALLED* = "GIT_NOT_INSTALLED"

  # Rendering errors
  ERROR_RENDER_FONT_LOAD_FAILED* = "RENDER_FONT_LOAD_FAILED"
  ERROR_RENDER_TEXTURE_FAILED* = "RENDER_TEXTURE_FAILED"
  ERROR_RENDER_SHADER_FAILED* = "RENDER_SHADER_FAILED"

  # Input errors
  ERROR_INPUT_INVALID_KEY* = "INPUT_INVALID_KEY"
  ERROR_INPUT_INVALID_MOUSE* = "INPUT_INVALID_MOUSE"

  # Validation errors
  ERROR_VALIDATION_REQUIRED* = "VALIDATION_REQUIRED"
  ERROR_VALIDATION_TYPE_MISMATCH* = "VALIDATION_TYPE_MISMATCH"
  ERROR_VALIDATION_OUT_OF_RANGE* = "VALIDATION_OUT_OF_RANGE"



# Error creation utilities
proc newEditorError*(code: string, message: string, context: string = ""): EditorError =
  result = EditorError(code: code, context: context)
  result.msg = message

proc newFileError*(
    code: string, message: string, filepath: string = "", operation: string = ""
): FileError =
  result = FileError(code: code, filepath: filepath, operation: operation)
  result.msg = message

proc newLSPError*(
    code: string, message: string, methodName: string = "", serverId: string = ""
): LSPError =
  result = LSPError(code: code, methodName: methodName, serverId: serverId)
  result.msg = message

proc newSyntaxError*(
    code: string,
    message: string,
    line: int = -1,
    column: int = -1,
    language: string = "",
): SyntaxError =
  result = SyntaxError(code: code, line: line, column: column, language: language)
  result.msg = message

proc newConfigError*(
    code: string, message: string, setting: string = "", value: string = ""
): ConfigError =
  result = ConfigError(code: code, setting: setting, value: value)
  result.msg = message

proc newGitError*(
    code: string, message: string, command: string = "", workingDir: string = ""
): GitError =
  result = GitError(code: code, command: command, workingDir: workingDir)
  result.msg = message

proc newRenderError*(
    code: string, message: string, component: string = ""
): RenderError =
  result = RenderError(code: code, component: component)
  result.msg = message

proc newInputError*(code: string, message: string, inputType: string = ""): InputError =
  result = InputError(code: code, inputType: inputType)
  result.msg = message

proc newValidationError*(
    code: string, message: string, field: string = "", constraint: string = ""
): ValidationError =
  result = ValidationError(code: code, field: field, constraint: constraint)
  result.msg = message



# Predefined error constructors for common cases
proc fileNotFound*(filepath: string): FileError =
  newFileError(ERROR_FILE_NOT_FOUND, fmt"File not found: {filepath}", filepath, "read")

proc fileAccessDenied*(filepath: string, operation: string): FileError =
  newFileError(
    ERROR_FILE_ACCESS_DENIED, fmt"Access denied: {filepath}", filepath, operation
  )

proc fileTooLarge*(filepath: string, size: int, maxSize: int): FileError =
  newFileError(
    ERROR_FILE_TOO_LARGE,
    fmt"File too large: {size} bytes (max: {maxSize})",
    filepath,
    "read",
  )

proc lspNotInitialized*(serverId: string): LSPError =
  newLSPError(
    ERROR_LSP_NOT_INITIALIZED, fmt"LSP server not initialized: {serverId}", "", serverId
  )

proc lspTimeout*(methodName: string, serverId: string): LSPError =
  newLSPError(
    ERROR_LSP_TIMEOUT, fmt"LSP request timeout: {methodName}", methodName, serverId
  )

proc configNotFound*(filepath: string): ConfigError =
  newConfigError(ERROR_CONFIG_NOT_FOUND, fmt"Configuration file not found: {filepath}")

proc configInvalidValue*(
    setting: string, value: string, expected: string
): ConfigError =
  newConfigError(
    ERROR_CONFIG_INVALID_VALUE,
    fmt"Invalid value for '{setting}': '{value}' (expected: {expected})",
    setting,
    value,
  )

proc gitNotRepository*(path: string): GitError =
  newGitError(ERROR_GIT_NOT_REPOSITORY, fmt"Not a git repository: {path}", "", path)



# Error formatting utilities
proc getUserMessage*(error: EditorError): string =
  ## Convert technical error to user-friendly message
  case error.code
  of ERROR_FILE_NOT_FOUND:
    "The file could not be found. It may have been moved or deleted."
  of ERROR_FILE_ACCESS_DENIED:
    "Permission denied. You don't have permission to access this file."
  of ERROR_FILE_TOO_LARGE:
    "The file is too large to open. Please try a smaller file."
  of ERROR_FILE_BINARY:
    "This appears to be a binary file that cannot be edited as text."
  of ERROR_LSP_CONNECTION_FAILED:
    "Language server connection failed. Some features may not be available."
  of ERROR_LSP_TIMEOUT:
    "Language server request timed out. Please try again."
  of ERROR_CONFIG_INVALID_FORMAT:
    "Configuration file format is invalid. Please check the syntax."
  of ERROR_GIT_NOT_REPOSITORY:
    "This folder is not a git repository. Git features are disabled."
  of ERROR_GIT_COMMAND_FAILED:
    "Git operation failed. Please check your git installation."

  else:
    error.msg

proc getDetailedMessage*(error: EditorError): string =
  ## Get detailed error message for debugging
  var parts: seq[string] = @[fmt"Error {error.code}: {error.msg}"]

  if error.context.len > 0:
    parts.add(fmt"Context: {error.context}")

  if error of FileError:
    let fe = FileError(error)
    if fe.filepath.len > 0:
      parts.add(fmt"File: {fe.filepath}")
    if fe.operation.len > 0:
      parts.add(fmt"Operation: {fe.operation}")
  elif error of LSPError:
    let le = LSPError(error)
    if le.serverId.len > 0:
      parts.add(fmt"Server: {le.serverId}")
    if le.methodName.len > 0:
      parts.add(fmt"Method: {le.methodName}")
  elif error of SyntaxError:
    let se = SyntaxError(error)
    if se.language.len > 0:
      parts.add(fmt"Language: {se.language}")
    if se.line >= 0:
      parts.add(fmt"Line: {se.line + 1}")
    if se.column >= 0:
      parts.add(fmt"Column: {se.column + 1}")
  elif error of ConfigError:
    let ce = ConfigError(error)
    if ce.setting.len > 0:
      parts.add(fmt"Setting: {ce.setting}")
    if ce.value.len > 0:
      parts.add(fmt"Value: {ce.value}")
  elif error of GitError:
    let ge = GitError(error)
    if ge.workingDir.len > 0:
      parts.add(fmt"Directory: {ge.workingDir}")
    if ge.command.len > 0:
      parts.add(fmt"Command: {ge.command}")


  parts.join("\n")

# Error recovery utilities
proc isRecoverable*(error: EditorError): bool =
  ## Check if an error is recoverable (user can retry)
  case error.code
  of ERROR_FILE_ACCESS_DENIED, ERROR_FILE_LOCKED, ERROR_LSP_TIMEOUT,
      ERROR_LSP_CONNECTION_FAILED, ERROR_GIT_COMMAND_FAILED:
    true
  of ERROR_FILE_NOT_FOUND, ERROR_FILE_TOO_LARGE, ERROR_FILE_BINARY,
      ERROR_CONFIG_INVALID_FORMAT, ERROR_GIT_NOT_REPOSITORY:
    false
  else:
    false

proc getSuggestedAction*(error: EditorError): string =
  ## Get suggested action for the user
  case error.code
  of ERROR_FILE_NOT_FOUND:
    "Check the file path and try again."
  of ERROR_FILE_ACCESS_DENIED:
    "Check file permissions or try running as administrator."
  of ERROR_FILE_TOO_LARGE:
    "Try opening a smaller file or increase the file size limit in settings."
  of ERROR_LSP_CONNECTION_FAILED:
    "Check if the language server is installed and try restarting the editor."
  of ERROR_LSP_TIMEOUT:
    "The language server may be busy. Try again in a moment."
  of ERROR_CONFIG_INVALID_FORMAT:
    "Check the configuration file syntax and fix any errors."
  of ERROR_GIT_NOT_REPOSITORY:
    "Initialize a git repository or open a folder that contains one."
  of ERROR_GIT_COMMAND_FAILED:
    "Check your git installation and repository status."
  else:
    "Please try again or contact support if the problem persists."

# Error logging utilities
proc shouldLog*(error: EditorError): bool =
  ## Check if error should be logged (not user-facing errors)
  case error.code
  of ERROR_FILE_NOT_FOUND, ERROR_FILE_ACCESS_DENIED:
    false # User errors, don't clutter logs
  else:
    true

proc getLogLevel*(error: EditorError): string =
  ## Get appropriate log level for error
  case error.code
  of ERROR_FILE_TOO_LARGE, ERROR_FILE_BINARY: "INFO"
  of ERROR_LSP_TIMEOUT, ERROR_CONFIG_INVALID_VALUE: "WARN"
  of ERROR_LSP_CONNECTION_FAILED, ERROR_RENDER_FONT_LOAD_FAILED: "ERROR"
  else: "ERROR"
