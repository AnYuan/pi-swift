import XCTest
import Foundation
@testable import PiPods

final class PiPodsCLITests: XCTestCase {
    private var tempDir: URL!
    private var store: PiPodsConfigStore!
    private var planner: PiPodsModelLifecyclePlanner!
    private var runtime: RecordingPodsRuntime!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-pods-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = PiPodsConfigStore(configDirectory: tempDir.path)
        runtime = RecordingPodsRuntime()

        let registry = PiPodsModelRegistry(models: [
            "demo-model": .init(name: "Demo", configs: [
                .init(gpuCount: 1, args: ["--gpu-memory-utilization", "0.8"])
            ])
        ])
        planner = PiPodsModelLifecyclePlanner(configStore: store, modelRegistry: registry)

        try store.save(.init(
            pods: [
                "alpha": .init(
                    ssh: "ssh -p 2222 root@1.2.3.4",
                    gpus: [.init(id: 0, name: "NVIDIA H100", memory: "80 GB")],
                    models: [:],
                    modelsPath: "/models"
                ),
                "beta": .init(
                    ssh: "ssh root@5.6.7.8",
                    gpus: [],
                    models: [:]
                )
            ],
            active: "alpha"
        ))
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testHelpAndVersion() {
        let help = run(["--help"])
        XCTAssertEqual(help.exitCode, 0)
        XCTAssertEqual(help.action, .showHelp)
        XCTAssertTrue(help.stdout.contains("Usage:"))
        XCTAssertTrue(help.stdout.contains("pods active <name>"))

        let version = run(["--version"])
        XCTAssertEqual(version.exitCode, 0)
        XCTAssertEqual(version.action, .showVersion)
        XCTAssertTrue(version.stdout.contains("pi-swift-pods"))
    }

    func testPodsListAndActivate() {
        let list = run(["pods"])
        XCTAssertEqual(list.exitCode, 0)
        XCTAssertEqual(list.action, .listPods)
        XCTAssertTrue(list.stdout.contains("* alpha"))
        XCTAssertTrue(list.stdout.contains("beta"))

        let activate = run(["pods", "active", "beta"])
        XCTAssertEqual(activate.exitCode, 0)
        XCTAssertEqual(store.load().active, "beta")
    }

