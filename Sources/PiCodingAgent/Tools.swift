import Foundation
import PiAI
import PiCoreTypes

public struct PiCodingAgentToolResult: Equatable, Sendable {
    public var content: [PiAIToolResultContentPart]
    public var details: JSONValue?

    public init(content: [PiAIToolResultContentPart], details: JSONValue? = nil) {
        self.content = content
        self.details = details
    }
}

public enum PiCodingAgentToolError: Error, Equatable, CustomStringConvertible {
    case invalidArguments(String)
    case unknownTool(String)
    case io(String)

    public var description: String {
        switch self {
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .io(let message): return "I/O error: \(message)"
        }
    }
}

public protocol PiCodingAgentTool: Sendable {
    var definition: PiToolDefinition { get }
    func execute(toolCallID: String, arguments: JSONValue) throws -> PiCodingAgentToolResult
}

public struct PiCodingAgentToolRegistry: Sendable {
    private var toolsByName: [String: any PiCodingAgentTool]

    public init(tools: [any PiCodingAgentTool] = []) {
        self.toolsByName = [:]
        for tool in tools {
            toolsByName[tool.definition.name] = tool
        }
    }

    public func listDefinitions() -> [PiToolDefinition] {
        toolsByName.values.map(\.definition).sorted { $0.name < $1.name }
    }

    public func execute(_ call: PiToolCall) throws -> PiCodingAgentToolResult {
        guard let tool = toolsByName[call.name] else {
            throw PiCodingAgentToolError.unknownTool(call.name)
        }
        return try tool.execute(toolCallID: call.id, arguments: call.arguments)
    }
}

public struct PiFileReadTool: PiCodingAgentTool, @unchecked Sendable {
    public let baseDirectory: String
    private let fileManager: FileManager

