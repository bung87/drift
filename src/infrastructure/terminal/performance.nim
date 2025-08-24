## Terminal Performance Optimization
## Utilities for memory management, rendering optimization, and performance monitoring

import std/[times, tables, deques, math, os]
import raylib as rl
import ../../shared/types

type
  PerformanceMetrics* = object
    frameTime*: float
    renderTime*: float
    updateTime*: float
    memoryUsage*: int
    bufferSize*: int
    lineCount*: int
    outputRate*: float  # Lines per second
    inputLatency*: float
    lastUpdateTime*: float

  RenderCache* = object
    texture*: rl.RenderTexture2D
    isDirty*: bool
    lastUsed*: float
    bounds*: rl.Rectangle
    lineRange*: tuple[start: int, count: int]

  MemoryManager* = ref object
    maxBufferSize*: int
    maxLineLength*: int
    maxRenderCaches*: int
    cleanupThreshold*: float
    lastCleanup*: float
    cleanupInterval*: float
    totalMemoryUsed*: int

  RenderOptimizer* = ref object
    renderCaches*: Table[string, RenderCache]
    texturePool*: seq[rl.RenderTexture2D]
    viewportCulling*: bool
    partialRedraws*: bool
    batchRendering*: bool
    cacheExpiry*: float
    memoryManager*: MemoryManager

  PerformanceProfiler* = ref object
    metrics*: PerformanceMetrics
    frameHistory*: Deque[float]
    renderHistory*: Deque[float]
    memoryHistory*: Deque[int]
    maxHistorySize*: int
    profilingEnabled*: bool
    startTime*: float

  TextureCache* = object
    texture*: rl.Texture2D
    text*: string
    font*: rl.Font
    fontSize*: float32
    color*: rl.Color
    createdTime*: float
    accessCount*: int

  PerformanceSettings* = object
    enableMemoryLimits*: bool
    enableRenderCaching*: bool
    enableViewportCulling*: bool
    enableProfiling*: bool
    maxBufferLines*: int
    maxLineLength*: int
    renderCacheSize*: int
    cleanupInterval*: float
    textCacheSize*: int
    textCacheExpiry*: float

# Default performance settings
proc defaultPerformanceSettings*(): PerformanceSettings =
  PerformanceSettings(
    enableMemoryLimits: true,
    enableRenderCaching: true,
    enableViewportCulling: true,
    enableProfiling: false,
    maxBufferLines: 10000,
    maxLineLength: 10000,
    renderCacheSize: 50,
    cleanupInterval: 30.0,  # 30 seconds
    textCacheSize: 1000,
    textCacheExpiry: 60.0   # 1 minute
  )

# Memory Manager
proc newMemoryManager*(settings: PerformanceSettings): MemoryManager =
  MemoryManager(
    maxBufferSize: settings.maxBufferLines,
    maxLineLength: settings.maxLineLength,
    maxRenderCaches: settings.renderCacheSize,
    cleanupThreshold: 0.8,  # Clean up when 80% full
    lastCleanup: times.getTime().toUnixFloat(),
    cleanupInterval: settings.cleanupInterval,
    totalMemoryUsed: 0
  )

proc estimateLineMemory*(line: TerminalLine): int =
  ## Estimate memory usage of a terminal line
  result = line.text.len * sizeof(char)
  result += line.styles.len * sizeof(TerminalTextStyle)
  result += sizeof(TerminalLine)

proc shouldCleanup*(manager: MemoryManager): bool =
  let currentTime = times.getTime().toUnixFloat()
  result = (currentTime - manager.lastCleanup) >= manager.cleanupInterval

proc cleanupBuffer*(manager: MemoryManager, buffer: TerminalBuffer): int =
  ## Clean up old lines from buffer, returns number of lines removed
  if buffer.lines.len <= manager.maxBufferSize:
    return 0
  
  let linesToRemove = buffer.lines.len - int(float(manager.maxBufferSize) * manager.cleanupThreshold)
  if linesToRemove > 0:
    for i in 0..<linesToRemove:
      manager.totalMemoryUsed -= estimateLineMemory(buffer.lines[0])
      buffer.lines.delete(0)
    
    buffer.currentLine = max(0, buffer.currentLine - linesToRemove)
    manager.lastCleanup = times.getTime().toUnixFloat()
    return linesToRemove
  
  return 0

