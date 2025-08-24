# Terminal Subsystem Refactoring and Cleanup

## Overview

This document outlines the comprehensive refactoring and cleanup plan for the Folx Editor terminal subsystem. The goal is to create a robust, maintainable, and high-performance terminal integration that eliminates technical debt and architectural issues.

## Current Issues Identified

### 1. **Architectural Problems**
- **Disabled Integration**: Terminal is currently disabled in main.nim due to compilation issues
- **Responsibility Overlap**: Terminal logic scattered across multiple components
- **Tight Coupling**: UI components tightly coupled with business logic
- **Missing Abstractions**: No clear separation between view, model, and controller layers

### 2. **Missing Components**
- **Dedicated Buffer**: Terminal buffer logic mixed in shared types
- **Dedicated View**: No pure rendering component
- **Dedicated Input**: Input handling scattered across components
- **Error Handling**: Limited error recovery and logging

### 3. **Performance Issues**
- **No Text Caching**: Inefficient text rendering
- **Memory Leaks**: Potential issues with texture cleanup
- **Blocking I/O**: Shell process I/O could block main thread
- **Large Buffer Growth**: No efficient buffer trimming

### 4. **Code Quality Issues**
- **Dead Code**: Redundant or obsolete implementations
- **Complex Dependencies**: Circular dependencies between components
- **Poor Documentation**: Limited inline documentation
- **Inconsistent Patterns**: Mixed coding patterns and styles

## Refactoring Plan

### Phase 1: Core Infrastructure (Week 1)

#### 1.1 Terminal Buffer Modernization
- [x] Create `src/infrastructure/terminal/terminal_buffer.nim`
  - High-performance line management
  - Memory optimization with configurable limits
  - Search functionality with highlighting
  - Command history with persistence
  - Export capabilities (text/HTML)
  - Comprehensive statistics tracking

#### 1.2 Terminal View Component
- [x] Create `src/components/terminal/terminal_view.nim`
  - Pure rendering component
  - Advanced text caching system
  - Smooth scrolling animations
  - Multiple cursor styles
  - Selection and search highlighting
  - Configurable themes and styling

#### 1.3 Terminal Input Handler
- [x] Create `src/components/terminal/terminal_input.nim`
  - Comprehensive keyboard handling
  - Mouse selection support
  - IME (Input Method Editor) support
  - Auto-completion system
  - Command history navigation
  - Configurable key bindings

### Phase 2: Integration and Services (Week 2)

#### 2.1 Service Layer Cleanup
- [ ] Refactor `terminal_service.nim`
  - Remove UI dependencies
  - Focus on session management
  - Improve error handling
  - Add service health monitoring

#### 2.2 Terminal Integration Modernization
- [ ] Update `terminal_integration.nim`
  - Use new dedicated components
  - Implement proper event routing
  - Add configuration validation
  - Improve resource cleanup

#### 2.3 Process Management Enhancement
- [ ] Enhance `shell_process.nim`
  - Add process health monitoring
  - Implement graceful shutdown
  - Add cross-platform PTY support
  - Improve error recovery

### Phase 3: UI and UX Improvements (Week 3)

#### 3.1 Terminal Panel Modernization
- [ ] Refactor `terminal_panel.nim`
  - Use new view and input components
  - Simplify rendering logic
  - Add accessibility features
  - Improve responsive design

#### 3.2 Drag-to-Resize Enhancement
- [ ] Improve drag interaction
  - Smooth animation curves
  - Better touch/gesture support
  - Configurable resistance
  - Visual feedback improvements

#### 3.3 Theme Integration
- [ ] Enhanced theme support
  - Dynamic color schemes
  - High contrast mode
  - User-customizable themes
  - Import/export theme configs

### Phase 4: Performance and Testing (Week 4)

#### 4.1 Performance Optimization
- [ ] Text rendering optimization
- [ ] Memory usage profiling
- [ ] I/O performance tuning
- [ ] Background processing

#### 4.2 Testing Infrastructure
- [ ] Unit tests for all components
- [ ] Integration tests
- [ ] Performance benchmarks
- [ ] Memory leak detection

## Cleanup Tasks

### Immediate Actions

1. **Remove Dead Code**
   ```bash
   # Remove obsolete terminal examples
   rm -f examples/terminal_*_old.nim
   
   # Clean up unused imports
   grep -r "import.*terminal" src/ | grep -v "# Used"
   ```

2. **Fix Import Dependencies**
   ```nim
   # Standardize imports across terminal files
   import std/[strutils, times, tables]
   import raylib as rl
   import ../../shared/types
   ```

