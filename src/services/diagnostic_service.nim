## LSP Diagnostic Service - Handles textDocument/publishDiagnostics messages
## Provides centralized diagnostic management for the editor

import std/[tables, json, strutils, strformat, sequtils, options]
import raylib as rl
import ui_service
import ../infrastructure/rendering/theme
import ../infrastructure/rendering/renderer

# LSP Diagnostic severity levels (as per LSP spec)
type
  DiagnosticSeverity* = enum
    dsError = 1      # LSP Error severity
    dsWarning = 2    # LSP Warning severity  
    dsInformation = 3 # LSP Information severity
    dsHint = 4       # LSP Hint severity

  Diagnostic* = object
    message*: string
    severity*: DiagnosticSeverity
    line*: int           # 0-based line number
    character*: int      # 0-based character offset
    endLine*: int        # 0-based end line number
    endCharacter*: int   # 0-based end character offset
    source*: string      # LSP server source (e.g., "nimlsp")
    code*: string        # Diagnostic code if available
    relatedInfo*: seq[string] # Related diagnostic information

  FileDiagnostics* = object
    uri*: string
    diagnostics*: seq[Diagnostic]
    errorCount*: int
    warningCount*: int
    infoCount*: int
    hintCount*: int
    lastUpdated*: float64

  DiagnosticService* = ref object
    uiService*: UIService
    renderer*: Renderer
    themeManager*: ThemeManager
    componentId*: string
    
    # Diagnostic storage
    fileDiagnostics*: Table[string, FileDiagnostics]
    totalErrors*: int
    totalWarnings*: int
    totalInfos*: int
    totalHints*: int
    
    # UI state
    showDiagnostics*: bool
    maxDisplayedDiagnostics*: int
    lastUpdateTime*: float64

# Constructor
proc newDiagnosticService*(
    uiService: UIService,
    renderer: Renderer,
    themeManager: ThemeManager,
): DiagnosticService =
  let componentId = "diagnostic_service"
  
  result = DiagnosticService(
    uiService: uiService,
    renderer: renderer,
    themeManager: themeManager,
    componentId: componentId,
    fileDiagnostics: initTable[string, FileDiagnostics](),
    totalErrors: 0,
    totalWarnings: 0,
    totalInfos: 0,
    totalHints: 0,
    showDiagnostics: true,
    maxDisplayedDiagnostics: 100,
    lastUpdateTime: 0.0,
  )

# Helper procedures
proc severityToString*(severity: DiagnosticSeverity): string =
  case severity
  of dsError: "Error"
  of dsWarning: "Warning"
  of dsInformation: "Info"
  of dsHint: "Hint"

proc severityToUIColor*(severity: DiagnosticSeverity): UIColorType =
  case severity
  of dsError: uiError
  of dsWarning: uiWarning
  of dsInformation: uiInfo
  of dsHint: uiTextMuted

proc intToSeverity*(severityInt: int): DiagnosticSeverity =
  case severityInt
  of 1: dsError
  of 2: dsWarning
  of 3: dsInformation
  of 4: dsHint
  else: dsError  # Default to error for unknown values

