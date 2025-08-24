## Simple notification system for user feedback
## Refactored to use ComponentManager architecture

import std/[tables, options]
import raylib as rl
import ../shared/[types, errors]
import ../services/[ui_service, component_manager]
import ../infrastructure/input/[input_handler, keyboard, mouse]
import ../infrastructure/rendering/theme
import results

type
  NotificationType* = enum
    ntSuccess = "success"
    ntError = "error" 
    ntWarning = "warning"
    ntInfo = "info"

  SimpleNotification* = ref object of UIComponent
    # ComponentManager integration
    componentManager*: ComponentManager
    
    # Notification data
    message*: string
    notificationType*: NotificationType
    showTime*: float64
    duration*: float64
    fadeOutDuration*: float64
    alpha*: float32
    
    # Animation state
    targetY*: float32
    currentY*: float32
    animationSpeed*: float32

  NotificationManager* = ref object
    componentManager*: ComponentManager
    notifications*: seq[SimpleNotification]
    maxNotifications*: int
    defaultDuration*: float64
    spacing*: float32
    containerBounds*: rl.Rectangle
    bounds*: rl.Rectangle  # Added for compatibility with main.nim
    nextId*: int

# Constants
const
  DEFAULT_NOTIFICATION_DURATION = 3.0
  FADE_OUT_DURATION = 0.5
  MAX_NOTIFICATIONS = 5
  NOTIFICATION_SPACING = 8.0
  NOTIFICATION_PADDING = 12.0
  NOTIFICATION_MIN_WIDTH = 200.0
  NOTIFICATION_MAX_WIDTH = 400.0
  NOTIFICATION_HEIGHT = 50.0
  ANIMATION_SPEED = 300.0

# Forward declarations
proc handleInput*(notification: SimpleNotification, event: UnifiedInputEvent): bool
proc render*(notification: SimpleNotification)
proc registerInputHandlers*(notification: SimpleNotification): Result[void, EditorError]
proc updateLayout*(manager: NotificationManager)
proc calculateNotificationBounds(manager: NotificationManager, notification: SimpleNotification, index: int): rl.Rectangle
proc dismiss*(notification: SimpleNotification)
proc handleClick*(notification: SimpleNotification, pos: MousePosition)

# SimpleNotification constructor
proc newSimpleNotification*(
  componentManager: ComponentManager,
  message: string,
  notificationType: NotificationType,
  duration: float64 = DEFAULT_NOTIFICATION_DURATION,
  id: string
): Result[SimpleNotification, EditorError] =
  ## Create new notification using ComponentManager
  
  let notification = SimpleNotification(
    componentManager: componentManager,
    message: message,
    notificationType: notificationType,
    showTime: rl.getTime(),
    duration: duration,
    fadeOutDuration: FADE_OUT_DURATION,
    alpha: 1.0,
    targetY: 0.0,
    currentY: -NOTIFICATION_HEIGHT, # Start off-screen
    animationSpeed: ANIMATION_SPEED
  )
  
  # Initialize UIComponent base
  notification.id = id
  notification.name = "SimpleNotification"
  notification.state = csVisible
  notification.bounds = rl.Rectangle(x: 0, y: 0, width: NOTIFICATION_MIN_WIDTH, height: NOTIFICATION_HEIGHT)
  notification.zIndex = 1500 # High z-index for notifications
  notification.isVisible = true
  notification.isEnabled = true
  notification.isDirty = true
  notification.data = initTable[string, string]()
  
  # Register with ComponentManager
  let registerResult = componentManager.registerComponent(
    id,
    notification,
    proc(event: UnifiedInputEvent): bool = notification.handleInput(event),
    proc(bounds: rl.Rectangle) = 
      notification.bounds = bounds
      notification.render()
  )
  
  if registerResult.isErr:
    return err(registerResult.error)
  
  # Register input handlers (minimal for notifications)
  let inputResult = notification.registerInputHandlers()
  if inputResult.isErr:
    return err(inputResult.error)
  
  return ok(notification)

# Input handling (minimal for notifications)
proc registerInputHandlers*(notification: SimpleNotification): Result[void, EditorError] =
  ## Register minimal input handlers for notifications
  
  # Notifications don't need many input handlers, but we register for clicks to dismiss
  var keyHandlers = initTable[KeyCombination, proc()]()
  
  let keyResult = notification.componentManager.registerInputHandlers(
    notification.id,
    keyHandlers,
    initTable[mouse.MouseButton, proc(pos: MousePosition)]()
  )
  
  if keyResult.isErr:
    return err(keyResult.error)
  
  # Register click to dismiss
  let dragResult = notification.componentManager.registerDragHandlers(
    notification.id,
    proc(pos: MousePosition) = notification.handleClick(pos),
    proc(pos: MousePosition) = discard,
    proc(pos: MousePosition) = discard
  )
  
  return dragResult

