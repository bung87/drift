## Modularized Async LSP Client
## No global state - all state encapsulated in LSPClient object
## All async procs are gcsafe - context passed as parameters

import std/[options, os, json, deques, tables, sequtils]
import chronos except Result
import chronos/timer except Result
import times
import results
import lsp_client
import lsp_client/nim_lsp_endpoint
import lsp_client/messages
import lsp_client/client_capabilities
import lsp_caps

# Add types that language service expects
type
  LSPPosition* = object
    line*: int
    character*: int

  LSPRange* = object
    start*: LSPPosition
    `end`*: LSPPosition

  TextEdit* = object
    range*: LSPRange
    newText*: string

  Location* = object
    uri*: string
    range*: LSPRange

  EditorError* = object
    msg*: string
    code*: string

proc newEditorError*(code: string, msg: string): EditorError =
  EditorError(msg: msg, code: code)

type
  LSPState* = enum
    lspUninitialized
    lspInitializing
    lspReady
    lspError
    lspShuttingDown
    lspShutdown

  LSPMessageKind* = enum
    lmkInitialize
    lmkHover
    lmkDefinition
    lmkNotification
    lmkDidOpen
    lmkDidChange
    lmkDidClose
    lmkShutdown

  LSPMessage* = object
    id: int
    case kind*: LSPMessageKind
    of lmkInitialize:
      discard
    of lmkHover:
      uri*: string
      line*: int
      character*: int
    of lmkDefinition:
      defUri*: string
      defLine*: int
      defCharacter*: int
    of lmkNotification:
      content*: string
    of lmkDidOpen:
      openUri*: string
      languageId*: string
      version*: int
      text*: string
    of lmkDidChange:
      changeUri*: string
      changeVersion*: int
      changeText*: string
    of lmkDidClose:
      closeUri*: string
    of lmkShutdown:
      discard

  LSPResponse* = object
    hasContent*: bool
    content*: string
    case kind*: LSPMessageKind
    of lmkInitialize:
      success*: bool
      errorMsg*: string
    of lmkDefinition:
      locations*: seq[Location]
    of lmkNotification:
      discard
    else:
      discard

  # Pending request tracking
  PendingRequest = object
    id: int
    methodName: string
    future: Future[JsonNode]
    timestamp: float

  LSPClientObj = object
    client: lsp_client.LspClient[LspNimEndpoint]
    endpoint: LspNimEndpoint
    state: LSPState
    errorMessage: string
    requestId: int
    # Message queues for internal async processing
    incomingQueue: Deque[LSPMessage]
    outgoingQueue: Deque[LSPResponse]
    # Pending requests table for proper request/response matching
    pendingRequests: Table[int, PendingRequest]
    # Async event loop handle
    asyncLoop: Future[void]
    stopRequested: bool
    # Message processing
    messageProcessor: Future[void]
    # Notification callback

    # Language this client is handling
    clientLanguage*: string

  LSPNimClient* = ref LSPClientObj

proc start*(client: LSPNimClient) {.async.}

proc newLSPClient*(): LSPNimClient =
  ## Create a new LSP client instance
  result = LSPNimClient(
    state: lspUninitialized, errorMessage: "", requestId: 0, stopRequested: false, clientLanguage: ""
  )
  result.incomingQueue = initDeque[LSPMessage]()
  result.outgoingQueue = initDeque[LSPResponse]()
  result.pendingRequests = initTable[int, PendingRequest]()
  # result.responseChan = cast[ptr Channel[LSPResponse]](alloc0(sizeof(Channel[LSPResponse]))) # Removed
  # result.responseChan.init() # Removed

proc getNextRequestId(client: LSPNimClient): int =
  inc client.requestId
  result = client.requestId

proc setState(client: LSPNimClient, state: LSPState, error: string = "") =
  client.state = state
  if error.len > 0:
    client.errorMessage = error

proc getState*(client: LSPNimClient): tuple[state: LSPState, error: string] =
  result = (client.state, client.errorMessage)

proc queueRequest*(client: LSPNimClient, msg: LSPMessage) =
  ## Queue a request to be processed by the async loop
  client.incomingQueue.addLast(msg)

proc getResponse*(client: LSPNimClient): Option[LSPResponse] =
  ## Get a response from the outgoing queue (non-blocking)
  if client.outgoingQueue.len > 0:
    result = some(client.outgoingQueue.popFirst())
  else:
    result = none(LSPResponse)

proc createClientCapabilities(): ClientCapabilities =
  create(
    ClientCapabilities,
    workspace = none(WorkspaceClientCapabilities),
    textDocument = some(createTextDocumentClientCapabilities()),
    window = none(WindowClientCapabilities),
    experimental = none(JsonNode),
  )

