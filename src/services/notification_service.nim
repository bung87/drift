## Notification Service
## Component-based notification system integrated with UI service

import std/[options, times, json, tables, sequtils]
import raylib as rl
import ../shared/utils
import ../shared/errors
import ../infrastructure/rendering/renderer
import ui_service
import algorithm
import results

# Notification component types
type
  NotificationType* = enum
    ntInfo = "info"
    ntWarning = "warning" 
    ntError = "error"
    ntSuccess = "success"

  NotificationComponent* = ref object of UIComponent
    message*: string
    notificationType*: NotificationType
    timestamp*: float
    duration*: float # How long to show (0 = until dismissed)
    dismissed*: bool
    fadeStart*: float # When to start fading out
    fadeDuration*: float # How long the fade takes
    maxWidth*: float32
    padding*: float32
    fontSize*: float32
    lineSpacing*: float32
    cornerRadius*: float32
    iconSize*: float32

  NotificationService* = ref object
    uiService*: UIService
    notifications*: Table[string, NotificationComponent]
    maxNotifications*: int
    margin*: float32
    animationDuration*: float
    fadeOutDuration*: float
    nextZIndex*: int

# Forward declarations
proc createNotificationComponent*(
    service: NotificationService, 
    message: string, 
    notificationType: NotificationType = ntInfo,
    duration: float = 5.0
): NotificationComponent

proc renderNotificationComponent*(service: NotificationService, component: NotificationComponent)
proc getNotificationColor*(notificationType: NotificationType): rl.Color
proc getNotificationBackground*(notificationType: NotificationType): rl.Color
proc getDefaultFont*(service: NotificationService): ptr rl.Font
proc updateNotificationLayout*(service: NotificationService)

# Service creation
proc newNotificationService*(uiService: UIService): NotificationService =
  NotificationService(
    uiService: uiService,
    notifications: Table[string, NotificationComponent](),
    maxNotifications: 5,
    margin: 20.0,
    animationDuration: 0.2,
    fadeOutDuration: 0.25,
    nextZIndex: 1000, # Start above regular UI components
  )

# Component creation
proc createNotificationComponent*(
    service: NotificationService, 
    message: string, 
    notificationType: NotificationType = ntInfo,
    duration: float = 5.0
): NotificationComponent =
  let id = "notification_" & $epochTime() & "_" & $service.notifications.len
  
  let component = NotificationComponent(
    # UIComponent fields
    id: id,
    name: "notification",
    state: csVisible,
    bounds: Rectangle(x: 0, y: 0, width: 350, height: 48), # Default size
    zIndex: service.nextZIndex,
    isVisible: true,
    isEnabled: true,
    isDirty: true,
    parent: nil,
    children: @[],
    data: Table[string, string](),
    
    # NotificationComponent fields
    message: message,
    notificationType: notificationType,
    timestamp: epochTime(),
    duration: duration,
    dismissed: false,
    fadeStart: 0.0,
    fadeDuration: service.fadeOutDuration,
    maxWidth: 350.0,
    padding: 12.0,
    fontSize: 13.0,
    lineSpacing: 3.0,
    cornerRadius: 4.0,
    iconSize: 7.0,
  )

  # Add to UI service
  service.uiService.components[id] = component
  service.notifications[id] = component
  inc service.nextZIndex

  # Mark UI as needing redraw
  service.uiService.needsRedraw = true
  service.uiService.layoutDirty = true

  component

# Notification management
proc addNotification*(
    service: NotificationService,
    message: string,
    notificationType: NotificationType = ntInfo,
    duration: float = 5.0
): string =
  ## Add a new notification and return its ID
  echo "DEBUG NotificationService.addNotification: Adding notification - message: '", message, "', type: ", notificationType, ", duration: ", duration
  
  let component = service.createNotificationComponent(message, notificationType, duration)
  
  # Position notification in bottom-right corner
  let viewport = service.uiService.getViewport()
  let x = viewport.width - service.margin - component.maxWidth
  let y = viewport.height - service.margin - component.bounds.height
  
  component.bounds = Rectangle(
    x: x,
    y: y,
    width: component.maxWidth,
    height: component.bounds.height
  )
  
  echo "DEBUG NotificationService.addNotification: Positioned notification at (", x, ", ", y, ")"
  
  # Update layout for all notifications
  service.updateNotificationLayout()
  
  echo "DEBUG NotificationService.addNotification: Created notification with ID: ", component.id
  component.id

