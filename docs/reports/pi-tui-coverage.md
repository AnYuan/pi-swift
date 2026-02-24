# PiTUI Coverage Report

Date: 2026-02-24

Command:

```bash
swift test --enable-code-coverage --filter PiTUITests
xcrun llvm-cov report .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  Sources/PiTUI/*.swift
```

Scope: `Sources/PiTUI/*`

Summary (TOTAL row for `Sources/PiTUI/*`):

- Regions coverage: `80.62%`
- Functions executed: `85.63%`
- Lines coverage: `89.09%`

Snapshot:

```text
Filename                         Regions    Missed Regions     Cover   Functions  Missed Functions  Executed       Lines      Missed Lines     Cover    Branches   Missed Branches     Cover
PiKillRing.swift                      16                 0   100.00%           7                 0   100.00%          25                 0   100.00%
PiTUIANSITerminal.swift               22                 4    81.82%          16                 2    87.50%          56                 8    85.71%
PiTUIANSIText.swift                  108                23    78.70%          16                 0   100.00%         187                30    83.96%
PiTUIAutocomplete.swift              167                45    73.05%          43                 6    86.05%         271                39    85.61%
PiTUIComponent.swift                  11                 6    45.45%           9                 4    55.56%          21                12    42.86%
PiTUIEditorComponent.swift            74                 9    87.84%          20                 3    85.00%         152                16    89.47%
PiTUIEditorHistory.swift              32                 1    96.88%          14                 1    92.86%          50                 4    92.00%
PiTUIEditorKeybindings.swift          16                 3    81.25%          12                 2    83.33%          37                 4    89.19%
PiTUIEditorModel.swift                67                15    77.61%          28                 4    85.71%         173                 9    94.80%
PiTUIImage.swift                      24                 4    83.33%          11                 3    72.73%          80                 7    91.25%
PiTUIInputComponent.swift             37                 3    91.89%          16                 2    87.50%          69                 2    97.10%
PiTUIInputModel.swift                186                59    68.28%          54                 8    85.19%         385                78    79.74%
PiTUIKeys.swift                       99                 4    95.96%          20                 1    95.00%         136                 2    98.53%
PiTUIMarkdown.swift                   73                 8    89.04%          19                 0   100.00%         150                 6    96.00%
PiTUIOverlayLayout.swift              51                 5    90.20%          23                 4    82.61%         138                 5    96.38%
PiTUIProcessTerminal.swift            39                15    61.54%          26                12    53.85%         108                30    72.22%
PiTUIRenderBuffer.swift               33                 3    90.91%          12                 0   100.00%          78                 4    94.87%
PiTUIRenderScheduler.swift             9                 0   100.00%           7                 0   100.00%          19                 0   100.00%
PiTUISelectList.swift                 65                11    83.08%          24                 3    87.50%         138                12    91.30%
PiTUISettingsList.swift              136                30    77.94%          42                12    71.43%         289                29    89.97%
PiTUIStdinBuffer.swift               113                20    82.30%          28                 2    92.86%         186                18    90.32%
PiTUITerminal.swift                   27                 6    77.78%          17                 1    94.12%          70                 6    91.43%
PiTUITerminalImage.swift              39                 5    87.18%          12                 2    83.33%          80                 6    92.50%
PiUndoStack.swift                      7                 0   100.00%           7                 0   100.00%          17                 0   100.00%
TUI.swift                            164                34    79.27%          39                 3    92.31%         329                27    91.79%
TOTAL                               1615               313    80.62%         522                75    85.63%        3244               354    89.09%
```
