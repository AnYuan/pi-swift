# PiAI Module Progress

## Scope

This document tracks `PiAI` implementation progress and parity status against `../pi-mono/packages/ai`.

## Implemented

### P2-1: Foundational model registry (minimum closed loop)

Files:

- `Sources/PiAI/ModelRegistry.swift`
- `Tests/PiAITests/PiAIModelRegistryTests.swift`

Implemented types and behavior:

- `PiAIModel`
  - provider ID
  - model ID
  - display name
  - `supportsTools` flag
  - `qualifiedID` helper (`provider/model`)
- `PiAIModelRegistry`
  - list all models
  - exact provider+model lookup (`model(provider:id:)`)
  - query search (`search`)
  - single-model resolution (`resolve`)
- `PiAIModelRegistryError`
  - `noMatches`
  - `ambiguous`

Matching behavior (current baseline):

- Exact provider/model lookup (case-insensitive)
- Provider-qualified wildcard search (supports `*`)
- Fuzzy search using token-aware matching
- Ambiguity detection with returned qualified IDs

## Tests Added

- exact lookup (case-insensitive)
- exact provider-qualified resolution
- wildcard search ordering
- fuzzy search ranking
- no-match error path
- ambiguous error path

## Notes / Decisions

- Fuzzy matching is token-aware (split on non-alphanumeric boundaries) to avoid false positives like matching `mini` against `gemini`.
- This registry is intentionally minimal and local/in-memory. Provider APIs, streaming, and context/message handling are implemented in later `P2` tasks.

## Parity Status vs `pi-mono`

- Partial (foundational only)
- Covers a small subset of the `pi-ai` package surface: model representation and selection primitives

## Verification Evidence

- `swift test` passed (includes `PiAIModelRegistryTests`)
- `swift build` passed

### P2-2: Unified context/message/event type model

Files:

- `Sources/PiAI/Types.swift`
- `Tests/PiAITests/PiAITypesTests.swift`
- `Tests/Fixtures/pi-ai/assistant-message-events.json`

Implemented types and behavior:

- `PiAIContext`
  - optional `systemPrompt`
  - `messages: [PiAIMessage]`
  - optional `tools: [PiAITool]`
- `PiAIMessage` (role-tagged union)
  - `.user(PiAIUserMessage)`
  - `.assistant(PiAIAssistantMessage)`
  - `.toolResult(PiAIToolResultMessage)`
- Content block types
  - text / thinking / image / tool-call content blocks
  - user content union (`string` or array of typed parts)
- Usage / cost model
  - `PiAIUsage`
  - `PiAIUsageCost`
  - `.zero` helpers for both
- Stop reason enum
  - `PiAIStopReason` (`stop`, `length`, `toolUse`, `error`, `aborted`)
- Assistant stream event union
  - start/text/thinking/toolcall lifecycle events
  - `done` and `error` terminal events
  - custom tagged `Codable` encoding using snake_case event names matching the tested wire shape

Tests added for P2-2:

- Context round-trip encoding/decoding across user + assistant + tool-result messages
- Assistant message event sequence round-trip
- Golden fixture for stable event JSON encoding

Notes / decisions:

- `PiAI` reuses `PiCoreTypes` foundational schema/JSON types (`PiToolDefinition`, `PiToolParameterSchema`, `JSONValue`) via a public `PiAITool` typealias.
- Event and content unions use explicit custom `Codable` to keep the wire shape stable and fixture-friendly.

### P2-3: Utility foundations (`JSON`, event-stream, validation, overflow)

Files:

- `Sources/PiAI/Utils/SSEParser.swift`
- `Sources/PiAI/Utils/JSONParsing.swift`
- `Sources/PiAI/Utils/Validation.swift`
- `Sources/PiAI/Utils/Overflow.swift`
- `Tests/PiAITests/PiAIUtilitiesTests.swift`

Implemented utilities:

- `PiAISSEParser`
  - Incremental SSE parsing across chunk boundaries
  - Supports `event`, `data`, and `id` fields
  - Multi-line `data:` aggregation
- `PiAIJSON.parseStreamingJSON`
  - Parses complete JSON into `JSONValue`
  - Best-effort partial JSON repair by appending missing closers / truncating invalid tail
  - Returns empty object (`{}`) for invalid or empty input
- `PiAIValidation`
  - Tool lookup by name
  - Recursive schema validation for common schema types:
    - object / array / string / number / integer / boolean / null
  - Supports `required`, `properties`, `items`, `enum`, and `additionalProperties: false`
- `PiAIOverflow.isContextOverflow`
  - Error-pattern detection for context overflow responses
  - Silent-overflow detection via usage vs contextWindow (z.ai-style behavior)

Tests added for P2-3:

- SSE parser single/chunked parsing
- complete + partial + invalid streaming JSON parsing
- valid and invalid tool-argument validation paths
- context overflow detection (error-based and silent-overflow cases)

### P2-4: First provider adapter (`OpenAI Responses`, mock-driven)

Files:

- `Sources/PiAI/Utils/AssistantMessageEventStream.swift`
- `Sources/PiAI/Providers/OpenAIResponsesAdapter.swift`
- `Tests/PiAITests/PiAIOpenAIResponsesProviderTests.swift`

Implemented behavior:

- `PiAIAssistantMessageEventStream`
  - AsyncSequence stream of `PiAIAssistantMessageEvent`
  - terminal result retrieval via `result()`
  - terminal handling for `.done` and `.error`
- `PiAIOpenAIResponsesProvider` (mock-driven adapter entry)
  - `streamMock(...)` executes an async mock event source
  - emits `start` / incremental events / terminal `done` or `error`