# Core diagnostic processing
proc parseDiagnostic*(diagnosticJson: JsonNode): Option[Diagnostic] =
  ## Parse a single diagnostic from LSP JSON
  try:
    if not diagnosticJson.hasKey("message"):
      echo "DEBUG DiagnosticService: Diagnostic missing message field"
      return none(Diagnostic)
    
    var diagnostic = Diagnostic(
      message: diagnosticJson["message"].getStr(""),
      severity: dsError,  # Default
      line: 0,
      character: 0,
      endLine: 0,
      endCharacter: 0,
      source: "",
      code: "",
      relatedInfo: @[]
    )
    
    # Parse severity
    if diagnosticJson.hasKey("severity"):
      diagnostic.severity = intToSeverity(diagnosticJson["severity"].getInt(1))
    
    # Parse range
    if diagnosticJson.hasKey("range"):
      let range = diagnosticJson["range"]
      if range.hasKey("start"):
        let start = range["start"]
        diagnostic.line = start{"line"}.getInt(0)
        diagnostic.character = start{"character"}.getInt(0)
      
      if range.hasKey("end"):
        let endPos = range["end"]
        diagnostic.endLine = endPos{"line"}.getInt(diagnostic.line)
        diagnostic.endCharacter = endPos{"character"}.getInt(diagnostic.character)
    
    # Parse source
    if diagnosticJson.hasKey("source"):
      diagnostic.source = diagnosticJson["source"].getStr("")
    
    # Parse code
    if diagnosticJson.hasKey("code"):
      let codeNode = diagnosticJson["code"]
      if codeNode.kind == JString:
        diagnostic.code = codeNode.getStr("")
      elif codeNode.kind == JInt:
        diagnostic.code = $codeNode.getInt()
    
    # Parse related information (simplified)
    if diagnosticJson.hasKey("relatedInformation"):
      let relatedInfo = diagnosticJson["relatedInformation"]
      if relatedInfo.kind == JArray:
        for info in relatedInfo:
          if info.hasKey("message"):
            diagnostic.relatedInfo.add(info["message"].getStr(""))
    
    return some(diagnostic)
    
  except Exception as e:
    echo "DEBUG DiagnosticService: Error parsing diagnostic: ", e.msg
    return none(Diagnostic)

proc updateDiagnosticCounts*(service: var DiagnosticService, fileDiag: var FileDiagnostics) =
  ## Update diagnostic counts for a file
  fileDiag.errorCount = 0
  fileDiag.warningCount = 0
  fileDiag.infoCount = 0
  fileDiag.hintCount = 0
  
  for diag in fileDiag.diagnostics:
    case diag.severity
    of dsError: inc fileDiag.errorCount
    of dsWarning: inc fileDiag.warningCount
    of dsInformation: inc fileDiag.infoCount
    of dsHint: inc fileDiag.hintCount

proc recalculateTotalCounts*(service: var DiagnosticService) =
  ## Recalculate total diagnostic counts across all files
  service.totalErrors = 0
  service.totalWarnings = 0
  service.totalInfos = 0
  service.totalHints = 0
  
  for _, fileDiag in service.fileDiagnostics:
    service.totalErrors += fileDiag.errorCount
    service.totalWarnings += fileDiag.warningCount
    service.totalInfos += fileDiag.infoCount
    service.totalHints += fileDiag.hintCount

# Main API methods
proc handlePublishDiagnostics*(service: var DiagnosticService, notificationJson: string): bool =
  ## Handle LSP textDocument/publishDiagnostics notification
  try:
    let notification = parseJson(notificationJson)
    
    if not notification.hasKey("params"):
      echo "DEBUG DiagnosticService: Notification missing params"
      return false
    
    let params = notification["params"]
    
    if not params.hasKey("uri"):
      echo "DEBUG DiagnosticService: Diagnostics missing uri"
      return false
    
    let uri = params["uri"].getStr("")
    if uri.len == 0:
      echo "DEBUG DiagnosticService: Empty uri in diagnostics"
      return false
    
    echo "DEBUG DiagnosticService: Processing diagnostics for URI: ", uri
    
    # Get or create file diagnostics
    var fileDiag: FileDiagnostics
    if uri in service.fileDiagnostics:
      fileDiag = service.fileDiagnostics[uri]
    else:
      fileDiag = FileDiagnostics(
        uri: uri,
        diagnostics: @[],
        errorCount: 0,
        warningCount: 0,
        infoCount: 0,
        hintCount: 0,
        lastUpdated: 0.0
      )
    
    # Clear existing diagnostics for this file
    fileDiag.diagnostics = @[]
    
    # Parse new diagnostics
    if params.hasKey("diagnostics"):
      let diagnostics = params["diagnostics"]
      if diagnostics.kind == JArray:
        echo "DEBUG DiagnosticService: Found ", diagnostics.len, " diagnostics"
        
        for diagJson in diagnostics:
          let diagnostic = parseDiagnostic(diagJson)
          if diagnostic.isSome:
            fileDiag.diagnostics.add(diagnostic.get())
          else:
            echo "DEBUG DiagnosticService: Failed to parse diagnostic"
    
    # Update counts
    service.updateDiagnosticCounts(fileDiag)
    fileDiag.lastUpdated = rl.getTime()
    
    # Store updated file diagnostics
    service.fileDiagnostics[uri] = fileDiag
    
    # Recalculate totals
    service.recalculateTotalCounts()
    service.lastUpdateTime = rl.getTime()
    
    echo "DEBUG DiagnosticService: Updated diagnostics for ", uri, 
          " - Errors: ", fileDiag.errorCount, 
          ", Warnings: ", fileDiag.warningCount,
          ", Infos: ", fileDiag.infoCount,
          ", Hints: ", fileDiag.hintCount
    
    echo "DEBUG DiagnosticService: Total counts - Errors: ", service.totalErrors,
          ", Warnings: ", service.totalWarnings,
          ", Infos: ", service.totalInfos,
          ", Hints: ", service.totalHints
    
    return true
    
  except Exception as e:
    echo "DEBUG DiagnosticService: Error handling diagnostics: ", e.msg
    return false

