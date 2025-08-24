## Notification Service Exampl
## Demonstrates how to use the component-based notification system

import std/[options, times]
import raylib as rl
import ../shared/[types, errors]
import ../infrastructure/rendering/[theme, renderer]
import ../infrastructure/input/input_handler
import ui_service
import notification_service

# Example usage of the notification service
proc exampleNotificationUsage*() =
  ## Example of how to use the notification service
  
  # 1. Create UI service dependencies
  let themeManager = newThemeManager()
  let renderer = newRenderer(themeManager)
  let inputHandler = newInputHandler()
  
  # 2. Create UI service
  let uiService = newUIService(themeManager.currentTheme, renderer, inputHandler)
  
  # 3. Create notification service
  let notificationService = newNotificationService(uiService)
  
  # 4. Add notifications
  let infoId = notificationService.addNotification(
    "This is an info notification",
    ntInfo,
    5.0
  )
  
  let warningId = notificationService.addNotification(
    "This is a warning notification with a longer message that might wrap to multiple lines",
    ntWarning,
    8.0
  )
  
  let errorId = notificationService.addNotification(
    "This is an error notification",
    ntError,
    10.0
  )
  
  let successId = notificationService.addNotification(
    "Operation completed successfully!",
    ntSuccess,
    3.0
  )
  
  # 5. Update and render in a loop
  echo "Notification IDs: ", notificationService.getAllNotificationIds()
  echo "Active notifications: ", notificationService.getActiveNotificationCount()
  
  # 6. Dismiss a specific notification
  discard notificationService.dismissNotification(infoId)
  
  # 7. Remove a notification completely
  discard notificationService.removeNotification(successId)
  
  # 8. Configure the service
  notificationService.setMaxNotifications(3)
  notificationService.setMargin(30.0)
  notificationService.setFadeOutDuration(0.5)
  
  # 9. Handle LSP notifications
  let lspMessage = """{
    "method": "window/showMessage",
    "params": {
      "type": 1,
      "message": "Error: Could not find module 'nonexistent'"
    }
  }"""
  
  notificationService.handleLSPNotification(lspMessage)

# Example of integrating with the main application
proc setupNotificationService*(uiService: UIService): NotificationService =
  ## Setup notification service for the main application
  let notificationService = newNotificationService(uiService)
  
  # Configure default settings
  notificationService.setMaxNotifications(5)
  notificationService.setMargin(20.0)
  notificationService.setAnimationDuration(0.2)
  notificationService.setFadeOutDuration(0.25)
  
  # Add some initial notifications
  notificationService.addNotification(
    "Welcome to Folx Editor!",
    ntInfo,
    3.0
  )
  
  return notificationService

# Example of handling different types of notifications
proc handleEditorNotifications*(
    notificationService: NotificationService,
    eventType: string,
    message: string
) =
  ## Handle different types of editor events and show appropriate notifications
  
  case eventType
  of "file_saved":
    notificationService.addNotification(
      "File saved successfully",
      ntSuccess,
      2.0
    )
  
  of "file_error":
    notificationService.addNotification(
      "Error saving file: " & message,
      ntError,
      8.0
    )
  
  of "syntax_error":
    notificationService.addNotification(
      "Syntax error detected: " & message,
      ntWarning,
      6.0
    )
  
  of "lsp_connected":
    notificationService.addNotification(
      "Language server connected",
      ntInfo,
      3.0
    )
  
  of "lsp_disconnected":
    notificationService.addNotification(
      "Language server disconnected",
      ntWarning,
      5.0
    )
  
  of "search_complete":
    notificationService.addNotification(
      "Search completed: " & message,
      ntInfo,
      4.0
    )
  
  else:
    notificationService.addNotification(
      message,
      ntInfo,
      4.0
    )

# Example of custom notification types
proc addCustomNotification*(
    notificationService: NotificationService,
    title: string,
    message: string,
    customType: string,
    duration: float = 5.0
) =
  ## Add a custom notification with a specific type
  
  let notificationType = case customType
    of "debug": ntInfo
    of "performance": ntWarning
    of "security": ntError
    of "update": ntSuccess
    else: ntInfo
  
  let fullMessage = title & ": " & message
  notificationService.addNotification(fullMessage, notificationType, duration)

# Example of notification service lifecycle
proc notificationServiceLifecycle*() =
  ## Demonstrate the complete lifecycle of the notification service
  
  # Setup
  let themeManager = newThemeManager()
  let renderer = newRenderer(themeManager)
  let inputHandler = newInputHandler()
  let uiService = newUIService(themeManager.currentTheme, renderer, inputHandler)
  let notificationService = newNotificationService(uiService)
  
  # Add notifications
  let id1 = notificationService.addNotification("First notification", ntInfo)
  let id2 = notificationService.addNotification("Second notification", ntWarning)
  let id3 = notificationService.addNotification("Third notification", ntError)
  
  # Update loop simulation
  for i in 0..<10:
    notificationService.update()
    notificationService.render()
    sleep(100) # Simulate frame time
  
  # Dismiss notifications
  discard notificationService.dismissNotification(id1)
  discard notificationService.removeNotification(id2)
  
  # Update again
  notificationService.update()
  notificationService.render()
  
  # Cleanup
  notificationService.clearAllNotifications()
  notificationService.cleanup()
  uiService.cleanup()

# Example of notification service with custom styling
proc createCustomNotificationService*(
    uiService: UIService,
    maxWidth: float32 = 400.0,
    margin: float32 = 25.0,
    fontSize: float32 = 14.0
): NotificationService =
  ## Create a notification service with custom styling
  
  let notificationService = newNotificationService(uiService)
  
  # Custom configuration
  notificationService.setMaxNotifications(3)
  notificationService.setMargin(margin)
  notificationService.setAnimationDuration(0.3)
  notificationService.setFadeOutDuration(0.4)
  
  # Customize component properties for all future notifications
  # (This would require modifying the createNotificationComponent proc)
  
  return notificationService 