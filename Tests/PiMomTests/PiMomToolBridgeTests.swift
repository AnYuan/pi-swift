import XCTest
import Foundation
import PiCoreTypes
@testable import PiMom
@testable import PiCodingAgent

final class PiMomToolBridgeTests: XCTestCase {
    func testCreateMomToolRegistryIncludesCoreToolsAndAttach() {
        let executor = RecordingMomExecutor()
        let registry = PiMomToolBridge.makeToolRegistry(
            workspaceDirectory: "/tmp/work",
            executor: executor,
            uploadFile: { _, _ in }
        )

        XCTAssertEqual(registry.listDefinitions().map(\.name), ["attach", "bash", "edit", "read", "write"])
    }

    func testMomBashToolDelegatesToSandboxExecutor() throws {
        let executor = RecordingMomExecutor(result: .init(stdout: "ok", stderr: "", code: 0))
        let tool = PiMomBashTool(executor: executor)

        let result = try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "command": .string("echo hi"),
                "timeout": .number(3)
            ])
        )

        XCTAssertEqual(executor.calls.count, 1)
        XCTAssertEqual(executor.calls[0].command, "echo hi")
        XCTAssertEqual(executor.calls[0].options.timeoutSeconds, 3)
        XCTAssertEqual(extractText(result), "ok")
    }

    func testMomAttachToolUploadsFileInsideWorkspace() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("report.txt")
        try "hi".write(to: fileURL, atomically: true, encoding: .utf8)

        let uploads = UploadRecorder()
        let tool = PiMomAttachTool(workspaceDirectory: tempDir.path, uploader: uploads)
        let result = try tool.execute(
            toolCallID: "a1",
            arguments: .object(["path": .string(fileURL.path)])
        )

        XCTAssertEqual(uploads.calls, [.init(filePath: fileURL.path, title: "report.txt")])
        XCTAssertEqual(extractText(result), "Attached file: report.txt")
    }

    func testMomAttachToolRejectsPathsOutsideWorkspace() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let outsideURL = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "x".write(to: outsideURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        let tool = PiMomAttachTool(workspaceDirectory: tempDir.path, uploader: UploadRecorder())
        XCTAssertThrowsError(try tool.execute(toolCallID: "a1", arguments: .object(["path": .string(outsideURL.path)]))) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("Attach path must be inside workspace: \(outsideURL.path)"))
        }
    }

    private func extractText(_ result: PiCodingAgentToolResult) -> String? {
        guard result.content.count == 1 else { return nil }
        guard case .text(let text) = result.content[0] else { return nil }
        return text.text
    }
}

private final class RecordingMomExecutor: PiMomExecutor, @unchecked Sendable {
    struct Call: Equatable {
        var command: String
        var options: PiMomExecOptions
    }

    private let resultValue: PiMomExecResult
    private(set) var calls: [Call] = []

    init(result: PiMomExecResult = .init(stdout: "", stderr: "", code: 0)) {
        self.resultValue = result
    }

    func exec(_ command: String, options: PiMomExecOptions) throws -> PiMomExecResult {
        calls.append(.init(command: command, options: options))
        return resultValue
    }

    func workspacePath(forHostPath hostPath: String) -> String {
        hostPath
    }
}

private final class UploadRecorder: PiMomFileUploading, @unchecked Sendable {
    struct Call: Equatable {
        var filePath: String
        var title: String
    }

    private(set) var calls: [Call] = []

    func upload(filePath: String, title: String) {
        calls.append(.init(filePath: filePath, title: title))
    }
}
