# PiPods Module Progress

## Scope

This document tracks `PiPods` migration progress and parity status against `../pi-mono/packages/pods` (GPU pod CLI, SSH command execution, model lifecycle orchestration, and local pod configuration management).

## `P6-3` Progress (Types + Config Store Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiPods/Types.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiPods/Config.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiPodsTests/PiPodsConfigStoreTests.swift`

Implemented in this slice:

- `PiPods` core data models
  - `PiPodsGPU`
  - `PiPodsModelProcess`
  - `PiPod`
  - `PiPodsConfig`
- local `pods.json` config management (`PiPodsConfigStore`)
  - load missing config as empty
  - save/load JSON config
  - add pod (first pod auto-activates)
  - remove pod (clears active if removed)
  - set active pod with validation
  - get active pod helper

Tests added:

- missing-config default behavior
- add/save/reload + first pod auto-active
- active pod switching validation
- remove-active clears active selection

Verification (slice):

- `swift test --filter PiPodsConfigStoreTests` passed on 2026-02-25
- `swift build` passed on 2026-02-25

## Notes / Parity Gaps (Pending)

- SSH command execution/parsing (`ssh.ts`)
- model lifecycle command generation and GPU/port allocation (`commands/models.ts`)
- CLI parsing/routing (`cli.ts`, `commands/pods.ts`, `commands/prompt.ts`)
- interactive/streaming SSH execution runtime integration