proc initializeClient*(client: LSPNimClient): Future[void] {.async.} =
  ## Initialize the LSP connection
  # Debug: Starting initialization
  client.setState(lspInitializing)

  # Create endpoint and client
  # Debug: Creating endpoint
  client.endpoint = LspNimEndpoint.new()
  # Debug: Creating LSP client
  client.client = newLspClient(client.endpoint)

  # Start the LSP server process
  # Debug: Starting LSP server process
  await client.endpoint.startProcess()
  # Debug: LSP server process started

  let currentDir = getCurrentDir()
  # Debug: Current directory
  let capabilities = createClientCapabilities()
  # Debug: Created client capabilities
  # Debug: Sending initialize request

  try:
    # Initialize through the client with timeout
    # Debug: Creating initialize future
    let initFuture = client.client.initialize(
      processId = getCurrentProcessId(),
      rootPath = some(currentDir),
      rootUri = "file://" & currentDir,
      initializationOptions = some(%*{}),
      capabilities = capabilities,
      trace = some("verbose"), # Enable verbose tracing
      workspaceFolders = none(seq[WorkspaceFolder]),
    )

    # Debug: Waiting for initialization

    # Use race to implement timeout
    let timeoutFuture = sleepAsync(chronos.milliseconds(10000)) # 10 second timeout
    let completedFuture = await race(initFuture, timeoutFuture)

    if completedFuture == timeoutFuture:
      # Debug: Initialize request timed out
      client.setState(lspError, "Initialization timeout - LSP server not responding")
      return

    let initialized = initFuture.read()
    # Debug: Initialize request completed
    # Debug: Response received

    # Check if the response is actually a notification (happens during init)
    try:
      let responseJson = initialized.JsonNode
      if responseJson.kind == JObject and responseJson.hasKey("method") and not responseJson.hasKey("id"):
        # Debug: Notification during initialization
        client.outgoingQueue.addLast(
          LSPResponse(
            kind: lmkNotification,
            hasContent: true,
            content: $responseJson,
          )
        )
      elif responseJson.kind == JObject and responseJson.hasKey("result"):
        # Debug: Normal initialization response
        discard
      else:
        # Debug: Unexpected response format
        discard
    except Exception as e:
      discard
      # Debug: Error processing initialization response

    # Send initialized notification
    # Debug: Sending initialized notification
    let notifyFuture = client.client.initialized()
    let notifyTimeoutFuture = sleepAsync(chronos.milliseconds(5000)) # 5 second timeout
    let notifyCompleted = await race(notifyFuture, notifyTimeoutFuture)

    if notifyCompleted == notifyTimeoutFuture:
      # Debug: Initialized notification timed out
      client.setState(lspError, "Initialized notification timeout")
      return

    # Debug: Initialized notification sent

    client.setState(lspReady)
    # Debug: Client is now ready
  except CatchableError as e:
    # Debug: Catchable error during initialization
    # Debug: Error type
    client.setState(lspError, e.msg)
  except Exception as e:
    # Debug: Exception during initialization
    # Debug: Exception type
    client.setState(lspError, e.msg)

