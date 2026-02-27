import Foundation
import PiCoreTypes

public struct PiAIOpenAICompatibleHTTPModel: Equatable, Sendable {
    public var provider: String
    public var id: String
    public var api: String
    public var baseURL: String
    public var completionsPath: String

    public init(
        provider: String = "openai-compatible",
        id: String,
        api: String = "openai-chat-completions",
        baseURL: String,
        completionsPath: String = "/v1/chat/completions"
    ) {
        self.provider = provider
        self.id = id
        self.api = api
        self.baseURL = baseURL
        self.completionsPath = completionsPath
    }
}

public struct PiAIOpenAICompatibleHTTPRequest: Sendable {
    public var url: URL
    public var headers: [String: String]
    public var body: Data

    public init(url: URL, headers: [String: String], body: Data) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct PiAIOpenAICompatibleHTTPResponse: Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol PiAIOpenAICompatibleHTTPTransport: Sendable {
    func perform(_ request: PiAIOpenAICompatibleHTTPRequest) async throws -> PiAIOpenAICompatibleHTTPResponse
}

public struct PiAIOpenAICompatibleURLSessionTransport: PiAIOpenAICompatibleHTTPTransport, Sendable {
    public init() {}

    public func perform(_ request: PiAIOpenAICompatibleHTTPRequest) async throws -> PiAIOpenAICompatibleHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return .init(statusCode: statusCode, body: data)
    }
}

public enum PiAIOpenAICompatibleHTTPError: Error, Equatable, Sendable {
    case invalidURL(String)
    case transport(String)
    case badStatus(code: Int, body: String)
    case invalidResponse(String)
}

public struct PiAIOpenAICompatibleHTTPProvider: Sendable {
    private let transport: any PiAIOpenAICompatibleHTTPTransport

    public init(transport: any PiAIOpenAICompatibleHTTPTransport = PiAIOpenAICompatibleURLSessionTransport()) {
        self.transport = transport
    }

    public func stream(
        model: PiAIOpenAICompatibleHTTPModel,
        context: PiAIContext,
        apiKey: String? = nil,
        extraHeaders: [String: String] = [:]
    ) -> PiAIAssistantMessageEventStream {
        let stream = PiAIAssistantMessageEventStream()

        Task {
            do {
                let request = try makeRequest(model: model, context: context, apiKey: apiKey, extraHeaders: extraHeaders)
                let response = try await perform(request: request)
                var output = try decodeResponse(response.body, model: model, timestamp: currentTimestamp())

                await stream.push(.start(partial: output))
                for block in output.content.enumerated() {
                    switch block.element {
                    case .text(let textBlock):
                        await stream.push(.textStart(contentIndex: block.offset, partial: output))
                        await stream.push(.textDelta(contentIndex: block.offset, delta: textBlock.text, partial: output))
                        await stream.push(.textEnd(contentIndex: block.offset, content: textBlock.text, partial: output))
                    case .toolCall(let toolCall):
                        await stream.push(.toolCallStart(contentIndex: block.offset, partial: output))
                        let argumentsJSON = serializeJSONObject(toolCall.arguments)
                        await stream.push(.toolCallDelta(contentIndex: block.offset, delta: argumentsJSON, partial: output))
                        await stream.push(.toolCallEnd(contentIndex: block.offset, toolCall: toolCall, partial: output))
                    case .thinking:
                        break
                    }
                }

                if output.stopReason == .error && output.errorMessage == nil {
                    output.errorMessage = "OpenAI-compatible response returned error finish reason"
                }
                await stream.push(.done(reason: output.stopReason, message: output))
            } catch {
                let errorMessage = describe(error)
                let terminal = PiAIAssistantMessage(
                    content: [],
                    api: model.api,
                    provider: model.provider,
                    model: model.id,
                    usage: .zero,
                    stopReason: .error,
                    errorMessage: errorMessage,
                    timestamp: currentTimestamp()
                )
                await stream.push(.error(reason: .error, error: terminal))
            }
        }

        return stream
    }

