# PiCodingAgent Coverage Report

Date: 2026-02-24

## Commands

```bash
swift test --enable-code-coverage --filter PiCodingAgentTests
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  Sources/PiCodingAgent/*.swift
```

## Coverage Snapshot (`Sources/PiCodingAgent/*`)

- Regions: `76.49%`
- Functions: `83.89%`
- Lines: `86.02%`

## Per-file Highlights

- Strong coverage areas
  - `Resources.swift`: Regions `84.19%`, Functions `90.00%`, Lines `92.92%`
  - `Settings.swift`: Regions `85.38%`, Functions `92.59%`, Lines `88.76%`
  - `InteractiveMode.swift`: Regions `74.02%`, Functions `87.23%`, Lines `91.36%`
  - `Tools.swift`: Regions `78.72%`, Functions `87.88%`, Lines `85.20%`
- `P5-10` additions
  - `FileProcessor.swift`: Regions `72.22%`, Functions `85.71%`, Lines `89.16%`
  - `HTMLExporter.swift`: Regions `75.00%`, Functions `84.62%`, Lines `88.38%`
  - `CLIArgs.swift` (with `--export`): Regions `82.98%`, Functions `100.00%`, Lines `95.35%`
  - `CLIApp.swift` (with export action routing): Regions `93.33%`, Functions `100.00%`, Lines `98.31%`

## Notable Remaining Gaps (Future Coverage Push)

- `Compaction.swift` line coverage remains low relative to module average (`71.84%`)
- `AuthStorage.swift` line coverage remains below target (`70.72%`)
- `InteractiveSession.swift` line coverage is low (`63.16%`) due limited runtime-path coverage
- `CLIExecutor.swift` missing failure-path coverage beyond export and invalid-RPC cases

## Notes

- This report completes `P5-11` by establishing a reproducible module-wide coverage baseline and documenting the current regression surface for `PiCodingAgent`.
- The next major plan step shifts to `P6` platform/peripheral migrations rather than forcing more `P5`-only test expansion in the same slice.