# Unified message dispatcher
proc dispatchMessage(client: LSPNimClient, messageJson: JsonNode) =
  ## Centralized message dispatcher that handles requests, responses, and notifications
  try:
    # Check if this is a response to a pending request
    if messageJson.hasKey("id") and messageJson["id"].kind != JNull:
      let id = messageJson["id"].getInt()
      if id in client.pendingRequests:
        let pending = client.pendingRequests[id]
        client.pendingRequests.del(id)

        # Check if this is a hover response and handle it specially
        if pending.methodName == "textDocument/hover":
          echo "DEBUG LSP: Processing hover response with ID ", id
          var hoverContent = ""
          var hasContent = false

          # Parse hover response from the JSON-RPC message
          if messageJson.hasKey("result") and messageJson["result"].kind != JNull:
            let hoverResult = messageJson["result"]
            echo "DEBUG LSP: Hover result: ", hoverResult

            if hoverResult.kind == JObject and hoverResult.hasKey("contents"):
              let contents = hoverResult["contents"]

              if contents.kind == JArray and contents.len > 0:
                let firstContent = contents[0]
                if firstContent.hasKey("value"):
                  hoverContent = firstContent["value"].getStr
                  hasContent = true
                  echo "DEBUG LSP: Extracted hover from array: ", hoverContent
              elif contents.kind == JString:
                hoverContent = contents.getStr
                hasContent = true
                echo "DEBUG LSP: Extracted hover from string: ", hoverContent
              elif contents.kind == JObject and contents.hasKey("value"):
                hoverContent = contents["value"].getStr
                hasContent = true
                echo "DEBUG LSP: Extracted hover from object: ", hoverContent
            elif hoverResult.hasKey("capabilities"):
              echo "DEBUG LSP: WARNING: Got capabilities response for hover request - ignoring"
              hasContent = false

          # Queue the parsed hover response
          client.outgoingQueue.addLast(
            LSPResponse(
              kind: lmkHover,
              hasContent: hasContent,
              content: hoverContent,
            )
          )
          echo "DEBUG LSP: Queued hover response - hasContent: ", hasContent, " content length: ", hoverContent.len

        # Complete the pending request with the raw JsonNode
        pending.future.complete(messageJson)
        return

    # Check if this is a notification (no id field)
    if not messageJson.hasKey("id") or messageJson["id"].kind == JNull:
      let methodName = if messageJson.hasKey("method"): messageJson["method"].getStr() else: ""
      case methodName
      of "textDocument/publishDiagnostics":
        # Handle diagnostics notification
        echo "DEBUG LSP: Received diagnostics notification"
        if messageJson.hasKey("params") and messageJson["params"].hasKey("diagnostics"):
          let diagnostics = messageJson["params"]["diagnostics"]
          if diagnostics.kind == JArray and diagnostics.len > 0:
            echo "DEBUG LSP: Found ", diagnostics.len, " diagnostics"
            # Queue notification for centralized handling
            client.outgoingQueue.addLast(
              LSPResponse(
                kind: lmkNotification,
                hasContent: true,
                content: $messageJson,
              )
            )
      of "window/showMessage":
        # Handle show message notification
        echo "DEBUG LSP: Received show message notification"
        if messageJson.hasKey("params"):
          let params = messageJson["params"]
          if params.hasKey("message"):
            let message = params["message"].getStr()
            let messageType = if params.hasKey("type"): params["type"].getInt() else: 1
            echo "DEBUG LSP: LSP server message (type ", messageType, "): ", message
            # Queue notification for centralized handling
            client.outgoingQueue.addLast(
              LSPResponse(
                kind: lmkNotification,
                hasContent: true,
                content: $messageJson,
              )
            )
      of "window/logMessage":
        # Handle log message notification
        echo "DEBUG LSP: Received log message notification"
        if messageJson.hasKey("params"):
          let params = messageJson["params"]
          if params.hasKey("message"):
            let message = params["message"].getStr()
            let messageType = if params.hasKey("type"): params["type"].getInt() else: 1
            echo "DEBUG LSP: LSP server log (type ", messageType, "): ", message
            # Queue notification for centralized handling
            client.outgoingQueue.addLast(
              LSPResponse(
                kind: lmkNotification,
                hasContent: true,
                content: $messageJson,
              )
            )
      else:
        # Handle other notifications
        if methodName.len > 0:
          echo "DEBUG LSP: Received notification: ", methodName
          if messageJson.hasKey("params"):
            echo "DEBUG LSP: Notification params: ", messageJson["params"]
          # Queue notification for centralized handling
          client.outgoingQueue.addLast(
            LSPResponse(
              kind: lmkNotification,
              hasContent: true,
              content: $messageJson,
            )
          )

  except Exception as e:
    echo "Error in dispatchMessage: ", e.msg

proc cleanupExpiredRequests(client: LSPNimClient) =
  ## Clean up expired pending requests
  let now = epochTime()
  const maxAge = 30.0 # 30 seconds

  var toRemove: seq[int] = @[]
  for id, pending in client.pendingRequests:
    if now - pending.timestamp > maxAge:
      toRemove.add(id)
      # Complete with timeout error
      pending.future.complete(%*{"error": {"code": -32000, "message": "Request timeout"}})

  for id in toRemove:
    client.pendingRequests.del(id)



proc hover*(
    client: LSPNimClient, uri: string, line: int, character: int
): Future[void] {.async.} =
  ## Send hover request - response will be handled by message processing
  try:
    if client.state != lspReady:
      echo "DEBUG LSP: Client not ready for hover, state: ", client.state
      return

    echo "DEBUG LSP: Sending hover request for ",
      uri, " at line:", line, " char:", character
    let position = createPosition(line = line, character = character)
    let textDocument = createTextDocumentIdentifier(uri = uri)
    echo "DEBUG LSP hover: Created position and textDocument objects"

    # Send hover request without pending tracking to avoid future completion issues
    discard client.client.hover(textDocument, position)
    echo "DEBUG LSP hover: Hover request sent successfully"

  except Exception as e:
    echo "DEBUG LSP hover: Exception occurred: ", e.msg