- `PiAIOpenAIResponsesEventProcessor` (internal)
  - maps a subset of OpenAI Responses-style events to `PiAIAssistantMessageEvent`
  - supports:
    - text item added + text deltas
    - function-call item added + argument deltas + function-call completion
    - response completion with usage + stop reason
  - uses `PiAIJSON.parseStreamingJSON` to incrementally parse tool-call arguments

Mock raw event coverage (current subset):

- `response.output_item.added` (`message`, `function_call`)
- `response.output_text.delta`
- `response.function_call_arguments.delta`
- `response.function_call_arguments.done`
- `response.completed`

Tests added for P2-4:

- event ordering for text + tool-call lifecycle from a mock source
- terminal error event/result when mock source throws

Notes / decisions:

- This task implements the provider adapter core and event mapping with a mock event source first (test-first and deterministic).
- Real HTTP transport/OpenAI SDK integration is deferred to later provider work; the current shape keeps the mapping logic isolated and testable.

### P2-5: Anthropic adapter (`anthropic-messages`, mock-driven)

Files:

- `Sources/PiAI/Providers/AnthropicMessagesAdapter.swift`
- `Tests/PiAITests/PiAIAnthropicProviderTests.swift`

Implemented behavior:

- `PiAIAnthropicMessagesProvider` (mock-driven adapter entry)
  - `streamMock(...)` executes an async mock Anthropic event source
  - emits `start` / incremental events / terminal `done` or `error`
- `PiAIAnthropicMessagesEventProcessor` (internal)
  - maps Anthropic Messages-style events into `PiAIAssistantMessageEvent`
  - supports:
    - `message_start` usage initialization
    - text block start/delta/stop
    - thinking block start/delta/signature/stop
    - `tool_use` block start + `input_json_delta` parsing + stop
    - `message_delta` stop reason + usage updates
    - `message_stop` terminal completion
- OAuth tool-name normalization helpers (Claude Code canonical casing compatible subset)
  - outbound canonicalization (`read` -> `Read`, `todowrite` -> `TodoWrite`)
  - inbound round-trip restoration against `context.tools` (case-insensitive match)
  - regression guard for `find != Glob` (no incorrect semantic mapping)

Mock raw event coverage (current subset):

- `message_start`
- `content_block_start` (`text`, `thinking`, `tool_use`)
- `content_block_delta` (`text_delta`, `thinking_delta`, `signature_delta`, `input_json_delta`)
- `content_block_stop`
- `message_delta`
- `message_stop`

Tests added for P2-5:

- event ordering and final message content for thinking + text + tool-use streaming from a mock source
- partial JSON tool-argument normalization across deltas
- OAuth tool-name normalization round-trip regression coverage (`find` remains `find`, not `Glob`)
- terminal error event/result when mock source throws

### P2-6: Google/Vertex family adapter core (mock-driven shared semantics)

Files:

- `Sources/PiAI/Providers/GoogleFamilyAdapter.swift`
- `Tests/PiAITests/PiAIGoogleFamilyProviderTests.swift`

Implemented behavior:

- `PiAIGoogleStreamingSemantics`
  - `isThinkingPart(thought:thoughtSignature:)` matches Google semantics (`thought == true` only)
  - `retainThoughtSignature(existing:incoming:)` preserves prior non-empty signature across deltas
- `PiAIGoogleFamilyProvider` (mock-driven adapter entry)
  - `streamMock(...)` for single-attempt mock streams
  - `streamMockRetryingEmptyAttempts(...)` for empty-stream retry behavior (single `start`, retry on empty attempts)
- `PiAIGoogleFamilyEventProcessor` (internal)
  - coalesces streamed text/thinking parts into content blocks with lifecycle events
  - preserves thinking/text signatures per block
  - maps function calls to tool-call lifecycle events
  - defaults missing function-call args to `{}` (no-arg tool compatibility)
  - generates deterministic tool-call IDs when providers omit IDs
  - applies Google-style usage metadata and finish-reason mapping
  - overrides terminal stop reason to `.toolUse` when tool calls are emitted

Mock raw chunk coverage (current subset):

- text parts (regular + thinking via `thought: true`)
- function-call parts (with/without `id`, with/without `args`)
- finish reason mapping
- usage metadata mapping (`prompt`, `candidates`, `thoughts`, `cached`, `total`)
- empty-attempt retry sequence

Tests added for P2-6:

- Google thinking signature semantics (`thoughtSignature` alone does not imply thinking)
- signature retention across omitted/empty deltas
- missing-args tool call defaults to empty object
- empty stream retry without duplicate `start`
- event ordering and content assembly for mixed thinking + text + tool call stream

## Parity Status vs `pi-mono`

- Partial
- Implemented foundational `PiAI` model registry, context/message/event types, utility foundations, and three provider adapter cores (OpenAI Responses, Anthropic Messages, Google-family shared semantics; all mock-driven)
- Real provider transport integrations and remaining provider/credential work are still pending (`P2-7+`)

## Verification Evidence

- `swift test` passed (includes `PiAIModelRegistryTests` and `PiAITypesTests`)
- `swift test` passed (includes `PiAIUtilitiesTests`)
- `swift test` passed (includes `PiAIOpenAIResponsesProviderTests`)
- `swift test` passed (includes `PiAIAnthropicProviderTests`)
- `swift test` passed (includes `PiAIGoogleFamilyProviderTests`)
- `swift build` passed

## Next Step

- `P2-7`: OAuth and provider credential helpers