3. **Consolidate Error Handling**
   ```nim
   # Create centralized error types
   # src/terminal/core/terminal_errors.nim
   type
     TerminalErrorCode* = enum
       tecNone
       tecProcessSpawn
       tecProcessIO
       tecResourceCleanup
       tecIOEvent
   ```

### Architectural Improvements

#### 1. **Separation of Concerns**

```nim
# Clear component responsibilities:

# TerminalBuffer: Data management only
# - Line storage and manipulation
# - Search and history
# - Memory management

# TerminalView: Pure rendering
# - Text display and styling
# - Cursor and selection rendering
# - Smooth scrolling

# TerminalInput: Input processing
# - Keyboard event handling
# - Mouse interaction
# - Command completion

# TerminalService: Business logic
# - Session management
# - Process coordination
# - Event routing
```

#### 2. **Event-Driven Architecture**

```nim
# Implement proper event system
type
  TerminalEvent* = object
    eventType*: TerminalEventType
    source*: string
    data*: JsonNode
    timestamp*: float

# Components communicate via events only
proc emitEvent*(event: TerminalEvent)
proc subscribeToEvents*(handler: EventHandler)
```

#### 3. **Configuration Management**

```nim
# Centralized configuration
type
  TerminalConfig* = object
    buffer*: TerminalBufferConfig
    view*: TerminalViewConfig
    input*: TerminalInputConfig
    service*: TerminalServiceConfig

# Configuration validation and defaults
proc validateConfig*(config: TerminalConfig): Result[void, string]
```

### Performance Optimizations

#### 1. **Text Rendering Cache**

```nim
# Implement efficient text caching
type
  TextCache* = object
    textures*: Table[string, RenderTexture2D]
    lastUsed*: Table[string, float]
    maxSize*: int

proc getCachedText*(cache: TextCache, text: string): RenderTexture2D
proc cleanupCache*(cache: TextCache)
```

#### 2. **Memory Management**

```nim
# Smart buffer management
proc autoCleanup*(buffer: TerminalBuffer)
  if buffer.shouldCleanup():
    let removed = buffer.cleanup()
    echo &"Cleaned up {removed} old lines"

# Resource pooling for frequent allocations
type
  ResourcePool*[T] = object
    available*: seq[T]
    inUse*: HashSet[T]
    factory*: proc(): T
```

#### 3. **Asynchronous I/O**

```nim
# Non-blocking process I/O
import std/asyncdispatch

proc readOutputAsync*(process: ShellProcess): Future[string] {.async.}
proc writeInputAsync*(process: ShellProcess, data: string): Future[bool] {.async.}
```

## Implementation Steps

### Step 1: Update Main Integration

```nim
# In src/main.nim, replace disabled terminal code:

proc initializeTerminal*(app: EditorApp): bool =
  try:
    let config = loadTerminalConfig("terminal_config.json")
    app.terminalIntegration = newTerminalIntegration(config)
    
    if not app.terminalIntegration.initialize():
      logError("Failed to initialize terminal integration")
      return false
    
    echo "✓ Terminal integration initialized"
    return true
  except Exception as e:
    logError(&"Terminal initialization error: {e.msg}")
    return false
```

### Step 2: Create Component Factory

```nim
# src/components/terminal/terminal_factory.nim

proc createTerminalComponents*(
  bounds: Rectangle,
  font: ptr Font,
  renderer: Renderer,
  config: TerminalConfig
): tuple[buffer: TerminalBuffer, view: TerminalView, input: TerminalInput] =
  
  let buffer = newTerminalBuffer(config.buffer)
  let view = newTerminalView(bounds, font, renderer, nil, config.view)
  let input = newTerminalInput(buffer, config.input)
  
  # Wire up events
  view.setBuffer(buffer)
  input.setBuffer(buffer)
  
  return (buffer, view, input)
```

### Step 3: Update Service Integration

```nim
# Enhanced service integration

proc createTerminalService*(config: TerminalServiceConfig): TerminalService =
  let service = newTerminalService(config)
  
  # Set up event routing
  service.setEventCallback(proc(event: TerminalEvent) =
    case event.eventType:
    of teOutputReceived:
      # Route to appropriate view
      routeOutputToView(event)
    of teSessionClosed:
      # Clean up resources
      cleanupSession(event.sessionId)
    else:
      discard
  )
  
  return service
```

## Testing Strategy

### Unit Tests

```nim
# tests/test_terminal_buffer.nim
suite "Terminal Buffer Tests":
  test "Line management":
    let buffer = newTerminalBuffer(defaultBufferConfig())
    buffer.addLine("test line", @[])
    check buffer.getLineCount() == 1
    check buffer.getLine(0).text == "test line"

  test "Memory cleanup":
    let config = TerminalBufferConfig(maxLines: 10, autoCleanup: true)
    let buffer = newTerminalBuffer(config)
    
    # Add more lines than limit
    for i in 0..<15:
      buffer.addLine($i, @[])
    
    check buffer.getLineCount() <= 10
```