    func testSSHCommandBuildsInvocationAndRoutesToRuntime() {
        runtime.nextResponse = .init(stdout: "ok\n")
        let result = run(["ssh", "echo hi"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .ssh(pod: nil, command: "echo hi"))
        XCTAssertEqual(runtime.calls.count, 1)
        XCTAssertEqual(runtime.calls[0].invocation.executable, "ssh")
        XCTAssertEqual(runtime.calls[0].invocation.arguments.last, "echo hi")
        XCTAssertTrue(runtime.calls[0].streaming)
    }

    func testStartCommandPlansAndPersistsModelEntry() {
        runtime.nextResponse = .init(stdout: "4242\n")
        let result = run([
            "start", "demo-model",
            "--name", "coder",
            "--memory", "90%",
            "--context", "32k"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(runtime.calls.count, 1)
        XCTAssertTrue(runtime.calls[0].invocation.arguments.contains("-t"))
        XCTAssertTrue(runtime.calls[0].invocation.arguments.contains("ServerAliveInterval=30"))
        XCTAssertTrue(runtime.calls[0].invocation.arguments.last?.contains("MODEL_NAME='coder'") == true)

        let config = store.load()
        XCTAssertEqual(config.pods["alpha"]?.models["coder"]?.pid, 4242)
        XCTAssertEqual(config.pods["alpha"]?.models["coder"]?.port, 8001)
        XCTAssertEqual(config.pods["alpha"]?.models["coder"]?.gpu, [0])
    }

    func testStopAndLogsCommandsRouteThroughRuntimeAndUpdateConfig() throws {
        var config = store.load()
        config.pods["alpha"]?.models["coder"] = .init(model: "demo-model", port: 8001, gpu: [0], pid: 4242)
        try store.save(config)

        runtime.nextResponse = .init(stdout: "")
        let logs = run(["logs", "coder"])
        XCTAssertEqual(logs.exitCode, 0)
        XCTAssertEqual(logs.action, .logs(instanceName: "coder", pod: nil))
        XCTAssertTrue(runtime.calls.last?.streaming == true)
        XCTAssertTrue(runtime.calls.last?.invocation.arguments.last?.contains("tail -f ~/.vllm_logs/coder.log") == true)

        let stop = run(["stop", "coder"])
        XCTAssertEqual(stop.exitCode, 0)
        XCTAssertEqual(runtime.calls.last?.invocation.arguments.last, "kill 4242")
        XCTAssertNil(store.load().pods["alpha"]?.models["coder"])
    }

    func testInvalidArgsReturnUsageError() {
        let result = run(["start", "demo-model"])
        XCTAssertEqual(result.exitCode, 2)
        if case .usageError = result.action {} else {
            XCTFail("Expected usage error")
        }
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }

    func testListModelsWithPodOverride() throws {
        var config = store.load()
        config.pods["beta"]?.models["other"] = .init(model: "m2", port: 9000, gpu: [1], pid: 111)
        try store.save(config)

        let result = run(["list", "--pod", "beta"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .listModels(pod: "beta"))
        XCTAssertTrue(result.stdout.contains("other m2 port=9000 pid=111"))
    }

    func testListModelsEmpty() {
        let result = run(["list"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .listModels(pod: nil))
        XCTAssertTrue(result.stdout.contains("(no models)"))
    }

    func testStopAllModelsReturnsCorrectCommand() throws {
        var config = store.load()
        config.pods["alpha"]?.models["coder"] = .init(model: "demo-model", port: 8001, gpu: [0], pid: 4242)
        config.pods["alpha"]?.models["coder2"] = .init(model: "demo-model", port: 8002, gpu: [1], pid: 4243)
        try store.save(config)

        runtime.nextResponse = .init(stdout: "")
        let stopAll = run(["stop"])
        XCTAssertEqual(stopAll.exitCode, 0)
        XCTAssertEqual(stopAll.action, .stop(instanceName: nil, pod: nil))
        // stop without name plans stop all, killing 4242 and 4243
        XCTAssertTrue(runtime.calls.last?.invocation.arguments.last?.contains("kill 4242") == true || runtime.calls.last?.invocation.arguments.last?.contains("kill 4243") == true)
        
        let loadedConfig = store.load()
        XCTAssertTrue(loadedConfig.pods["alpha"]?.models.isEmpty == true)
    }

    func testStartArgumentParsingEdgeCases() {
        // Missing value for --name
        let result1 = run(["start", "model", "--name"])
        XCTAssertEqual(result1.exitCode, 2)
        XCTAssertTrue(result1.stderr.contains("Missing value for --name"))

        // Missing value for --pod
        let result2 = run(["start", "model", "--name", "n1", "--pod"])
        XCTAssertEqual(result2.exitCode, 2)
        XCTAssertTrue(result2.stderr.contains("Missing value for --pod"))

        // Missing value for --memory
        let result3 = run(["start", "model", "--name", "n1", "--memory"])
        XCTAssertEqual(result3.exitCode, 2)
        XCTAssertTrue(result3.stderr.contains("Missing value for --memory"))

        // Missing value for --context
        let result4 = run(["start", "model", "--name", "n1", "--context"])
        XCTAssertEqual(result4.exitCode, 2)
        XCTAssertTrue(result4.stderr.contains("Missing value for --context"))

        // Invalid gpus type
        let result5 = run(["start", "model", "--name", "n1", "--gpus", "abc"])
        XCTAssertEqual(result5.exitCode, 2)
        XCTAssertTrue(result5.stderr.contains("--gpus must be a positive number"))
        
        // Unknown option
        let result6 = run(["start", "model", "--name", "n1", "--unknown-opt"])
        XCTAssertEqual(result6.exitCode, 2)
        XCTAssertTrue(result6.stderr.contains("Unknown option: --unknown-opt"))
    }
    
    func testStartFailureDueToPlannerError() {
        // Attempt to start unknown model with GPU override (unsupported)
        let result = run(["start", "unknown-repo/model", "--name", "n1", "--gpus", "1"])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("--gpus is only supported for known models"))
    }

    func testLogsForNonExistentModel() {
        let logs = run(["logs", "non-existent"])
        XCTAssertEqual(logs.exitCode, 1)
        XCTAssertTrue(logs.stderr.contains("Model 'non-existent' not found."))
    }

    func testSSHActionCommandBuildingEdgeCases() {
        // Run SSH against explicit pod
        runtime.nextResponse = .init()
        let result1 = run(["ssh", "beta", "echo pod override"])
        XCTAssertEqual(result1.exitCode, 0)
        XCTAssertEqual(result1.action, .ssh(pod: "beta", command: "echo pod override"))
        
        // Empty pod lookup failure
        let result2 = run(["ssh", "unknown_pod", "echo fail"])
        XCTAssertEqual(result2.exitCode, 1)
        XCTAssertTrue(result2.stderr.contains("podNotFound") || result2.stderr.contains("not found"))
    }

    private func run(_ argv: [String]) -> PiPodsCLIResult {
        PiPodsCLIApp.run(
            argv: argv,
            env: .init(executableName: "pi-pods", processEnv: ["HF_TOKEN": "hf_x", "PI_API_KEY": "pi_y"]),
            configStore: store,
            planner: planner,
            runtime: runtime
        )
    }
}

private final class RecordingPodsRuntime: PiPodsCLIRuntime, @unchecked Sendable {
    struct Call: Equatable {
        var invocation: PiPodsSSHInvocation
        var streaming: Bool
    }

    var nextResponse = PiPodsCLIRuntimeResponse()
    private(set) var calls: [Call] = []

    func run(_ invocation: PiPodsSSHInvocation, streaming: Bool) -> PiPodsCLIRuntimeResponse {
        calls.append(.init(invocation: invocation, streaming: streaming))
        return nextResponse
    }
}