proc handleInput*(notification: SimpleNotification, event: UnifiedInputEvent): bool =
  ## Handle input events (minimal for notifications)
  if not notification.isVisible:
    return false
  
  case event.kind:
  of uiekMouse:
    if event.mouseEvent.eventType == metButtonPressed and event.mouseEvent.button == mbLeft:
      let mousePos = rl.Vector2(x: event.mouseEvent.position.x, y: event.mouseEvent.position.y)
      if rl.checkCollisionPointRec(mousePos, notification.bounds):
        # Click on notification dismisses it
        notification.dismiss()
        return true
  else:
    discard
  
  return false

proc handleClick*(notification: SimpleNotification, pos: MousePosition) =
  ## Handle click to dismiss notification
  let mousePos = rl.Vector2(x: pos.x, y: pos.y)
  if rl.checkCollisionPointRec(mousePos, notification.bounds):
    notification.dismiss()

proc dismiss*(notification: SimpleNotification) =
  ## Dismiss the notification immediately
  notification.isVisible = false
  discard notification.componentManager.setComponentVisibility(notification.id, false)
  notification.componentManager.markComponentDirty(notification.id)

# Get notification color based on type
proc getNotificationColor(componentManager: ComponentManager, notificationType: NotificationType): rl.Color =
  case notificationType:
  of ntSuccess:
    return componentManager.getUIColor(uiSuccess)
  of ntError:
    return componentManager.getUIColor(uiError)
  of ntWarning:
    return componentManager.getUIColor(uiWarning)
  of ntInfo:
    return componentManager.getUIColor(uiInfo)

# Rendering using ComponentManager services
proc render*(notification: SimpleNotification) =
  ## Render using ComponentManager's renderer and theme
  if not notification.isVisible or notification.alpha <= 0:
    return
  
  let bounds = notification.bounds
  
  # Get notification color
  let baseColor = getNotificationColor(notification.componentManager, notification.notificationType)
  
  # Apply alpha to background
  let bgColor = rl.Color(
    r: baseColor.r,
    g: baseColor.g, 
    b: baseColor.b,
    a: uint8(baseColor.a.float32 * notification.alpha * 0.9)
  )
  
  # Draw background with rounded corners
  rl.drawRectangleRounded(bounds, 0.1, 8, bgColor)
  
  # Draw border
  let borderColor = rl.Color(
    r: baseColor.r,
    g: baseColor.g,
    b: baseColor.b, 
    a: uint8(baseColor.a.float32 * notification.alpha)
  )
  rl.drawRectangleRoundedLines(bounds, 0.1, 8, 1.0, borderColor)
  
  # Draw text
  let textColor = rl.Color(
    r: 255,
    g: 255,
    b: 255,
    a: uint8(255.0 * notification.alpha)
  )
  
  let textX = bounds.x + NOTIFICATION_PADDING
  let textY = bounds.y + NOTIFICATION_PADDING
  
  rl.drawText(
    notification.message,
    textX.int32,
    textY.int32,
    14,
    textColor
  )
  
  notification.isDirty = false

proc update*(notification: SimpleNotification, deltaTime: float32) =
  ## Update notification animation and lifecycle
  let currentTime = rl.getTime()
  let elapsed = currentTime - notification.showTime
  
  # Update alpha based on lifecycle
  if elapsed >= notification.duration + notification.fadeOutDuration:
    # Notification should be removed
    notification.isVisible = false
    discard notification.componentManager.setComponentVisibility(notification.id, false)
  elif elapsed >= notification.duration:
    # Start fade out
    let fadeProgress = (elapsed - notification.duration) / notification.fadeOutDuration
    notification.alpha = 1.0 - fadeProgress.float32
    notification.componentManager.markComponentDirty(notification.id)
  else:
    # Full visibility
    notification.alpha = 1.0
  
  # Update position animation
  if abs(notification.currentY - notification.targetY) > 1.0:
    let direction = if notification.targetY > notification.currentY: 1.0 else: -1.0
    notification.currentY += direction * notification.animationSpeed * deltaTime
    notification.bounds.y = notification.currentY
    discard notification.componentManager.updateComponentBounds(notification.id, notification.bounds)
    notification.componentManager.markComponentDirty(notification.id)

