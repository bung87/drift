## Centralized Cursor Manager
## Prevents cursor flickering by managing cursor state changes efficiently
## Only updates cursor when necessary and handles priority conflicts

import raylib as rl
import std/[tables]

type
  CursorPriority* = enum
    cpDefault = 0      # Lowest priority - default cursor
    cpTextEditor = 10  # Text editing areas (I-beam)
    cpUI = 20          # UI elements (buttons, links)
    cpDrag = 30        # Drag operations (resize, move)
    cpModal = 40       # Modal dialogs or critical UI

  CursorRequest* = object
    cursor*: rl.MouseCursor
    priority*: CursorPriority
    requestTime*: float
    requesterId*: string  # For debugging

  CursorManager* = ref object
    currentCursor: rl.MouseCursor
    currentPriority: CursorPriority
    lastUpdateTime: float
    requests: Table[string, CursorRequest]
    debugMode: bool

# Global instance
var globalCursorManager*: CursorManager

proc newCursorManager*(debugMode: bool = false): CursorManager =
  ## Create a new cursor manager
  result = CursorManager(
    currentCursor: rl.MouseCursor.Default,
    currentPriority: cpDefault,
    lastUpdateTime: 0.0,
    requests: initTable[string, CursorRequest](),
    debugMode: debugMode
  )

proc initGlobalCursorManager*(debugMode: bool = false) =
  ## Initialize the global cursor manager
  globalCursorManager = newCursorManager(debugMode)

proc requestCursor*(manager: CursorManager, requesterId: string, 
                   cursor: rl.MouseCursor, priority: CursorPriority) =
  ## Request a cursor change with priority
  let currentTime = rl.getTime()
  
  let request = CursorRequest(
    cursor: cursor,
    priority: priority,
    requestTime: currentTime,
    requesterId: requesterId
  )
  
  manager.requests[requesterId] = request
  
  if manager.debugMode:
    echo "Cursor request from ", requesterId, ": ", cursor, " (priority: ", priority, ")"

proc clearCursorRequest*(manager: CursorManager, requesterId: string) =
  ## Clear a cursor request from a specific requester
  if requesterId in manager.requests:
    if manager.debugMode:
      echo "Clearing cursor request from ", requesterId
    manager.requests.del(requesterId)

proc updateCursor*(manager: CursorManager) =
  ## Update the cursor based on current requests (call once per frame)
  let currentTime = rl.getTime()
  
  # Clean up old requests (older than 1 second)
  var toRemove: seq[string] = @[]
  for requesterId, request in manager.requests.pairs:
    if currentTime - request.requestTime > 1.0:
      toRemove.add(requesterId)
  
  for requesterId in toRemove:
    manager.requests.del(requesterId)
  
  # Find highest priority request
  var highestPriority = cpDefault
  var targetCursor = rl.MouseCursor.Default
  
  for request in manager.requests.values:
    if request.priority > highestPriority:
      highestPriority = request.priority
      targetCursor = request.cursor
  
  # Only update if cursor or priority changed
  if targetCursor != manager.currentCursor or highestPriority != manager.currentPriority:
    if manager.debugMode:
      echo "Updating cursor: ", manager.currentCursor, " -> ", targetCursor, 
           " (priority: ", manager.currentPriority, " -> ", highestPriority, ")"
    
    rl.setMouseCursor(targetCursor)
    manager.currentCursor = targetCursor
    manager.currentPriority = highestPriority
    manager.lastUpdateTime = currentTime

# Convenience functions for global manager
proc requestCursor*(requesterId: string, cursor: rl.MouseCursor, 
                   priority: CursorPriority) =
  ## Request cursor change using global manager
  if globalCursorManager != nil:
    globalCursorManager.requestCursor(requesterId, cursor, priority)

proc clearCursorRequest*(requesterId: string) =
  ## Clear cursor request using global manager
  if globalCursorManager != nil:
    globalCursorManager.clearCursorRequest(requesterId)

proc updateGlobalCursor*() =
  ## Update global cursor (call once per frame in main loop)
  if globalCursorManager != nil:
    globalCursorManager.updateCursor()

# Specific cursor type helpers
proc requestTextCursor*(requesterId: string) =
  requestCursor(requesterId, rl.MouseCursor.IBeam, cpTextEditor)

proc requestHandCursor*(requesterId: string) =
  requestCursor(requesterId, rl.MouseCursor.PointingHand, cpUI)

proc requestResizeCursor*(requesterId: string) =
  requestCursor(requesterId, rl.MouseCursor.ResizeNS, cpDrag)

proc requestDefaultCursor*(requesterId: string) =
  requestCursor(requesterId, rl.MouseCursor.Default, cpDefault)

# Mouse area detection helpers
proc isMouseInRect*(rect: rl.Rectangle): bool =
  ## Check if mouse is within rectangle bounds
  let mousePos = rl.getMousePosition()
  return rl.checkCollisionPointRec(mousePos, rect)

proc isMouseInTextArea*(bounds: rl.Rectangle, padding: float32 = 0.0): bool =
  ## Check if mouse is in a text editing area
  let expandedBounds = rl.Rectangle(
    x: bounds.x - padding,
    y: bounds.y - padding,
    width: bounds.width + (padding * 2),
    height: bounds.height + (padding * 2)
  )
  return isMouseInRect(expandedBounds)