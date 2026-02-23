import XCTest
import PiAI
import PiCoreTypes
@testable import PiAgentCore

final class PiAgentLoopRegressionTests: XCTestCase {
    actor Recorder {
        private var transformedMessages: [PiAgentMessage] = []
        private var convertedMessages: [PiAIMessage] = []

        func setTransformed(_ messages: [PiAgentMessage]) {
            transformedMessages = messages
        }

        func setConverted(_ messages: [PiAIMessage]) {
            convertedMessages = messages
        }

        func snapshot() -> (transformedCount: Int, convertedCount: Int, convertedRoles: [String]) {
            (
                transformedMessages.count,
                convertedMessages.count,
                convertedMessages.map { message in
                    switch message {
                    case .user: return "user"
                    case .assistant: return "assistant"
                    case .toolResult: return "toolResult"
                    }
                }
            )
        }
    }

    func testCustomMessagesCanBeFilteredInConvertToLLMForRun() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let custom = PiAgentMessage.custom(.init(
            role: "notification",
            content: .object(["text": .string("notice")]),
            timestamp: 1
        ))
        let prompt = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 2))
        let recorder = Recorder()

        let stream = PiAgentLoop.run(
            prompts: [prompt],
            context: .init(systemPrompt: "You are helpful.", messages: [custom], tools: []),
            config: .init(
                model: model,
                convertToLLM: { messages in
                    let converted = messages.compactMap { message -> PiAIMessage? in
                        if message.role == "notification" {
                            return nil
                        }
                        return message.asAIMessage
                    }
                    await recorder.setConverted(converted)
                    return converted
                }
            ),
            runtimeTools: []
        ) { _, aiContext in
            XCTAssertEqual(aiContext.messages.count, 1)
            let s = PiAIAssistantMessageEventStream()
            Task {
                s.push(.done(reason: .stop, message: .init(
                    content: [.text(.init(text: "Response"))],
                    api: "openai-responses",
                    provider: "openai",
                    model: "gpt-4o-mini",
                    usage: .zero,
                    stopReason: .stop,
                    timestamp: 3
                )))
            }
            return s
        }

        for await _ in stream {}
        _ = await stream.result()

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.convertedCount, 1)
        XCTAssertEqual(snapshot.convertedRoles, ["user"])
    }

    func testTransformContextRunsBeforeConvertToLLM() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let recorder = Recorder()
        let context = PiAgentContext(
            systemPrompt: "You are helpful.",
            messages: [
                .user(.init(content: .text("old message 1"), timestamp: 1)),
                .assistant(.init(content: [.text(.init(text: "old response 1"))], api: "x", provider: "x", model: "x", usage: .zero, stopReason: .stop, timestamp: 2)),
                .user(.init(content: .text("old message 2"), timestamp: 3)),
                .assistant(.init(content: [.text(.init(text: "old response 2"))], api: "x", provider: "x", model: "x", usage: .zero, stopReason: .stop, timestamp: 4)),
            ],
            tools: []
        )
        let prompt = PiAgentMessage.user(.init(content: .text("new message"), timestamp: 5))

        let stream = PiAgentLoop.run(
            prompts: [prompt],
            context: context,
            config: .init(
                model: model,
                convertToLLM: { messages in
                    let converted = messages.compactMap(\.asAIMessage)
                    await recorder.setConverted(converted)
                    return converted
                },
                transformContext: { messages, _ in
                    let transformed = Array(messages.suffix(2))
                    await recorder.setTransformed(transformed)
                    return transformed
                }
            ),
            runtimeTools: []
        ) { _, _ in
            let s = PiAIAssistantMessageEventStream()
            Task {
                s.push(.done(reason: .stop, message: .init(
                    content: [.text(.init(text: "Response"))],
                    api: "openai-responses",
                    provider: "openai",
                    model: "gpt-4o-mini",
                    usage: .zero,
                    stopReason: .stop,
                    timestamp: 6
                )))
            }
            return s
        }

        for await _ in stream {}
        _ = await stream.result()

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.transformedCount, 2)
        XCTAssertEqual(snapshot.convertedCount, 2)
    }
}
