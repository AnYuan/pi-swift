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

- SSH command execution/parsing (`ssh.ts`) runtime execution is pending, but command parsing/invocation planning is now implemented
- model lifecycle command generation and GPU/port allocation (`commands/models.ts`) foundation is implemented (mockable planning), but remote execution/runtime log streaming is pending
- CLI parsing/routing (`cli.ts`, `commands/pods.ts`, `commands/prompt.ts`)
- interactive/streaming SSH execution runtime integration

## `P6-3` Progress (SSH + Model Lifecycle Planning Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiPods/SSH.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiPods/ModelRegistry.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiPods/Lifecycle.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiPodsTests/PiPodsCommandPlanningTests.swift`

Implemented in this slice:

- SSH command parsing + invocation planning
  - parse `ssh` command (`host`, `port`, `args`)
  - SSH exec invocation builder (keepalive, force TTY)
  - SCP invocation builder (`-P <port>`, `host:path`)
- known-model registry foundation (subset catalog + injected registry for tests)
  - known/unknown model detection
  - GPU-count/GPU-type config resolution
- model lifecycle planning (`PiPodsModelLifecyclePlanner`)
  - active/override pod resolution
  - next available port allocation (`8001+`)
  - least-used GPU selection (round-robin-ish usage balancing)
  - start plan generation (`vLLM args`, memory/context overrides, env exports, remote start/log commands)
  - stop plan generation (single model or all tracked PIDs)

Tests added:

- SSH parse + exec/scp invocation generation
- next-port and least-used GPU selection
- known-model start plan with memory/context override command generation
- unknown-model GPU override rejection
- stop command generation for one/all models

Verification (slice):

- `swift test --filter PiPodsCommandPlanningTests` passed on 2026-02-25
- `swift build` passed on 2026-02-25
