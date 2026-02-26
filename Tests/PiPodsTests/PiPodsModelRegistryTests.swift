import XCTest
@testable import PiPods

final class PiPodsModelRegistryTests: XCTestCase {
    func testIsKnownModel() {
        let registry = PiPodsModelRegistry(models: [
            "known": .init(name: "Known Model", configs: [])
        ])
        XCTAssertTrue(registry.isKnownModel("known"))
        XCTAssertFalse(registry.isKnownModel("unknown"))
    }

    func testDisplayName() {
        let registry = PiPodsModelRegistry(models: [
            "known": .init(name: "Pretty Name", configs: [])
        ])
        XCTAssertEqual(registry.displayName(for: "known"), "Pretty Name")
        XCTAssertEqual(registry.displayName(for: "unknown"), "unknown")
    }

    func testKnownModelIDs() {
        let registry = PiPodsModelRegistry(models: [
            "z-model": .init(name: "Z", configs: []),
            "a-model": .init(name: "A", configs: [])
        ])
        XCTAssertEqual(registry.knownModelIDs(), ["a-model", "z-model"])
    }

    func testResolveConfigReturnsNilForUnknownModel() {
        let registry = PiPodsModelRegistry(models: [:])
        XCTAssertNil(registry.resolveConfig(modelID: "unknown", gpus: [], requestedGPUCount: 1))
    }

    func testResolveConfigMatchesExactGPUType() {
        let registry = PiPodsModelRegistry(models: [
            "model": .init(name: "M", configs: [
                .init(gpuCount: 1, gpuTypes: ["A100"], args: ["--match-a100"]),
                .init(gpuCount: 1, gpuTypes: ["H100"], args: ["--match-h100"])
            ])
        ])
        
        // Exact match
        let gpus1 = [PiPodsGPU(id: 0, name: "NVIDIA A100", memory: "80 GB")]
        let resolved1 = registry.resolveConfig(modelID: "model", gpus: gpus1, requestedGPUCount: 1)
        XCTAssertEqual(resolved1?.args, ["--match-a100"])
        
        let gpus2 = [PiPodsGPU(id: 0, name: "NVIDIA H100", memory: "80 GB")]
        let resolved2 = registry.resolveConfig(modelID: "model", gpus: gpus2, requestedGPUCount: 1)
        XCTAssertEqual(resolved2?.args, ["--match-h100"])
    }

    func testResolveConfigMatchesPartialGPUType() {
        let registry = PiPodsModelRegistry(models: [
            "model": .init(name: "M", configs: [
                .init(gpuCount: 1, gpuTypes: ["RTX 4090"], args: ["--match-4090"])
            ])
        ])
        
        // Partial match where registry type is included in GPU name
        let gpus1 = [PiPodsGPU(id: 0, name: "NVIDIA RTX 4090", memory: "24 GB")]
        let resolved1 = registry.resolveConfig(modelID: "model", gpus: gpus1, requestedGPUCount: 1)
        XCTAssertEqual(resolved1?.args, ["--match-4090"])
    }

    func testResolveConfigFallsBackToConfigWithoutGPUTypes() {
        let registry = PiPodsModelRegistry(models: [
            "model": .init(name: "M", configs: [
                .init(gpuCount: 1, gpuTypes: ["A100"], args: ["--match-a100"]),
                .init(gpuCount: 1, args: ["--fallback"])
            ])
        ])
        
        let gpus = [PiPodsGPU(id: 0, name: "NVIDIA RTX 3090", memory: "24 GB")]
        let resolved = registry.resolveConfig(modelID: "model", gpus: gpus, requestedGPUCount: 1)
        XCTAssertEqual(resolved?.args, ["--fallback"])
    }

    func testResolveConfigReturnsNilIfNoMatchingGPUCount() {
        let registry = PiPodsModelRegistry(models: [
            "model": .init(name: "M", configs: [
                .init(gpuCount: 2, args: ["--match-2"])
            ])
        ])
        let gpus = [PiPodsGPU(id: 0, name: "NVIDIA A100", memory: "80 GB")]
        XCTAssertNil(registry.resolveConfig(modelID: "model", gpus: gpus, requestedGPUCount: 1))
    }

    func testResolveConfigCarriesOverModelLevelNotes() {
        let registry = PiPodsModelRegistry(models: [
            "model": .init(name: "M", configs: [
                .init(gpuCount: 1, args: ["--arg"])
            ], notes: "model notes")
        ])
        let gpus = [PiPodsGPU(id: 0, name: "NVIDIA A100", memory: "80 GB")]
        let resolved = registry.resolveConfig(modelID: "model", gpus: gpus, requestedGPUCount: 1)
        XCTAssertEqual(resolved?.notes, "model notes")
    }

    func testResolveConfigPrefersConfigLevelNotes() {
        let registry = PiPodsModelRegistry(models: [
            "model": .init(name: "M", configs: [
                .init(gpuCount: 1, args: ["--arg"], notes: "config notes")
            ], notes: "model notes")
        ])
        let gpus = [PiPodsGPU(id: 0, name: "NVIDIA A100", memory: "80 GB")]
        let resolved = registry.resolveConfig(modelID: "model", gpus: gpus, requestedGPUCount: 1)
        XCTAssertEqual(resolved?.notes, "config notes")
    }
}
