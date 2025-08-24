## Status Bar Service - Service-based status bar using UIService
## Provides clean status bar functionality integrated with the service architecture

import std/[tables, strutils, algorithm, strformat, os]
import raylib as rl
import shared/errors
import services/ui_service
import infrastructure/rendering/[theme, renderer]
import infrastructure/input/[input_handler, keyboard, mouse]
import icons
import results

# Status bar specific types
type
  StatusBarAlign* = enum
    sbaLeft = "left"
    sbaRight = "right"
    sbaCenter = "center"

  StatusBarElementType* = enum
    sbeText = "text"
    sbeIcon = "icon"
    sbeProgress = "progress"
    sbeButton = "button"
    sbeCustom = "custom"

  StatusBarElement* = object
    id*: string
    elementType*: StatusBarElementType
    text*: string
    icon*: string
    align*: StatusBarAlign
    priority*: int
    width*: float32
    minWidth*: float32
    maxWidth*: float32
    visible*: bool
    enabled*: bool
    colorType*: UIColorType
    tooltip*: string
    onClick*: proc()
    data*: Table[string, string]

  StatusBarConfig* = object
    height*: float32
    padding*: float32
    fontSize*: float32
    showBorder*: bool
    autoHide*: bool
    updateInterval*: float32

  StatusBarService* = ref object
    uiService*: UIService
    renderer*: Renderer
    themeManager*: ThemeManager
    componentId*: string
    config*: StatusBarConfig
    elements*: Table[string, StatusBarElement]
    elementOrder*: seq[string]
    bounds*: rl.Rectangle
    visible*: bool
    lastUpdateTime*: float64
    # Diagnostic support
    showDiagnostics*: bool
    diagnosticErrorCount*: int
    diagnosticWarningCount*: int
    # Drag detection state
    dragStartPos*: rl.Vector2
    isDragging*: bool

# Default configuration
proc defaultStatusBarConfig*(): StatusBarConfig =
  StatusBarConfig(
    height: 24.0,
    padding: 8.0,
    fontSize: 11.0,
    showBorder: true,
    autoHide: false,
    updateInterval: 0.1, # Update 10 times per second
  )

# Constructor
proc newStatusBarService*(
    uiService: UIService,
    renderer: Renderer,
    themeManager: ThemeManager,
    config: StatusBarConfig = defaultStatusBarConfig(),
): StatusBarService =
  let componentId = "status_bar"
  # let component = uiService.createComponent(componentId, "Status Bar")  # Unused variable

  result = StatusBarService(
    uiService: uiService,
    renderer: renderer,
    themeManager: themeManager,
    componentId: componentId,
    config: config,
    elements: initTable[string, StatusBarElement](),
    elementOrder: @[],
    bounds: rl.Rectangle(x: 0, y: 0, width: 1200, height: config.height),
    visible: true,
    lastUpdateTime: 0.0,
    showDiagnostics: true,
    diagnosticErrorCount: 0,
    diagnosticWarningCount: 0,
    dragStartPos: rl.Vector2(x: 0.0, y: 0.0),
    isDragging: false,
  )

  # Configure the UI component
  discard uiService.setComponentBounds(componentId, result.bounds)
  discard uiService.setComponentState(componentId, csVisible)

# Element management
proc addElement*(
    service: var StatusBarService,
    id: string,
    text: string = "",
    align: StatusBarAlign = sbaLeft,
    priority: int = 50,
    elementType: StatusBarElementType = sbeText,
    colorType: UIColorType = uiText,
    icon: string = "",
): bool =
  ## Add a new status bar element
  if id in service.elements:
    return false

  let element = StatusBarElement(
    id: id,
    elementType: elementType,
    text: text,
    icon: icon,
    align: align,
    priority: priority,
    width: 0.0, # Will be calculated
    minWidth: 20.0,
    maxWidth: 300.0,
    visible: true,
    enabled: true,
    colorType: colorType,
    data: initTable[string, string](),
  )

  service.elements[id] = element
  service.elementOrder.add(id)

  # Sort by priority
  let elements = service.elements
  service.elementOrder.sort(
    proc(a, b: string): int =
    result = cmp(elements[b].priority, elements[a].priority)
  )

  return true

