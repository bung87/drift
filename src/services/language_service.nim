import std/[options, tables, os, strutils, sequtils]
import chronos
import raylib as rl
import ../shared/errors
import ../domain
import ../lsp_thread_wrapper
from ../infrastructure/external/lsp_client_async import Location
import ../enhanced_syntax
import notification_service
import diagnostic_service
import ../shared/types
import ../shared/constants
import json

# Hover response validation to prevent race conditions
proc validateHoverResponse*(content: string, expectedSymbol: string, expectedPosition: CursorPos): bool =
  ## Validate that the LSP hover response matches the expected symbol and position
  ## This prevents race conditions where old responses show up for new symbols
  
  if content.len == 0:
    return false  # Empty responses are never valid
  
  if expectedSymbol.len == 0:
    return false  # No expected symbol means we shouldn't have gotten a response
  
  # Smart symbol matching - handle common cases where symbols don't match exactly
  let contentLower = content.toLowerAscii()
  let expectedLower = expectedSymbol.toLowerAscii()
  
  # Extract the core symbol name from compound symbols like "rl.setConfigFlags"
  let symbolParts = expectedSymbol.split('.')
  let coreSymbol = if symbolParts.len > 0: symbolParts[^1] else: expectedSymbol  # Get last part
  
  # Check multiple matching strategies
  let directMatch = expectedLower in contentLower
  let coreMatch = coreSymbol.toLowerAscii() in contentLower
  let prefixMatch = contentLower.contains(expectedLower.replace("rl.", "raylib."))  # Handle rl -> raylib
  let suffixMatch = contentLower.contains("." & coreSymbol.toLowerAscii())  # Handle qualified names
  
  let symbolMatches = directMatch or coreMatch or prefixMatch or suffixMatch
  
  if not symbolMatches:
    # Debug: Symbol matching failed
    echo "  - Direct match (", expectedLower, "): ", directMatch
    echo "  - Core match (", coreSymbol.toLowerAscii(), "): ", coreMatch  
    echo "  - Prefix match: ", prefixMatch
    echo "  - Suffix match: ", suffixMatch
    echo "  - Content: ", content[0..min(100, content.len-1)]
    return false
  
  # Additional validation: check for reasonable content
  let hasValidContent = content.len > 5 and (
    content.contains("proc") or      # Nim procedures
    content.contains("func") or      # Nim functions  
    content.contains("var") or       # Variables
    content.contains("let") or       # Constants
    content.contains("type") or      # Types
    content.contains("```") or       # Code blocks
    content.contains(":") or         # Type annotations
    content.contains("=")            # Assignments/definitions
  )
  
  if not hasValidContent:
    # Debug: Content doesn't look like valid hover info
    return false
  
  # Debug: Response validated for symbol
  return true

export HoverInfo

# Hover timing constants
# HOVER_REQUEST_DEBOUNCE_MS moved to shared/constants.nim

# Language service types
type
  DocumentState = object
    uri: string
    language: string
    version: int
    content: string

  HoverState = object
    content: string
    lastRequestTime: float
    pendingRequest: bool
    requestId: int  # Track request order to avoid race conditions
    currentRequest: tuple[symbol: string, position: CursorPos]  # Consolidated request tracking

  DefinitionState = object
    locations: seq[Location]
    lastRequestTime: float
    lastRequestSymbol: string
    pendingRequest: bool
    requestId: int

  LanguageService* = ref object
    # LSP clients by language
    lspClients: Table[string, LSPWrapper]

    # Document tracking
    openDocuments: Table[string, DocumentState]

    # Hover state
    hoverState: HoverState
    
    # Definition state
    definitionState: DefinitionState

    # Health monitoring
    clientHealth: Table[string, float] # Last successful operation time
    clientErrors: Table[string, int] # Error count per client
    clientLastReset: Table[string, float] # Last reset time per client
    lastHealthCheck: float # Last health check time
    maxErrorsBeforeReset: int # Max errors before client reset

    # Thread recovery tracking
    lastResponseTime: Table[string, float] # Last time we got a response from each client
    stuckThreadDetectionTime: float # How long to wait before considering thread stuck

    # Settings
    enableHover*: bool
    enableDiagnostics*: bool
    hoverTimeout*: float # seconds

    # Supported languages
    supportedLanguages*: seq[string]

    # Notification service for LSP events
    notificationService*: NotificationService

    # Diagnostic service for LSP diagnostics
    diagnosticService*: DiagnosticService

