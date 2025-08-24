## Terminal Error Handling Module
## Centralized error management for terminal subsystem with comprehensive
## error codes, logging, recovery mechanisms, and debugging support

import std/[times, strformat, os, tables]

type
  TerminalErrorCode* = enum
    ## Error classification codes for terminal operations
    tecNone = "NONE",                    # No error
    tecProcessSpawn = "PROCESS_SPAWN",   # Failed to spawn shell process
    tecProcessIO = "PROCESS_IO",         # I/O error with shell process
    tecResourceCleanup = "CLEANUP",      # Error during resource cleanup
    tecIOEvent = "IO_EVENT",             # General I/O event error
    tecAnsiParse = "ANSI_PARSE",         # ANSI escape sequence parsing error
    tecBufferOverflow = "BUFFER_OVERFLOW", # Buffer size exceeded
    tecInvalidState = "INVALID_STATE",   # Invalid component state
    tecConfigError = "CONFIG_ERROR",     # Configuration validation error
    tecPermission = "PERMISSION",        # Permission/access error
    tecTimeout = "TIMEOUT",              # Operation timeout
    tecNetwork = "NETWORK",              # Network-related error
    tecFileSystem = "FILESYSTEM",        # File system operation error
    tecMemory = "MEMORY",                # Memory allocation error
    tecThreading = "THREADING",          # Threading/concurrency error
    tecValidation = "VALIDATION"         # Input validation error

  TerminalErrorSeverity* = enum
    ## Error severity levels
    tesInfo = "INFO",         # Informational
    tesWarning = "WARNING",   # Warning but operation can continue
    tesError = "ERROR",       # Error that prevents operation
    tesCritical = "CRITICAL", # Critical system error
    tesFatal = "FATAL"        # Fatal error requiring shutdown

  TerminalError* = ref object of CatchableError
    ## Terminal-specific exception with enhanced error information
    code*: TerminalErrorCode
    severity*: TerminalErrorSeverity
    context*: string           # Where the error occurred
    timestamp*: float          # When the error occurred
    details*: Table[string, string]  # Additional error details
    cause*: ref Exception      # Original exception if wrapping
    sessionId*: int           # Associated terminal session
    recoverable*: bool        # Whether error recovery is possible
    retryCount*: int         # Number of retry attempts made

  ErrorStatistics* = object
    ## Error tracking and statistics
    totalErrors*: int
    errorsByCode*: Table[TerminalErrorCode, int]
    errorsBySeverity*: Table[TerminalErrorSeverity, int]
    lastError*: float
    errorRate*: float         # Errors per minute
    recoverableErrors*: int
    fatalErrors*: int

var
  errorStats* = ErrorStatistics(
    totalErrors: 0,
    errorsByCode: initTable[TerminalErrorCode, int](),
    errorsBySeverity: initTable[TerminalErrorSeverity, int](),
    lastError: 0.0,
    errorRate: 0.0,
    recoverableErrors: 0,
    fatalErrors: 0
  )
  
  errorLogEnabled* = true
  errorLogFile* = ""
  maxLogSize* = 10 * 1024 * 1024  # 10MB
  enableStackTrace* = true

# Forward declarations
proc updateErrorStats(error: TerminalError)

# Error creation and management
proc newTerminalError*(
  code: TerminalErrorCode, 
  message: string, 
  context: string = "",
  severity: TerminalErrorSeverity = tesError,
  sessionId: int = -1,
  recoverable: bool = true,
  cause: ref Exception = nil
): TerminalError =
  ## Create a new terminal error with comprehensive information
  result = TerminalError(
    code: code,
    severity: severity,
    context: context,
    timestamp: times.getTime().toUnixFloat(),
    details: initTable[string, string](),
    cause: cause,
    sessionId: sessionId,
    recoverable: recoverable,
    retryCount: 0
  )
  
  result.msg = message
  
  # Add context information to details
  if context.len > 0:
    result.details["context"] = context
  
  result.details["error_code"] = $code
  result.details["severity"] = $severity
  result.details["timestamp"] = $result.timestamp
  result.details["recoverable"] = $recoverable
  
  if sessionId >= 0:
    result.details["session_id"] = $sessionId
  
  # Add stack trace if enabled
  if enableStackTrace:
    try:
      result.details["stack_trace"] = getStackTrace()
    except:
      result.details["stack_trace"] = "Stack trace unavailable"
  
  # Update statistics
  updateErrorStats(result)

proc addDetail*(error: TerminalError, key: string, value: string) =
  ## Add additional detail to an error
  error.details[key] = value

proc incrementRetry*(error: TerminalError) =
  ## Increment retry count for an error
  inc error.retryCount
  error.details["retry_count"] = $error.retryCount

proc markUnrecoverable*(error: TerminalError) =
  ## Mark an error as unrecoverable
  error.recoverable = false
  error.severity = tesCritical
  error.details["recoverable"] = "false"