proc updateElement*(
    service: var StatusBarService,
    id: string,
    text: string = "",
    visible: bool = true,
    colorType: UIColorType = uiText,
): bool =
  ## Update an existing status bar element
  if id notin service.elements:
    return false

  service.elements[id].text = text
  service.elements[id].visible = visible
  service.elements[id].colorType = colorType
  return true

proc removeElement*(service: var StatusBarService, id: string): bool =
  ## Remove a status bar element
  if id notin service.elements:
    return false

  service.elements.del(id)
  let index = service.elementOrder.find(id)
  if index >= 0:
    service.elementOrder.delete(index)

  return true

proc clearElements*(service: var StatusBarService) =
  ## Clear all status bar elements
  service.elements.clear()
  service.elementOrder.setLen(0)

# Predefined element types
proc addGitBranch*(
    service: var StatusBarService,
    branch: string,
    isDirty: bool = false,
    priority: int = 100,
): bool =
  let text =
    if branch.len > 0:
      branch & (if isDirty: " *" else: "")
    else:
      ""
  let icon = "gitbranch.svg" # The drawRasterizedIcon function will prepend resources/icons/
  return service.addElement("git_branch", text, sbaLeft, priority, sbeIcon,
      uiAccent, icon)

# Status bar elements update procedure (moved from main.nim)
proc updateStatusBarElements*(currentFile: string) =
  ## Update service-based status bar with proper layout
  # Determine file type based on current file
  var fileType = "Text"
  if currentFile.len > 0:
    let ext = currentFile.splitFile().ext.toLower()
    case ext
    of ".nim":
      fileType = "Nim"
    of ".ts", ".tsx":
      fileType = "TypeScript"
    of ".js", ".jsx":
      fileType = "JavaScript"
    of ".py":
      fileType = "Python"
    of ".rs":
      fileType = "Rust"
    of ".go":
      fileType = "Go"
    of ".cpp", ".cc", ".cxx":
      fileType = "C++"
    of ".c":
      fileType = "C"
    of ".md":
      fileType = "Markdown"
    else:
      fileType = "Text"

  # Note: Diagnostic service integration would need to be handled separately
  # For now, we'll use 0 counts as placeholders
  let diagnosticErrors = 0
  let diagnosticWarnings = 0
  discard diagnosticErrors
  discard diagnosticWarnings

  # Note: Status bar service integration would need proper service registration
  # For now, this is a placeholder implementation

proc addLineColumn*(
    service: var StatusBarService, line: int, column: int, priority: int = 10
): bool =
  let text = &"Ln {line}, Col {column}"
  return service.addElement("line_column", text, sbaRight, priority, sbeText, uiText)

proc addFileType*(
    service: var StatusBarService, fileType: string, priority: int = 20
): bool =
  let text = fileType.toUpperAscii()
  return service.addElement("file_type", text, sbaRight, priority, sbeText, uiTextMuted)



proc addEncoding*(
    service: var StatusBarService, encoding: string, priority: int = 30
): bool =
  return
    service.addElement("encoding", encoding, sbaRight, priority, sbeText, uiTextMuted)

proc addLineEnding*(
    service: var StatusBarService, lineEnding: string, priority: int = 25
): bool =
  return service.addElement(
    "line_ending", lineEnding, sbaRight, priority, sbeText, uiTextMuted
  )

proc addSelectionInfo*(
    service: var StatusBarService, selectionLength: int = 0, priority: int = 15
): bool =
  let text =
    if selectionLength > 0:
      &"({selectionLength} selected)"
    else:
      ""

  return service.addElement("selection", text, sbaRight, priority, sbeText, uiInfo)