# Add after the HoverState and LanguageService type definitions
# Remove getLastHoverSymbol
# Remove from newLanguageService
proc newLanguageService*(): LanguageService =
  var service = LanguageService()
  service.hoverState = HoverState(
    content: "",
    lastRequestTime: 0.0,
    pendingRequest: false,
    requestId: 0,
    currentRequest: (symbol: "", position: CursorPos(line: -1, col: -1))
  )
  service.definitionState = DefinitionState(
    locations: @[],
    lastRequestTime: 0.0,
    lastRequestSymbol: "",
    pendingRequest: false,
    requestId: 0
  )
  service.lastHealthCheck = 0.0
  service.maxErrorsBeforeReset = 3
  service.enableHover = true
  service.enableDiagnostics = true
  service.hoverTimeout = 3.0
  service.stuckThreadDetectionTime = 5.0  # 5 seconds to detect stuck thread
  service.supportedLanguages = @["nim", "python", "javascript", "typescript", "rust", "go"]
  service.notificationService = nil
  service.diagnosticService = nil
  return service

proc setNotificationService*(service: LanguageService, notificationService: NotificationService) =
  ## Set the notification service for LSP event notifications
  service.notificationService = notificationService

proc setDiagnosticService*(service: LanguageService, diagnosticService: DiagnosticService) =
  ## Set the diagnostic service for LSP diagnostic handling
  service.diagnosticService = diagnosticService

proc handleLSPNotification*(service: LanguageService, language: string, message: string, notificationType: notification_service.NotificationType = notification_service.ntInfo) =
  ## Handle LSP notification and show it to the user
  if service.notificationService != nil:
    let fullMessage = "LSP (" & language & "): " & message
    discard service.notificationService.addNotification(fullMessage, notificationType, 6.0)

proc handleLSPMessage*(service: LanguageService, language: string, methodName: string, params: JsonNode) =
  ## Handle LSP server messages and show them as notifications
  # Debug: Received LSP message

  if service.notificationService == nil:
    # Debug: Notification service is nil
    return

  case methodName
  of "window/showMessage":
    if params.hasKey("message"):
      let message = params["message"].getStr()
      let messageType = if params.hasKey("type"): params["type"].getInt() else: 1

      # Debug: Processing window/showMessage

      # Convert LSP message type to notification type
      let notificationType = case messageType
        of 1: notification_service.ntError    # Error
        of 2: notification_service.ntWarning  # Warning
        of 3: notification_service.ntInfo     # Info
        of 4: notification_service.ntSuccess  # Log
        else: notification_service.ntInfo

      service.handleLSPNotification(language, message, notificationType)
      # Debug: Added notification for window/showMessage

  of "window/logMessage":
    if params.hasKey("message"):
      let message = params["message"].getStr()
      # Debug: Processing window/logMessage
      service.handleLSPNotification(language, "Log: " & message, notification_service.ntInfo)
      # Debug: Added notification for window/logMessage

  of "textDocument/publishDiagnostics":
    # Debug: Processing textDocument/publishDiagnostics

    # Handle diagnostics through diagnostic service if available
    if service.diagnosticService != nil:
      # Reconstruct the full notification JSON for the diagnostic service
      let fullNotification = %*{
        "method": "textDocument/publishDiagnostics",
        "params": params
      }
      let success = service.diagnosticService.handlePublishDiagnostics($fullNotification)


    # Still provide legacy notification support
    if params.hasKey("diagnostics"):
      let diagnostics = params["diagnostics"]
      if diagnostics.kind == JArray and diagnostics.len > 0:
        let errorCount = diagnostics.filterIt(it.hasKey("severity") and it["severity"].getInt() == 1).len
        let warningCount = diagnostics.filterIt(it.hasKey("severity") and it["severity"].getInt() == 2).len

        # Debug: Legacy diagnostic handling

        if errorCount > 0 or warningCount > 0:
          let message = "Found " & $errorCount & " errors, " & $warningCount & " warnings"
          let notificationType = if errorCount > 0: notification_service.ntError else: notification_service.ntWarning
          service.handleLSPNotification(language, message, notificationType)
          # Debug: Added notification for diagnostics


