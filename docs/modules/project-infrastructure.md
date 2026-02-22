# Project Infrastructure (P1-1)

## Purpose

This document records the initial Swift project/module skeleton created for `pi-swift` (`P1-1`) and how it maps to the `pi-mono` package structure.

## Implemented in P1-1

- SwiftPM package manifest: `Package.swift`
- Base Swift targets (placeholder modules) matching `pi-mono` package boundaries:
  - `PiCoreTypes`
  - `PiAI`
  - `PiAgentCore`
  - `PiTUI`
  - `PiCodingAgent`
  - `PiMom`
  - `PiPods`
  - `PiWebUIBridge`
- Executable target:
  - `PiSwiftCLI` (product name: `pi-swift`)
- Test targets for all library targets with smoke tests
- `.gitignore` entries for Swift build artifacts (`.build/`, `.swiftpm/`)

## Target Dependency Mapping (Initial)

- `PiAI` -> `PiCoreTypes`
- `PiAgentCore` -> `PiCoreTypes`, `PiAI`
- `PiTUI` -> `PiCoreTypes`
- `PiCodingAgent` -> `PiCoreTypes`, `PiAI`, `PiAgentCore`, `PiTUI`
- `PiMom` -> `PiCoreTypes`, `PiAI`, `PiAgentCore`, `PiCodingAgent`
- `PiPods` -> `PiCoreTypes`, `PiAI`, `PiAgentCore`
- `PiWebUIBridge` -> `PiCoreTypes`, `PiAI`, `PiAgentCore`
- `PiSwiftCLI` -> `PiCodingAgent`

These are placeholder dependencies meant to encode the migration order and integration boundaries from `docs/ARCHITECTURE.md`.

## Verification Evidence

- `swift build` passes
- `swift test` passes (8 smoke tests)

## Known Gaps (Expected at This Stage)

- No real feature implementation yet (only placeholder APIs)
- No fixture/golden infrastructure yet (`P1-2`)
- No shared message/event/tool schema types yet (`P1-3`)

## Next Step

- Implement `P1-2`: shared test utilities and fixture/golden infrastructure

