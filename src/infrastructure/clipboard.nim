## Unified clipboard service for Drift editor
## Provides clipboard abstraction without direct Raylib dependencies

import raylib as rl

## Clipboard service for cross-platform clipboard operations

type ClipboardService* = ref object
  ## Service for managing clipboard operations

proc newClipboardService*(): ClipboardService =
  ## Create a new clipboard service instance
  ClipboardService()

proc setText*(service: ClipboardService, text: string) =
  ## Set text to clipboard
  rl.setClipboardText(text)

proc getText*(service: ClipboardService): string =
  ## Get text from clipboard
  try:
    return $rl.getClipboardText()
  except:
    return ""

proc hasText*(service: ClipboardService): bool =
  ## Check if clipboard has text content
  try:
    let text = $rl.getClipboardText()
    return text.len > 0
  except:
    return false