proc dismissNotification*(
    service: NotificationService, 
    notificationId: string
): Result[void, EditorError] =
  ## Dismiss a specific notification
  if notificationId notin service.notifications:
    return err(EditorError(msg: "Notification not found", code: "NOTIFICATION_NOT_FOUND"))
  
  let component = service.notifications[notificationId]
  component.dismissed = true
  component.fadeStart = epochTime()
  component.isDirty = true
  service.uiService.needsRedraw = true
  
  ok()

proc removeNotification*(
    service: NotificationService, 
    notificationId: string
): Result[void, EditorError] =
  ## Remove a notification completely
  if notificationId notin service.notifications:
    return err(EditorError(msg: "Notification not found", code: "NOTIFICATION_NOT_FOUND"))
  
  let component = service.notifications[notificationId]
  
  # Remove from UI service
  discard service.uiService.removeComponent(notificationId)
  
  # Remove from notifications table
  service.notifications.del(notificationId)
  
  # Update layout for remaining notifications
  service.updateNotificationLayout()
  
  ok()

proc clearAllNotifications*(service: NotificationService) =
  ## Clear all notifications
  for notificationId in service.notifications.keys:
    discard service.removeNotification(notificationId)

# Font utilities
proc getDefaultFont*(service: NotificationService): ptr rl.Font =
  ## Get the default font from the renderer, fallback to Raylib default if not found
  let font = service.uiService.renderer.getFont("ui")
  if font != nil:
    return font
  else:
    var defaultFont = rl.getFontDefault()
    return defaultFont.addr

# Layout management
proc notificationCmp(a, b: NotificationComponent): int =
  if a.timestamp > b.timestamp: return -1
  elif a.timestamp < b.timestamp: return 1
  else: return 0

proc updateNotificationLayout*(service: NotificationService) =
  ## Update positions of all visible notifications
  let viewport = service.uiService.getViewport()
  let margin = service.margin
  var y = viewport.height - margin
  
  # Sort notifications by timestamp (newest first)
  var sortedNotifications = toSeq(service.notifications.values)
  sortedNotifications = sortedNotifications.sorted(notificationCmp)
  
  for component in sortedNotifications:
    if component.isVisible and not component.dismissed:
      let x = viewport.width - margin - component.maxWidth
      
      # Calculate height based on message content
      let contentWidth = component.maxWidth - 2 * component.padding - 28.0
      let font = service.getDefaultFont()
      let lines = wrapText(component.message, contentWidth, component.fontSize, font[])
      let lineHeight = component.fontSize + component.lineSpacing
      let contentHeight = lines.len.float32 * lineHeight - component.lineSpacing
      let height = max(48.0, contentHeight + 2 * component.padding)
      
      component.bounds = Rectangle(
        x: x,
        y: y - height,
        width: component.maxWidth,
        height: height
      )
      
      y -= height + 5.0 # Add spacing between notifications
      
      # Stop if we would go off the top of the screen
      if y < 100.0:
        break

# Update and rendering
proc update*(service: NotificationService) =
  ## Update notification states (fading, auto-dismiss)
  let currentTime = epochTime()
  var toRemove: seq[string] = @[]
  
  for notificationId, component in service.notifications:
    # Check if notification should be auto-dismissed
    if component.duration > 0 and currentTime - component.timestamp > component.duration:
      if component.fadeStart == 0.0:
        # Start fade out
        component.fadeStart = currentTime
        component.isDirty = true
      elif currentTime - component.fadeStart > component.fadeDuration:
        # Remove after fade out
        toRemove.add(notificationId)
  
  # Remove expired notifications
  for notificationId in toRemove:
    discard service.removeNotification(notificationId)
  
  # Update layout if needed
  if toRemove.len > 0:
    service.updateNotificationLayout()