proc addDiagnostics*(
    service: var StatusBarService,
    errorCount: int = 0,
    warningCount: int = 0,
    priority: int = 80
): bool =
  ## Add diagnostic information to status bar
  service.diagnosticErrorCount = errorCount
  service.diagnosticWarningCount = warningCount

  if not service.showDiagnostics or (errorCount == 0 and warningCount == 0):
    # Remove diagnostic element if no diagnostics or disabled
    discard service.removeElement("diagnostics")
    return true

  var parts: seq[string] = @[]
  var colorType = uiTextMuted

  if errorCount > 0:
    parts.add(&"✗{errorCount}")
    colorType = uiError

  if warningCount > 0:
    parts.add(&"⚠{warningCount}")
    if colorType == uiTextMuted:
      colorType = uiWarning

  let text = parts.join(" ")

  # Update existing element or add new one
  if "diagnostics" in service.elements:
    return service.updateElement("diagnostics", text, true, colorType)
  else:
    return service.addElement("diagnostics", text, sbaLeft, priority, sbeText, colorType)

# Layout calculation
proc calculateElementWidths*(service: var StatusBarService) =
  ## Calculate element widths based on content
  let font = service.renderer.getFont("ui")

  for id in service.elementOrder:
    if id in service.elements:
      var element = service.elements[id]
      if element.visible:
        let textSize = service.renderer.measureText(
          font[], element.text, service.config.fontSize, 1.0
        )
        element.width = max(
          element.minWidth,
          min(element.maxWidth, textSize.x + service.config.padding * 2),
        )
        service.elements[id] = element

proc getElementsByAlign*(
    service: StatusBarService, align: StatusBarAlign
): seq[string] =
  ## Get elements filtered by alignment
  result = @[]
  for id in service.elementOrder:
    if id in service.elements:
      let element = service.elements[id]
      if element.visible and element.align == align:
        result.add(id)

# Rendering
proc render*(service: var StatusBarService, bounds: rl.Rectangle) =
  ## Render the status bar
  service.bounds = bounds

  if not service.visible:
    return

  # Update component bounds
  discard service.uiService.setComponentBounds(service.componentId, bounds)

  # Calculate element widths
  service.calculateElementWidths()

  # Draw background
  service.renderer.drawThemedRectangle(bounds, uiStatusbar)

  # Draw border if enabled
  if service.config.showBorder:
    let borderRect =
      rl.Rectangle(x: bounds.x, y: bounds.y, width: bounds.width, height: 1.0)
    service.renderer.drawThemedRectangle(borderRect, uiBorder)

  let font = service.renderer.getFont("ui")
  let textY = bounds.y + (bounds.height - service.config.fontSize) / 2.0

  # Render left-aligned elements
  var leftX = bounds.x + service.config.padding
  let leftElements = service.getElementsByAlign(sbaLeft)
  for id in leftElements:
    if id in service.elements:
      let element = service.elements[id]
      let color = service.themeManager.getUIColor(element.colorType)

      if element.elementType == sbeIcon and element.icon.len > 0:
        # Draw icon first
        let iconSize = service.config.fontSize * 1.2 # Make icon slightly larger than font
        drawRasterizedIcon(element.icon, leftX, textY, iconSize, color)
        leftX += iconSize + 4.0 # Add some spacing between icon and text
        
        # Draw text if present
        if element.text.len > 0:
          service.renderer.drawText(
            font[],
            element.text,
            rl.Vector2(x: leftX, y: textY),
            service.config.fontSize,
            1.0,
            color,
          )
          leftX += service.renderer.measureText(font[], element.text,
              service.config.fontSize, 1.0).x + service.config.padding
        else:
          leftX += service.config.padding
      else:
        # Regular text element
        service.renderer.drawText(
          font[],
          element.text,
          rl.Vector2(x: leftX, y: textY),
          service.config.fontSize,
          1.0,
          color,
        )
        leftX += element.width + service.config.padding

  # Render right-aligned elements (reverse order for proper right-to-left layout)
  var rightX = bounds.x + bounds.width - service.config.padding
  let rightElements = service.getElementsByAlign(sbaRight)

  # Render right-aligned elements from right to left
  for i in countdown(rightElements.len - 1, 0):
    let id = rightElements[i]
    if id in service.elements:
      let element = service.elements[id]
      rightX -= element.width

      let color = service.themeManager.getUIColor(element.colorType)
      service.renderer.drawText(
        font[],
        element.text,
        rl.Vector2(x: rightX, y: textY),
        service.config.fontSize,
        1.0,
        color,
      )

      # Add spacing between elements (varied spacing to match layout)
      if i > 0:
        let currentId = rightElements[i]
        # let nextId =  # Unused variable
        #   if i > 0:
        #     rightElements[i - 1]
        #   else:
        #     ""

        # Specific spacing based on element types to match the layout
        if currentId == "file_type":
          rightX -= service.config.padding * 3 # More space before file type
        elif currentId == "line_ending":
          rightX -= service.config.padding * 2 # Medium space before line ending
        elif currentId == "encoding":
          rightX -= service.config.padding # Normal space before encoding
        else:
          rightX -= service.config.padding * 4 # Large space before line/column

  # Render center-aligned elements
  let centerElements = service.getElementsByAlign(sbaCenter)
  if centerElements.len > 0:
    var totalCenterWidth = 0.0
    for id in centerElements:
      if id in service.elements:
        totalCenterWidth += service.elements[id].width + service.config.padding

    var centerX = bounds.x + (bounds.width - totalCenterWidth) / 2.0
    for id in centerElements:
      if id in service.elements:
        let element = service.elements[id]
        let color = service.themeManager.getUIColor(element.colorType)

        service.renderer.drawText(
          font[],
          element.text,
          rl.Vector2(x: centerX, y: textY),
          service.config.fontSize,
          1.0,
          color,
        )
        centerX += element.width + service.config.padding