# Error statistics and tracking
proc updateErrorStats(error: TerminalError) =
  ## Update global error statistics
  inc errorStats.totalErrors
  errorStats.lastError = error.timestamp
  
  # Update by code
  if error.code in errorStats.errorsByCode:
    inc errorStats.errorsByCode[error.code]
  else:
    errorStats.errorsByCode[error.code] = 1
  
  # Update by severity
  if error.severity in errorStats.errorsBySeverity:
    inc errorStats.errorsBySeverity[error.severity]
  else:
    errorStats.errorsBySeverity[error.severity] = 1
  
  # Update counters
  if error.recoverable:
    inc errorStats.recoverableErrors
  
  if error.severity in [tesCritical, tesFatal]:
    inc errorStats.fatalErrors
  
  # Calculate error rate (errors per minute)
  let currentTime = times.getTime().toUnixFloat()
  let timeDiff = currentTime - errorStats.lastError
  if timeDiff > 0:
    errorStats.errorRate = float(errorStats.totalErrors) / (timeDiff / 60.0)

proc getErrorStats*(): ErrorStatistics =
  ## Get current error statistics
  errorStats

proc resetErrorStats*() =
  ## Reset error statistics
  errorStats = ErrorStatistics(
    totalErrors: 0,
    errorsByCode: initTable[TerminalErrorCode, int](),
    errorsBySeverity: initTable[TerminalErrorSeverity, int](),
    lastError: 0.0,
    errorRate: 0.0,
    recoverableErrors: 0,
    fatalErrors: 0
  )

# Error logging
proc formatErrorMessage(error: TerminalError): string =
  ## Format error for logging
  let timeStr = times.fromUnixFloat(error.timestamp).format("yyyy-MM-dd HH:mm:ss")
  
  result = &"[{timeStr}] {error.severity}: {error.code} - {error.msg}"
  
  if error.context.len > 0:
    result.add(&" (Context: {error.context})")
  
  if error.sessionId >= 0:
    result.add(&" (Session: {error.sessionId})")
  
  if error.retryCount > 0:
    result.add(&" (Retry: {error.retryCount})")
  
  # Add details
  if error.details.len > 0:
    result.add("\n  Details:")
    for key, value in error.details.pairs:
      if key notin ["context", "session_id", "retry_count"]:  # Skip already shown
        result.add(&"\n    {key}: {value}")
  
  # Add cause if present
  if error.cause != nil:
    result.add(&"\n  Caused by: {error.cause.msg}")

proc logTerminalError*(error: TerminalError) =
  ## Log terminal error to console and file
  if not errorLogEnabled:
    return
  
  let message = formatErrorMessage(error)
  
  # Always log to console
  case error.severity:
  of tesInfo:
    echo "[INFO] ", message
  of tesWarning:
    echo "[WARNING] ", message
  of tesError:
    echo "[ERROR] ", message
  of tesCritical:
    echo "[CRITICAL] ", message
  of tesFatal:
    echo "[FATAL] ", message
  
  # Log to file if specified
  if errorLogFile.len > 0:
    try:
      let logDir = parentDir(errorLogFile)
      if not dirExists(logDir):
        createDir(logDir)
      
      # Check log file size and rotate if needed
      if fileExists(errorLogFile):
        let fileSize = getFileSize(errorLogFile)
        if fileSize > maxLogSize:
          let backupFile = errorLogFile & ".old"
          if fileExists(backupFile):
            removeFile(backupFile)
          moveFile(errorLogFile, backupFile)
      
      let file = open(errorLogFile, fmAppend)
      defer: file.close()
      
      file.writeLine(message)
      file.flushFile()
      
    except Exception as e:
      echo "[ERROR] Failed to write to error log: ", e.msg

proc logErrorWithContext*(
  code: TerminalErrorCode,
  message: string,
  context: string = "",
  severity: TerminalErrorSeverity = tesError,
  sessionId: int = -1
) =
  ## Convenience function to create and log an error
  let error = newTerminalError(code, message, context, severity, sessionId)
  logTerminalError(error)

# Error recovery and handling
proc isRecoverable*(error: TerminalError): bool =
  ## Check if an error is recoverable
  result = error.recoverable and error.retryCount < 3 and error.severity notin [tesCritical, tesFatal]

proc shouldRetry*(error: TerminalError): bool =
  ## Check if an operation should be retried for this error
  case error.code:
  of tecProcessIO, tecTimeout, tecNetwork:
    return error.retryCount < 3
  of tecMemory, tecResourceCleanup:
    return error.retryCount < 1
  of tecProcessSpawn:
    return error.retryCount < 2
  else:
    return false