    public init(baseDirectory: String, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    public var definition: PiToolDefinition {
        .init(
            name: "read",
            description: "Read a text file",
            parameters: .init(
                type: .object,
                properties: [
                    "path": .init(type: .string),
                    "offset": .init(type: .integer),
                    "limit": .init(type: .integer),
                ],
                required: ["path"],
                additionalProperties: false
            )
        )
    }

    public func execute(toolCallID: String, arguments: JSONValue) throws -> PiCodingAgentToolResult {
        let object = try requireObject(arguments)
        let path = try requireString(object, key: "path")
        let offset = intValue(object["offset"]) ?? 0
        let limit = intValue(object["limit"])

        let resolved = resolvePath(path)
        guard fileManager.fileExists(atPath: resolved) else {
            throw PiCodingAgentToolError.io("File not found: \(path)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: resolved))
        } catch {
            throw PiCodingAgentToolError.io("Failed to read file: \(path)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PiCodingAgentToolError.io("Non-UTF8 file not supported in read tool: \(path)")
        }

        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard offset >= 0 else {
            throw PiCodingAgentToolError.invalidArguments("offset must be >= 0")
        }
        guard offset <= allLines.count else {
            throw PiCodingAgentToolError.io("offset \(offset) is beyond end of file")
        }

        let selected: [String]
        let truncation: JSONValue?
        if let limit, limit >= 0 {
            let end = min(allLines.count, offset + limit)
            selected = Array(allLines[offset..<end])
            truncation = end < allLines.count
                ? .object([
                    "offset": .number(Double(offset)),
                    "limit": .number(Double(limit)),
                    "remainingLines": .number(Double(allLines.count - end))
                ])
                : nil
        } else {
            selected = offset == allLines.count ? [] : Array(allLines[offset...])
            truncation = nil
        }

        var output = selected.joined(separator: "\n")
        if let limit, let truncation {
            output += "\n\n[truncated: showing \(selected.count) lines from offset \(offset); use offset=\(offset + limit)]"
            return .init(content: [.text(.init(text: output))], details: .object(["truncation": truncation]))
        }

        return .init(content: [.text(.init(text: output))])
    }

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") { return path }
        return (baseDirectory as NSString).appendingPathComponent(path)
    }
}

public struct PiFileWriteTool: PiCodingAgentTool, @unchecked Sendable {
    public let baseDirectory: String
    private let fileManager: FileManager

    public init(baseDirectory: String, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    public var definition: PiToolDefinition {
        .init(
            name: "write",
            description: "Write a text file",
            parameters: .init(
                type: .object,
                properties: [
                    "path": .init(type: .string),
                    "content": .init(type: .string),
                ],
                required: ["path", "content"],
                additionalProperties: false
            )
        )
    }

    public func execute(toolCallID: String, arguments: JSONValue) throws -> PiCodingAgentToolResult {
        let object = try requireObject(arguments)
        let path = try requireString(object, key: "path")
        let content = try requireString(object, key: "content")
        let resolved = path.hasPrefix("/") ? path : (baseDirectory as NSString).appendingPathComponent(path)

        let dir = (resolved as NSString).deletingLastPathComponent
        do {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            try content.write(toFile: resolved, atomically: true, encoding: .utf8)
        } catch {
            throw PiCodingAgentToolError.io("Failed to write file: \(path)")
        }

        return .init(content: [.text(.init(text: "Wrote \(content.utf8.count) bytes to \(path)"))])
    }
}

public struct PiFileEditTool: PiCodingAgentTool, @unchecked Sendable {
    public let baseDirectory: String
    private let fileManager: FileManager

    public init(baseDirectory: String, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    public var definition: PiToolDefinition {
        .init(
            name: "edit",
            description: "Replace a unique text snippet in a file",
            parameters: .init(
                type: .object,
                properties: [
                    "path": .init(type: .string),
                    "oldText": .init(type: .string),
                    "newText": .init(type: .string),
                ],
                required: ["path", "oldText", "newText"],
                additionalProperties: false
            )
        )
    }

    public func execute(toolCallID: String, arguments: JSONValue) throws -> PiCodingAgentToolResult {
        let object = try requireObject(arguments)
        let path = try requireString(object, key: "path")
        let oldText = try requireString(object, key: "oldText")
        let newText = try requireString(object, key: "newText")
        guard oldText != newText else {
            throw PiCodingAgentToolError.invalidArguments("oldText and newText are identical")
        }

        let resolved = path.hasPrefix("/") ? path : (baseDirectory as NSString).appendingPathComponent(path)
        guard fileManager.fileExists(atPath: resolved) else {
            throw PiCodingAgentToolError.io("File not found: \(path)")
        }

        let original: String
        do {
            original = try String(contentsOfFile: resolved, encoding: .utf8)
        } catch {
            throw PiCodingAgentToolError.io("Failed to read file: \(path)")
        }

        let matches = original.ranges(of: oldText)
        guard !matches.isEmpty else {
            throw PiCodingAgentToolError.io("oldText not found in \(path)")
        }
        guard matches.count == 1, let range = matches.first else {
            throw PiCodingAgentToolError.io("oldText matched multiple locations in \(path)")
        }

        let updated = original.replacingCharacters(in: range, with: newText)
        do {
            try updated.write(toFile: resolved, atomically: true, encoding: .utf8)
        } catch {
            throw PiCodingAgentToolError.io("Failed to write file: \(path)")
        }

        let lineEnding = original.contains("\r\n") ? "\r\n" : "\n"
        let summary = [
            "--- old",
            "+++ new",
            "- \(oldText.replacingOccurrences(of: lineEnding, with: "\\n"))",
            "+ \(newText.replacingOccurrences(of: lineEnding, with: "\\n"))"
        ].joined(separator: "\n")

        return .init(
            content: [.text(.init(text: "Edited \(path)"))],
            details: .object([
                "diff": .string(summary),
                "replacements": .number(1),
            ])
        )
    }
}

public struct PiBashTool: PiCodingAgentTool, @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        public var workingDirectory: String
        public var shellPath: String
        public var commandPrefix: String?
        public var defaultTimeoutSeconds: TimeInterval
        public var maxOutputBytes: Int

        public init(
            workingDirectory: String,
            shellPath: String = "/bin/zsh",
            commandPrefix: String? = nil,
            defaultTimeoutSeconds: TimeInterval = 10,
            maxOutputBytes: Int = 32_768
        ) {
            self.workingDirectory = workingDirectory
            self.shellPath = shellPath
            self.commandPrefix = commandPrefix
            self.defaultTimeoutSeconds = defaultTimeoutSeconds
            self.maxOutputBytes = max(256, maxOutputBytes)
        }
    }

    public let configuration: Configuration
    private let fileManager: FileManager

    public init(configuration: Configuration, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public var definition: PiToolDefinition {
        .init(
            name: "bash",
            description: "Execute a shell command",
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

    public func execute(toolCallID: String, arguments: JSONValue) throws -> PiCodingAgentToolResult {
        let object = try requireObject(arguments)
        let command = try requireString(object, key: "command")
        let timeout = doubleValue(object["timeout"]) ?? configuration.defaultTimeoutSeconds

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: configuration.workingDirectory, isDirectory: &isDir), isDir.boolValue else {
            throw PiCodingAgentToolError.io("Working directory not found: \(configuration.workingDirectory)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.shellPath)
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.workingDirectory)

        let composedCommand: String = {
            if let commandPrefix = configuration.commandPrefix, !commandPrefix.isEmpty {
                return commandPrefix + "\n" + command
            }
            return command
        }()
        process.arguments = ["-lc", composedCommand]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw PiCodingAgentToolError.io("Failed to spawn shell: \(configuration.shellPath)")
        }

        let sema = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sema.signal() }
        let waitResult = sema.wait(timeout: .now() + max(0.1, timeout))
        if waitResult == .timedOut {
            process.terminate()
            _ = sema.wait(timeout: .now() + 1)
            throw PiCodingAgentToolError.io("Command timed out after \(Int(timeout))s")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var details: [String: JSONValue] = [
            "exitCode": .number(Double(process.terminationStatus))
        ]

        if output.utf8.count > configuration.maxOutputBytes {
            let suffixData = Data(output.utf8.suffix(configuration.maxOutputBytes))
            output = String(data: suffixData, encoding: .utf8) ?? String(decoding: suffixData, as: UTF8.self)
            details["truncated"] = .bool(true)
        }

        if process.terminationStatus != 0 {
            throw PiCodingAgentToolError.io("Command failed with exit code \(process.terminationStatus): \(output)")
        }

        return .init(content: [.text(.init(text: output))], details: .object(details))
    }
}

private func requireObject(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let obj) = value else {
        throw PiCodingAgentToolError.invalidArguments("expected object arguments")
    }
    return obj
}

private func requireString(_ obj: [String: JSONValue], key: String) throws -> String {
    guard let value = obj[key] else {
        throw PiCodingAgentToolError.invalidArguments("missing `\(key)`")
    }
    guard case .string(let str) = value else {
        throw PiCodingAgentToolError.invalidArguments("`\(key)` must be string")
    }
    return str
}

private func intValue(_ value: JSONValue?) -> Int? {
    guard let value else { return nil }
    switch value {
    case .number(let n):
        return Int(n)
    case .string(let s):
        return Int(s)
    default:
        return nil
    }
}

private func doubleValue(_ value: JSONValue?) -> Double? {
    guard let value else { return nil }
    switch value {
    case .number(let n):
        return n
    case .string(let s):
        return Double(s)
    default:
        return nil
    }
}

private extension String {
    func ranges(of needle: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var results: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = self.range(of: needle, range: searchStart..<endIndex) {
            results.append(range)
            searchStart = range.upperBound
        }
        return results
    }
}