# Update and input handling
proc update*(service: var StatusBarService, deltaTime: float64) =
  ## Update status bar state
  let currentTime = rl.getTime()

  if currentTime - service.lastUpdateTime >= service.config.updateInterval:
    # Perform periodic updates here if needed
    service.lastUpdateTime = currentTime

# Input handling
proc handleMouseEvent*(service: StatusBarService, event: MouseEvent): bool =
  ## Handle mouse events for status bar
  if not service.visible:
    return false

  let mousePos = rl.Vector2(x: event.position.x, y: event.position.y)

  # Check if mouse is in status bar bounds
  if not rl.checkCollisionPointRec(mousePos, service.bounds):
    return false

  case event.eventType:
  of metButtonPressed:
    if event.button == mbLeft:
      # Handle element clicks
      # This could be expanded to handle clickable elements
      return true
  of metMoved:
    # Handle hover effects
    return false
  else:
    return false

# Move handleKeyboardEvent above handleInput
proc handleKeyboardEvent*(service: StatusBarService, event: InputEvent): bool =
  ## Handle keyboard events for status bar
  if not service.visible:
    return false

  # Status bar doesn't handle keyboard events directly
  return false

proc handleInput*(service: StatusBarService, event: UnifiedInputEvent): bool =
  ## Handle unified input events for status bar
  if not service.visible:
    return false

  case event.kind:
  of uiekMouse:
    return service.handleMouseEvent(event.mouseEvent)
  of uiekKeyboard:
    return service.handleKeyboardEvent(event.keyEvent)
  else:
    return false

proc registerInputHandlers*(service: StatusBarService): Result[void, EditorError] =
  ## Register input handlers with ComponentManager
  # Status bar doesn't need keyboard shortcuts
  return ok()

