# PiAgentCore Module Progress

## Scope

This document tracks `PiAgentCore` implementation progress and parity status against `../pi-mono/packages/agent`.

## Implemented

### P3-1: AgentState / AgentMessage / AgentEvent types

Files:

- `Sources/PiAgentCore/Types.swift`
- `Tests/PiAgentCoreTests/PiAgentCoreTypesTests.swift`
- `Tests/Fixtures/pi-agent-core/agent-events.json`

Implemented types and behavior:

- `PiAgentThinkingLevel`
  - `off`, `minimal`, `low`, `medium`, `high`, `xhigh`
- `PiAgentCustomMessage`
  - generic custom role + JSON payload + timestamp container for app-specific messages
- `PiAgentMessage`
  - `.user(PiAIUserMessage)`
  - `.assistant(PiAIAssistantMessage)`
  - `.toolResult(PiAIToolResultMessage)`
  - `.custom(PiAgentCustomMessage)`
  - `role`, `timestamp` helpers
  - `asAIMessage` conversion for standard messages (`custom` returns `nil`)
- `PiAgentTool`
  - tool metadata (`name`, `label`, `description`, `parameters`)
  - `asAITool` conversion helper
- `PiAgentToolExecutionResult`
  - tool result content blocks + JSON details payload
- `PiAgentContext`
  - `systemPrompt`, `messages`, optional `tools`
- `PiAgentState`
  - core agent runtime state fields mirroring `pi-mono` shape
  - `empty(model:...)` initializer for predictable defaults
- `PiAgentEvent`
  - agent/turn/message/tool-execution lifecycle events
  - custom tagged `Codable` encoding using snake_case event names for fixture stability

## Tests Added

- `PiAgentState.empty(...)` default initialization behavior
- `PiAgentMessage` round-trip encoding/decoding (including custom messages)
- standard `PiAgentMessage -> PiAIMessage` conversion behavior
- `PiAgentEvent` round-trip encoding/decoding
- golden fixture for agent event JSON encoding (`Tests/Fixtures/pi-agent-core/agent-events.json`)

## Notes / Decisions

- Custom agent messages are represented as `PiAgentCustomMessage` with a freeform JSON payload to preserve extensibility while keeping `Codable`/fixtures simple.
- Tool execution result `details` is modeled as `JSONValue` (instead of generics) for stable storage/event serialization in early phases.
- `PiAgentTool` currently models metadata only; executable behavior is deferred to later `P3` tasks.

### P3-2: Agent loop (single turn)

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopSingleTurnTests.swift`

Implemented behavior:

- `PiAgentEventStream`
  - async event stream wrapper for `PiAgentEvent`
  - supports awaiting final emitted message list through `result()`
  - finishes automatically on `.agentEnd(...)`
- `PiAgentLoopConfig`
  - model selection
  - pluggable agent-message -> `PiAIMessage` conversion (`standardMessageConverter` by default)
- `PiAgentLoop.runSingleTurn(...)`
  - emits `agent_start` / `turn_start`
  - appends prompt messages to working context and emits prompt `message_start` + `message_end`
  - builds `PiAIContext` and consumes provider assistant streaming events
  - converts streaming assistant partials into `message_start` + `message_update` + `message_end`
  - emits `turn_end` and `agent_end` with final emitted messages
  - error fallback path emits synthetic assistant error message and still closes the turn/agent sequence

Tests added:

- single-turn event ordering for prompt + streamed assistant message
- final `result()` contains prompt + final assistant message
- terminal assistant `.done(...)` without a prior `.start(...)` synthesizes assistant `message_start`

## Parity Status vs `pi-mono`

- Partial (foundational types + single-turn agent loop)
- Covers core state/message/event contracts and the minimum single-turn streaming loop required for tool-loop work

## Verification Evidence

- `swift test` passed (includes `PiAgentCoreTypesTests` and `PiAgentLoopSingleTurnTests`)
- `swift build` passed

## Next Step

- `P3-3`: Tool execution loop (multi-turn)
