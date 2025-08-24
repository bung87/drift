## Thread-based LSP wrapper for Folx editor
## Provides asynchronous interface to LSP operations using threads
## All responses are handled centrally in the polling function

import std/[options, locks, json, times]
import chronos except Result
import infrastructure/external/lsp_client_async

type
  LSPCommand = enum
    cmdInitialize
    cmdHover
    cmdDefinition
    cmdDidOpen
    cmdDidClose
    cmdShutdown
    cmdGetStatus

  LSPThreadData = ref object
    shouldStop: bool
    thread: Thread[ptr LSPThreadData]
    asyncClient: LSPNimClient

  LSPWrapper* = ref object
    threadData*: LSPThreadData
    lock*: Lock
    isInitialized*: bool
    isShutdown*: bool
    lastHoverResponse*: Option[string]
    lastDefinitionResponse*: seq[Location]
    lastStatusResponse*: string
    lastError*: string
    pendingNotifications*: seq[string]

proc lspThreadProc(threadData: ptr LSPThreadData) {.thread.} =
  ## Main LSP thread procedure - keeps LSP client alive
  var threadStartTime = getTime()
  
  try:
    threadData.asyncClient = newLSPClient()
    waitFor threadData.asyncClient.initializeClient()
    
    proc runEventLoop() {.async.} =
      asyncSpawn threadData.asyncClient.start()
      while not threadData.shouldStop:
        await sleepAsync(100)
    waitFor runEventLoop()
  except Exception as e:
    echo "LSP Thread Error: ", e.msg
  finally:
    if not threadData.asyncClient.isNil:
      try:
        waitFor threadData.asyncClient.shutdown()
      except:
        discard

proc newLSPWrapper*(): LSPWrapper =
  ## Create a new thread-based LSP wrapper
  result = LSPWrapper(
    threadData: LSPThreadData(shouldStop: false),
    isInitialized: false,
    isShutdown: false,
    lastHoverResponse: none(string),
    lastDefinitionResponse: @[],
    lastStatusResponse: "Starting up...",
    lastError: "",
    pendingNotifications: @[]
  )
  initLock(result.lock)
  createThread(result.threadData.thread, lspThreadProc, addr result.threadData)

proc isClientReady(wrapper: LSPWrapper): bool =
  wrapper.isInitialized and wrapper.threadData.thread.running and not wrapper.threadData.asyncClient.isNil

proc validateClientReady(wrapper: LSPWrapper, operation: string): bool =
  if not wrapper.isInitialized:
    return false
  if not wrapper.isClientReady():
    return false
  return true

proc requestHover*(wrapper: LSPWrapper, uri: string, line: int, character: int) =
  if not wrapper.validateClientReady("hover"):
    return
  wrapper.threadData.asyncClient.queueRequest(LSPMessage(
    kind: lmkHover,
    uri: uri,
    line: line,
    character: character
  ))

proc requestDefinition*(wrapper: LSPWrapper, uri: string, line: int, character: int) =
  if not wrapper.validateClientReady("definition"):
    return
  wrapper.threadData.asyncClient.queueRequest(LSPMessage(
    kind: lmkDefinition,
    defUri: uri,
    defLine: line,
    defCharacter: character
  ))

proc initializeLSP*(wrapper: LSPWrapper, language: string = "") =
  if not wrapper.threadData.asyncClient.isNil:
    wrapper.threadData.asyncClient.clientLanguage = language
    wrapper.isInitialized = true
    wrapper.lastStatusResponse = "Ready"

proc notifyDocumentOpen*(wrapper: LSPWrapper, uri: string, content: string, language: string) =
  if wrapper.threadData.asyncClient.isNil:
    return
  wrapper.threadData.asyncClient.queueRequest(LSPMessage(
    kind: lmkDidOpen,
    openUri: uri,
    languageId: language,
    version: 0,
    text: content
  ))

proc notifyDocumentClose*(wrapper: LSPWrapper, uri: string) =
  if wrapper.threadData.asyncClient.isNil:
    return
  wrapper.threadData.asyncClient.queueRequest(LSPMessage(
    kind: lmkDidClose,
    closeUri: uri
  ))

