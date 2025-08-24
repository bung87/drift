## Drag Interaction System
## Handles drag gestures for revealing/hiding the terminal panel with smooth animations

import std/[math, times]
import raylib as rl

type
  DragState* = enum
    dsIdle,          # No drag in progress
    dsTracking,      # Tracking potential drag
    dsDragging,      # Active drag in progress
    dsAnimating      # Animating to final position

  DragDirection* = enum
    ddNone,
    ddUp,
    ddDown,
    ddLeft,
    ddRight

  EasingType* = enum
    etLinear,
    etEaseOut,
    etEaseIn,
    etEaseInOut,
    etBounce,
    etSmooth,
    etSpring

  DragThreshold* = object
    distance*: float32      # Minimum distance to start drag
    velocity*: float32      # Minimum velocity to trigger action
    openThreshold*: float32 # How far to drag to keep panel open
    closeThreshold*: float32 # How far to drag to close panel

  AnimationCurve* = object
    duration*: float32
    easingType*: EasingType
    startValue*: float32
    endValue*: float32
    startTime*: float32

  DragEvent* = object
    eventType*: DragEventType
    position*: rl.Vector2
    delta*: rl.Vector2
    velocity*: rl.Vector2
    progress*: float32      # 0.0 to 1.0 for panel reveal progress

  DragEventType* = enum
    detDragStart,
    detDragUpdate,
    detDragEnd,
    detDragCancel,
    detAnimationComplete

  TerminalPanelDragHandler* = ref object
    # State management
    state*: DragState
    isEnabled*: bool
    isTerminalStarting*: bool
    
    # Drag properties
    startPosition*: rl.Vector2
    currentPosition*: rl.Vector2
    lastPosition*: rl.Vector2
    dragDelta*: rl.Vector2
    totalDragDistance*: rl.Vector2
    
    # Timing
    dragStartTime*: float32
    lastUpdateTime*: float32
    velocity*: rl.Vector2
    
    # Panel properties
    panelBounds*: rl.Rectangle
    statusBarBounds*: rl.Rectangle
    dragZone*: rl.Rectangle        # Area where drag can be initiated
    maxPanelHeight*: float32
    currentPanelHeight*: float32
    targetPanelHeight*: float32
    
    # Configuration
    thresholds*: DragThreshold
    animation*: AnimationCurve
    snapToPositions*: seq[float32]  # Positions to snap to (0.0, 1.0, etc.)
    
    # Callbacks
    onDragEvent*: proc(event: DragEvent) {.closure.}
    onPanelHeightChanged*: proc(height: float32, progress: float32) {.closure.}

# Default configuration
proc defaultDragThreshold*(): DragThreshold =
  DragThreshold(
    distance: 5.0,
    velocity: 50.0,
    openThreshold: 0.3,      # 30% of max height
    closeThreshold: 0.7      # 70% of max height when closing
  )

proc defaultAnimationCurve*(duration: float32 = 0.4): AnimationCurve =
  AnimationCurve(
    duration: duration,
    easingType: etEaseOut,
    startValue: 0.0,
    endValue: 0.0,
    startTime: 0.0
  )