proc didOpen*(
    client: LSPNimClient, uri: string, languageId: string, version: int, text: string
): Future[void] {.async.} =
  ## Notify document opened
  try:
    if client.state != lspReady:
      echo "DEBUG LSP: Client not ready for didOpen, state: ", client.state
      return

    echo "DEBUG LSP: Sending didOpen for ",
      uri, " (language:", languageId, ", version:", version, ", content length:",
      text.len, ")"
    let textDocument = createTextDocumentItem(
      uri = uri, languageId = languageId, version = version, text = text
    )

    await client.client.didOpen(textDocument)
    echo "DEBUG LSP: didOpen completed successfully for ", uri
  except Exception:
    echo "LSP didOpen error occurred"

proc didChange*(
    client: LSPNimClient, uri: string, version: int, text: string
): Future[void] {.async.} =
  ## Notify document changed
  try:
    if client.state != lspReady:
      return

    let textDocument =
      createVersionedTextDocumentIdentifier(uri = uri, version = version)
    let change = createTextDocumentContentChangeEvent(
      range = none(Range), rangeLength = none(int), text = text
    )
    await client.client.didChange(textDocument, @[change])
  except Exception:
    echo "LSP didChange error occurred"

proc didClose*(client: LSPNimClient, uri: string): Future[void] {.async.} =
  ## Notify document closed
  try:
    if client.state != lspReady:
      return

    let textDocument = createTextDocumentIdentifier(uri = uri)
    await client.client.didClose(textDocument)
  except Exception:
    echo "LSP didClose error occurred"

proc shutdown*(client: LSPNimClient): Future[void] {.async.} =
  ## Shutdown the LSP connection
  try:
    client.setState(lspShuttingDown)

    if not client.client.isNil:
      discard await client.client.shutdown()
      discard await client.client.exit()

    if not client.endpoint.isNil:
      client.endpoint.stopProcess()

    client.setState(lspShutdown)
  except Exception:
    client.setState(lspShutdown, "Shutdown error occurred")

