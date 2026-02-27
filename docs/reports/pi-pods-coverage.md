# PiPods Coverage Report

Generated: 2026-02-27

## Summary

| Metric | Covered | Total | Percentage |
|--------|---------|-------|------------|
| Regions | 240 | 352 | 68.18% |
| Functions | 68 | 84 | 80.95% |
| Lines | 577 | 720 | 80.14% |

## Per-File Breakdown

| File | Regions | Functions | Lines |
|------|---------|-----------|-------|
| CLI.swift | 62.67% | 72.22% | 74.11% |
| Config.swift | 82.35% | 88.89% | 83.08% |
| Lifecycle.swift | 74.04% | 86.21% | 86.27% |
| ModelRegistry.swift | 50.00% | 53.33% | 67.80% |
| SSH.swift | 71.88% | 88.89% | 86.44% |
| Types.swift | 100.00% | 100.00% | 100.00% |

## Analysis

- **Types** has 100% coverage (pure data types)
- **Config**, **Lifecycle**, and **SSH** have solid coverage (83-86% lines)
- **CLI** coverage is moderate (74% lines) — some command branches untested
- **ModelRegistry** is the lowest (67% lines) — some config resolution paths and GPU type matching untested

## Notable Gaps

- `PiPodsCLIApp.execute()`: several command action branches not fully covered (ssh, logs, start with options)
- `PiPodsModelRegistry.resolveConfig()`: GPU type matching and multi-config selection partially tested
- `PiPodsModelLifecyclePlanner.planStart()`: some memory/context parsing edge cases

## Test Count

16 tests in `PiPodsTests`
