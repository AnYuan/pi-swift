# PiAgentCore Coverage Report

Date: 2026-02-27

## Command

```bash
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  Sources/PiAgentCore/AgentLoop.swift \
  Sources/PiAgentCore/Types.swift \
  Sources/PiAgentCore/PiAgentCore.swift
```

## Coverage Snapshot (`Sources/PiAgentCore/*`)

- Regions: `90.91%` (310/341)
- Functions: `95.71%` (67/70)
- Lines: `93.52%` (1024/1095)

## Per-file Highlights

- `Sources/PiAgentCore/AgentLoop.swift`
  - Regions: `87.88%`
  - Functions: `96.43%`
  - Lines: `93.21%`
- `Sources/PiAgentCore/Types.swift`
  - Regions: `95.10%`
  - Functions: `92.86%`
  - Lines: `94.61%`

## Notes

- Current regression suite covers:
  - single-turn loop event ordering
  - multi-turn tool execution and tool-result replay
  - continue/retry entrypoint behavior
  - steering/follow-up queue control
  - loop/tool-triggered abort
  - request-options plumbing (`reasoning`, `sessionId`, `thinkingBudgets`)
  - custom-message filtering and `transformContext -> convertToLLM` ordering

## P7 Changes

- Parallel tool execution support in `AgentLoop` — concurrent tool dispatch with structured concurrency, improving region/line counts
