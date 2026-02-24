import Foundation
import PiCoreTypes

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

    public init(version: String = PiCodingAgentCLIApp.versionString) {
        self.version = version
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

    public func handleRPC(_ requestJSON: String) throws -> String {
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

    public func handleRPC(_ requestJSON: String) throws -> String {
        try runner.handleRPC(requestJSON)
    }
}