# Constructor
proc newTerminalPanelDragHandler*(
  statusBarBounds: rl.Rectangle,
  maxPanelHeight: float32,
  thresholds: DragThreshold = defaultDragThreshold()
): TerminalPanelDragHandler =
  result = TerminalPanelDragHandler(
    state: dsIdle,
    isEnabled: true,
    isTerminalStarting: false,
    
    startPosition: rl.Vector2(x: 0, y: 0),
    currentPosition: rl.Vector2(x: 0, y: 0),
    lastPosition: rl.Vector2(x: 0, y: 0),
    dragDelta: rl.Vector2(x: 0, y: 0),
    totalDragDistance: rl.Vector2(x: 0, y: 0),
    
    dragStartTime: 0.0,
    lastUpdateTime: 0.0,
    velocity: rl.Vector2(x: 0, y: 0),
    
    statusBarBounds: statusBarBounds,
    maxPanelHeight: maxPanelHeight,
    currentPanelHeight: 0.0,
    targetPanelHeight: 0.0,
    
    thresholds: thresholds,
    animation: defaultAnimationCurve(),
    snapToPositions: @[0.0, 1.0],  # Closed and fully open
    
    onDragEvent: nil,
    onPanelHeightChanged: nil
  )
  
  # Create drag zone that includes the status bar for easy access when terminal is hidden
  result.dragZone = rl.Rectangle(
    x: statusBarBounds.x,
    y: statusBarBounds.y - 50.0,  # 50px above status bar
    width: statusBarBounds.width,
    height: statusBarBounds.height + 60.0  # Include status bar + extra area
  )
  
  # Initialize panel bounds
  result.panelBounds = rl.Rectangle(
    x: statusBarBounds.x,
    y: statusBarBounds.y - maxPanelHeight,
    width: statusBarBounds.width,
    height: 0.0  # Start hidden
  )

# Easing functions
proc evaluateEasing*(easingType: EasingType, t: float32): float32 =
  let clampedT = clamp(t, 0.0, 1.0)
  
  case easingType:
  of etLinear:
    return clampedT
  of etEaseOut:
    return 1.0 - (1.0 - clampedT) * (1.0 - clampedT)
  of etEaseIn:
    return clampedT * clampedT
  of etEaseInOut:
    if clampedT < 0.5:
      return 2.0 * clampedT * clampedT
    else:
      return 1.0 - pow(-2.0 * clampedT + 2.0, 3.0) / 2.0
  of etSmooth:
    # Smooth cubic bezier-like curve
    return clampedT * clampedT * (3.0 - 2.0 * clampedT)
  of etSpring:
    # Spring animation with slight overshoot
    let s = 1.70158
    return clampedT * clampedT * ((s + 1.0) * clampedT - s)
  of etBounce:
    # Bounce easing implementation
    let n1 = 7.5625
    let d1 = 2.75
    var t = clampedT
    
    if t < 1.0 / d1:
      return n1 * t * t
    elif t < 2.0 / d1:
      t -= 1.5 / d1
      return n1 * t * t + 0.75
    elif t < 2.5 / d1:
      t -= 2.25 / d1
      return n1 * t * t + 0.9375
    else:
      t -= 2.625 / d1
      return n1 * t * t + 0.984375

# Animation management
proc startAnimation*(handler: TerminalPanelDragHandler, targetHeight: float32, duration: float32 = 0.25) =
  handler.state = dsAnimating
  
  # Choose easing based on animation direction and context
  let easingType = if targetHeight > handler.currentPanelHeight:
    if handler.isTerminalStarting: etSmooth else: etEaseOut
  else:
    etEaseOut
  
  handler.animation = AnimationCurve(
    duration: duration,
    easingType: easingType,
    startValue: handler.currentPanelHeight,
    endValue: targetHeight,
    startTime: times.getTime().toUnixFloat()
  )
  handler.targetPanelHeight = targetHeight

proc updateAnimation*(handler: TerminalPanelDragHandler): bool =
  if handler.state != dsAnimating:
    return false
  
  let currentTime = times.getTime().toUnixFloat()
  let elapsed = currentTime - handler.animation.startTime
  let progress = elapsed / handler.animation.duration
  
  if progress >= 1.0:
    # Animation complete
    handler.currentPanelHeight = handler.animation.endValue
    handler.state = dsIdle
    
    if handler.onPanelHeightChanged != nil:
      let heightProgress = handler.currentPanelHeight / handler.maxPanelHeight
      handler.onPanelHeightChanged(handler.currentPanelHeight, heightProgress)
    
    if handler.onDragEvent != nil:
      let event = DragEvent(
        eventType: detAnimationComplete,
        position: handler.currentPosition,
        delta: rl.Vector2(x: 0, y: 0),
        velocity: rl.Vector2(x: 0, y: 0),
        progress: handler.currentPanelHeight / handler.maxPanelHeight
      )
      handler.onDragEvent(event)
    
    return false
  else:
    # Update animation
    let easedProgress = evaluateEasing(handler.animation.easingType, progress)
    let range = handler.animation.endValue - handler.animation.startValue
    handler.currentPanelHeight = handler.animation.startValue + (range * easedProgress)
    
    if handler.onPanelHeightChanged != nil:
      let heightProgress = handler.currentPanelHeight / handler.maxPanelHeight
      handler.onPanelHeightChanged(handler.currentPanelHeight, heightProgress)
    
    return true