proc getRecoveryAction*(error: TerminalError): string =
  ## Get suggested recovery action for an error
  case error.code:
  of tecProcessSpawn:
    return "Check shell path and permissions, try alternative shell"
  of tecProcessIO:
    return "Restart shell process, check process health"
  of tecResourceCleanup:
    return "Force cleanup, restart component"
  of tecIOEvent:
    return "Reset I/O handlers, reinitialize connection"
  of tecAnsiParse:
    return "Skip malformed sequence, continue processing"
  of tecBufferOverflow:
    return "Clear buffer, increase limits"
  of tecInvalidState:
    return "Reset component state, reinitialize"
  of tecConfigError:
    return "Validate configuration, use defaults"
  of tecPermission:
    return "Check file/directory permissions"
  of tecTimeout:
    return "Increase timeout, check system load"
  of tecNetwork:
    return "Check network connectivity, retry connection"
  of tecFileSystem:
    return "Check disk space, file permissions"
  of tecMemory:
    return "Free memory, restart if critical"
  of tecThreading:
    return "Synchronize threads, restart thread pool"
  of tecValidation:
    return "Validate input, use safe defaults"
  else:
    return "Check logs, restart component if needed"

# Error prevention and validation
proc validateErrorCode*(code: TerminalErrorCode): bool =
  ## Validate if error code is valid
  code != tecNone

proc validateSeverity*(severity: TerminalErrorSeverity): bool =
  ## Validate if severity level is valid
  severity in [tesInfo, tesWarning, tesError, tesCritical, tesFatal]

# Configuration
proc configureErrorLogging*(
  enabled: bool = true,
  logFile: string = "",
  maxSize: int = 10 * 1024 * 1024,
  stackTrace: bool = true
) =
  ## Configure error logging settings
  errorLogEnabled = enabled
  errorLogFile = logFile
  maxLogSize = maxSize
  enableStackTrace = stackTrace

proc getErrorLogPath*(): string =
  ## Get current error log file path
  errorLogFile

# Error querying and analysis
proc getErrorsByCode*(code: TerminalErrorCode): int =
  ## Get error count for specific error code
  if code in errorStats.errorsByCode:
    errorStats.errorsByCode[code]
  else:
    0

proc getErrorsBySeverity*(severity: TerminalErrorSeverity): int =
  ## Get error count for specific severity level
  if severity in errorStats.errorsBySeverity:
    errorStats.errorsBySeverity[severity]
  else:
    0

proc getMostCommonError*(): tuple[code: TerminalErrorCode, count: int] =
  ## Get the most frequently occurring error
  result = (tecNone, 0)
  for code, count in errorStats.errorsByCode.pairs:
    if count > result.count:
      result = (code, count)

proc getErrorRate*(): float =
  ## Get current error rate (errors per minute)
  errorStats.errorRate

proc hasRecentErrors*(withinSeconds: float = 60.0): bool =
  ## Check if there have been errors within the specified time window
  let currentTime = times.getTime().toUnixFloat()
  return (currentTime - errorStats.lastError) <= withinSeconds

# System health checking
proc getSystemHealth*(): tuple[status: string, errorCount: int, criticalCount: int] =
  ## Get overall system health based on error statistics
  let criticalCount = getErrorsBySeverity(tesCritical) + getErrorsBySeverity(tesFatal)
  let totalCount = errorStats.totalErrors
  
  let status = if criticalCount > 0:
                 "CRITICAL"
               elif totalCount > 10 and errorStats.errorRate > 1.0:
                 "DEGRADED"
               elif totalCount > 0:
                 "WARNING"
               else:
                 "HEALTHY"
  
  return (status, totalCount, criticalCount)

# Cleanup and maintenance
proc cleanupErrorSystem*() =
  ## Clean up error system resources
  resetErrorStats()
  
  # Clean up old log files
  if errorLogFile.len > 0:
    try:
      let backupFile = errorLogFile & ".old"
      if fileExists(backupFile):
        let fileAge = getLastModificationTime(backupFile)
        let currentTime = times.getTime()
        if (currentTime - fileAge).inDays > 7:  # Remove logs older than 7 days
          removeFile(backupFile)
    except:
      discard  # Ignore cleanup errors

# Initialize error logging with sensible defaults
proc initErrorSystem*(logPath: string = "", enableLogging: bool = true) =
  ## Initialize the error system with configuration
  let actualLogPath = if logPath.len > 0:
                        logPath
                      else:
                        joinPath(getTempDir(), "folx_terminal_errors.log")
  
  configureErrorLogging(enableLogging, actualLogPath, maxLogSize, enableStackTrace)
  resetErrorStats()
  
  # Log system initialization
  if enableLogging:
    logErrorWithContext(tecNone, "Terminal error system initialized", 
                       "error_system.init", tesInfo)

# Export commonly used error creation functions
template errorProcessSpawn*(msg: string, ctx: string = ""): TerminalError =
  newTerminalError(tecProcessSpawn, msg, ctx, tesError)

template errorProcessIO*(msg: string, ctx: string = ""): TerminalError =
  newTerminalError(tecProcessIO, msg, ctx, tesWarning)

template errorResourceCleanup*(msg: string, ctx: string = ""): TerminalError =
  newTerminalError(tecResourceCleanup, msg, ctx, tesWarning)

template errorAnsiParse*(msg: string, ctx: string = ""): TerminalError =
  newTerminalError(tecAnsiParse, msg, ctx, tesWarning, recoverable = true)

template errorIOEvent*(msg: string, ctx: string = ""): TerminalError =
  newTerminalError(tecIOEvent, msg, ctx, tesError)