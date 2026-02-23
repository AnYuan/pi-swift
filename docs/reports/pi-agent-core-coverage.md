# PiAgentCore Coverage Report

Date: 2026-02-23

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

- Regions: `90.68%`
- Functions: `96.72%`
- Lines: `92.55%`

## Per-file Highlights

- `Sources/PiAgentCore/AgentLoop.swift`
  - Regions: `86.90%`
  - Functions: `97.87%`
  - Lines: `91.86%`
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