proc handleLSPMessage*(service: LanguageService, language: string, jsonString: string) =
  ## Handle LSP message from JSON string (overload for notification processing)
  try:
    let messageJson = parseJson(jsonString)
    if messageJson.hasKey("method"):
      let methodName = messageJson["method"].getStr()
      let params = if messageJson.hasKey("params"): messageJson["params"] else: newJNull()
      echo "DEBUG LanguageService.handleLSPMessage: Parsing JSON notification - method: '", methodName, "'"
      service.handleLSPMessage(language, methodName, params)
    else:
      echo "DEBUG LanguageService.handleLSPMessage: JSON message has no method field"
  except Exception as e:
    echo "DEBUG LanguageService.handleLSPMessage: Error parsing JSON notification: ", e.msg

# Forward declarations for recovery procedures
proc checkAndRecoverStuckThread(service: LanguageService, language: string, wrapper: LSPWrapper, currentTime: float)
proc recoverStuckThread(service: LanguageService, language: string)

# LSP client management
proc ensureLSPClient(service: LanguageService, language: string): LSPWrapper =
  ## Get or create LSP client for language
  echo "DEBUG LanguageService.ensureLSPClient: Called for language: '", language, "'"
  if language in service.lspClients:
    echo "DEBUG LanguageService.ensureLSPClient: Client already exists for language: ", language
    let wrapper = service.lspClients[language]
    echo "DEBUG LanguageService.ensureLSPClient: Client status: ", wrapper.getLastStatusResponse()
    return wrapper

  echo "DEBUG LanguageService.ensureLSPClient: Creating new LSP client for language: ", language
  echo "DEBUG LanguageService.ensureLSPClient: Supported languages: ", service.supportedLanguages.join(", ")

  if language notin service.supportedLanguages:
    echo "DEBUG LanguageService.ensureLSPClient: Language '", language, "' is not supported, skipping client creation"
    # Create a dummy wrapper that will fail health checks
    let wrapper = newLSPWrapper()
    service.lspClients[language] = wrapper
    return wrapper

  let wrapper = newLSPWrapper()

  # Initialize client asynchronously using thread wrapper
  echo "DEBUG LanguageService.ensureLSPClient: Starting client initialization for ", language
  wrapper.initializeLSP(language)

  # Note: We can't check success immediately since it's async
  # The success/failure will be handled in the polling loop
  echo "DEBUG LanguageService.ensureLSPClient: Initialization request sent for ", language

  service.lspClients[language] = wrapper
  service.clientHealth[language] = rl.getTime()
  service.clientErrors[language] = 0
  echo "DEBUG LanguageService.ensureLSPClient: Client stored in service for language: ", language
  return wrapper

# Document management
proc openDocument*(
    service: LanguageService, filePath: string, content: string
): Result[void, errors.EditorError] =
  ## Open a document with the language service
  try:
    let detectedLang = enhanced_syntax.detectLanguage(filePath)
    let language = $detectedLang
    let uri = "file://" & filePath.absolutePath()

    echo "DEBUG LanguageService: Opening document: ", uri, " as language: ", language

    # Store document state
    service.openDocuments[uri] =
      DocumentState(uri: uri, language: language, version: 1, content: content)

    # Send to LSP client
    if language in service.supportedLanguages:
      let wrapper = service.ensureLSPClient(language)

      # Send didOpen notification asynchronously
      wrapper.notifyDocumentOpen(uri, content, language)

    return ok()
  except Exception as e:
    return err(
      errors.EditorError(
        msg: "Failed to open document: " & e.msg, code: "DOC_OPEN_FAILED"
      )
    )