### Integration Tests

```nim
# tests/test_terminal_integration.nim
suite "Terminal Integration Tests":
  test "Component communication":
    let components = createTerminalComponents(...)
    
    # Test event flow
    components.input.handleTextInput("test")
    # Should propagate to buffer and trigger view update
    
  test "Session lifecycle":
    let service = createTerminalService(...)
    let session = service.createSession("test")
    
    check session.id > 0
    check service.getSessionCount() == 1
    
    service.closeSession(session.id)
    check service.getSessionCount() == 0
```

### Performance Tests

```nim
# tests/test_terminal_performance.nim
suite "Terminal Performance Tests":
  test "Buffer performance with large data":
    let buffer = newTerminalBuffer(defaultBufferConfig())
    let startTime = getTime()
    
    for i in 0..<10000:
      buffer.addLine(&"Line {i} with some content", @[])
    
    let duration = getTime() - startTime
    check duration.inMilliseconds < 1000  # Should complete in < 1s
  
  test "Rendering performance":
    # Test text cache efficiency
    # Test large buffer rendering
    # Test smooth scrolling performance
```

## Monitoring and Maintenance

### Performance Monitoring

```nim
# Built-in performance monitoring
type
  TerminalMetrics* = object
    renderTime*: float
    inputLatency*: float
    memoryUsage*: int
    activeSessions*: int
    bufferSize*: int

proc getMetrics*(): TerminalMetrics
proc logMetrics*(metrics: TerminalMetrics)
```

### Health Checks

```nim
# System health monitoring
proc checkTerminalHealth*(): HealthStatus =
  var issues: seq[string] = @[]
  
  # Check memory usage
  if getCurrentMemoryUsage() > maxMemoryThreshold:
    issues.add("High memory usage")
  
  # Check process health
  for session in getAllSessions():
    if not session.process.isHealthy():
      issues.add(&"Unhealthy session: {session.id}")
  
  return if issues.len == 0: hsHealthy else: hsWarning
```

### Automated Cleanup

```nim
# Scheduled maintenance tasks
proc scheduleMaintenance*() =
  # Run every 5 minutes
  setInterval(300_000, proc() =
    cleanupTerminalCaches()
    optimizeBufferMemory()
    validateSessionHealth()
  )
```

## Migration Guide

### For Existing Code

1. **Update Imports**
   ```nim
   # Old
   import components/terminal_panel
   
   # New
   import components/terminal/terminal_view
   import components/terminal/terminal_input
   import infrastructure/terminal/terminal_buffer
   ```

2. **Replace Component Usage**
   ```nim
   # Old
   let panel = newTerminalPanel(...)
   
   # New
   let (buffer, view, input) = createTerminalComponents(...)
   ```

3. **Update Event Handling**
   ```nim
   # Old
   panel.handleKeyInput(key)
   
   # New
   if not input.handleKeyInput(key):
     # Fallback handling
   ```

## Success Metrics

### Technical Metrics
- [ ] 100% test coverage for core components
- [ ] < 100ms terminal startup time
- [ ] < 16ms average render time (60 FPS)
- [ ] < 10MB memory usage for 10,000 lines
- [ ] Zero memory leaks in 24h stress test

### User Experience Metrics
- [ ] Smooth drag-to-resize (no frame drops)
- [ ] Instant command history navigation
- [ ] Responsive auto-completion (< 50ms)
- [ ] Reliable session management
- [ ] Cross-platform compatibility

### Code Quality Metrics
- [ ] Zero circular dependencies
- [ ] < 15 cyclomatic complexity per function
- [ ] 90%+ documentation coverage
- [ ] All TODO items resolved
- [ ] Consistent code style across components

## Timeline

| Week | Focus Area | Deliverables |
|------|------------|--------------|
| 1 | Core Infrastructure | New buffer, view, input components |
| 2 | Service Integration | Updated services and integration |
| 3 | UI/UX Improvements | Enhanced panel and interactions |
| 4 | Testing & Polish | Complete test suite and optimizations |

## Conclusion

This refactoring plan addresses all identified issues in the terminal subsystem while maintaining backward compatibility where possible. The new architecture provides clear separation of concerns, improved performance, and better maintainability.

The modular design allows for incremental implementation and testing, reducing risk while delivering immediate benefits. Once complete, the terminal subsystem will be a robust, efficient, and maintainable component that serves as a model for other parts of the Folx Editor.