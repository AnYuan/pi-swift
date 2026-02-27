import Foundation
import PiCoreTypes
import PiAI

public struct PiCodingAgentModeInput: Equatable, Sendable {
    public var prompt: String?
    public var pipedInput: String?

    public init(prompt: String? = nil, pipedInput: String? = nil) {
        self.prompt = prompt
        self.pipedInput = pipedInput
    }
}

public struct PiCodingAgentRPCErrorEnvelope: Codable, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

private struct PiCodingAgentRPCRequestEnvelope: Codable, Equatable {
    var id: String?
    var method: String
    var params: [String: JSONValue]?
}

private struct PiCodingAgentRPCResponseEnvelope: Codable, Equatable {
    var id: String?
    var result: [String: JSONValue]?
    var error: PiCodingAgentRPCErrorEnvelope?
}

public final class PiCodingAgentModeRunner {
    public let version: String
    private let encoder: JSONEncoder
    private let toolRegistry: PiCodingAgentToolRegistry?
    private let localRuntime: PiCodingAgentOpenAICompatibleRuntime

    public init(
        version: String = PiCodingAgentCLIApp.versionString,
        toolRegistry: PiCodingAgentToolRegistry? = nil,
        localRuntime: PiCodingAgentOpenAICompatibleRuntime = .init()
    ) {
        self.version = version
        self.toolRegistry = toolRegistry
        self.localRuntime = localRuntime
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public func runPrint(_ input: PiCodingAgentModeInput) -> String {
        let prompt = input.prompt ?? ""
        let piped = input.pipedInput ?? ""
        return """
        mode: print
        version: \(version)
        prompt: \(prompt)
        pipedInput: \(piped)
        status: ok
        """
    }

    public func runJSON(_ input: PiCodingAgentModeInput) -> String {
        let events: [[String: String]] = [
            [
                "type": "mode.start",
                "mode": "json",
                "version": version,
            ],
            [
                "type": "input",
                "prompt": input.prompt ?? "",
                "pipedInput": input.pipedInput ?? "",
            ],
            [
                "type": "result",
                "status": "ok",
            ]
        ]

        return events.compactMap { event -> String? in
            guard let data = try? encoder.encode(event) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
    }

    public func handleRPC(_ requestJSON: String) async throws -> String {
        let request = try JSONDecoder().decode(PiCodingAgentRPCRequestEnvelope.self, from: Data(requestJSON.utf8))

        let response: PiCodingAgentRPCResponseEnvelope
        switch request.method {
        case "ping":
            response = .init(id: request.id, result: [
                "ok": .bool(true),
                "version": .string(version),
            ], error: nil)
        case "run.print":
            let input = PiCodingAgentModeInput(
                prompt: request.params?["prompt"]?.stringValue,
                pipedInput: request.params?["pipedInput"]?.stringValue
            )
            response = .init(id: request.id, result: [
                "output": .string(runPrint(input))
            ], error: nil)
        case "run.json":
            let input = PiCodingAgentModeInput(
                prompt: request.params?["prompt"]?.stringValue,
                pipedInput: request.params?["pipedInput"]?.stringValue
            )
            response = .init(id: request.id, result: [
                "output": .string(runJSON(input))
            ], error: nil)
        case "run.local":
            guard let prompt = request.params?["prompt"]?.stringValue, !prompt.isEmpty else {
                response = .init(id: request.id, result: nil, error: .init(code: "invalid_params", message: "Missing run.local param: prompt"))
                break
            }
            let provider = request.params?["provider"]?.stringValue ?? "openai-compatible"
            let modelID = request.params?["model"]?.stringValue
                ?? PiCodingAgentModelResolver.defaultModelPerProvider["openai-compatible"]
                ?? "mlx-community/Qwen3.5-35B-A3B-bf16"
            let baseURL = request.params?["baseURL"]?.stringValue ?? "http://127.0.0.1:1234"
            let path = request.params?["path"]?.stringValue ?? "/v1/chat/completions"
            let apiKey = request.params?["apiKey"]?.stringValue
            let systemPrompt = request.params?["systemPrompt"]?.stringValue

            let model = PiAIOpenAICompatibleHTTPModel(
                provider: provider,
                id: modelID,
                baseURL: baseURL,
                completionsPath: path
            )
            let message = await localRuntime.run(
                prompt: prompt,
                systemPrompt: systemPrompt,
                model: model,
                apiKey: apiKey
            )
            if message.stopReason == .error {
                response = .init(
                    id: request.id,
                    result: nil,
                    error: .init(code: "local_runtime_error", message: message.errorMessage ?? "Local model request failed")
                )
            } else {
                response = .init(
                    id: request.id,
                    result: [
                        "output": .string(extractAssistantText(message)),
                        "provider": .string(message.provider),
                        "model": .string(message.model),
                        "stopReason": .string(message.stopReason.rawValue),
                    ],
                    error: nil
                )
            }
        case "tools.list":
            let definitions = toolRegistry?.listDefinitions() ?? []
            response = .init(id: request.id, result: [
                "tools": .array(definitions.compactMap { jsonValue(fromCodable: $0) })
            ], error: nil)
        case "tools.execute":
            guard let toolRegistry else {
                response = .init(id: request.id, result: nil, error: .init(code: "tooling_unavailable", message: "No tool registry configured"))
                break
            }
            guard let name = request.params?["name"]?.stringValue else {
                response = .init(id: request.id, result: nil, error: .init(code: "invalid_params", message: "Missing tools.execute param: name"))
                break
            }
            let toolCallID = request.params?["id"]?.stringValue ?? UUID().uuidString
            let arguments = request.params?["arguments"] ?? .object([:])
            do {
                let result = try await toolRegistry.execute(.init(id: toolCallID, name: name, arguments: arguments))
                response = .init(id: request.id, result: [
                    "toolCallID": .string(toolCallID),
                    "text": .string(extractToolText(result)),
                    "details": result.details ?? .null
                ], error: nil)
            } catch {
                response = .init(
                    id: request.id,
                    result: nil,
                    error: .init(code: "tool_error", message: String(describing: error))
                )
            }
        default:
            response = .init(
                id: request.id,
                result: nil,
                error: .init(code: "method_not_found", message: "Unknown RPC method: \(request.method)")
            )
        }

        let data = try encoder.encode(response)
        return String(decoding: data, as: UTF8.self)
    }
}

public struct PiCodingAgentSDK {
    public var runner: PiCodingAgentModeRunner

    public init(runner: PiCodingAgentModeRunner = .init()) {
        self.runner = runner
    }

    public func runPrint(prompt: String? = nil, pipedInput: String? = nil) -> String {
        runner.runPrint(.init(prompt: prompt, pipedInput: pipedInput))
    }

    public func runJSON(prompt: String? = nil, pipedInput: String? = nil) -> String {
        runner.runJSON(.init(prompt: prompt, pipedInput: pipedInput))
    }

    public func handleRPC(_ requestJSON: String) async throws -> String {
        try await runner.handleRPC(requestJSON)
    }

    public func listTools() -> [PiToolDefinition] {
        runner.listTools()
    }

    public func executeTool(_ call: PiToolCall) async throws -> PiCodingAgentToolResult {
        try await runner.executeTool(call)
    }
}

extension PiCodingAgentModeRunner {
    public func listTools() -> [PiToolDefinition] {
        toolRegistry?.listDefinitions() ?? []
    }

    public func executeTool(_ call: PiToolCall) async throws -> PiCodingAgentToolResult {
        guard let toolRegistry else {
            throw PiCodingAgentToolError.io("No tool registry configured")
        }
        return try await toolRegistry.execute(call)
    }
}

private func extractToolText(_ result: PiCodingAgentToolResult) -> String {
    result.content.compactMap { part -> String? in
        if case .text(let content) = part { return content.text }
        return nil
    }.joined(separator: "\n")
}

private func extractAssistantText(_ message: PiAIAssistantMessage) -> String {
    message.content.compactMap { part -> String? in
        if case .text(let content) = part { return content.text }
        return nil
    }.joined(separator: "\n")
}

private func jsonValue(fromCodable value: some Encodable) -> JSONValue? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(AnyEncodable(value)),
          let object = try? JSONDecoder().decode(JSONValue.self, from: data) else {
        return nil
    }
    return object
}

private struct AnyEncodable: Encodable {
    let encodeFunc: (Encoder) throws -> Void

    init(_ wrapped: some Encodable) {
        self.encodeFunc = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
