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

### P3-3: Tool execution loop (multi-turn)

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopToolExecutionTests.swift`

Implemented behavior:

- `PiAgentRuntimeTool`
  - runtime tool wrapper that keeps serializable `PiAgentTool` metadata separate from executable async closure
  - supports progress callback -> `tool_execution_update`
- `PiAgentLoop.run(...)`
  - multi-turn agent loop with tool execution
  - replays prompt messages, streams assistant response, executes tool calls, injects tool-result messages, and starts next turn until no tool calls remain
  - preserves `turn_end` payload with `toolResults` for each assistant turn
  - reuses `PiAIValidation.validateToolArguments(...)` before execution
- Tool execution event/message lifecycle
  - emits `tool_execution_start` / `tool_execution_update` / `tool_execution_end`
  - emits corresponding `message_start` / `message_end` for injected `toolResult` messages
  - converts execution failures into error tool-result messages instead of crashing the agent stream

Tests added:

- multi-turn loop executes tool call and emits tool execution lifecycle events
- tool result is injected into second-turn LLM context
- final agent result includes prompt + assistant(toolCall) + toolResult + assistant(final)

### P3-4 (in progress): `runContinue(...)` retry/continue entrypoint baseline

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopContinueTests.swift`

Implemented in this slice:

- `PiAgentLoop.runContinue(...)` synchronous precondition checks
  - rejects empty context (`cannotContinueWithoutMessages`)
  - rejects continuing from a trailing assistant message (`cannotContinueFromAssistantMessage`)
- continue-path execution reuses the multi-turn loop without re-emitting existing user prompt message events
- custom trailing messages are allowed when caller provides a custom `convertToLLM` implementation (matching `pi-mono` behavior and caller-responsibility model)

Notes:

- `P3-4` is not complete yet. This commit only covers the continue/retry entrypoint baseline. Abort/session-id/thinking-budget parity work remains.

## Parity Status vs `pi-mono`

- Partial (foundational types + single-turn loop + baseline multi-turn tool execution loop)
- Covers core state/message/event contracts and the minimum tool-call execution/replay loop needed for higher-level agent runtime features

## Verification Evidence

- `swift test` passed (includes `PiAgentCoreTypesTests`, `PiAgentLoopSingleTurnTests`, and `PiAgentLoopToolExecutionTests`)
- `swift build` passed

## Next Step

- `P3-4`: continue/retry/abort/sessionId/thinkingBudgets