    private func makeRequest(
        model: PiAIOpenAICompatibleHTTPModel,
        context: PiAIContext,
        apiKey: String?,
        extraHeaders: [String: String]
    ) throws -> PiAIOpenAICompatibleHTTPRequest {
        guard var url = URL(string: model.baseURL) else {
            throw PiAIOpenAICompatibleHTTPError.invalidURL(model.baseURL)
        }
        let path = model.completionsPath.hasPrefix("/") ? model.completionsPath : "/" + model.completionsPath
        url.append(path: path)

        let payload = OpenAICompatibleRequestBody(
            model: model.id,
            messages: context.messages.compactMap(asRequestMessage),
            tools: context.tools?.map {
                .init(function: .init(
                    name: $0.name,
                    description: $0.description,
                    parameters: $0.parameters
                ))
            },
            stream: false
        )
        let bodyData = try JSONEncoder().encode(payload)

        var headers = ["Content-Type": "application/json"]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        for (name, value) in extraHeaders {
            headers[name] = value
        }
        return .init(url: url, headers: headers, body: bodyData)
    }

    private func perform(request: PiAIOpenAICompatibleHTTPRequest) async throws -> PiAIOpenAICompatibleHTTPResponse {
        do {
            let response = try await transport.perform(request)
            if !(200..<300).contains(response.statusCode) {
                let body = String(data: response.body, encoding: .utf8) ?? ""
                throw PiAIOpenAICompatibleHTTPError.badStatus(code: response.statusCode, body: body)
            }
            return response
        } catch let error as PiAIOpenAICompatibleHTTPError {
            throw error
        } catch {
            throw PiAIOpenAICompatibleHTTPError.transport(describe(error))
        }
    }

    private func decodeResponse(_ data: Data, model: PiAIOpenAICompatibleHTTPModel, timestamp: Int64) throws -> PiAIAssistantMessage {
        let decoded: OpenAICompatibleResponse
        do {
            decoded = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
        } catch {
            throw PiAIOpenAICompatibleHTTPError.invalidResponse("Failed to decode response JSON")
        }
        guard let choice = decoded.choices.first else {
            throw PiAIOpenAICompatibleHTTPError.invalidResponse("Missing response choice")
        }

        var contentBlocks: [PiAIAssistantContentPart] = []
        let text = extractContentText(choice.message.content)
        if !text.isEmpty {
            contentBlocks.append(.text(.init(text: text)))
        }
        for call in choice.message.toolCalls ?? [] {
            let args = extractJSONObject(PiAIJSON.parseStreamingJSON(call.function.arguments))
            contentBlocks.append(.toolCall(.init(id: call.id, name: call.function.name, arguments: args)))
        }

        let usage = PiAIUsage(
            input: decoded.usage?.promptTokens ?? 0,
            output: decoded.usage?.completionTokens ?? 0,
            cacheRead: 0,
            cacheWrite: 0,
            totalTokens: decoded.usage?.totalTokens ?? ((decoded.usage?.promptTokens ?? 0) + (decoded.usage?.completionTokens ?? 0)),
            cost: .zero
        )

        return .init(
            content: contentBlocks,
            api: model.api,
            provider: model.provider,
            model: model.id,
            usage: usage,
            stopReason: mapStopReason(choice.finishReason),
            errorMessage: nil,
            timestamp: timestamp
        )
    }

    private func mapStopReason(_ value: String?) -> PiAIStopReason {
        switch value?.lowercased() {
        case "tool_calls":
            return .toolUse
        case "length":
            return .length
        case "error":
            return .error
        default:
            return .stop
        }
    }

