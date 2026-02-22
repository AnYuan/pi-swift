# PiCoreTypes (P1-3)

## Purpose

`PiCoreTypes` contains shared foundational data structures that will be used across `PiAI`, `PiAgentCore`, and higher layers. This task establishes the minimum cross-module type system needed to start `pi-ai` work.

## Implemented in P1-3

### JSON primitives

- `JSONValue`
  - Recursive JSON value enum
  - `Codable`, `Equatable`, `Sendable`
  - Supports `null`, `bool`, `number`, `string`, `array`, `object`

### Tool-related types

- `PiSchemaType`
- `PiToolParameterSchema`
  - Recursive tool parameter schema model (implemented as immutable `final class` to support recursion in Swift)
- `PiToolDefinition`
- `PiToolCall`
- `PiToolResult`

### Message-related types

- `PiMessageRole`
- `PiAttachmentReference`
- `PiMessagePart` (tagged enum with custom `Codable`)
  - `text`
  - `image`
  - `toolCall`
  - `toolResult`
- `PiMessage`

### Stream events

- `PiStreamEvent` (tagged enum with custom `Codable`)
  - `start`
  - `textStart`
  - `textDelta`
  - `textEnd`
  - `toolCall`
  - `toolResult`
  - `finish`
  - `error`

## Test Coverage Added

- `Tests/PiCoreTypesTests/PiCoreTypesCodableTests.swift`
  - nested `JSONValue` codable round-trip
  - tool schema + message codable/equality round-trip
  - stream event encoding golden fixture + decode round-trip

### Golden fixtures

- `Tests/Fixtures/core-types/stream-events.json`

This validates stable JSON encoding shape for an example event sequence, using the shared `PiTestSupport` golden verification helper introduced in `P1-2`.

## Notes / Decisions

- `PiToolParameterSchema` is an immutable `final class` (instead of a struct) because Swift value types cannot directly model the recursive schema shape used here.
- `PiMessagePart` and `PiStreamEvent` use explicit tagged encoding to keep the wire shape stable and easy to diff in fixtures.

## Known Gaps (Expected)

- No validation engine yet (schema validation comes later in `PiAI`)
- Event type set is intentionally minimal and may expand as provider adapters are implemented
- No cost/token accounting types yet (expected in `PiAI`)

## Verification Evidence

- `swift test` passed (includes `PiCoreTypesCodableTests`)
- `swift build` passed

## Next Step

- `P2-1`: `pi-ai` foundational types and model registry (minimum closed loop)

