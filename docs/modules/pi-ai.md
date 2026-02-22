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

## Parity Status vs `pi-mono`

- Partial
- Implemented foundational `PiAI` model registry plus context/message/event type system and utility foundations
- Streaming/network/provider adapters are still pending (`P2-4+`)
  - Provider adapters are now the next major step (`P2-4+`)

## Verification Evidence

- `swift test` passed (includes `PiAIModelRegistryTests` and `PiAITypesTests`)
- `swift test` passed (includes `PiAIUtilitiesTests`)
- `swift build` passed

## Next Step

- `P2-4`: OpenAI Responses adapter (first provider)