proc processMessages(client: LSPNimClient) {.async.} =
  ## Main async loop for processing LSP messages
  echo "DEBUG LSP processMessages: Starting message processing loop"

  var loopCount = 0
  while not client.stopRequested:
    inc loopCount
    if loopCount mod 20 == 1:  # Print every 20 iterations (every ~1 second)
      echo "DEBUG LSP processMessages: Loop iteration #", loopCount, ", client state: ", client.state, ", queue length: ", client.incomingQueue.len
    # Clean up expired requests
    client.cleanupExpiredRequests()

    # Process incoming messages
    var messages: seq[LSPMessage] = @[]
    while client.incomingQueue.len > 0:
      messages.add(client.incomingQueue.popFirst())

    if messages.len > 0:
      echo "DEBUG LSP processMessages: Processing ", messages.len, " messages"

    for msg in messages:
      echo "DEBUG LSP processMessages: Processing message kind: ", msg.kind
      case msg.kind
      of lmkInitialize:
        if client.state != lspReady:
          await client.initializeClient()
          client.outgoingQueue.addLast(
            LSPResponse(kind: lmkInitialize, success: true, errorMsg: "")
          )
      of lmkHover:
        echo "DEBUG LSP processMessages: Hover request received, client state: ", client.state
        if client.state == lspReady:
          echo "DEBUG LSP processMessages: Processing hover request for URI: ",
            msg.uri, ", line: ", msg.line, ", char: ", msg.character

          try:
            echo "DEBUG LSP processMessages: Sending direct hover request"
            let textDocument = createTextDocumentIdentifier(uri = msg.uri)
            let position = createPosition(line = msg.line, character = msg.character)

            # Use async spawn to handle the hover response without blocking
            proc handleHoverResponse() {.async.} =
              try:
                let hoverResponse = await client.client.hover(textDocument, position)
                let content = hoverResponse.JsonNode
                echo "DEBUG LSP processMessages: Got hover response: ", content

                var hoverContent = ""
                var hasContent = false

                # Parse the response - first extract result, then contents
                var hoverData: JsonNode
                if content.kind == JObject and content.hasKey("result"):
                  hoverData = content["result"]
                else:
                  hoverData = content

                if hoverData.kind == JObject and hoverData.hasKey("contents"):
                  let contents = hoverData["contents"]
                  if contents.kind == JArray and contents.len > 0:
                    # Handle array format - extract from first element
                    let firstContent = contents[0]
                    if firstContent.hasKey("value"):
                      hoverContent = firstContent["value"].getStr
                      hasContent = true
                      echo "DEBUG LSP processMessages: Extracted from array: ", hoverContent
                  elif contents.kind == JObject and contents.hasKey("value"):
                    # Handle object format
                    hoverContent = contents["value"].getStr
                    hasContent = true
                    echo "DEBUG LSP processMessages: Extracted from object: ", hoverContent
                  elif contents.kind == JString:
                    # Handle string format
                    hoverContent = contents.getStr
                    hasContent = true
                    echo "DEBUG LSP processMessages: Extracted from string: ", hoverContent

                echo "DEBUG LSP processMessages: Extracted hover content: ", hoverContent
                client.outgoingQueue.addLast(
                  LSPResponse(
                    kind: lmkHover,
                    hasContent: hasContent,
                    content: hoverContent,
                  )
                )
              except Exception as e:
                echo "DEBUG LSP processMessages: Hover response error: ", e.msg
                client.outgoingQueue.addLast(
                  LSPResponse(
                    kind: lmkHover,
                    hasContent: false,
                    content: "",
                  )
                )

            asyncSpawn handleHoverResponse()
            echo "DEBUG LSP processMessages: Hover request spawned"

          except Exception as e:
            echo "DEBUG LSP processMessages: Hover request exception: ", e.msg
            client.outgoingQueue.addLast(
              LSPResponse(
                kind: lmkHover,
                hasContent: false,
                content: "",
              )
            )
        else:
          echo "DEBUG LSP processMessages: Client not ready for hover, state is: ", client.state
      of lmkNotification:
        echo "DEBUG LSP processMessages: Processing notification"
        # Add notification to outgoing queue for centralized handling
        client.outgoingQueue.addLast(
          LSPResponse(
            kind: lmkNotification,
            hasContent: true,
            content: msg.content,
          )
        )
        echo "DEBUG LSP processMessages: Notification queued for polling"
      of lmkDefinition:
        echo "DEBUG LSP processMessages: Definition request received, client state: ", client.state
        if client.state == lspReady:
          echo "DEBUG LSP processMessages: Processing definition request for URI: ",
            msg.defUri, ", line: ", msg.defLine, ", char: ", msg.defCharacter

          try:
            echo "DEBUG LSP processMessages: Sending definition request"
            let textDocument = createTextDocumentIdentifier(uri = msg.defUri)
            let position = createPosition(line = msg.defLine, character = msg.defCharacter)

            # Use async spawn to handle the definition response without blocking
            proc handleDefinitionResponse() {.async.} =
              try:
                let definitionResult = await client.client.definition(textDocument, position, none(string), none(string))
                var locations: seq[Location] = @[]

                # Convert the DefinitionResponse to JsonNode
                let jsonResponse = definitionResult.JsonNode
                if not jsonResponse.isNil and jsonResponse.kind == JObject and jsonResponse.hasKey("result"):
                  let resultData = jsonResponse["result"]
                  if not resultData.isNil:
                    if resultData.kind == JArray:
                      # Multiple locations
                      for item in resultData.getElems():
                        if item.hasKey("uri") and item.hasKey("range"):
                          let uri = item["uri"].getStr()
                          let range = item["range"]
                          if range.hasKey("start") and range.hasKey("end"):
                            let start = range["start"]
                            let endPos = range["end"]
                            if start.hasKey("line") and start.hasKey("character") and
                               endPos.hasKey("line") and endPos.hasKey("character"):
                              let location = Location(
                                uri: uri,
                                range: LSPRange(
                                  start: LSPPosition(
                                    line: start["line"].getInt(),
                                    character: start["character"].getInt()
                                  ),
                                  `end`: LSPPosition(
                                    line: endPos["line"].getInt(),
                                    character: endPos["character"].getInt()
                                  )
                                )
                              )
                              locations.add(location)
                    elif resultData.hasKey("uri") and resultData.hasKey("range"):
                      # Single location
                      let uri = resultData["uri"].getStr()
                      let range = resultData["range"]
                      if range.hasKey("start") and range.hasKey("end"):
                        let start = range["start"]
                        let endPos = range["end"]
                        if start.hasKey("line") and start.hasKey("character") and
                           endPos.hasKey("line") and endPos.hasKey("character"):
                          let location = Location(
                            uri: uri,
                            range: LSPRange(
                              start: LSPPosition(
                                line: start["line"].getInt(),
                                character: start["character"].getInt()
                              ),
                              `end`: LSPPosition(
                                line: endPos["line"].getInt(),
                                character: endPos["character"].getInt()
                              )
                            )
                          )
                          locations.add(location)

                echo "DEBUG LSP processMessages: Definition response parsed, found ", locations.len, " locations"
                client.outgoingQueue.addLast(
                  LSPResponse(
                    kind: lmkDefinition,
                    locations: locations
                  )
                )
              except Exception as e:
                echo "DEBUG LSP processMessages: Definition response error: ", e.msg
                client.outgoingQueue.addLast(
                  LSPResponse(
                    kind: lmkDefinition,
                    locations: @[]
                  )
                )

            asyncSpawn handleDefinitionResponse()
            echo "DEBUG LSP processMessages: Definition request spawned"

          except Exception as e:
            echo "DEBUG LSP processMessages: Definition request exception: ", e.msg
            client.outgoingQueue.addLast(
              LSPResponse(
                kind: lmkDefinition,
                locations: @[]
              )
            )
        else:
          echo "DEBUG LSP processMessages: Client not ready for definition, state is: ", client.state
      of lmkDidOpen:
        if client.state == lspReady:
          await client.didOpen(msg.openUri, msg.languageId, msg.version, msg.text)
      of lmkDidChange:
        if client.state == lspReady:
          await client.didChange(msg.changeUri, msg.changeVersion, msg.changeText)
      of lmkDidClose:
        if client.state == lspReady:
          await client.didClose(msg.closeUri)
      of lmkShutdown:
        await client.shutdown()
        client.stopRequested = true
        break

    # Small delay to prevent busy loop
    await sleepAsync(chronos.milliseconds(50))

