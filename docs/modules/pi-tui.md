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
  - Virtual terminal now uses the same ANSI-safe line sanitization semantics as the TUI/ANSI terminal path.
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIANSITerminal.swift`
  - writer-based ANSI/VT terminal adapter that translates row writes/clears into escape sequences
  - test hooks for input simulation and resize callbacks (supports unit testing without a real process terminal)
  - synchronized output begin/end markers (`CSI ?2026 h/l`)
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIANSIText.swift`
  - ANSI-aware visible-width calculation (CSI + OSC hyperlink sequence skipping)
  - display-width handling for wide characters (CJK/emoji ranges) and zero-width scalars (combining marks / ZWJ / variation selectors)
  - ANSI-safe visible-width truncation (preserves escape sequences)
  - line-end reset helper to prevent style leakage across terminal rows
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIProcessTerminal.swift`
  - host-based process terminal scaffold (`PiTUITerminalHost` + `PiTUIProcessTerminal`)
  - delegates ANSI rendering to `PiTUIANSITerminal`
  - bridges host input/resize callbacks into `PiTUI` terminal interface
  - includes minimal `PiTUIStandardIOHost` stdout-backed implementation (stdin/raw-mode/signal wiring deferred)

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
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIRenderScheduler.swift`
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUIComponent.swift`
- Added `/Users/anyuan/Development/pi-swift/Sources/PiTUI/PiTUICursor.swift`
- Current `PiTUI` foundation supports:
  - child component composition (`render(width:)`)
  - `start()` / `stop()`
  - `requestRender(force:)` with scheduler-driven coalescing (default immediate scheduler)
  - test-only/manual scheduler for deterministic render queue flushing
  - scheduler-generation isolation so stale pending renders are ignored across `stop()` / restart boundaries
  - `clearOnShrink` toggle
  - `fullRedraws` counter (regression observability)
  - cursor-marker extraction + optional hardware cursor positioning
  - ANSI-safe line sanitization in render loop (visible-width truncation + line-end reset) before diffing
  - synchronized output batching around full and differential render passes
  - viewport projection to terminal height (renders the bottom visible window of long content)
  - cursor-position projection into visible viewport coordinates for long content

## Verified Regression Coverage (current slice)

- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIDifferentialRenderingTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIANSITerminalTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIANSITextTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIRenderSchedulingTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUICursorTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUISynchronizedOutputTests.swift`
- Added `/Users/anyuan/Development/pi-swift/Tests/PiTUITests/PiTUIProcessTerminalTests.swift`
- Covered scenarios (derived from `../pi-mono/packages/tui/test/tui-render.test.ts`):
  - width change triggers full redraw
  - content shrink clears stale rows when `clearOnShrink` is enabled
  - differential rendering updates only a changed middle line
  - content -> empty -> content transition
  - long content renders bottom viewport window
  - appending content shifts viewport to latest rows
  - shrink then later line change still targets correct row
  - only first line changes
  - only last line changes
  - multiple non-adjacent lines change
  - styled line gets reset at line end (style-leak prevention baseline)
  - ANSI-styled line truncates by visible width before diffing/rendering
- ANSI terminal adapter coverage:
  - hide/show cursor VT sequences
  - clear screen VT sequence
  - row-targeted line write + clear + truncation
  - resize/input callback plumbing
  - out-of-bounds row no-op safety
  - ANSI-visible-width truncation + automatic reset append for styled lines
  - synchronized output begin/end VT markers
- ANSI text utility coverage:
  - visible width ignores CSI color sequences
  - visible width ignores OSC-8 hyperlink wrappers
  - visible width handles wide and combining scalars
  - visible-width truncation preserves ANSI sequences
  - visible-width truncation does not split wide characters
  - reset helper behavior for ANSI vs plain text lines
- Render scheduling coverage:
  - multiple `requestRender()` calls coalesce before scheduler flush
  - resize-triggered render coalesces with explicit render request
  - pending scheduled render is ignored after `stop()`
  - stale scheduled render from previous session does not run after restart
- Cursor handling coverage:
  - cursor marker removal from rendered output
  - cursor row/column positioning in virtual terminal
  - ANSI-aware cursor column calculation (ignores style escape sequences before marker)
  - wide-character cursor column accounting (`你` counts as width 2)
  - cursor marker row projection from long content into visible viewport
  - no-marker path keeps hardware cursor hidden
- Synchronized output coverage:
  - first render wrapped in begin/end sync markers
  - differential render wrapped in begin/end sync markers
  - no-op render does not emit sync markers
- Process terminal scaffold coverage:
  - host writer receives delegated ANSI output
  - host input/resize callbacks bridge to `PiTUIProcessTerminal` callbacks and dimension updates
  - stop delegation
  - `PiTUIStandardIOHost` writer injection + dimension clamping

## Not Yet Implemented in `P4-1`

- Full stdin/raw-mode/signal-driven process terminal integration (current `PiTUIStandardIOHost` is a minimal stdout-backed scaffold)
- overlay composition and viewport-aware diff behavior
- advanced viewport/scrollback overwrite semantics matching `pi-mono` (current implementation projects to visible bottom viewport but does not yet model scrollback/cursor movement intricacies)
- overflow/visible-width handling parity with ANSI-aware width functions

These remain in scope for subsequent `P4-1` slices before the task is marked complete.