proc clearDiagnostics*(service: var DiagnosticService, uri: string = ""): bool =
  ## Clear diagnostics for a specific file or all files
  if uri.len == 0:
    # Clear all diagnostics
    service.fileDiagnostics.clear()
    service.totalErrors = 0
    service.totalWarnings = 0
    service.totalInfos = 0
    service.totalHints = 0
    echo "DEBUG DiagnosticService: Cleared all diagnostics"
    return true
  else:
    # Clear diagnostics for specific file
    if uri in service.fileDiagnostics:
      service.fileDiagnostics.del(uri)
      service.recalculateTotalCounts()
      echo "DEBUG DiagnosticService: Cleared diagnostics for ", uri
      return true
    else:
      echo "DEBUG DiagnosticService: No diagnostics found for ", uri
      return false

# Query methods
proc getDiagnostics*(service: DiagnosticService, uri: string): seq[Diagnostic] =
  ## Get diagnostics for a specific file
  if uri in service.fileDiagnostics:
    return service.fileDiagnostics[uri].diagnostics
  else:
    return @[]

proc getFileDiagnostics*(service: DiagnosticService, uri: string): Option[FileDiagnostics] =
  ## Get complete file diagnostics info
  if uri in service.fileDiagnostics:
    return some(service.fileDiagnostics[uri])
  else:
    return none(FileDiagnostics)

proc getAllFilesWithDiagnostics*(service: DiagnosticService): seq[string] =
  ## Get list of all files that have diagnostics
  result = @[]
  for uri, _ in service.fileDiagnostics:
    result.add(uri)

proc hasErrors*(service: DiagnosticService): bool =
  service.totalErrors > 0

proc hasWarnings*(service: DiagnosticService): bool =
  service.totalWarnings > 0

proc hasDiagnostics*(service: DiagnosticService): bool =
  service.totalErrors + service.totalWarnings + service.totalInfos + service.totalHints > 0

# Count accessors
proc getTotalErrors*(service: DiagnosticService): int =
  service.totalErrors

proc getTotalWarnings*(service: DiagnosticService): int =
  service.totalWarnings

proc getTotalInfos*(service: DiagnosticService): int =
  service.totalInfos

proc getTotalHints*(service: DiagnosticService): int =
  service.totalHints

proc getTotalDiagnostics*(service: DiagnosticService): int =
  service.totalErrors + service.totalWarnings + service.totalInfos + service.totalHints

# Status formatting for UI
proc getStatusText*(service: DiagnosticService): string =
  ## Get formatted status text for status bar
  if not service.hasDiagnostics():
    return ""
  
  var parts: seq[string] = @[]
  
  if service.totalErrors > 0:
    parts.add(&"{service.totalErrors} error" & (if service.totalErrors != 1: "s" else: ""))
  
  if service.totalWarnings > 0:
    parts.add(&"{service.totalWarnings} warning" & (if service.totalWarnings != 1: "s" else: ""))
  
  if service.totalInfos > 0:
    parts.add(&"{service.totalInfos} info" & (if service.totalInfos != 1: "s" else: ""))
  
  if service.totalHints > 0:
    parts.add(&"{service.totalHints} hint" & (if service.totalHints != 1: "s" else: ""))
  
  return parts.join(", ")