proc start*(client: LSPNimClient) {.async.} =
  ## Start the async processing loop
  client.asyncLoop = processMessages(client)

proc stop*(client: LSPNimClient): Future[void] {.async.} =
  ## Stop the LSP client
  client.stopRequested = true
  if client.asyncLoop != nil:
    await client.asyncLoop



proc parseCompletionItem(json: JsonNode): CompletionItem =
  ## Parse a CompletionItem from JSON
  # For now, return a default CompletionItem since it's a distinct type
  # and we can't easily construct it without knowing its underlying type
  # This is a temporary workaround until we understand the CompletionItem type better

  # Extract label (required field)
  if not json.hasKey("label"):
    # If no label, return a default item
    return CompletionItem.default

  # For now, just return a default CompletionItem
  # TODO: Implement proper parsing when we understand the CompletionItem type structure
  return CompletionItem.default

proc completion*(
    client: LSPNimClient, uri: string, position: LSPPosition
): Future[Result[seq[CompletionItem], EditorError]] {.async.} =
  ## Request completion items
  try:
    if client.state != lspReady:
      return err(
        Result[seq[CompletionItem], EditorError],
        EditorError(msg: "LSP client not ready", code: "LSP_NOT_READY"),
      )

    let textDocument = createTextDocumentIdentifier(uri = uri)
    let pos = createPosition(line = position.line, character = position.character)

    let response = await client.client.completion(textDocument, pos)

    # Extract completion items from the response
    var completionItems: seq[CompletionItem] = @[]

    # Parse the response JSON
    let responseJson = response.JsonNode

    # Check for errors first
    if responseJson.hasKey("error"):
      return err(
        Result[seq[CompletionItem], EditorError],
        EditorError(
          msg: "LSP completion error: " & $responseJson["error"],
          code: "LSP_COMPLETION_ERROR",
        ),
      )

    # Extract result from response
    if responseJson.hasKey("result") and responseJson["result"].kind != JNull:
      let completionResult = responseJson["result"]

      case completionResult.kind
      of JArray:
        # Direct array of CompletionItem
        for item in completionResult:
          if item.kind == JObject:
            # Parse CompletionItem from JSON object
            let completionItem = parseCompletionItem(item)
            completionItems.add(completionItem)
      of JObject:
        # CompletionList with items field
        if completionResult.hasKey("items") and completionResult["items"].kind == JArray:
          for item in completionResult["items"]:
            if item.kind == JObject:
              let completionItem = parseCompletionItem(item)
              completionItems.add(completionItem)
      else:
        # Unexpected result type
        return err(
          Result[seq[CompletionItem], EditorError],
          EditorError(
            msg: "Unexpected completion result type", code: "LSP_COMPLETION_PARSE_ERROR"
          ),
        )

    return ok(completionItems)
  except Exception as e:
    return err(
      Result[seq[CompletionItem], EditorError],
      EditorError(msg: "Completion failed: " & e.msg, code: "LSP_COMPLETION_FAILED"),
    )