# Utility functions
proc calculateVelocity*(handler: TerminalPanelDragHandler): rl.Vector2 =
  let currentTime = times.getTime().toUnixFloat()
  let deltaTime = currentTime - handler.lastUpdateTime
  
  if deltaTime > 0.001:  # Avoid division by zero
    let deltaPosition = rl.Vector2(
      x: handler.currentPosition.x - handler.lastPosition.x,
      y: handler.currentPosition.y - handler.lastPosition.y
    )
    result = rl.Vector2(
      x: deltaPosition.x / deltaTime,
      y: deltaPosition.y / deltaTime
    )
  else:
    result = handler.velocity

proc isPointInDragZone*(handler: TerminalPanelDragHandler, point: rl.Vector2): bool =
  rl.checkCollisionPointRec(point, handler.dragZone)

proc getDragProgress*(handler: TerminalPanelDragHandler): float32 =
  if handler.maxPanelHeight <= 0:
    return 0.0
  return clamp(handler.currentPanelHeight / handler.maxPanelHeight, 0.0, 1.0)

proc shouldOpenPanel*(handler: TerminalPanelDragHandler): bool =
  let progress = handler.getDragProgress()
  let upwardVelocity = -handler.velocity.y  # Negative Y is upward
  
  # Open if dragged past threshold or has sufficient upward velocity
  return progress >= handler.thresholds.openThreshold or 
         (upwardVelocity > handler.thresholds.velocity and progress > 0.1)

proc shouldClosePanel*(handler: TerminalPanelDragHandler): bool =
  let progress = handler.getDragProgress()
  let downwardVelocity = handler.velocity.y  # Positive Y is downward
  
  # Close if dragged below threshold or has sufficient downward velocity
  return progress <= (1.0 - handler.thresholds.closeThreshold) or
         (downwardVelocity > handler.thresholds.velocity and progress < 0.9)

# Main interaction handling
proc handleMouseDown*(handler: TerminalPanelDragHandler, mousePos: rl.Vector2): bool =
  if not handler.isEnabled:
    return false
  
  # Allow drag even during animation for responsive feel
  if handler.state == dsAnimating:
    handler.state = dsIdle  # Stop animation to allow manual control
  
  if handler.isPointInDragZone(mousePos):
    handler.state = dsTracking
    handler.startPosition = mousePos
    handler.currentPosition = mousePos
    handler.lastPosition = mousePos
    handler.dragStartTime = times.getTime().toUnixFloat()
    handler.lastUpdateTime = handler.dragStartTime
    handler.totalDragDistance = rl.Vector2(x: 0, y: 0)
    handler.velocity = rl.Vector2(x: 0, y: 0)
    
    return true
  
  return false

