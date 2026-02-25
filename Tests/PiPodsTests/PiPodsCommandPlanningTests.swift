import XCTest
import Foundation
@testable import PiPods

final class PiPodsCommandPlanningTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-pods-planner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSSHParserBuildsExecAndScpInvocations() throws {
        let ssh = try PiPodsSSHCommand.parse("ssh -p 2222 root@1.2.3.4")
        XCTAssertEqual(ssh.host, "root@1.2.3.4")
        XCTAssertEqual(ssh.port, "2222")

        let exec = ssh.execInvocation(command: "echo hi", keepAlive: true, forceTTY: true)
        XCTAssertEqual(exec.executable, "ssh")
        XCTAssertEqual(exec.arguments.suffix(2), ["root@1.2.3.4", "echo hi"])
        XCTAssertTrue(exec.arguments.contains("-t"))
        XCTAssertTrue(exec.arguments.contains("ServerAliveInterval=30"))

        let scp = ssh.scpInvocation(localPath: "/tmp/a", remotePath: "/tmp/b")
        XCTAssertEqual(scp, .init(executable: "scp", arguments: ["-P", "2222", "/tmp/a", "root@1.2.3.4:/tmp/b"]))
    }

    func testModelPlannerSelectsLeastUsedGPUsAndNextPort() throws {
        let store = try makeConfigStore(activePod: .init(
            ssh: "ssh root@1.2.3.4",
            gpus: [
                .init(id: 0, name: "NVIDIA H100", memory: "80 GB"),
                .init(id: 1, name: "NVIDIA H100", memory: "80 GB"),
                .init(id: 2, name: "NVIDIA H100", memory: "80 GB"),
            ],
            models: [
                "a": .init(model: "m1", port: 8001, gpu: [0], pid: 10),
                "b": .init(model: "m2", port: 8003, gpu: [1], pid: 11),
                "c": .init(model: "m3", port: 8005, gpu: [1], pid: 12),
            ],
            modelsPath: "/models"
        ))
        let planner = PiPodsModelLifecyclePlanner(configStore: store)
        let pod = try planner.resolvePod(podOverride: nil).pod

        XCTAssertEqual(planner.nextPort(for: pod), 8002)
        XCTAssertEqual(planner.selectGPUs(for: pod, count: 2), [2, 0]) // usage: gpu2=0, gpu0=1, gpu1=2
    }

    func testPlanStartKnownModelAppliesMemoryAndContextOverrides() throws {
        let registry = PiPodsModelRegistry(models: [
            "test-model": .init(name: "Test Model", configs: [
                .init(gpuCount: 1, args: ["--gpu-memory-utilization", "0.8", "--max-model-len", "4096"])
            ])
        ])
        let store = try makeConfigStore(activePod: .init(
            ssh: "ssh root@1.2.3.4",
            gpus: [.init(id: 0, name: "NVIDIA H100", memory: "80 GB")],
            models: [:],
            modelsPath: "/mnt/models"
        ))
        let planner = PiPodsModelLifecyclePlanner(configStore: store, modelRegistry: registry)

        let plan = try planner.planStart(
            modelID: "test-model",
            instanceName: "coder",
            options: .init(memory: "90%", context: "32k"),
            env: ["HF_TOKEN": "hf_x", "PI_API_KEY": "pi_y"]
        )

        XCTAssertEqual(plan.port, 8001)
        XCTAssertEqual(plan.gpuIDs, [0])
        XCTAssertTrue(plan.vllmArgs.contains("--gpu-memory-utilization"))
        XCTAssertTrue(plan.vllmArgs.contains("0.9"))
        XCTAssertTrue(plan.vllmArgs.contains("--max-model-len"))
        XCTAssertTrue(plan.vllmArgs.contains("32768"))
        XCTAssertEqual(plan.envExports["HF_TOKEN"], "hf_x")
        XCTAssertEqual(plan.envExports["PI_API_KEY"], "pi_y")
        XCTAssertEqual(plan.envExports["CUDA_VISIBLE_DEVICES"], "0")
        XCTAssertTrue(plan.logsCommand.contains("coder.log"))
        XCTAssertTrue(plan.remoteStartCommand.contains("MODEL_NAME='coder'"))
    }

    func testPlanStartUnknownModelRejectsGPUOverrideWithoutCustomArgs() throws {
        let store = try makeConfigStore(activePod: .init(
            ssh: "ssh root@1.2.3.4",
            gpus: [.init(id: 0, name: "NVIDIA H100", memory: "80 GB")],
            models: [:],
            modelsPath: "/mnt/models"
        ))
        let planner = PiPodsModelLifecyclePlanner(configStore: store, modelRegistry: .init(models: [:]))

        XCTAssertThrowsError(try planner.planStart(
            modelID: "unknown/repo",
            instanceName: "x",
            options: .init(gpus: 1),
            env: [:]
        )) { error in
            XCTAssertEqual(error as? PiPodsPlannerError, .unsupportedGPUOverrideForUnknownModel)
        }
    }

    func testPlanStopBuildsKillCommandForOneOrAllModels() throws {
        let store = try makeConfigStore(activePod: .init(
            ssh: "ssh root@1.2.3.4",
            gpus: [],
            models: [
                "one": .init(model: "m1", port: 8001, gpu: [0], pid: 123),
                "two": .init(model: "m2", port: 8002, gpu: [1], pid: 456),
            ],
            modelsPath: "/models"
        ))
        let planner = PiPodsModelLifecyclePlanner(configStore: store)

        XCTAssertEqual(try planner.planStop(instanceName: "one", podOverride: nil).remoteCommand, "kill 123")
        XCTAssertEqual(try planner.planStop(instanceName: nil, podOverride: nil).remoteCommand, "kill 123 456")
    }

    private func makeConfigStore(activePod: PiPod) throws -> PiPodsConfigStore {
        let store = PiPodsConfigStore(configDirectory: tempDir.path)
        try store.save(.init(pods: ["alpha": activePod], active: "alpha"))
        return store
    }
}
