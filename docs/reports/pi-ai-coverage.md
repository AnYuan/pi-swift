# PiAI Coverage Report

Date: 2026-02-27

Command:

```bash
swift test --enable-code-coverage
xcrun llvm-cov report .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata
```

Scope: `Sources/PiAI/*`

Summary (TOTAL row for `Sources/PiAI/*`):

- Regions coverage: `83.76%` (769/918)
- Functions executed: `95.18%` (178/187)
- Lines coverage: `92.76%` (1653/1782)

Snapshot:

```text
Filename                                                                      Regions    Missed Regions     Cover   Functions  Missed Functions  Executed       Lines      Missed Lines     Cover    Branches   Missed Branches     Cover
Sources/PiAI/ModelRegistry.swift                                                   83                17    79.52%          30                 2    93.33%         135                10    92.59%           0                 0         -
Sources/PiAI/Providers/AnthropicMessagesAdapter.swift                             104                19    81.73%          28                 1    96.43%         285                12    95.79%           0                 0         -
Sources/PiAI/Providers/GoogleFamilyAdapter.swift                                  115                22    80.87%          28                 1    96.43%         317                30    90.54%           0                 0         -
Sources/PiAI/Providers/OpenAIResponsesAdapter.swift                                48                 8    83.33%          14                 0   100.00%         165                 2    98.79%           0                 0         -
Sources/PiAI/Types.swift                                                          193                31    83.94%          20                 0   100.00%         311                35    88.75%           0                 0         -
Sources/PiAI/Utils/AssistantMessageEventStream.swift                               42                 4    90.48%           8                 1    87.50%          61                 6    90.16%           0                 0         -
Sources/PiAI/Utils/JSONParsing.swift                                               64                13    79.69%           7                 0   100.00%         102                 9    91.18%           0                 0         -
Sources/PiAI/Utils/OAuthHelpers.swift                                              31                 1    96.77%          12                 1    91.67%          70                 1    98.57%           0                 0         -
Sources/PiAI/Utils/Overflow.swift                                                  17                 0   100.00%           3                 0   100.00%          23                 0   100.00%           0                 0         -
Sources/PiAI/Utils/SSEParser.swift                                                 31                 7    77.42%           8                 1    87.50%          73                 9    87.67%           0                 0         -
Sources/PiAI/Utils/Validation.swift                                                58                12    79.31%          11                 2    81.82%          89                11    87.64%           0                 0         -
TOTAL                                                                             918               149    83.76%         187                 9    95.18%        1782               129    92.76%           0                 0         -
```

## P7 Changes

- Pre-compiled regex patterns in `ModelRegistry`, `Types`, and `AssistantMessageEventStream` — moved from runtime `Regex` construction to `#/.../#` literals, which reshuffled region/line counts in those files