proc updateDocument*(
    service: LanguageService, filePath: string, content: string
): Result[void, errors.EditorError] =
  ## Update document content
  try:
    let uri = "file://" & filePath.absolutePath()

    if uri notin service.openDocuments:
      # Try to open it first
      return service.openDocument(filePath, content)

    var docState = service.openDocuments[uri]
    docState.version += 1
    docState.content = content
    service.openDocuments[uri] = docState

    # Send to LSP client
    if docState.language in service.supportedLanguages and
        docState.language in service.lspClients:
      discard # let wrapper = service.lspClients[docState.language]
      # Document change not implemented in thread wrapper yet
      # TODO: Add document change support

    return ok()
  except Exception as e:
    return err(
      errors.EditorError(
        msg: "Failed to update document: " & e.msg, code: "DOC_UPDATE_FAILED"
      )
    )

proc closeDocument*(service: LanguageService, filePath: string) =
  ## Close a document
  let uri = "file://" & filePath.absolutePath()

  if uri in service.openDocuments:
    let docState = service.openDocuments[uri]

    # Send to LSP client
    if docState.language in service.lspClients:
      let wrapper = service.lspClients[docState.language]
      wrapper.notifyDocumentClose(uri)

    service.openDocuments.del(uri)

# Clear hover state (moved before reset function)
proc clearHover*(service: LanguageService) =
  ## Clear current hover state completely
  service.hoverState.content = ""
  service.hoverState.pendingRequest = false
  service.hoverState.requestId = 0
  service.hoverState.currentRequest = (symbol: "", position: CursorPos(line: -1, col: -1))

# LSP Client Reset (moved before health monitoring to fix declaration order)
proc resetLSPClientImpl(service: LanguageService, language: string) =
  ## Internal reset function for LSP client with aggressive cleanup
  echo "DEBUG LanguageService: Resetting LSP client for language: ", language

  # Show notification about reset
  if service.notificationService != nil:
    discard service.notificationService.addNotification(
      "LSP client reset for " & language & " language server",
      ntWarning,
      6.0
    )

  # First clear all state to prevent stale data
  service.clearHover()

  if language in service.lspClients:
    let wrapper = service.lspClients[language]

    try:
      wrapper.shutdownLSP()
    except:
      echo "DEBUG LanguageService: Error shutting down LSP client: ", language

    service.lspClients.del(language)

  # Reset health tracking completely
  service.clientHealth.del(language)
  service.clientErrors.del(language)

  # Record reset time to prevent excessive resets
  service.clientLastReset[language] = rl.getTime().float

  # Force clear any remaining state
  service.hoverState.content = ""
  service.hoverState.pendingRequest = false
  service.hoverState.requestId = 0
  service.hoverState.currentRequest = (symbol: "", position: CursorPos(line: -1, col: -1))

# Health monitoring
proc checkClientHealth*(service: LanguageService, language: string): bool =
  ## Check if LSP client is healthy
  if language notin service.lspClients:
    return false

  let wrapper = service.lspClients[language]
  let status = wrapper.getLastStatusResponse()
  let currentTime = rl.getTime()

  if status == "Ready":
    service.clientHealth[language] = currentTime
    service.clientErrors[language] = 0
    return true
  elif status.contains("Error") and not status.contains("Timeout"):
    # Only count non-timeout errors as critical
    service.clientErrors[language] = service.clientErrors.getOrDefault(language, 0) + 1
    return false
  elif status.contains("Timeout"):
    # Timeouts (especially hover timeouts) are not critical - don't increment error count
    echo "DEBUG LanguageService: LSP timeout detected but not counting as critical error"
    return false

  return true