proc handleMouseMove*(handler: TerminalPanelDragHandler, mousePos: rl.Vector2): bool =
  if not handler.isEnabled:
    return false
  
  let currentTime = times.getTime().toUnixFloat()
  handler.lastPosition = handler.currentPosition
  handler.currentPosition = mousePos
  handler.lastUpdateTime = currentTime
  
  case handler.state:
  of dsTracking:
    # Check if we've moved enough to start dragging
    let distance = sqrt(
      pow(mousePos.x - handler.startPosition.x, 2) +
      pow(mousePos.y - handler.startPosition.y, 2)
    )
    
    if distance >= handler.thresholds.distance:
      handler.state = dsDragging
      handler.totalDragDistance = rl.Vector2(
        x: mousePos.x - handler.startPosition.x,
        y: mousePos.y - handler.startPosition.y
      )
      
      if handler.onDragEvent != nil:
        let event = DragEvent(
          eventType: detDragStart,
          position: mousePos,
          delta: rl.Vector2(x: 0, y: 0),
          velocity: rl.Vector2(x: 0, y: 0),
          progress: handler.getDragProgress()
        )
        handler.onDragEvent(event)
      
      return true
  
  of dsDragging:
    # Update drag
    handler.dragDelta = rl.Vector2(
      x: mousePos.x - handler.lastPosition.x,
      y: mousePos.y - handler.lastPosition.y
    )
    handler.totalDragDistance = rl.Vector2(
      x: mousePos.x - handler.startPosition.x,
      y: mousePos.y - handler.startPosition.y
    )
    handler.velocity = handler.calculateVelocity()
    
    # Update panel height based on drag distance
    # Negative Y movement (upward) increases panel height
    let dragAmount = -handler.totalDragDistance.y
    let newHeight = clamp(dragAmount, 0.0, handler.maxPanelHeight)
    
    if newHeight != handler.currentPanelHeight:
      handler.currentPanelHeight = newHeight
      
      if handler.onPanelHeightChanged != nil:
        let progress = handler.getDragProgress()
        handler.onPanelHeightChanged(handler.currentPanelHeight, progress)
      
      if handler.onDragEvent != nil:
        let event = DragEvent(
          eventType: detDragUpdate,
          position: mousePos,
          delta: handler.dragDelta,
          velocity: handler.velocity,
          progress: handler.getDragProgress()
        )
        handler.onDragEvent(event)
    
    return true
  
  else:
    return false

proc handleMouseUp*(handler: TerminalPanelDragHandler, mousePos: rl.Vector2): bool =
  if not handler.isEnabled:
    return false
  
  let wasTracking = handler.state == dsTracking
  let wasDragging = handler.state == dsDragging
  
  if wasTracking or wasDragging:
    handler.velocity = handler.calculateVelocity()
    
    if wasDragging:
      # Determine final state based on position and velocity
      let targetHeight = if handler.shouldOpenPanel():
                          handler.maxPanelHeight
                        elif handler.shouldClosePanel():
                          0.0
                        else:
                          # Snap to nearest position
                          let progress = handler.getDragProgress()
                          if progress > 0.5: handler.maxPanelHeight else: 0.0
      
      # Animate to final position
      handler.startAnimation(targetHeight)
      
      if handler.onDragEvent != nil:
        let event = DragEvent(
          eventType: detDragEnd,
          position: mousePos,
          delta: rl.Vector2(x: 0, y: 0),
          velocity: handler.velocity,
          progress: handler.getDragProgress()
        )
        handler.onDragEvent(event)
    else:
      # Was just tracking, cancel
      handler.state = dsIdle
      
      if handler.onDragEvent != nil:
        let event = DragEvent(
          eventType: detDragCancel,
          position: mousePos,
          delta: rl.Vector2(x: 0, y: 0),
          velocity: rl.Vector2(x: 0, y: 0),
          progress: handler.getDragProgress()
        )
        handler.onDragEvent(event)
    
    return true
  
  return false

proc update*(handler: TerminalPanelDragHandler) =
  if not handler.isEnabled:
    return
  
  # Update animation if active
  discard handler.updateAnimation()
  
  # Update panel bounds based on current height
  handler.panelBounds.height = handler.currentPanelHeight
  handler.panelBounds.y = handler.statusBarBounds.y - handler.currentPanelHeight

# Configuration methods
proc setMaxPanelHeight*(handler: TerminalPanelDragHandler, height: float32) =
  handler.maxPanelHeight = height
  # Clamp current height to new maximum
  if handler.currentPanelHeight > height:
    handler.currentPanelHeight = height

