# PiAI Coverage Report

Date: 2026-02-23

Command:

```bash
swift test --enable-code-coverage
xcrun llvm-cov report .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata
```

Scope: `Sources/PiAI/*`

Summary (TOTAL row for `Sources/PiAI/*`):

- Regions coverage: `86.03%`
- Functions executed: `96.09%`
- Lines coverage: `94.22%`

Snapshot:

```text
Filename                                                                      Regions    Missed Regions     Cover   Functions  Missed Functions  Executed       Lines      Missed Lines     Cover    Branches   Missed Branches     Cover
Sources/PiAI/ModelRegistry.swift                                                   83                18    78.31%          30                 3    90.00%         135                13    90.37%           0                 0         -
Sources/PiAI/Providers/AnthropicMessagesAdapter.swift                             104                19    81.73%          28                 1    96.43%         285                12    95.79%           0                 0         -
Sources/PiAI/Providers/GoogleFamilyAdapter.swift                                  115                22    80.87%          28                 1    96.43%         317                30    90.54%           0                 0         -
Sources/PiAI/Providers/OpenAIResponsesAdapter.swift                                48                 8    83.33%          14                 0   100.00%         165                 2    98.79%           0                 0         -
Sources/PiAI/Types.swift                                                          193                33    82.90%          20                 0   100.00%         311                38    87.78%           0                 0         -
Sources/PiAI/Utils/AssistantMessageEventStream.swift                               22                 1    95.45%           9                 0   100.00%          87                 3    96.55%           0                 0         -
Sources/PiAI/Utils/JSONParsing.swift                                               64                13    79.69%           7                 0   100.00%         102                 9    91.18%           0                 0         -
Sources/PiAI/Utils/OAuthHelpers.swift                                              31                 1    96.77%          12                 1    91.67%          70                 1    98.57%           0                 0         -
Sources/PiAI/Utils/Overflow.swift                                                  17                 0   100.00%           3                 0   100.00%          23                 0   100.00%           0                 0         -
Sources/PiAI/Utils/SSEParser.swift                                                 31                 7    77.42%           8                 1    87.50%          73                 9    87.67%           0                 0         -
Sources/PiAI/Utils/Validation.swift                                                58                12    79.31%          11                 2    81.82%          89                11    87.64%           0                 0         -
TOTAL                                                                            1460               204    86.03%         588                23    96.09%        3702               214    94.22%           0                 0         -
```
