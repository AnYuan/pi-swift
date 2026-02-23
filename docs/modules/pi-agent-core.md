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

### P3-4 slice: `runContinue(...)` retry/continue entrypoint baseline

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopContinueTests.swift`

Implemented in this slice:

- `PiAgentLoop.runContinue(...)` synchronous precondition checks
  - rejects empty context (`cannotContinueWithoutMessages`)
  - rejects continuing from a trailing assistant message (`cannotContinueFromAssistantMessage`)
- continue-path execution reuses the multi-turn loop without re-emitting existing user prompt message events
- custom trailing messages are allowed when caller provides a custom `convertToLLM` implementation (matching `pi-mono` behavior and caller-responsibility model)

Notes (historical slice context):

- This slice established the continue/retry entrypoint baseline. Later P3-4 slices added abort and request-option parity.

### P3-4 slice: steering/follow-up runtime-control loops

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopSteeringTests.swift`

Implemented in this slice:

- `PiAgentLoopConfig`
  - optional `getSteeringMessages` callback
  - optional `getFollowUpMessages` callback
- Runtime loop control behavior
  - queued steering messages are injected before the next assistant turn
  - remaining tool calls in the same assistant message are skipped when steering messages arrive
  - skipped tool calls emit error `tool_execution_end` + injected error `toolResult` messages (matching `pi-mono` behavior)
  - follow-up messages can restart the loop after the agent would otherwise stop

Tests added:

- queued steering message skips remaining tool calls and is injected before the next LLM call
- follow-up message continues the loop after a normal stop and starts a new assistant turn

Notes (historical slice context):

- This slice added runtime queue control. Later P3-4 slices completed abort and request-option plumbing.

### P3-4 slice: abort controller (loop-level)

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopAbortTests.swift`

Implemented in this slice:

- `PiAgentAbortController`
  - thread-safe `abort()` / `isAborted`
- loop-level abort checks in `run(...)`, `runContinue(...)`, and `runSingleTurn(...)`
  - abort is checked before LLM invocation and at key loop boundaries
  - aborted execution emits a synthetic assistant terminal message with `stopReason = .aborted`
  - stream still closes via normal `turn_end` + `agent_end` flow
- runtime tool execution receives the same `PiAgentAbortController` instance
  - tools can trigger abort and the loop stops before the next assistant request

Tests added:

- pre-aborted `runContinue(...)` skips LLM factory invocation and returns an assistant message with `stopReason = .aborted`
- tool-triggered abort prevents the next assistant call and terminates with an `.aborted` assistant message

Notes (historical slice context):

- This slice introduced loop-level abort handling. A later slice added request-options plumbing and stronger abort coverage.

### P3-4 slice: request-options plumbing (`sessionId` / `reasoning` / `thinkingBudgets`)

Files:

- `Sources/PiAgentCore/AgentLoop.swift`
- `Tests/PiAgentCoreTests/PiAgentLoopRequestOptionsTests.swift`

Implemented in this slice:

- `PiAgentThinkingBudgets`
  - Swift parity shape for token budgets by thinking level (`minimal`, `low`, `medium`, `high`)
- `PiAgentLLMRequestOptions`
  - loop-to-provider request options payload (`reasoning`, `sessionId`, `thinkingBudgets`)
- `PiAgentLoopConfig`
  - added `thinkingLevel`, `sessionId`, and `thinkingBudgets`
- `PiAgentLoop` assistant factory overloads
  - existing 2-argument factory API remains supported for backwards compatibility
  - new overloads pass `PiAgentLLMRequestOptions` to the assistant stream factory
- reasoning mapping behavior
  - `thinkingLevel == .off` maps to `reasoning = nil`
  - other levels map through directly

Tests added:

- `runSingleTurn(...)` passes `sessionId`, `thinkingBudgets`, and non-`off` reasoning to factory options
- `runSingleTurn(...)` omits `reasoning` when `thinkingLevel == .off`

Notes:

- These options are plumbed through the loop/factory boundary in `PiAgentCore`; provider-specific adapter consumption remains an integration concern outside this module.

### P3-4 completion summary

Completed runtime-control capabilities in `PiAgentCore` now cover:

- continue/retry entrypoint via `runContinue(...)`
- steering and follow-up message polling/injection loops
- queued steering skip behavior for remaining tool calls
- loop-level and tool-triggered abort via `PiAgentAbortController`
- request-options plumbing (`reasoning`, `sessionId`, `thinkingBudgets`) to the assistant stream factory boundary

## Parity Status vs `pi-mono`

- Partial (foundational types + single-turn loop + multi-turn tool loop + runtime-control baseline)
- Covers core state/message/event contracts, tool-call execution/replay, and the major runtime-control hooks needed by higher-level agent orchestration

## Verification Evidence

- `swift test` passed (includes `PiAgentLoopContinueTests`, `PiAgentLoopSteeringTests`, `PiAgentLoopAbortTests`, and `PiAgentLoopRequestOptionsTests`)
- `swift build` passed

## Next Step

- `P3-5`: `pi-agent-core` regression test completion