proc pollLSPResponses*(service: LanguageService) =
  ## Poll for available LSP responses from all clients
  ## This should be called regularly from the main thread
  let currentTime = rl.getTime()
  var totalPolled = 0
  var responsesReceived = 0

  # Create a copy of keys to avoid iterator invalidation during recovery
  let languages = toSeq(service.lspClients.keys)

  for language in languages:
    # Check if client was deleted during recovery
    if language notin service.lspClients:
      echo "DEBUG LanguageService: Skipping polling for removed client: ", language
      continue

    let wrapper = service.lspClients[language]

    # Additional safety check: ensure wrapper and thread data are valid
    if wrapper.isNil or wrapper.threadData.isNil:
      echo "DEBUG LanguageService: Skipping nil wrapper or threadData for language: ", language
      service.clientErrors[language] = service.clientErrors.getOrDefault(language, 0) + 1
      continue

    try:
      pollLSPResponses(wrapper)

      # Handle centralized response data
      if wrapper.isInitialized and service.notificationService != nil:
        # Check if this is a newly initialized client
        if language notin service.clientHealth:
          echo "DEBUG LanguageService: LSP client initialized successfully for ", language
          discard service.notificationService.addNotification(
            "LSP client initialized for " & language & " language",
            ntSuccess,
            4.0
          )

      # Handle hover responses with enhanced state management and request cancellation
      let hoverResponse = wrapper.getLastHoverResponse()
      if hoverResponse.isSome:
        let content = hoverResponse.get()
        echo "DEBUG LanguageService pollLSPResponses: Received hover response with ", content.len, " chars"

        # Enhanced validation: only update if we were expecting a response AND request hasn't been cancelled
        if service.hoverState.pendingRequest:
          let expectedPosition = service.hoverState.currentRequest.position
          
          # Simplified validation - just check if we have content and it's not empty
          let responseIsValid = content.len > 0
          
          if responseIsValid:
            echo "DEBUG LanguageService pollLSPResponses: Valid response at position (", expectedPosition.line, ",", expectedPosition.col, "): ", content[0..min(100, content.len-1)]
            service.hoverState.content = content
            service.hoverState.pendingRequest = false
            echo "DEBUG LanguageService pollLSPResponses: Updated hover state - content length=", content.len, " pendingRequest=false"
          else:
            echo "DEBUG LanguageService pollLSPResponses: LSP response is empty or invalid - ignoring"
            service.hoverState.pendingRequest = false
        else:
          echo "DEBUG LanguageService pollLSPResponses: Received hover response but no pending request - ignoring"

        # Always clear the response to avoid processing it again
        wrapper.clearHoverResponse()
      else:
        # Enhanced cleanup for stuck requests with better timeout handling
        if service.hoverState.pendingRequest:
          let timeSinceRequest = currentTime - service.hoverState.lastRequestTime
          if timeSinceRequest > 5.0:  # 5 second timeout
            echo "DEBUG LanguageService pollLSPResponses: Hover request timed out - clearing pending state"
            service.hoverState.pendingRequest = false
          else:
            discard
            # echo "DEBUG LanguageService pollLSPResponses: Waiting for hover response (", timeSinceRequest.int, "s elapsed)"

      # Handle definition responses
      let definitionResponse = wrapper.getLastDefinitionResponse()
      if definitionResponse.len > 0:
        echo "DEBUG LanguageService pollLSPResponses: Received definition response with ", definitionResponse.len, " locations"
        if service.definitionState.pendingRequest:
          service.definitionState.locations = definitionResponse
          service.definitionState.pendingRequest = false
          echo "DEBUG LanguageService pollLSPResponses: Updated definition state with ", definitionResponse.len, " locations"
        else:
          echo "DEBUG LanguageService pollLSPResponses: Received unexpected definition response - ignoring"
        
        # Clear the response to avoid processing it again
        wrapper.clearDefinitionResponse()
      else:
        # Timeout handling for definition requests
        if service.definitionState.pendingRequest:
          let timeSinceRequest = currentTime - service.definitionState.lastRequestTime
          if timeSinceRequest > 5.0:  # 5 second timeout
            echo "DEBUG LanguageService pollLSPResponses: Definition request timed out - clearing pending state"
            service.definitionState.pendingRequest = false

      # Handle LSP notifications (window/showMessage, window/logMessage, diagnostics)
      if wrapper.hasNotifications():
        let notifications = wrapper.getNotifications()
        echo "DEBUG LanguageService pollLSPResponses: Processing ", notifications.len, " LSP notifications"
        for notification in notifications:
          try:
            service.handleLSPMessage(language, notification)
          except Exception as e:
            echo "DEBUG LanguageService pollLSPResponses: Error processing notification: ", e.msg

      # Handle errors
      let lastError = wrapper.getLastError()
      if lastError.len > 0 and service.notificationService != nil:
        discard service.notificationService.addNotification(
          "LSP error for " & language & ": " & lastError,
          ntError,
          8.0
        )

      # Check for stuck thread recovery
      service.checkAndRecoverStuckThread(language, wrapper, currentTime)
      # If the client was deleted during recovery, skip further processing
      if language notin service.lspClients:
        echo "DEBUG LanguageService: Client was deleted during recovery for: ", language
        continue
      totalPolled += 1
    except Exception as e:
      echo "DEBUG LanguageService: Error polling LSP client for ", language, ": ", e.msg
      # Mark client as unhealthy
      service.clientErrors[language] = service.clientErrors.getOrDefault(language, 0) + 1
      # If client was deleted during error handling, skip further processing
      if language notin service.lspClients:
        echo "DEBUG LanguageService: Client was deleted during error handling for: ", language
        continue
      totalPolled += 1

  # Debug output only when there's something interesting happening
  let shouldDebug = service.hoverState.pendingRequest or
                   service.hoverState.content.len > 0 or
                   (service.lastHealthCheck == 0.0 or (currentTime - service.lastHealthCheck) > 10.0)

  if shouldDebug:
    if service.hoverState.pendingRequest:
      echo "DEBUG LanguageService: Waiting for hover response"
    elif service.hoverState.content.len > 0:
      echo "DEBUG LanguageService: Have hover content (", service.hoverState.content.len, " chars)"
    else:
      echo "DEBUG LanguageService: Polled ", totalPolled, " LSP clients - no active hover requests"

    if responsesReceived > 0:
      echo "DEBUG LanguageService: Received ", responsesReceived, " responses this poll cycle"
    service.lastHealthCheck = currentTime

