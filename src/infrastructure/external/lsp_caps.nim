import sequtils,options
import lsp_client/client_capabilities

const TagSupportValueSet = {low(CompletionItemTag) .. high(
    CompletionItemTag)}.toSeq
const DocumentationFormat = {low(MarkupKind) .. high(MarkupKind)}.toSeq

proc createTextDocumentClientCapabilities*(): TextDocumentClientCapabilities =
  createTextDocumentClientCapabilities(
    synchronization = some(createTextDocumentSyncClientCapabilities(
      dynamicRegistration = some(true),
      willSave = none(bool),
      willSaveWaitUntil = none(bool),
      didSave = none(bool),
    )),
        hover = some(createHoverClientCapabilities(
      dynamicRegistration = some(true),
      contentFormat = some(DocumentationFormat),
      documentationFormat = some(DocumentationFormat)
    )),
    completion = some(createCompletionClientCapabilities(
      dynamicRegistration = some(true),
      completionItem = some(createCompletionItemCompletionClientCapabilities(
        snippetSupport = none(bool),
        commitCharactersSupport = none(bool),
        documentationFormat = some(DocumentationFormat),
        deprecatedSupport = some(true),
        preselectSupport = none(bool),
        tagSupport = some(createTagSupportCompletionItemCompletionClientCapabilities(
          valueSet = TagSupportValueSet
        ))
      )),
      completionItemKind = some(createCompletionItemKind(
        valueSet = some({low(CompletionItemKindEnum) .. high(CompletionItemKindEnum)}.toSeq)
      )),
      contextSupport = none(bool),
      insertTextMode = none(InsertTextMode),
    )),
    foldingRange = none(FoldingRangeClientCapabilities),
    selectionRange = none(SelectionRangeClientCapabilities),
    publishDiagnostics = none(PublishDiagnosticsClientCapabilities),
    declaration = none(DeclarationClientCapabilities),
    signatureHelp = none(SignatureHelpClientCapabilities),
    definition = some(createDefinitionClientCapabilities(dynamicRegistration = some(true), linkSupport = none(bool))),
    typeDefinition = some(createTypeDefinitionClientCapabilities(dynamicRegistration = some(true), linkSupport = none(bool))),
    implementation = some(createImplementationClientCapabilities(dynamicRegistration = some(true), linkSupport = none(bool))),
    references = some(createReferenceClientCapabilities(dynamicRegistration = some(true))),
    documentHighlight = some(createDocumentHighlightClientCapabilities(dynamicRegistration = some(true))),
    documentSymbol = some(createDocumentSymbolClientCapabilities(dynamicRegistration = some(true),
        hierarchicalDocumentSymbolSupport = none(bool))),
    codeAction = none(CodeActionClientCapabilities),
    codeLens = none(CodeLensClientCapabilities),
    formatting = none(DocumentFormattingClientCapabilities),
    rangeFormatting = none(DocumentRangeFormattingClientCapabilities),
    onTypeFormatting = none(DocumentOnTypeFormattingClientCapabilities),
    rename = some(createRenameClientCapabilities(dynamicRegistration = some(true), prepareSupport = none(bool))),
    documentLink = none(DocumentLinkClientCapabilities),
    colorProvider = none(DocumentColorClientCapabilities),
  )