# NotificationManager implementation
proc newNotificationManager*(
  componentManager: ComponentManager,
  containerBounds: rl.Rectangle
): NotificationManager =
  ## Create new notification manager
  NotificationManager(
    componentManager: componentManager,
    notifications: @[],
    maxNotifications: MAX_NOTIFICATIONS,
    defaultDuration: DEFAULT_NOTIFICATION_DURATION,
    spacing: NOTIFICATION_SPACING,
    containerBounds: containerBounds,
    nextId: 0
  )

proc calculateNotificationBounds(manager: NotificationManager, notification: SimpleNotification, index: int): rl.Rectangle =
  ## Calculate bounds for a notification at the given index
  let textWidth = rl.measureText(notification.message, 14)
  let width = max(NOTIFICATION_MIN_WIDTH, min(textWidth.float32 + NOTIFICATION_PADDING * 2, NOTIFICATION_MAX_WIDTH))
  let height = NOTIFICATION_HEIGHT
  
  # Position from top-right of container
  let x = manager.containerBounds.x + manager.containerBounds.width - width - 20
  let y = manager.containerBounds.y + 20 + (height + manager.spacing) * index.float32
  
  return rl.Rectangle(x: x, y: y, width: width, height: height)

proc updateLayout*(manager: NotificationManager) =
  ## Update layout of all notifications
  for i, notification in manager.notifications:
    if notification.isVisible:
      let newBounds = manager.calculateNotificationBounds(notification, i)
      notification.targetY = newBounds.y
      notification.bounds = newBounds
      discard notification.componentManager.updateComponentBounds(notification.id, newBounds)

proc show*(manager: NotificationManager, 
          message: string, 
          notificationType: NotificationType = ntInfo, 
          duration: float64 = DEFAULT_NOTIFICATION_DURATION): Result[void, EditorError] =
  ## Show a new notification
  
  # Remove oldest notification if at max capacity
  if manager.notifications.len >= manager.maxNotifications:
    let oldNotification = manager.notifications[0]
    oldNotification.dismiss()
    discard manager.componentManager.unregisterComponent(oldNotification.id)
    manager.notifications.delete(0)
  
  # Create new notification
  let id = "notification_" & $manager.nextId
  manager.nextId += 1
  
  let notificationResult = newSimpleNotification(
    manager.componentManager,
    message,
    notificationType,
    duration,
    id
  )
  
  if notificationResult.isErr:
    return err(notificationResult.error)
  
  let notification = notificationResult.get()
  manager.notifications.add(notification)
  
  # Update layout
  manager.updateLayout()
  
  return ok()

proc update*(manager: NotificationManager, deltaTime: float32) =
  ## Update all notifications
  # Update each notification
  for i in countdown(manager.notifications.len - 1, 0):
    let notification = manager.notifications[i]
    notification.update(deltaTime)
    
    # Remove expired notifications
    if not notification.isVisible:
      discard manager.componentManager.unregisterComponent(notification.id)
      manager.notifications.delete(i)
  
  # Update layout after removals
  if manager.notifications.len > 0:
    manager.updateLayout()

# Convenience methods
proc showSuccess*(manager: NotificationManager, message: string, duration: float64 = DEFAULT_NOTIFICATION_DURATION): Result[void, EditorError] =
  manager.show(message, ntSuccess, duration)

proc showError*(manager: NotificationManager, message: string, duration: float64 = DEFAULT_NOTIFICATION_DURATION * 1.5): Result[void, EditorError] =
  manager.show(message, ntError, duration)

proc showWarning*(manager: NotificationManager, message: string, duration: float64 = DEFAULT_NOTIFICATION_DURATION): Result[void, EditorError] =
  manager.show(message, ntWarning, duration)

proc showInfo*(manager: NotificationManager, message: string, duration: float64 = DEFAULT_NOTIFICATION_DURATION): Result[void, EditorError] =
  manager.show(message, ntInfo, duration)

# Clear all notifications
proc clear*(manager: NotificationManager) =
  ## Clear all notifications
  for notification in manager.notifications:
    notification.dismiss()
    discard manager.componentManager.unregisterComponent(notification.id)
  manager.notifications = @[]

# Update container bounds (for responsive design)
proc updateBounds*(manager: NotificationManager, bounds: rl.Rectangle) =
  ## Update container bounds
  manager.containerBounds = bounds
  manager.updateLayout()

# Cleanup
proc cleanup*(manager: NotificationManager) =
  ## Clean up all notifications and resources
  manager.clear()