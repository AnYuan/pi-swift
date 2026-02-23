# `pi-tui` Module Notes

## Status

- `P4-1` is in progress.
- This document tracks verified incremental slices before `P4-1` is marked `DONE` in `/Users/anyuan/Development/pi-swift/docs/PLAN.md`.

## Implemented (P4-1 foundation slice)

### Terminal Abstraction (test-oriented)

- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUITerminal.swift`
- Introduced `PiTUITerminal` protocol for:
  - lifecycle (`start` / `stop`)
  - viewport dimensions (`columns` / `rows`)
  - cursor visibility (`hideCursor` / `showCursor`)
  - screen mutations (`clearScreen`, `writeLine`, `clearLine`)
- Added `PiTUIVirtualTerminal` for deterministic tests and operation logging.
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIANSITerminal.swift`
  - writer-based ANSI/VT terminal adapter that translates row writes/clears into escape sequences
  - test hooks for input simulation and resize callbacks (supports unit testing without a real process terminal)

### Render Buffer + Differential Plan

- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIRenderBuffer.swift`
- Introduced a render-state buffer that tracks:
  - `previousLines`
  - `previousWidth`
  - `maxLinesRendered`
- Supports:
  - first-render full redraw
  - width-change full redraw
  - `clearOnShrink` full redraw
  - differential row edits + extra-row clearing

### Minimal Core TUI Render Loop

- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/TUI.swift`
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIComponent.swift`
- Current `PiTUI` foundation supports:
  - child component composition (`render(width:)`)
  - `start()` / `stop()`
  - sync `requestRender(force:)`
  - `clearOnShrink` toggle
  - `fullRedraws` counter (regression observability)

## Verified Regression Coverage (current slice)

- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIDifferentialRenderingTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIANSITerminalTests.swift`
- Covered scenarios (derived from `../pi-mono/packages/tui/test/tui-render.test.ts`):
  - width change triggers full redraw
  - content shrink clears stale rows when `clearOnShrink` is enabled
  - differential rendering updates only a changed middle line
  - content -> empty -> content transition
  - shrink then later line change still targets correct row
  - only first line changes
  - only last line changes
  - multiple non-adjacent lines change
- ANSI terminal adapter coverage:
  - hide/show cursor VT sequences
  - clear screen VT sequence
  - row-targeted line write + clear + truncation
  - resize/input callback plumbing
  - out-of-bounds row no-op safety

## Not Yet Implemented in `P4-1`

- ANSI/VT sequence renderer and real process terminal integration
- cursor-position tracking / hardware cursor placement
- synchronized output batching
- style reset handling between lines
- overlay composition and viewport-aware diff behavior
- overflow/visible-width handling parity with ANSI-aware width functions

These remain in scope for subsequent `P4-1` slices before the task is marked complete.
