# PiMom Module Progress

## Scope

This document tracks `PiMom` migration progress and parity status against `../pi-mono/packages/mom` (Slack bot + sandboxed command execution + persistent workspace orchestration).

## `P6-2` Progress (Sandbox Abstraction Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/Sandbox.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomSandboxTests.swift`

Implemented in this slice:

- sandbox config parsing parity foundation
  - `host`
  - `docker:<container>`
  - structured parse errors for invalid sandbox type / missing docker container name
- sandbox execution abstraction
  - `PiMomExecutor` protocol
  - `PiMomHostExecutor`
  - `PiMomDockerExecutor`
  - `PiMomExecutorFactory`
- process runner abstraction for testability
  - `PiMomProcessRunning`
  - `PiMomDefaultProcessRunner` (Process-based)
- Docker command wrapping semantics
  - wraps commands with `docker exec <container> sh -c ...`
  - shell escaping for single quotes
- workspace path translation parity
  - host -> passthrough
  - docker -> `/workspace`

Tests added:

- host/docker sandbox parsing
- parse error paths
- host executor shell invocation shape
- docker executor wrapping + escaping behavior

Verification (slice):

- `swift test --filter PiMomSandboxTests` passed on 2026-02-24

## `P6-2` Progress (Slack Event Dispatch Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/SlackDispatch.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomSlackDispatchTests.swift`

Implemented in this slice:

- Slack event model parity foundation
  - `PiMomSlackEventType` (`mention`, `dm`)
  - `PiMomSlackEvent`
  - `PiMomSlackFileRef`
- mockable handler/notifier protocols
  - `PiMomSlackCommandHandling`
  - `PiMomSlackNotifying`
- per-channel dispatch queue foundation (`PiMomSlackEventDispatcher`)
  - queued user events for idle channels
  - scheduled event queue with max size (default `5`)
  - FIFO draining by channel
- stop/busy command routing semantics (aligned to `pi-mono` behavior)
  - `"stop"` executes immediately when running (not queued)
  - idle `"stop"` posts `_Nothing running_`
  - busy mention vs DM messaging uses distinct hint text

Tests added:

- immediate stop command routing when running
- idle stop command fallback message
- busy mention/DM message text parity
- queued idle user event draining to handler
- scheduled event queue max-size and FIFO behavior

Verification (slice):

- `swift test --filter PiMomSlackDispatchTests` passed on 2026-02-24

## `P6-2` Progress (Tool Delegation Bridge Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/Tools.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomToolBridgeTests.swift`

Implemented in this slice:

- `PiMom` -> `PiCodingAgent` tool bridge (`PiMomToolBridge`)
  - reuses `PiCodingAgent` core tools: `read`, `write`, `edit`
  - injects `PiMomBashTool` (sandbox-backed via `PiMomExecutor`)
  - injects `PiMomAttachTool` (workspace-scoped upload callback)
- sandbox-backed bash tool (`PiMomBashTool`)
  - delegates command execution to `PiMomExecutor`
  - supports optional timeout
  - returns text output and surfaces non-zero exit as tool error
- attach tool (`PiMomAttachTool`)
  - validates path stays inside workspace
  - validates file exists
  - uploads via injected `PiMomFileUploading`
  - returns deterministic confirmation text

Tests added:

- tool registry composition (`attach`, `bash`, `edit`, `read`, `write`)
- sandboxed bash delegation + timeout passthrough
- attach upload success path
- attach path-outside-workspace rejection

Verification (slice):

- `swift test --filter PiMomToolBridgeTests` passed on 2026-02-24

## `P6-2` Progress (Channel Store / Attachment Queue Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/Store.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomChannelStoreTests.swift`

Implemented in this slice:

- channel workspace persistence foundation (`PiMomChannelStore`)
  - per-channel directory creation
  - Slack attachment local filename generation (timestamp-based + sanitized)
  - attachment metadata extraction + background-download queue staging
  - drainable attachment download processing via injected downloader
  - `log.jsonl` append for channel messages
  - duplicate log suppression (channel + timestamp)
  - `lastTimestamp(channelID:)`
  - bot response logging helper
- testable attachment downloader abstraction
  - `PiMomAttachmentDownloading`
  - default URLSession-based downloader (`PiMomURLSessionAttachmentDownloader`)

Tests added:

- attachment filename sanitization + Slack timestamp -> ms conversion
- attachment processing queue + download draining writes files
- log message dedupe + `lastTimestamp` + date auto-fill

Verification (slice):

- `swift test --filter PiMomChannelStoreTests` passed on 2026-02-24

## `P6-2` Progress (Context Sync Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/Context.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomContextStoreTests.swift`

Implemented in this slice:

- `log.jsonl` -> `context.jsonl` sync foundation (`PiMomContextStore`)
  - JSONL append/load for `PiAgentMessage`
  - sync excludes current Slack message timestamp
  - sync skips bot messages
  - timestamp-ordered append
  - user-message dedupe against existing context
  - normalization parity helpers (timestamp prefix + `<slack_attachments>` stripping)

Tests added:

- log sync ordering / bot-skip behavior
- exclude-current-message semantics
- normalization-based dedupe (timestamp prefix + attachment block)

Verification (slice):

- `swift test --filter PiMomContextStoreTests` passed on 2026-02-25
- `swift build` passed on 2026-02-25

## `P6-2` Progress (Run Coordinator + Mock Slack Integration Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/Coordinator.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiMom/SlackDispatch.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomCoordinatorTests.swift`

Implemented in this slice:

- mockable Slack runtime integration contracts
  - `PiMomSlackClient`
  - `PiMomWorkScheduling`
  - `PiMomRunner`
- run result/stop semantics
  - `PiMomRunResult`
  - `PiMomRunStopReason`
- Slack response context adapter (`PiMomSlackRunContext`)
  - typing placeholder
  - main message accumulation / replacement
  - thread reply support
  - working-indicator toggling
  - file upload and delete hooks
  - bot-response logging to `log.jsonl`
- run orchestration (`PiMomRunCoordinator`)
  - incoming user event preprocessing + attachment staging/logging
  - `PiMomSlackEventDispatcher` integration
  - per-channel runner lifecycle (`running`, `stopRequested`, `stopMessageTS`)
  - stop command abort path (`_Stopping..._` -> `_Stopped_`)
  - scheduled event drain after current run completes
  - context sync execution before runner invocation

Tests added:

- user-event -> log -> context-sync -> run -> bot-response flow
- running stop command abort + `_Stopped_` message update flow
- scheduled event queued during run executes after completion

Verification (slice):

- `swift test --filter PiMomCoordinatorTests` passed on 2026-02-25
- `swift test --filter PiMomTests` passed (25 `PiMom` tests) on 2026-02-25
- `swift build` passed on 2026-02-25

## Coverage Report (P7-9)

Coverage report: `docs/reports/pi-mom-coverage.md`

Summary: Regions 71.80%, Functions 83.93%, Lines 77.30% (25 tests)

## Notes / Parity Gaps (Known Differences / Future Work)

- real Slack Socket Mode / Web API runtime adapter (current implementation provides mockable integration contracts + coordinator only)
- event file watcher / scheduler
- `pi-mono` full agent/session/runtime wiring (`agent.ts` feature surface) is not yet ported; `P6-2` currently covers the planned migration scope (Slack integration contracts, tool delegation, sandbox abstraction, persistence/context foundations, and mock-tested coordinator flow)