proc render*(service: NotificationService) =
  ## Render all visible notifications
  for component in service.notifications.values:
    if component.isVisible and not component.dismissed:
      service.renderNotificationComponent(component)

proc renderNotificationComponent*(
    service: NotificationService, 
    component: NotificationComponent
) =
  ## Render a single notification component
  
  let currentTime = epochTime()
  let notificationColor = getNotificationColor(component.notificationType)
  let backgroundColor = getNotificationBackground(component.notificationType)
  
  # Calculate opacity based on fade state
  var opacity = 1.0
  if component.fadeStart > 0:
    let fadeProgress = (currentTime - component.fadeStart) / component.fadeDuration
    opacity = max(0.0, 1.0 - fadeProgress)
  
  # Apply opacity to colors
  let alpha = (255.0 * opacity).uint8
  let bgColor = rl.Color(
    r: backgroundColor.r, 
    g: backgroundColor.g, 
    b: backgroundColor.b, 
    a: alpha
  )
  let textColor = rl.Color(r: 230, g: 230, b: 230, a: alpha)
  let borderColor = rl.Color(
    r: notificationColor.r, 
    g: notificationColor.g, 
    b: notificationColor.b, 
    a: alpha
  )
  
  # Get font and wrap text
  let font = service.getDefaultFont()
  let contentWidth = component.maxWidth - 2 * component.padding - 28.0
  let lines = wrapText(component.message, contentWidth, component.fontSize, font[])
  
  # Calculate height
  let lineHeight = component.fontSize + component.lineSpacing
  let contentHeight = lines.len.float32 * lineHeight - component.lineSpacing
  let totalHeight = max(48.0, contentHeight + 2 * component.padding)
  
  # Draw drop shadow
  let shadowColor = rl.Color(r: 0, g: 0, b: 0, a: (80.0 * opacity).uint8)
  rl.drawRectangleRounded(
    Rectangle(
      x: component.bounds.x + 1, 
      y: component.bounds.y + 1, 
      width: component.maxWidth, 
      height: totalHeight
    ),
    component.cornerRadius / 100.0,
    0,
    shadowColor
  )
  
  # Draw background
  rl.drawRectangleRounded(
    Rectangle(
      x: component.bounds.x, 
      y: component.bounds.y, 
      width: component.maxWidth, 
      height: totalHeight
    ),
    component.cornerRadius / 100.0,
    0,
    bgColor
  )
  
  # Draw left border
  rl.drawRectangle(
    component.bounds.x.int32, 
    component.bounds.y.int32, 
    3, 
    totalHeight.int32, 
    borderColor
  )
  
  # Draw icon
  let iconX = component.bounds.x + 14.0
  let iconY = component.bounds.y + (totalHeight - 16.0) / 2.0
  
  case component.notificationType
  of ntInfo:
    # Draw info circle with "i"
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize), borderColor)
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize - 2), bgColor)
    rl.drawText(
      font[], "i", rl.Vector2(x: iconX - 2, y: iconY + 3), 11.0, 1.0, borderColor
    )
  of ntWarning:
    # Draw warning circle with "!"
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize), borderColor)
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize - 2), bgColor)
    rl.drawText(
      font[], "!", rl.Vector2(x: iconX - 2, y: iconY + 2), 11.0, 1.0, borderColor
    )
  of ntError:
    # Draw error circle with "×"
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize), borderColor)
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize - 2), bgColor)
    rl.drawText(
      font[], "×", rl.Vector2(x: iconX - 3, y: iconY + 2), 11.0, 1.0, borderColor
    )
  of ntSuccess:
    # Draw success circle with "✓"
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize), borderColor)
    rl.drawCircle(iconX.int32, (iconY + 8).int32, float32(component.iconSize - 2), bgColor)
    rl.drawText(
      font[], "✓", rl.Vector2(x: iconX - 3, y: iconY + 2), 11.0, 1.0, borderColor
    )
  
  # Draw text
  let textX = component.bounds.x + component.padding + 24.0
  var textY = component.bounds.y + component.padding + 2.0
  for line in lines:
    rl.drawText(
      font[], line, rl.Vector2(x: textX, y: textY), component.fontSize, 1.0, textColor
    )
    textY += lineHeight

