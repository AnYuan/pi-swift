# PiTUI Coverage Report

Date: 2026-02-27

Command:

```bash
swift test --enable-code-coverage --filter PiTUITests
xcrun llvm-cov report .build/arm64-apple-macosx/debug/pi-swiftPackageTests.xctest/Contents/MacOS/pi-swiftPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  Sources/PiTUI/*.swift
```

Scope: `Sources/PiTUI/*`

## Summary

| Metric | Covered | Total | Percentage |
|--------|---------|-------|------------|
| Regions | 1485 | 1821 | 81.55% |
| Functions | 399 | 463 | 86.11% |
| Lines | 3084 | 3434 | 89.81% |

## Per-File Breakdown

| File | Regions | Functions | Lines |
|------|---------|-----------|-------|
| PiKillRing.swift | 100.00% | 100.00% | 100.00% |
| PiTUIANSITerminal.swift | 81.82% | 87.50% | 85.71% |
| PiTUIANSIText.swift | 82.41% | 100.00% | 88.24% |
| PiTUIAutocomplete.swift | 73.05% | 86.05% | 85.61% |
| PiTUIComponent.swift | 45.45% | 55.56% | 42.86% |
| PiTUIEditorComponent.swift | 87.84% | 85.00% | 89.47% |
| PiTUIEditorHistory.swift | 96.88% | 92.86% | 92.00% |
| PiTUIEditorKeybindings.swift | 81.25% | 83.33% | 89.19% |
| PiTUIEditorModel.swift | 77.61% | 85.71% | 94.80% |
| PiTUIImage.swift | 83.33% | 72.73% | 91.25% |
| PiTUIInputComponent.swift | 91.89% | 87.50% | 97.10% |
| PiTUIInputModel.swift | 68.28% | 85.19% | 79.74% |
| PiTUIKeys.swift | 95.96% | 95.00% | 98.53% |
| PiTUIMarkdown.swift | 89.04% | 100.00% | 96.00% |
| PiTUIOverlayLayout.swift | 90.20% | 82.61% | 96.38% |
| PiTUIProcessTerminal.swift | 61.54% | 53.85% | 72.22% |
| PiTUIRenderBuffer.swift | 100.00% | 100.00% | 100.00% |
| PiTUIRenderScheduler.swift | 100.00% | 100.00% | 100.00% |
| PiTUISelectList.swift | 86.15% | 87.50% | 91.30% |
| PiTUISettingsList.swift | 78.68% | 73.81% | 91.35% |
| PiTUIStdinBuffer.swift | 82.30% | 92.86% | 90.32% |
| PiTUITerminal.swift | 77.78% | 94.12% | 91.43% |
| PiTUITerminalImage.swift | 87.18% | 83.33% | 92.50% |
| PiUndoStack.swift | 100.00% | 100.00% | 100.00% |
| TUI.swift | 79.27% | 92.31% | 91.79% |

## P7 Changes

- Bounded kill ring (`PiKillRing`) and bounded undo stack (`PiUndoStack`) — added capacity limits with automatic eviction, maintaining 100% coverage
- `PiTUIRenderBuffer` reached 100% coverage (up from 90.91% regions, 94.87% lines)
- `PiTUIANSIText` improved to 82.41% regions (from 78.70%) and 88.24% lines (from 83.96%)
- `PiTUISettingsList` improved to 73.81% functions (from 71.43%) and 91.35% lines (from 89.97%)