proc handleDragDetection*(service: var StatusBarService, mousePos: rl.Vector2,
    onDragUp: proc()): bool =
  ## Handle drag detection for terminal panel activation
  if not service.visible or not rl.checkCollisionPointRec(mousePos,
      service.bounds):
    return false

  # Check if mouse is near the top edge of the status bar (drag zone)
  let dragZoneHeight = 12.0 # Increased from 8 to 12 pixels for easier targeting
  let dragZone = rl.Rectangle(
    x: service.bounds.x,
    y: service.bounds.y,
    width: service.bounds.width,
    height: dragZoneHeight
  )

  # If mouse is in drag zone and left button is pressed
  if rl.checkCollisionPointRec(mousePos, dragZone) and rl.isMouseButtonPressed(
      rl.MouseButton.Left):
    # Start drag detection - track initial position
    service.dragStartPos = mousePos
    service.isDragging = true
    return true

  # If we're already dragging and mouse is moving up
  if service.isDragging and rl.isMouseButtonDown(rl.MouseButton.Left):
    let dragDistance = service.dragStartPos.y - mousePos.y
    if dragDistance > 10.0: # Require at least 10 pixels of upward movement
      onDragUp()
      service.isDragging = false
      return true

  # If mouse button is released, stop dragging
  if rl.isMouseButtonReleased(rl.MouseButton.Left):
    service.isDragging = false
    return false

  return false

# Configuration
proc setVisible*(service: var StatusBarService, visible: bool) =
  service.visible = visible
  if visible:
    discard service.uiService.setComponentState(service.componentId, csVisible)
  else:
    discard service.uiService.setComponentState(service.componentId, csHidden)

proc setHeight*(service: var StatusBarService, height: float32) =
  service.config.height = height
  service.bounds.height = height

proc getHeight*(service: StatusBarService): float32 =
  service.config.height

proc setConfig*(service: var StatusBarService, config: StatusBarConfig) =
  service.config = config

proc getConfig*(service: StatusBarService): StatusBarConfig =
  service.config

# Convenience update functions
proc updateAll*(
    service: var StatusBarService,
    gitBranch: string = "",
    gitDirty: bool = false,
    line: int = 1,
    column: int = 1,
    fileType: string = "",
    encoding: string = "UTF-8",
    lineEnding: string = "LF",
    selectionLength: int = 0,
    diagnosticErrors: int = 0,
    diagnosticWarnings: int = 0,
) =
  ## Update all common status bar elements at once
  discard service.updateElement(
    "git_branch",
    if gitBranch.len > 0:
      gitBranch & (if gitDirty: " *" else: "")
    else:
      "",
    gitBranch.len > 0,
    uiAccent,
  )

  discard service.updateElement("line_column", &"Ln {line}, Col {column}")

  discard service.updateElement(
    "file_type", fileType.toUpperAscii(), fileType.len > 0, uiTextMuted
  )

  discard service.updateElement("encoding", encoding, encoding.len > 0, uiTextMuted)

  discard
    service.updateElement("line_ending", lineEnding, lineEnding.len > 0, uiTextMuted)



  let selectionText =
    if selectionLength > 0:
      &"({selectionLength} selected)"
    else:
      ""
  discard service.updateElement("selection", selectionText, selectionLength > 0, uiInfo)

  # Update diagnostics
  discard service.addDiagnostics(diagnosticErrors, diagnosticWarnings)

# Diagnostic configuration
proc setShowDiagnostics*(service: var StatusBarService, show: bool) =
  service.showDiagnostics = show
  # Refresh diagnostics display
  discard service.addDiagnostics(service.diagnosticErrorCount,
      service.diagnosticWarningCount)

proc getShowDiagnostics*(service: StatusBarService): bool =
  service.showDiagnostics

proc updateDiagnostics*(service: var StatusBarService, errorCount: int,
    warningCount: int) =
  ## Update diagnostic counts and refresh display
  discard service.addDiagnostics(errorCount, warningCount)

proc getDiagnosticCounts*(service: StatusBarService): tuple[errors: int,
    warnings: int] =
  (service.diagnosticErrorCount, service.diagnosticWarningCount)

# Cleanup
proc cleanup*(service: var StatusBarService) =
  ## Clean up resources
  service.clearElements()
  discard service.uiService.removeComponent(service.componentId)
