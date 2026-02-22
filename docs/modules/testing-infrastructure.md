# Testing Infrastructure (P1-2)

## Purpose

This document records the shared test infrastructure introduced in `P1-2`: reusable fixture loading, golden-file verification, and test directory conventions for future parity work.

## Implemented in P1-2

- Shared test-support target:
  - `PiTestSupport`
- Reusable helpers:
  - repository-root discovery (walk-up to `Package.swift`)
  - fixture loading (`String` / `Data`)
  - fixture writing for generated test outputs
  - golden-file verification with update modes
  - line-based diff generation for mismatches
- New test target:
  - `PiTestSupportTests`
- Shared fixture directory conventions:
  - `Tests/Fixtures/common/...`
  - `Tests/Fixtures/goldens/...`

## Files

- `Package.swift` (adds `PiTestSupport` + `PiTestSupportTests`, wires test targets to shared support)
- `Sources/PiTestSupport/PiTestSupport.swift`
- `Tests/PiTestSupportTests/FixtureLoaderTests.swift`
- `Tests/PiTestSupportTests/GoldenFileTests.swift`
- `Tests/Fixtures/common/sample.txt`
- `Tests/Fixtures/goldens/example.txt`

## API Summary (Initial)

- `RepositoryLayout`
  - Resolves repository root and fixture root from a caller file path
- `FixtureLoader`
  - Loads text/data fixtures and writes generated fixtures under `Tests/Fixtures`
- `GoldenFile`
  - Verifies actual text against a golden fixture
  - Supports update modes (`never`, `fromEnvironment`, `always`)
  - Produces line-based diffs on mismatch

## Intended Usage Pattern

1. Create `FixtureLoader(callerFilePath: #filePath)` in tests.
2. Read inputs from `Tests/Fixtures/...`.
3. Compare outputs using `GoldenFile.verifyText(...)`.
4. For intentional golden updates, use `UPDATE_GOLDENS=1` (or explicit `.always` in targeted tests).

## Verification Evidence

- `swift test` passes (includes fixture and golden behavior tests)
- `swift build` passes

## Known Gaps (Expected at This Stage)

- No binary fixture helpers yet (beyond raw `Data` loading)
- No structured golden serializers (JSON/event stream helpers will likely come later)
- No per-module fixture namespaces enforced yet (convention only for now)

## Next Step

- `P1-3`: implement cross-module foundational types (messages/events/tools schema base)

