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

## Next Step

- `P2-2`: unified message context and stream event model in `PiAI`