proc enforceLineLengthLimit*(manager: MemoryManager, line: var TerminalLine) =
  ## Enforce maximum line length limit
  if line.text.len > manager.maxLineLength:
    line.text = line.text[0..<manager.maxLineLength] & "..."
    
    # Adjust styles to fit truncated text
    for i in countdown(line.styles.len - 1, 0):
      if line.styles[i].startPos >= line.text.len:
        line.styles.delete(i)
      elif line.styles[i].endPos > line.text.len:
        line.styles[i].endPos = line.text.len

# Render Optimizer
proc newRenderOptimizer*(settings: PerformanceSettings): RenderOptimizer =
  RenderOptimizer(
    renderCaches: initTable[string, RenderCache](),
    texturePool: @[],
    viewportCulling: settings.enableViewportCulling,
    partialRedraws: settings.enableRenderCaching,
    batchRendering: true,
    cacheExpiry: 300.0,  # 5 minutes
    memoryManager: newMemoryManager(settings)
  )

proc getTextureFromPool*(optimizer: RenderOptimizer, width: int, height: int): rl.RenderTexture2D =
  ## Get a render texture from the pool or create a new one
  for i in countdown(optimizer.texturePool.len - 1, 0):
    let texture = optimizer.texturePool[i]
    if texture.texture.width == width and texture.texture.height == height:
      result = texture
      optimizer.texturePool.delete(i)
      return
  
  # Create new texture if none available in pool
  result = rl.loadRenderTexture(width, height)

proc returnTextureToPool*(optimizer: RenderOptimizer, texture: rl.RenderTexture2D) =
  ## Return a render texture to the pool
  if optimizer.texturePool.len < optimizer.memoryManager.maxRenderCaches:
    optimizer.texturePool.add(texture)
  else:
    rl.unloadRenderTexture(texture)

proc getCacheKey*(bounds: rl.Rectangle, lineStart: int, lineCount: int): string =
  ## Generate cache key for render cache
  &"cache_{bounds.x}_{bounds.y}_{bounds.width}_{bounds.height}_{lineStart}_{lineCount}"

proc shouldCullLine*(lineY: float32, lineHeight: float32, viewport: rl.Rectangle): bool =
  ## Check if a line should be culled from rendering
  lineY + lineHeight < viewport.y or lineY > viewport.y + viewport.height

proc cleanupRenderCaches*(optimizer: RenderOptimizer) =
  ## Clean up expired render caches
  let currentTime = times.getTime().toUnixFloat()
  var keysToRemove: seq[string] = @[]
  
  for key, cache in optimizer.renderCaches.pairs:
    if currentTime - cache.lastUsed > optimizer.cacheExpiry:
      keysToRemove.add(key)
  
  for key in keysToRemove:
    let cache = optimizer.renderCaches[key]
    optimizer.returnTextureToPool(cache.texture)
    optimizer.renderCaches.del(key)

proc invalidateCache*(optimizer: RenderOptimizer, key: string) =
  ## Mark a render cache as dirty
  if key in optimizer.renderCaches:
    optimizer.renderCaches[key].isDirty = true

proc invalidateAllCaches*(optimizer: RenderOptimizer) =
  ## Mark all render caches as dirty
  for key in optimizer.renderCaches.keys:
    optimizer.renderCaches[key].isDirty = true

# Performance Profiler
proc newPerformanceProfiler*(maxHistorySize: int = 1000): PerformanceProfiler =
  PerformanceProfiler(
    metrics: PerformanceMetrics(),
    frameHistory: initDeque[float](),
    renderHistory: initDeque[float](),
    memoryHistory: initDeque[int](),
    maxHistorySize: maxHistorySize,
    profilingEnabled: false,
    startTime: times.getTime().toUnixFloat()
  )

proc startFrame*(profiler: PerformanceProfiler) =
  ## Mark the start of a frame for profiling
  if not profiler.profilingEnabled:
    return
  profiler.metrics.lastUpdateTime = times.getTime().toUnixFloat()

proc endFrame*(profiler: PerformanceProfiler) =
  ## Mark the end of a frame and update metrics
  if not profiler.profilingEnabled:
    return
  
  let currentTime = times.getTime().toUnixFloat()
  profiler.metrics.frameTime = currentTime - profiler.metrics.lastUpdateTime
  
  # Add to history
  profiler.frameHistory.addLast(profiler.metrics.frameTime)
  if profiler.frameHistory.len > profiler.maxHistorySize:
    discard profiler.frameHistory.popFirst()