# Color utilities
proc getNotificationColor*(notificationType: NotificationType): rl.Color =
  ## Get the appropriate color for a notification type
  case notificationType
  of ntInfo:
    rl.Color(r: 14, g: 165, b: 233, a: 255) # Info blue
  of ntWarning:
    rl.Color(r: 250, g: 204, b: 21, a: 255) # Warning yellow
  of ntError:
    rl.Color(r: 239, g: 68, b: 68, a: 255) # Error red
  of ntSuccess:
    rl.Color(r: 34, g: 197, b: 94, a: 255) # Success green

proc getNotificationBackground*(notificationType: NotificationType): rl.Color =
  ## Get the background color for a notification type
  rl.Color(r: 30, g: 30, b: 30, a: 250) # Dark background

# LSP integration
proc parseLSPNotification*(
    jsonData: string
): Option[tuple[messageType: int, message: string]] =
  ## Parse LSP notification from JSON
  try:
    let json = parseJson(jsonData)
    
    # Handle window/showMessage notifications
    if json.hasKey("method") and json["method"].getStr() == "window/showMessage":
      if json.hasKey("params"):
        let params = json["params"]
        if params.hasKey("type") and params.hasKey("message"):
          let messageType = params["type"].getInt()
          let message = params["message"].getStr()
          return some((messageType, message))
    
    # Handle other LSP notifications
    elif json.hasKey("result") and json.hasKey("error") == false:
      let message = "LSP: " & jsonData[0 .. min(100, jsonData.len - 1)]
      return some((3, message)) # Treat as info
  except Exception as e:
    let message = "LSP notification parse error: " & e.msg
    return some((2, message)) # Treat as warning
  
  return none(tuple[messageType: int, message: string])

proc handleLSPNotification*(
    service: NotificationService, 
    jsonData: string
) =
  ## Handle LSP notification and add it to the notification system
  let parsed = parseLSPNotification(jsonData)
  if parsed.isSome:
    let (messageType, message) = parsed.get()
    
    # Convert LSP message type to notification type
    let notificationType = case messageType
      of 1: ntError    # LSP Error
      of 2: ntWarning  # LSP Warning
      of 3: ntInfo     # LSP Info
      of 4: ntInfo     # LSP Log
      else: ntInfo
    
    # Determine duration based on message type
    let duration = case messageType
      of 1: 10.0  # Errors stay longer
      of 2: 8.0   # Warnings stay medium time
      else: 6.0   # Info messages stay shorter time
    
    discard service.addNotification(message, notificationType, duration)

# Utility functions
proc getNotificationCount*(service: NotificationService): int =
  service.notifications.len

proc getActiveNotificationCount*(service: NotificationService): int =
  service.notifications.values.toSeq().countIt(not it.dismissed)

proc getAllNotificationIds*(service: NotificationService): seq[string] =
  toSeq(service.notifications.keys)

proc getNotification*(service: NotificationService, notificationId: string): Option[NotificationComponent] =
  if notificationId in service.notifications:
    some(service.notifications[notificationId])
  else:
    none(NotificationComponent)

proc setMaxNotifications*(service: NotificationService, maxCount: int) =
  service.maxNotifications = maxCount

proc getMaxNotifications*(service: NotificationService): int =
  service.maxNotifications

proc setMargin*(service: NotificationService, margin: float32) =
  service.margin = margin
  service.updateNotificationLayout()

proc getMargin*(service: NotificationService): float32 =
  service.margin

proc setAnimationDuration*(service: NotificationService, duration: float) =
  service.animationDuration = duration

proc getAnimationDuration*(service: NotificationService): float =
  service.animationDuration

proc setFadeOutDuration*(service: NotificationService, duration: float) =
  service.fadeOutDuration = duration
  # Update existing notifications
  for component in service.notifications.values:
    component.fadeDuration = duration

proc getFadeOutDuration*(service: NotificationService): float =
  service.fadeOutDuration

# Cleanup
proc cleanup*(service: NotificationService) =
  service.clearAllNotifications()
  service.notifications.clear()