import Foundation
import PiAI

public struct PiCodingAgentOpenAICompatibleRuntime: Sendable {
    private let provider: PiAIOpenAICompatibleHTTPProvider
    private let timestamp: @Sendable () -> Int64

    public init(
        provider: PiAIOpenAICompatibleHTTPProvider = .init(),
        timestamp: @escaping @Sendable () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1000).rounded())
        }
    ) {
        self.provider = provider
        self.timestamp = timestamp
    }

    public func run(
        prompt: String,
        systemPrompt: String? = nil,
        model: PiAIOpenAICompatibleHTTPModel,
        apiKey: String? = nil
    ) async -> PiAIAssistantMessage {
        let context = PiAIContext(
            systemPrompt: systemPrompt,
            messages: [
                .user(.init(content: .text(prompt), timestamp: timestamp()))
            ],
            tools: nil
        )
        let stream = provider.stream(model: model, context: context, apiKey: apiKey)
        for await _ in stream {}
        return await stream.result()
    }
}