proc performHealthCheck*(service: LanguageService) =
  ## Perform health check on all LSP clients and poll for responses
  let currentTime = rl.getTime()

  # Poll for responses first
  service.pollLSPResponses()

  for language, wrapper in service.lspClients.pairs:
    let lastHealth = service.clientHealth.getOrDefault(language, 0.0)
    let timeSinceLastHealth = currentTime - lastHealth

    # If client hasn't been healthy for more than 30 seconds, check status
    if timeSinceLastHealth > 30.0:
      let status = getLSPStatus(wrapper)
      if status == "Ready":
        service.clientHealth[language] = currentTime
        service.clientErrors[language] = 0
        echo "DEBUG LanguageService: Client ", language, " is healthy (status: ", status, ")"
      elif status.contains("Error"):
        service.clientErrors[language] = service.clientErrors.getOrDefault(language, 0) + 1
        echo "DEBUG LanguageService: Client ", language, " has error (status: ", status, ")"
      else:
        echo "DEBUG LanguageService: Client ", language, " status: ", status

# Simple hover request function - language service should only handle LSP communication
proc requestHover*(
    service: LanguageService,
    filePath: string,
    line: int,
    character: int
): bool =
  ## Simple LSP hover request - no UI logic, just LSP communication
  echo "DEBUG LanguageService.requestHover: Called with filePath='", filePath, "', line=", line, ", character=", character
  
  if not service.enableHover:
    echo "DEBUG LanguageService.requestHover: Hover is disabled"
    return false

  # Basic validation
  if filePath.len == 0 or line < 0 or character < 0:
    echo "DEBUG LanguageService.requestHover: Basic validation failed - filePath.len=", filePath.len, " line=", line, " character=", character
    return false

  # Detect language
  var language: string
  try:
    let detectedLang = enhanced_syntax.detectLanguage(filePath)
    language = $detectedLang
    echo "DEBUG LanguageService.requestHover: Detected language: ", language
  except Exception as e:
    echo "DEBUG LanguageService.requestHover: Language detection failed: ", e.msg
    return false

  # Check if we have an LSP client for this language
  if language notin service.lspClients:
    echo "DEBUG LanguageService.requestHover: No LSP client for language: ", language
    return false

  # Check client health
  let healthStatus = service.checkClientHealth(language)
  echo "DEBUG LanguageService.requestHover: Client health check result: ", healthStatus
  if not healthStatus:
    return false

  # Make LSP request
  try:
    let lspWrapper = service.lspClients[language]
    if lspWrapper.isNil:
      echo "DEBUG LanguageService.requestHover: LSP wrapper is nil for language: ", language
      return false
    
    echo "DEBUG LanguageService.requestHover: Client status: ", lspWrapper.getLastStatusResponse()
    echo "DEBUG LanguageService.requestHover: Client initialized: ", lspWrapper.isInitialized
    
    let uri = "file://" & filePath.absolutePath()
    echo "DEBUG LanguageService.requestHover: Sending LSP hover request for URI: ", uri, " at line: ", line, ", character: ", character
    lspWrapper.requestHover(uri, line, character)
    
    # Update state for tracking
    service.hoverState.pendingRequest = true
    service.hoverState.lastRequestTime = rl.getTime()
    inc service.hoverState.requestId
    # Track current request for validation - use a placeholder symbol since we don't have the actual symbol here
    service.hoverState.currentRequest = (symbol: "hover_request", position: CursorPos(line: line, col: character))
    
    echo "DEBUG LanguageService.requestHover: Sent hover request for position (", line, ",", character, ")"
    return true

  except Exception as e:
    echo "DEBUG LanguageService.requestHover: LSP request failed: ", e.msg
    service.hoverState.pendingRequest = false
    return false