proc markRenderStart*(profiler: PerformanceProfiler) =
  ## Mark the start of rendering
  if profiler.profilingEnabled:
    profiler.metrics.lastUpdateTime = times.getTime().toUnixFloat()

proc markRenderEnd*(profiler: PerformanceProfiler) =
  ## Mark the end of rendering
  if not profiler.profilingEnabled:
    return
  
  let currentTime = times.getTime().toUnixFloat()
  profiler.metrics.renderTime = currentTime - profiler.metrics.lastUpdateTime
  
  profiler.renderHistory.addLast(profiler.metrics.renderTime)
  if profiler.renderHistory.len > profiler.maxHistorySize:
    discard profiler.renderHistory.popFirst()

proc updateMemoryMetrics*(profiler: PerformanceProfiler, memoryUsage: int, bufferSize: int, lineCount: int) =
  ## Update memory-related metrics
  if not profiler.profilingEnabled:
    return
  
  profiler.metrics.memoryUsage = memoryUsage
  profiler.metrics.bufferSize = bufferSize
  profiler.metrics.lineCount = lineCount
  
  profiler.memoryHistory.addLast(memoryUsage)
  if profiler.memoryHistory.len > profiler.maxHistorySize:
    discard profiler.memoryHistory.popFirst()

proc calculateOutputRate*(profiler: PerformanceProfiler, newLineCount: int): float =
  ## Calculate output rate in lines per second
  if not profiler.profilingEnabled:
    return 0.0
  
  let currentTime = times.getTime().toUnixFloat()
  let timeDiff = currentTime - profiler.startTime
  
  if timeDiff > 0:
    profiler.metrics.outputRate = float(newLineCount) / timeDiff
  
  return profiler.metrics.outputRate

proc getAverageFrameTime*(profiler: PerformanceProfiler): float =
  ## Get average frame time from history
  if profiler.frameHistory.len == 0:
    return 0.0
  
  var total = 0.0
  for frameTime in profiler.frameHistory:
    total += frameTime
  
  return total / float(profiler.frameHistory.len)

proc getAverageRenderTime*(profiler: PerformanceProfiler): float =
  ## Get average render time from history
  if profiler.renderHistory.len == 0:
    return 0.0
  
  var total = 0.0
  for renderTime in profiler.renderHistory:
    total += renderTime
  
  return total / float(profiler.renderHistory.len)

proc getFPS*(profiler: PerformanceProfiler): float =
  ## Get current FPS
  let avgFrameTime = profiler.getAverageFrameTime()
  if avgFrameTime > 0:
    return 1.0 / avgFrameTime
  return 0.0

proc getPerformanceSummary*(profiler: PerformanceProfiler): string =
  ## Get a summary of performance metrics
  let fps = profiler.getFPS()
  let avgFrame = profiler.getAverageFrameTime() * 1000  # Convert to ms
  let avgRender = profiler.getAverageRenderTime() * 1000
  
  result = &"""Performance Summary:
FPS: {fps:.1f}
Avg Frame Time: {avgFrame:.2f}ms
Avg Render Time: {avgRender:.2f}ms
Memory Usage: {profiler.metrics.memoryUsage} bytes
Buffer Size: {profiler.metrics.bufferSize} lines
Output Rate: {profiler.metrics.outputRate:.1f} lines/sec"""

# Text Caching for Performance
var globalTextCache = initTable[string, TextureCache]()
var textCacheSettings = defaultPerformanceSettings()

proc generateTextCacheKey*(text: string, fontSize: float32, color: rl.Color): string =
  ## Generate cache key for text rendering
  &"text_{text.len}_{fontSize}_{color.r}_{color.g}_{color.b}_{hash(text)}"

proc getCachedTextTexture*(text: string, font: rl.Font, fontSize: float32, color: rl.Color): Option[rl.Texture2D] =
  ## Get cached text texture if available
  if not textCacheSettings.enableRenderCaching:
    return none(rl.Texture2D)
  
  let key = generateTextCacheKey(text, fontSize, color)
  if key in globalTextCache:
    var cache = globalTextCache[key]
    cache.accessCount += 1
    cache.createdTime = times.getTime().toUnixFloat()  # Update access time
    globalTextCache[key] = cache
    return some(cache.texture)
  
  return none(rl.Texture2D)