proc getCompactStatusText*(service: DiagnosticService): string =
  ## Get compact status text for status bar (just numbers)
  if not service.hasDiagnostics():
    return ""
  
  var parts: seq[string] = @[]
  
  if service.totalErrors > 0:
    parts.add(&"✗{service.totalErrors}")
  
  if service.totalWarnings > 0:
    parts.add(&"⚠{service.totalWarnings}")
  
  return parts.join(" ")

# Status bar integration helpers
proc getPrimaryStatusColor*(service: DiagnosticService): UIColorType =
  ## Get the primary status color based on diagnostic severity
  if service.totalErrors > 0:
    return uiError
  elif service.totalWarnings > 0:
    return uiWarning
  elif service.totalInfos > 0:
    return uiInfo
  else:
    return uiTextMuted

# Diagnostic filtering and searching
proc getDiagnosticsByLine*(service: DiagnosticService, uri: string, line: int): seq[Diagnostic] =
  ## Get diagnostics for a specific line in a file
  let fileDiagnostics = service.getDiagnostics(uri)
  return fileDiagnostics.filterIt(it.line == line)

proc getDiagnosticsBySeverity*(service: DiagnosticService, uri: string, severity: DiagnosticSeverity): seq[Diagnostic] =
  ## Get diagnostics of a specific severity for a file
  let fileDiagnostics = service.getDiagnostics(uri)
  return fileDiagnostics.filterIt(it.severity == severity)

proc getNextDiagnostic*(service: DiagnosticService, uri: string, currentLine: int, currentChar: int): Option[Diagnostic] =
  ## Get the next diagnostic after the current position
  let diagnostics = service.getDiagnostics(uri)
  
  for diag in diagnostics:
    if diag.line > currentLine or (diag.line == currentLine and diag.character > currentChar):
      return some(diag)
  
  return none(Diagnostic)

proc getPreviousDiagnostic*(service: DiagnosticService, uri: string, currentLine: int, currentChar: int): Option[Diagnostic] =
  ## Get the previous diagnostic before the current position
  let diagnostics = service.getDiagnostics(uri)
  
  for i in countdown(diagnostics.len - 1, 0):
    let diag = diagnostics[i]
    if diag.line < currentLine or (diag.line == currentLine and diag.character < currentChar):
      return some(diag)
  
  return none(Diagnostic)

# Configuration
proc setMaxDisplayedDiagnostics*(service: var DiagnosticService, max: int) =
  service.maxDisplayedDiagnostics = max

proc setShowDiagnostics*(service: var DiagnosticService, show: bool) =
  service.showDiagnostics = show

proc getShowDiagnostics*(service: DiagnosticService): bool =
  service.showDiagnostics

# Update and maintenance
proc update*(service: var DiagnosticService, deltaTime: float64) =
  ## Update diagnostic service state
  # Could be used for periodic cleanup, expiring old diagnostics, etc.
  discard

# Cleanup
proc cleanup*(service: var DiagnosticService) =
  ## Clean up diagnostic service resources
  discard service.clearDiagnostics()
  discard service.uiService.removeComponent(service.componentId)

# Debug helpers
proc printDiagnosticSummary*(service: DiagnosticService) =
  ## Print diagnostic summary for debugging
  echo "=== Diagnostic Summary ==="
  echo "Total files with diagnostics: ", service.fileDiagnostics.len
  echo "Total errors: ", service.totalErrors
  echo "Total warnings: ", service.totalWarnings
  echo "Total infos: ", service.totalInfos
  echo "Total hints: ", service.totalHints
  
  for uri, fileDiag in service.fileDiagnostics:
    echo "File: ", uri
    echo "  Errors: ", fileDiag.errorCount, ", Warnings: ", fileDiag.warningCount
    echo "  Infos: ", fileDiag.infoCount, ", Hints: ", fileDiag.hintCount
    echo "  Last updated: ", fileDiag.lastUpdated