    private func asRequestMessage(_ message: PiAIMessage) -> OpenAICompatibleRequestMessage? {
        switch message {
        case .user(let user):
            return .init(role: "user", content: userContentText(user.content), toolCallID: nil, toolCalls: nil)
        case .assistant(let assistant):
            let text = assistant.content.compactMap { part -> String? in
                if case .text(let textBlock) = part { return textBlock.text }
                return nil
            }.joined(separator: "\n")
            let toolCalls = assistant.content.compactMap { part -> OpenAICompatibleRequestToolCall? in
                guard case .toolCall(let toolCall) = part else { return nil }
                return .init(
                    id: toolCall.id,
                    function: .init(name: toolCall.name, arguments: serializeJSONObject(toolCall.arguments))
                )
            }
            return .init(
                role: "assistant",
                content: text,
                toolCallID: nil,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
        case .toolResult(let tool):
            let text = tool.content.compactMap { part -> String? in
                if case .text(let value) = part { return value.text }
                return nil
            }.joined(separator: "\n")
            return .init(role: "tool", content: text, toolCallID: tool.toolCallId, toolCalls: nil)
        }
    }

    private func userContentText(_ content: PiAIUserContent) -> String {
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            return parts.compactMap { part -> String? in
                switch part {
                case .text(let text): return text.text
                case .image: return "[image]"
                }
            }.joined(separator: "\n")
        }
    }

    private func extractContentText(_ content: OpenAICompatibleResponseMessageContent?) -> String {
        guard let content else { return "" }
        switch content {
        case .string(let text):
            return text
        case .parts(let parts):
            return parts.compactMap(\.text).joined(separator: "\n")
        case .null:
            return ""
        }
    }

    private func extractJSONObject(_ value: JSONValue) -> [String: JSONValue] {
        if case .object(let object) = value {
            return object
        }
        return [:]
    }

    private func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return String(describing: error)
    }

    private func serializeJSONObject(_ object: [String: JSONValue]) -> String {
        if let data = try? JSONEncoder().encode(JSONValue.object(object)),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}

private struct OpenAICompatibleRequestBody: Encodable {
    var model: String
    var messages: [OpenAICompatibleRequestMessage]
    var tools: [OpenAICompatibleRequestTool]?
    var stream: Bool
}

private struct OpenAICompatibleRequestMessage: Encodable {
    var role: String
    var content: String?
    var toolCallID: String?
    var toolCalls: [OpenAICompatibleRequestToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

private struct OpenAICompatibleRequestTool: Encodable {
    var type = "function"
    var function: OpenAICompatibleRequestFunction
}

private struct OpenAICompatibleRequestFunction: Encodable {
    var name: String
    var description: String
    var parameters: PiToolParameterSchema
}

private struct OpenAICompatibleRequestToolCall: Encodable {
    var id: String
    var type = "function"
    var function: OpenAICompatibleRequestToolCallFunction
}

private struct OpenAICompatibleRequestToolCallFunction: Encodable {
    var name: String
    var arguments: String
}

private struct OpenAICompatibleResponse: Decodable {
    var choices: [OpenAICompatibleChoice]
    var usage: OpenAICompatibleUsage?
}

private struct OpenAICompatibleChoice: Decodable {
    var message: OpenAICompatibleChoiceMessage
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenAICompatibleChoiceMessage: Decodable {
    var content: OpenAICompatibleResponseMessageContent?
    var toolCalls: [OpenAICompatibleResponseToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private enum OpenAICompatibleResponseMessageContent: Decodable {
    case string(String)
    case parts([OpenAICompatibleResponseContentPart])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([OpenAICompatibleResponseContentPart].self) {
            self = .parts(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported content value")
    }
}

private struct OpenAICompatibleResponseContentPart: Decodable {
    var type: String?
    var text: String?
}

private struct OpenAICompatibleResponseToolCall: Decodable {
    var id: String
    var function: OpenAICompatibleResponseToolCallFunction
}

private struct OpenAICompatibleResponseToolCallFunction: Decodable {
    var name: String
    var arguments: String
}

private struct OpenAICompatibleUsage: Decodable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