proc setStatusBarBounds*(handler: TerminalPanelDragHandler, bounds: rl.Rectangle) =
  handler.statusBarBounds = bounds
  
  # Update drag zone to follow status bar and ensure it's always accessible
  handler.dragZone = rl.Rectangle(
    x: bounds.x,
    y: bounds.y - 50.0,  # 50px above status bar
    width: bounds.width,
    height: bounds.height + 60.0  # Include status bar + extra area
  )
  
  # Update panel bounds
  handler.panelBounds.x = bounds.x
  handler.panelBounds.width = bounds.width
  handler.panelBounds.y = bounds.y - handler.currentPanelHeight

proc setEnabled*(handler: TerminalPanelDragHandler, enabled: bool) =
  if not enabled and handler.state in [dsTracking, dsDragging]:
    # Cancel any active drag
    handler.state = dsIdle
  handler.isEnabled = enabled

# Immediate panel control (without animation)
proc setPanelHeight*(handler: TerminalPanelDragHandler, height: float32) =
  handler.currentPanelHeight = clamp(height, 0.0, handler.maxPanelHeight)
  handler.targetPanelHeight = handler.currentPanelHeight
  
  if handler.onPanelHeightChanged != nil:
    let progress = handler.getDragProgress()
    handler.onPanelHeightChanged(handler.currentPanelHeight, progress)

proc showPanel*(handler: TerminalPanelDragHandler, animated: bool = true) =
  handler.isTerminalStarting = true  # Mark as starting for smoother animation
  if animated:
    # Immediately set a non-zero height so isOpen() returns true
    handler.currentPanelHeight = handler.maxPanelHeight * 0.1  # Set to 10% of max height
    handler.startAnimation(handler.maxPanelHeight, 0.3)
  else:
    handler.setPanelHeight(handler.maxPanelHeight)

proc hidePanel*(handler: TerminalPanelDragHandler, animated: bool = true) =
  handler.isTerminalStarting = false
  if animated:
    handler.startAnimation(0.0, 0.25)
  else:
    handler.setPanelHeight(0.0)

proc togglePanel*(handler: TerminalPanelDragHandler, animated: bool = true) =
  let isOpen = handler.currentPanelHeight > handler.maxPanelHeight * 0.4
  if isOpen:
    handler.hidePanel(animated)
  else:
    handler.showPanel(animated)

proc setTerminalStarting*(handler: TerminalPanelDragHandler, starting: bool) =
  ## Set whether terminal is currently starting up
  handler.isTerminalStarting = starting

# State queries
proc isOpen*(handler: TerminalPanelDragHandler): bool =
  handler.currentPanelHeight > 0.0

proc isFullyOpen*(handler: TerminalPanelDragHandler): bool =
  abs(handler.currentPanelHeight - handler.maxPanelHeight) < 1.0

proc isClosed*(handler: TerminalPanelDragHandler): bool =
  handler.currentPanelHeight <= 0.0

proc isDragging*(handler: TerminalPanelDragHandler): bool =
  handler.state == dsDragging

proc isAnimating*(handler: TerminalPanelDragHandler): bool =
  handler.state == dsAnimating

# Debug rendering
proc renderDebugInfo*(handler: TerminalPanelDragHandler) =
  when defined(debug):
    # Draw drag zone
    rl.drawRectangleLines(int32(handler.dragZone.x), int32(handler.dragZone.y), int32(handler.dragZone.width), int32(handler.dragZone.height), rl.RED)
    
    # Draw panel bounds
    if handler.currentPanelHeight > 0:
      rl.drawRectangleLines(int32(handler.panelBounds.x), int32(handler.panelBounds.y), int32(handler.panelBounds.width), int32(handler.panelBounds.height), rl.GREEN)
    
    # Draw state info
    let stateText = case handler.state:
                    of dsIdle: "IDLE"
                    of dsTracking: "TRACKING" 
                    of dsDragging: "DRAGGING"
                    of dsAnimating: "ANIMATING"
    
    rl.drawText(stateText, 10'i32, 10'i32, 12'i32, rl.WHITE)
    
    # Draw progress
    let progressText = "Progress: " & $int(handler.getDragProgress() * 100) & "%"
    rl.drawText(progressText, 10'i32, 25'i32, 12'i32, rl.WHITE)