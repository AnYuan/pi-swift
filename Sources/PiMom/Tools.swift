import Foundation
import PiAI
import PiCodingAgent
import PiCoreTypes

public protocol PiMomFileUploading: Sendable {
    func upload(filePath: String, title: String)
}

public struct PiMomBashTool: PiCodingAgentTool, Sendable {
    public let executor: any PiMomExecutor

    public init(executor: any PiMomExecutor) {
        self.executor = executor
    }

    public var definition: PiToolDefinition {
        .init(
            name: "bash",
            description: "Execute a shell command in mom's sandbox",
            parameters: .init(
                type: .object,
                properties: [
                    "command": .init(type: .string),
                    "timeout": .init(type: .number),
                ],
                required: ["command"],
                additionalProperties: false
            )
        )
    }

    public func execute(toolCallID: String, arguments: JSONValue) async throws -> PiCodingAgentToolResult {
        _ = toolCallID
        let object = try momRequireObject(arguments)
        let command = try momRequireString(object, key: "command")
        let timeout = object["timeout"]?.numberValue

        let execResult = try executor.exec(command, options: .init(timeoutSeconds: timeout))
        var output = execResult.stdout
        if !execResult.stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += execResult.stderr
        }
        if output.isEmpty { output = "(no output)" }

        if execResult.code != 0 {
            throw PiCodingAgentToolError.io("\(output)\n\nCommand exited with code \(execResult.code)")
        }

        return .init(content: [.text(.init(text: output))])
    }
}

public struct PiMomAttachTool: PiCodingAgentTool, Sendable {
    public let workspaceDirectory: String
    public let uploader: any PiMomFileUploading

    public init(workspaceDirectory: String, uploader: any PiMomFileUploading) {
        self.workspaceDirectory = URL(fileURLWithPath: workspaceDirectory).standardizedFileURL.path
        self.uploader = uploader
    }

    public var definition: PiToolDefinition {
        .init(
            name: "attach",
            description: "Attach a file from the mom workspace to the Slack response",
            parameters: .init(
                type: .object,
                properties: [
                    "path": .init(type: .string),
                    "title": .init(type: .string),
                ],
                required: ["path"],
                additionalProperties: false
            )
        )
    }

    public func execute(toolCallID: String, arguments: JSONValue) async throws -> PiCodingAgentToolResult {
        _ = toolCallID
        let object = try momRequireObject(arguments)
        let rawPath = try momRequireString(object, key: "path")
        let resolved = URL(fileURLWithPath: rawPath, relativeTo: URL(fileURLWithPath: workspaceDirectory))
            .standardizedFileURL.path

        guard isPathInsideWorkspace(resolved) else {
            throw PiCodingAgentToolError.io("Attach path must be inside workspace: \(resolved)")
        }
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw PiCodingAgentToolError.io("Attach file not found: \(resolved)")
        }

        let title = object["title"]?.stringValue ?? URL(fileURLWithPath: resolved).lastPathComponent
        uploader.upload(filePath: resolved, title: title)
        return .init(content: [.text(.init(text: "Attached file: \(title)"))])
    }

    private func isPathInsideWorkspace(_ path: String) -> Bool {
        path == workspaceDirectory || path.hasPrefix(workspaceDirectory + "/")
    }
}

public enum PiMomToolBridge {
    public static func makeToolRegistry(
        workspaceDirectory: String,
        executor: any PiMomExecutor,
        uploadFile: @escaping @Sendable (String, String) -> Void
    ) -> PiCodingAgentToolRegistry {
        let uploader = ClosureUploader(upload: uploadFile)
        return .init(tools: [
            PiFileReadTool(baseDirectory: workspaceDirectory),
            PiMomBashTool(executor: executor),
            PiFileEditTool(baseDirectory: workspaceDirectory),
            PiFileWriteTool(baseDirectory: workspaceDirectory),
            PiMomAttachTool(workspaceDirectory: workspaceDirectory, uploader: uploader),
        ])
    }

    private struct ClosureUploader: PiMomFileUploading, Sendable {
        let upload: @Sendable (String, String) -> Void

        func upload(filePath: String, title: String) {
            upload(filePath, title)
        }
    }
}

private func momRequireObject(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let object) = value else {
        throw PiCodingAgentToolError.invalidArguments("Expected object arguments")
    }
    return object
}

private func momRequireString(_ object: [String: JSONValue], key: String) throws -> String {
    guard let value = object[key], case .string(let string) = value else {
        throw PiCodingAgentToolError.invalidArguments("Missing string argument: \(key)")
    }
    return string
}

private extension JSONValue {
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