proc checkAndRecoverStuckThread(service: LanguageService, language: string, wrapper: LSPWrapper, currentTime: float) =
  ## Simple check for stuck thread - no complex timing logic
  # Just check if we have a responsive client, recovery is handled elsewhere
  discard

proc recoverStuckThread(service: LanguageService, language: string) =
  ## Recover a stuck LSP thread by restarting the client
  echo "DEBUG LanguageService: Recovering stuck LSP thread for language: ", language

  # Show notification about recovery
  if service.notificationService != nil:
    discard service.notificationService.addNotification(
      "LSP thread recovered for " & language & " language server",
      ntWarning,
      8.0
    )

  # Clear hover state to prevent stale data
  service.clearHover()

  # Reset the client completely
  service.resetLSPClientImpl(language)

  # Force recreation on next request
  if language in service.lspClients:
    service.lspClients.del(language)

  # Clear response tracking
  service.lastResponseTime.del(language)

  echo "DEBUG LanguageService: LSP thread recovery completed for: ", language

proc checkHoverResponse*(service: LanguageService): Option[HoverInfo] =
  ## Check if hover is active and return only real LSP content
  if service.hoverState.content.len > 0:
    return some(HoverInfo(content: service.hoverState.content))
  return none(HoverInfo)

proc isHoverActive*(service: LanguageService): bool =
  ## Check if hover is currently active
  service.hoverState.content.len > 0

proc getCurrentHover*(service: LanguageService): Option[HoverInfo] =
  if service.hoverState.content.len > 0:
    return some(HoverInfo(content: service.hoverState.content))
  else:
    return none(HoverInfo)

proc updateCurrentHoverRequest*(service: LanguageService, symbol: string, position: CursorPos) =
  ## Update the current hover request tracking with the actual symbol
  service.hoverState.currentRequest = (symbol: symbol, position: position)

# Settings
proc setHoverEnabled*(service: LanguageService, enabled: bool) =
  service.enableHover = enabled
  if not enabled:
    service.clearHover()

proc setHoverTimeout*(service: LanguageService, timeout: float) =
  service.hoverTimeout = timeout

# Status and diagnostics
proc getStatus*(service: LanguageService): string =
  ## Get overall status of language service
  var activeClients = 0
  var readyClients = 0
  var errorClients = 0
  var timeoutClients = 0

  for lang, wrapper in service.lspClients.pairs:
    inc activeClients
    let status = wrapper.getLastStatusResponse()
    if status == "Ready":
      inc readyClients
    elif status.contains("Timeout"):
      inc timeoutClients
      echo "DEBUG LanguageService: Client for ", lang, " has timeout (expected, non-critical): ", status
    elif status.contains("Error"):
      inc errorClients
      echo "DEBUG LanguageService: Client for ", lang, " in critical error state: ", status

  if activeClients == 0:
    return "No LSP clients"
  elif errorClients > 0:
    var statusParts: seq[string] = @[]
    statusParts.add($errorClients & " clients with CRITICAL errors")
    if timeoutClients > 0:
      statusParts.add($timeoutClients & " clients with timeouts (normal)")
    statusParts.add("ready: " & $readyClients & "/" & $activeClients)
    return statusParts.join(", ")
  elif timeoutClients > 0:
    return $timeoutClients & " clients with timeouts (normal behavior, ready: " & $readyClients & "/" & $activeClients & ")"
  elif readyClients == activeClients:
    return "All LSP clients ready (" & $readyClients & ")"
  else:
    return $readyClients & "/" & $activeClients & " LSP clients ready"