proc hover*(
    client: LSPNimClient, uri: string, position: LSPPosition
): Future[Result[Option[string], EditorError]] {.async.} =
  ## Request hover information
  try:
    if client.state != lspReady:
      echo "DEBUG LSP hover: Client not ready, state: ", client.state
      return err(
        Result[Option[string], EditorError],
        EditorError(msg: "LSP client not ready", code: "LSP_NOT_READY"),
      )

    echo "DEBUG LSP hover: Sending request for ", uri, " at line:", position.line, " char:", position.character
    let textDocument = createTextDocumentIdentifier(uri = uri)
    let pos = createPosition(line = position.line, character = position.character)

    echo "DEBUG LSP hover: Calling client.hover..."
    let hoverResult = await client.client.hover(textDocument, pos)
    let content = hoverResult.JsonNode
    echo "DEBUG LSP hover: Raw response from LSP server: ", content
    echo "DEBUG LSP hover: Content type: ", content.kind
    echo "DEBUG LSP hover: Content is null: ", content.kind == JNull

    # Check if response has result field first (standard LSP response format)
    var hoverData: JsonNode
    if content.kind == JObject and content.hasKey("result"):
      echo "DEBUG LSP hover: Response has 'result' field"
      hoverData = content["result"]
    else:
      echo "DEBUG LSP hover: Response has no 'result' field, using raw content"
      hoverData = content

    if hoverData.kind == JObject and hoverData.hasKey("contents"):
      echo "DEBUG LSP hover: Hover data has 'contents' field"
      let contents = hoverData["contents"]
      echo "DEBUG LSP hover: Contents type: ", contents.kind
      echo "DEBUG LSP hover: Contents value: ", contents

      if contents.kind == JArray:
        echo "DEBUG LSP hover: Contents is array with length: ", contents.len
        if contents.len > 0:
          let firstContent = contents[0]
          echo "DEBUG LSP hover: First content: ", firstContent
          if firstContent.hasKey("value"):
            let value = firstContent["value"].getStr
            echo "DEBUG LSP hover: Extracted value: '", value, "'"
            return ok(Result[Option[string], EditorError], some(value))
          else:
            echo "DEBUG LSP hover: First content has no 'value' field"
        else:
          echo "DEBUG LSP hover: Contents array is empty"
      elif contents.kind == JString:
        let value = contents.getStr
        echo "DEBUG LSP hover: Contents is string: '", value, "'"
        return ok(Result[Option[string], EditorError], some(value))
      elif contents.kind == JObject:
        echo "DEBUG LSP hover: Contents is object: ", contents
        if contents.hasKey("value"):
          let value = contents["value"].getStr
          echo "DEBUG LSP hover: Extracted value from object: '", value, "'"
          return ok(Result[Option[string], EditorError], some(value))
        else:
          echo "DEBUG LSP hover: Contents object has no 'value' field"
    else:
      echo "DEBUG LSP hover: Hover data has no 'contents' field or is not an object"
      if hoverData.kind == JObject:
        echo "DEBUG LSP hover: Available fields in hover data: ", hoverData.keys.toSeq
      if content.kind == JObject:
        echo "DEBUG LSP hover: Available fields in raw response: ", content.keys.toSeq

    echo "DEBUG LSP hover: No usable content found, returning none"
    return ok(Result[Option[string], EditorError], none(string))
  except Exception as e:
    echo "DEBUG LSP hover: Exception occurred: ", e.msg
    echo "DEBUG LSP hover: Exception type: ", e.name
    return err(
      Result[Option[string], EditorError],
      EditorError(msg: "Hover failed: " & e.msg, code: "LSP_HOVER_FAILED"),
    )

proc gotoDefinition*(
    client: LSPNimClient, uri: string, position: LSPPosition
): Future[Result[seq[Location], EditorError]] {.async.} =
  ## Request goto definition
  try:
    if client.state != lspReady:
      return err(
        Result[seq[Location], EditorError],
        EditorError(msg: "LSP client not ready", code: "LSP_NOT_READY"),
      )

    let textDocument = createTextDocumentIdentifier(uri = uri)
    let pos = createPosition(line = position.line, character = position.character)
    let definitionResult =
      await client.client.definition(textDocument, pos, none(string), none(string))

    # Parse the definition result
    var locations: seq[Location] = @[]
    # Convert the DefinitionResponse to JsonNode
    let jsonResponse = definitionResult.JsonNode
    if not jsonResponse.isNil and jsonResponse.kind == JObject and jsonResponse.hasKey("result"):
      let resultData = jsonResponse["result"]
      if not resultData.isNil:
        if resultData.kind == JArray:
          # Multiple locations
          for item in resultData.getElems():
            if item.hasKey("uri") and item.hasKey("range"):
              let uri = item["uri"].getStr()
              let range = item["range"]
              if range.hasKey("start") and range.hasKey("end"):
                let start = range["start"]
                let endPos = range["end"]
                if start.hasKey("line") and start.hasKey("character") and
                   endPos.hasKey("line") and endPos.hasKey("character"):
                  let location = Location(
                    uri: uri,
                    range: LSPRange(
                      start: LSPPosition(
                        line: start["line"].getInt(),
                        character: start["character"].getInt()
                      ),
                      `end`: LSPPosition(
                        line: endPos["line"].getInt(),
                        character: endPos["character"].getInt()
                      )
                    )
                  )
                  locations.add(location)
        elif resultData.hasKey("uri") and resultData.hasKey("range"):
          # Single location
          let uri = resultData["uri"].getStr()
          let range = resultData["range"]
          if range.hasKey("start") and range.hasKey("end"):
            let start = range["start"]
            let endPos = range["end"]
            if start.hasKey("line") and start.hasKey("character") and
               endPos.hasKey("line") and endPos.hasKey("character"):
              let location = Location(
                uri: uri,
                range: LSPRange(
                  start: LSPPosition(
                    line: start["line"].getInt(),
                    character: start["character"].getInt()
                  ),
                  `end`: LSPPosition(
                    line: endPos["line"].getInt(),
                    character: endPos["character"].getInt()
                  )
                )
              )
              locations.add(location)

    return ok(Result[seq[Location], EditorError], locations)
  except Exception as e:
    return err(
      Result[seq[Location], EditorError],
      EditorError(
        msg: "Goto definition failed: " & e.msg, code: "LSP_DEFINITION_FAILED"
      ),
    )

