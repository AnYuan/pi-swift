# PiCodingAgent Coverage Report

Date: 2026-02-27

## Commands

```bash
swift test --enable-code-coverage --filter PiCodingAgentTests
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  Sources/PiCodingAgent/*.swift
```

## Summary

| Metric | Covered | Total | Percentage |
|--------|---------|-------|------------|
| Regions | 1232 | 1595 | 77.26% |
| Functions | 396 | 465 | 85.17% |
| Lines | 2519 | 2899 | 86.90% |

## Per-File Breakdown

| File | Regions | Functions | Lines |
|------|---------|-----------|-------|
| AuthStorage.swift | 62.83% | 70.27% | 70.72% |
| CLIApp.swift | 93.33% | 100.00% | 98.31% |
| CLIArgs.swift | 82.98% | 100.00% | 95.35% |
| CLIExecutor.swift | 80.00% | 66.67% | 88.89% |
| Compaction.swift | 60.53% | 70.73% | 72.87% |
| FileProcessor.swift | 72.22% | 85.71% | 89.16% |
| HTMLExporter.swift | 75.00% | 84.62% | 88.38% |
| InteractiveMode.swift | 74.02% | 87.23% | 91.36% |
| InteractiveSession.swift | 60.00% | 60.00% | 63.16% |
| ModelResolver.swift | 77.78% | 89.66% | 89.30% |
| Modes.swift | 72.88% | 77.42% | 83.98% |
| PiCodingAgent.swift | 100.00% | 100.00% | 100.00% |
| Resources.swift | 84.19% | 90.00% | 92.92% |
| SessionStore.swift | 79.25% | 83.33% | 85.59% |
| SessionTree.swift | 80.00% | 94.12% | 90.27% |
| Settings.swift | 85.38% | 92.59% | 88.76% |
| Tools.swift | 81.12% | 91.67% | 90.75% |

## Notable Remaining Gaps

- `Compaction.swift` line coverage remains low relative to module average (`72.87%`)
- `AuthStorage.swift` line coverage remains below target (`70.72%`)
- `InteractiveSession.swift` line coverage is low (`63.16%`) due to limited runtime-path coverage
- `CLIExecutor.swift` function coverage is low (`66.67%`) — missing failure-path coverage beyond export and invalid-RPC cases

## P7 Changes

- Async tool execution with structured concurrency in `Tools.swift` — improved regions from 78.72% to 81.12% and functions from 87.88% to 91.67%
- Token estimation utilities added, improving `Compaction.swift` coverage (regions 60.53%, lines 72.87%)
- Overflow fix propagated from PiAI, touching `InteractiveMode.swift` and `Modes.swift`
- `CLIExecutor.swift` improved regions from previous baseline to 80.00%

## Notes

- 366 tests total across all modules
- The next major plan step shifts to P7+ platform/peripheral migrations rather than forcing more test expansion in the same slice