proc cacheTextTexture*(text: string, font: rl.Font, fontSize: float32, color: rl.Color, texture: rl.Texture2D) =
  ## Cache a text texture
  if not textCacheSettings.enableRenderCaching or globalTextCache.len >= textCacheSettings.textCacheSize:
    return
  
  let key = generateTextCacheKey(text, fontSize, color)
  globalTextCache[key] = TextureCache(
    texture: texture,
    text: text,
    font: font,
    fontSize: fontSize,
    color: color,
    createdTime: times.getTime().toUnixFloat(),
    accessCount: 1
  )

proc cleanupTextCache*() =
  ## Clean up expired text cache entries
  let currentTime = times.getTime().toUnixFloat()
  var keysToRemove: seq[string] = @[]
  
  for key, cache in globalTextCache.pairs:
    if currentTime - cache.createdTime > textCacheSettings.textCacheExpiry:
      keysToRemove.add(key)
  
  for key in keysToRemove:
    let cache = globalTextCache[key]
    rl.unloadTexture(cache.texture)
    globalTextCache.del(key)

# Viewport Culling
proc calculateVisibleLineRange*(viewport: rl.Rectangle, lineHeight: float32, totalLines: int, scrollOffset: int): tuple[start: int, count: int] =
  ## Calculate which lines are visible in the viewport
  let visibleLines = int(viewport.height / lineHeight) + 2  # Add buffer
  let startLine = max(0, scrollOffset)
  let endLine = min(totalLines, startLine + visibleLines)
  
  result = (start: startLine, count: endLine - startLine)

proc shouldRenderLine*(lineIndex: int, visibleRange: tuple[start: int, count: int]): bool =
  ## Check if a line should be rendered based on visible range
  lineIndex >= visibleRange.start and lineIndex < visibleRange.start + visibleRange.count

# Memory Usage Calculation
proc calculateBufferMemoryUsage*(buffer: TerminalBuffer): int =
  ## Calculate total memory usage of a terminal buffer
  result = sizeof(TerminalBuffer)
  for line in buffer.lines:
    result += estimateLineMemory(line)

proc calculateSystemMemoryUsage*(): int =
  ## Get current system memory usage (simplified)
  when defined(windows):
    # Windows memory usage (placeholder)
    result = 0
  elif defined(linux):
    try:
      let status = readFile("/proc/self/status")
      for line in status.splitLines():
        if line.startsWith("VmRSS:"):
          let parts = line.split()
          if parts.len >= 2:
            result = parseInt(parts[1]) * 1024  # Convert KB to bytes
            break
    except:
      result = 0
  else:
    # macOS and other systems (placeholder)
    result = 0

# Performance Testing Utilities
proc generateLargeOutput*(lineCount: int, lineLength: int = 80): seq[string] =
  ## Generate large output for performance testing
  result = @[]
  for i in 0..<lineCount:
    var line = &"Line {i}: "
    while line.len < lineLength:
      line.add("A")
    result.add(line)

proc measureRenderPerformance*(renderFunc: proc(), iterations: int = 100): float =
  ## Measure rendering performance over multiple iterations
  let startTime = times.getTime().toUnixFloat()
  
  for i in 0..<iterations:
    renderFunc()
  
  let endTime = times.getTime().toUnixFloat()
  return (endTime - startTime) / float(iterations)

proc measureMemoryGrowth*(testFunc: proc(), initialSize: int): tuple[growth: int, peakUsage: int] =
  ## Measure memory growth during a test function
  let initialMemory = calculateSystemMemoryUsage()
  var peakMemory = initialMemory
  
  testFunc()
  
  let finalMemory = calculateSystemMemoryUsage()
  peakMemory = max(peakMemory, finalMemory)
  
  result = (growth: finalMemory - initialMemory, peakUsage: peakMemory)

# Configuration
proc updatePerformanceSettings*(settings: PerformanceSettings) =
  ## Update global performance settings
  textCacheSettings = settings

proc getPerformanceSettings*(): PerformanceSettings =
  ## Get current performance settings
  textCacheSettings