proc findReferences*(
    client: LSPNimClient, uri: string, position: LSPPosition, includeDeclaration: bool
): Future[Result[seq[Location], EditorError]] {.async.} =
  ## Request find references
  try:
    if client.state != lspReady:
      return err(
        Result[seq[Location], EditorError],
        EditorError(msg: "LSP client not ready", code: "LSP_NOT_READY"),
      )

    # For now, return empty locations since there's no built-in references method
    # and we can't easily access the endpoint directly
    return ok(Result[seq[Location], EditorError], newSeq[Location]())
  except Exception as e:
    return err(
      Result[seq[Location], EditorError],
      EditorError(
        msg: "Find references failed: " & e.msg, code: "LSP_REFERENCES_FAILED"
      ),
    )

proc documentSymbols*(
    client: LSPNimClient, uri: string
): Future[Result[seq[DocumentSymbol], EditorError]] {.async.} =
  ## Request document symbols
  try:
    if client.state != lspReady:
      return err(EditorError(msg: "LSP client not ready", code: "LSP_NOT_READY"))

    let textDocument = createTextDocumentIdentifier(uri = uri)
    let symbolsResult =
      await client.client.documentSymbol(textDocument, none(string), none(string))
    # For now, return empty symbols
    return ok(Result[seq[DocumentSymbol], EditorError], newSeq[DocumentSymbol]())
  except Exception as e:
    return err(
      EditorError(msg: "Document symbols failed: " & e.msg, code: "LSP_SYMBOLS_FAILED")
    )

proc formatDocument*(
    client: LSPNimClient, uri: string
): Future[Result[seq[TextEdit], EditorError]] {.async.} =
  ## Request document formatting
  try:
    if client.state != lspReady:
      return err(
        Result[seq[TextEdit], EditorError],
        EditorError(msg: "LSP client not ready", code: "LSP_NOT_READY"),
      )

    # For now, return empty text edits since there's no built-in formatting method
    # and we can't easily access the endpoint directly
    return ok(Result[seq[TextEdit], EditorError], newSeq[TextEdit]())
  except Exception as e:
    return err(
      Result[seq[TextEdit], EditorError],
      EditorError(msg: "Format document failed: " & e.msg, code: "LSP_FORMAT_FAILED"),
    )

# Convenience functions for thread-safe operations
proc initialize*(client: LSPNimClient): int =
  ## Queue an initialization request and return request ID
  let id = client.getNextRequestId()
  client.queueRequest(LSPMessage(id: id, kind: lmkInitialize))
  return id

proc requestHover*(client: LSPNimClient, uri: string, line: int, character: int): int =
  ## Queue a hover request and return request ID
  let id = client.getNextRequestId()
  client.queueRequest(
    LSPMessage(id: id, kind: lmkHover, uri: uri, line: line, character: character)
  )
  return id

proc notifyDidOpen*(
    client: LSPNimClient, uri: string, languageId: string, version: int, text: string
) =
  ## Queue a document open notification
  client.queueRequest(
    LSPMessage(
      kind: lmkDidOpen,
      openUri: uri,
      languageId: languageId,
      version: version,
      text: text,
    )
  )

proc notifyDidChange*(client: LSPNimClient, uri: string, version: int, text: string) =
  ## Queue a document change notification
  client.queueRequest(
    LSPMessage(
      kind: lmkDidChange, changeUri: uri, changeVersion: version, changeText: text
    )
  )

proc notifyDidClose*(client: LSPNimClient, uri: string) =
  ## Queue a document close notification
  client.queueRequest(LSPMessage(kind: lmkDidClose, closeUri: uri))

proc isReady*(client: LSPNimClient): bool =
  ## Check if the client is ready for requests
  let (state, _) = client.getState()
  return state == lspReady

proc getStatus*(client: LSPNimClient): string =
  ## Get human-readable status
  let (state, error) = client.getState()
  case state
  of lspUninitialized:
    "Not initialized"
  of lspInitializing:
    "Initializing..."
  of lspReady:
    "Ready"
  of lspError:
    "Error: " & error
  of lspShuttingDown:
    "Shutting down..."
  of lspShutdown:
    "Shutdown"