proc getLSPClientCount*(service: LanguageService): int =
  service.lspClients.len

proc isLanguageSupported*(service: LanguageService, language: string): bool =
  language in service.supportedLanguages

proc resetLSPClient*(service: LanguageService, language: string) =
  ## Reset a specific LSP client that's in error state
  service.resetLSPClientImpl(language)

proc resetAllErrorClients*(service: LanguageService) =
  ## Reset all LSP clients that are in critical error state (excludes timeouts)
  var languagesToReset: seq[string] = @[]

  for lang, wrapper in service.lspClients.pairs:
    let status = wrapper.getLastStatusResponse()
    # Only reset for critical errors, not timeouts
    if status.contains("Error") and not status.contains("Timeout"):
      languagesToReset.add(lang)

  for lang in languagesToReset:
    service.resetLSPClientImpl(lang)

# Cleanup
proc shutdown*(service: LanguageService) =
  ## Shutdown all LSP clients
  echo "DEBUG LanguageService: Shutting down language service"

  for wrapper in service.lspClients.values:
    try:
      wrapper.shutdownLSP()
    except:
      discard # Ignore shutdown errors

  service.lspClients.clear()
  service.openDocuments.clear()
  service.clearHover()

# Definition support
proc requestDefinition*(
    service: LanguageService,
    filePath: string,
    line: int,
    character: int,
    symbol: string
): bool =
  ## Request go-to-definition for a symbol at the specified position
  echo "DEBUG LanguageService.requestDefinition: Requesting definition for '", symbol, "' at ", filePath, ":", line, ":", character

  let currentTime = rl.getTime()
  
  # Get or detect language
  var language = ""
  let uri = "file://" & filePath.replace("\\", "/")
  
  if uri in service.openDocuments:
    language = service.openDocuments[uri].language
  else:
    let detectedLang = detectLanguage(filePath)
    language = $detectedLang
    echo "DEBUG LanguageService.requestDefinition: Detected language: ", language

  # Ensure LSP client exists and is healthy
  var clientHealthy = true
  let wrapper = service.ensureLSPClient(language)

  # Check client health
  if language in service.lspClients:
    let status = wrapper.getLSPStatus()
    if not (status == "Ready" or status.contains("Timeout")):
      echo "DEBUG LanguageService.requestDefinition: Client not ready for definition request: ", status
      return false
    
    # Update request state
    service.definitionState.lastRequestTime = currentTime
    service.definitionState.lastRequestSymbol = symbol
    service.definitionState.pendingRequest = true
    inc service.definitionState.requestId
    
    # Clear previous results
    service.definitionState.locations = @[]
    
    # Make LSP request
    let lspWrapper = service.lspClients[language]
    let requestResult = try:
      # Open document if not already open
      let uri = if filePath.startsWith("file://"): filePath else: "file://" & filePath.replace("\\", "/")
      if uri notin service.openDocuments:
        echo "DEBUG LanguageService.requestDefinition: Opening document for definition request"
        let openResult = service.openDocument(filePath, "")
        if openResult.isErr:
          echo "DEBUG LanguageService.requestDefinition: Failed to open document"
          return false
      
      lspWrapper.requestDefinition(uri, line, character)
      true
    except Exception as e:
      echo "DEBUG LanguageService.requestDefinition: Exception during definition request: ", e.msg
      false
    
    if not requestResult:
      service.definitionState.pendingRequest = false
      return false
    
    echo "DEBUG LanguageService.requestDefinition: Definition request sent successfully"
    return true
  
  echo "DEBUG LanguageService.requestDefinition: No LSP client available for language: ", language
  return false

proc getLastDefinitionResponse*(service: LanguageService): seq[Location] =
  ## Get the last definition response
  return service.definitionState.locations

proc clearDefinitionResponse*(service: LanguageService) =
  ## Clear definition response
  service.definitionState.locations = @[]
  service.definitionState.pendingRequest = false

proc isDefinitionPending*(service: LanguageService): bool =
  ## Check if a definition request is pending
  return service.definitionState.pendingRequest
