# PiMom Coverage Report

Generated: 2026-02-27

## Summary

| Metric | Covered | Total | Percentage |
|--------|---------|-------|------------|
| Regions | 247 | 344 | 71.80% |
| Functions | 94 | 112 | 83.93% |
| Lines | 630 | 815 | 77.30% |

## Per-File Breakdown

| File | Regions | Functions | Lines |
|------|---------|-----------|-------|
| Context.swift | 78.38% | 100.00% | 93.23% |
| Coordinator.swift | 68.29% | 83.78% | 78.52% |
| Sandbox.swift | 38.78% | 50.00% | 39.81% |
| SlackDispatch.swift | 100.00% | 100.00% | 100.00% |
| Store.swift | 82.61% | 84.00% | 83.11% |
| Tools.swift | 68.29% | 86.67% | 86.73% |

## Analysis

- **SlackDispatch** has 100% coverage across all metrics
- **Context** and **Store** have strong coverage (83-93% lines)
- **Coordinator** coverage is moderate (78% lines) — some run lifecycle paths untested
- **Sandbox** is the lowest (39% lines) — `PiMomDockerExecutor` and `PiMomDefaultProcessRunner` are largely untested as they depend on system process execution and Docker runtime

## Notable Gaps

- `PiMomDockerExecutor`: docker exec wrapping untested (requires Docker runtime)
- `PiMomDefaultProcessRunner`: real process execution untested (uses `Process()`)
- `PiMomHostExecutor`: real shell execution untested
- Some `PiMomRunCoordinator` error paths and abort flows

## Test Count

25 tests in `PiMomTests`