proc shutdownLSP*(wrapper: LSPWrapper) =
  if wrapper.isShutdown:
    return
    
  if wrapper.threadData.asyncClient.isNil:
    return
  
  try:
    wrapper.threadData.asyncClient.queueRequest(LSPMessage(kind: lmkShutdown))
    wrapper.threadData.shouldStop = true
    wrapper.isShutdown = true
    
    if wrapper.threadData.thread.running:
      joinThread(wrapper.threadData.thread)
  except Exception as e:
    echo "LSP Shutdown Error: ", e.msg
    wrapper.isShutdown = true

proc cleanup*(wrapper: LSPWrapper) =
  if wrapper.isNil or wrapper.threadData.isNil:
    return
  if not wrapper.isShutdown:
    wrapper.shutdownLSP()

proc handleNotification(wrapper: LSPWrapper, lspResp: LSPResponse) =
  if not lspResp.hasContent:
    return
    
  let notificationJson = parseJson(lspResp.content)
  if not notificationJson.hasKey("method"):
    return
    
  let methodName = notificationJson["method"].getStr
  wrapper.pendingNotifications.add(lspResp.content)

proc pollLSPResponses*(wrapper: LSPWrapper) =
  if wrapper.isNil or wrapper.threadData.isNil or not wrapper.threadData.thread.running:
    return
    
  if wrapper.threadData.asyncClient.isNil:
    return
  
  try:
    if not wrapper.isInitialized:
      let clientState = wrapper.threadData.asyncClient.getState()
      if clientState.state == lspReady:
        wrapper.isInitialized = true
        wrapper.lastStatusResponse = "Ready"
        wrapper.lastError = ""
      elif clientState.error.len > 0:
        wrapper.lastError = clientState.error
        wrapper.lastStatusResponse = "Error: " & clientState.error
    
    while true:
      let lspResponse = wrapper.threadData.asyncClient.getResponse()
      if lspResponse.isNone:
        break
        
      let lspResp = lspResponse.get()
      
      case lspResp.kind
      of lmkHover:
        wrapper.lastHoverResponse = if lspResp.hasContent and lspResp.content.len > 0: some(lspResp.content) else: none(string)
      of lmkDefinition:
        wrapper.lastDefinitionResponse = lspResp.locations
      of lmkInitialize:
        if lspResp.success:
          wrapper.isInitialized = true
          wrapper.lastStatusResponse = "Ready"
        else:
          wrapper.lastError = lspResp.errorMsg
          wrapper.lastStatusResponse = "Initialization failed: " & lspResp.errorMsg
      of lmkNotification:
        wrapper.handleNotification(lspResp)
      else:
        discard
  except Exception as e:
    echo "LSP Poll Error: ", e.msg

# Convenience functions for accessing the centralized response data
proc getLastHoverResponse*(wrapper: LSPWrapper): Option[string] =
  wrapper.lastHoverResponse

proc getLastStatusResponse*(wrapper: LSPWrapper): string =
  wrapper.lastStatusResponse

proc getLastError*(wrapper: LSPWrapper): string =
  wrapper.lastError

proc clearHoverResponse*(wrapper: LSPWrapper) =
  wrapper.lastHoverResponse = none(string)

proc getLastDefinitionResponse*(wrapper: LSPWrapper): seq[Location] =
  wrapper.lastDefinitionResponse

proc clearDefinitionResponse*(wrapper: LSPWrapper) =
  wrapper.lastDefinitionResponse = @[]

proc getNotifications*(wrapper: LSPWrapper): seq[string] =
  ## Get all pending LSP notifications
  result = wrapper.pendingNotifications
  wrapper.pendingNotifications = @[]  # Clear after getting

proc hasNotifications*(wrapper: LSPWrapper): bool =
  ## Check if there are pending notifications
  wrapper.pendingNotifications.len > 0

proc getLSPStatus*(wrapper: LSPWrapper): string =
  ## Get current LSP status (non-blocking)
  if not wrapper.threadData.thread.running:
    return "Thread not running"
  if wrapper.isInitialized:
    return "Ready"
  elif wrapper.lastError.len > 0:
    return "Error: " & wrapper.lastError
  else:
    return wrapper.lastStatusResponse