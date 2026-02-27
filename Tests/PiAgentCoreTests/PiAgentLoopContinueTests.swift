import XCTest
import PiAI
import PiCoreTypes
@testable import PiAgentCore

final class PiAgentLoopContinueTests: XCTestCase {
    func testRunContinueThrowsWhenContextHasNoMessages() {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let context = PiAgentContext(systemPrompt: "You are helpful.", messages: [], tools: [])

        XCTAssertThrowsError(
            try PiAgentLoop.runContinue(
                context: context,
                config: .init(model: model),
                runtimeTools: []
            ) { _, _ in
                XCTFail("assistantStreamFactory should not be called")
                return PiAIAssistantMessageEventStream()
            }
        ) { error in
            XCTAssertEqual(error as? PiAgentLoopError, .cannotContinueWithoutMessages)
        }
    }

    func testRunContinueThrowsWhenLastContextMessageIsAssistant() {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let assistant = PiAgentMessage.assistant(.init(
            content: [.text(.init(text: "done"))],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .zero,
            stopReason: .stop,
            timestamp: 1
        ))
        let context = PiAgentContext(systemPrompt: "", messages: [assistant], tools: [])

        XCTAssertThrowsError(
            try PiAgentLoop.runContinue(
                context: context,
                config: .init(model: model),
                runtimeTools: []
            ) { _, _ in
                XCTFail("assistantStreamFactory should not be called")
                return PiAIAssistantMessageEventStream()
            }
        ) { error in
            XCTAssertEqual(error as? PiAgentLoopError, .cannotContinueFromAssistantMessage)
        }
    }

    func testRunContinueUsesExistingContextWithoutReEmittingUserPromptEvents() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let user = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let context = PiAgentContext(systemPrompt: "You are helpful.", messages: [user], tools: [])

        let stream = try PiAgentLoop.runContinue(
            context: context,
            config: .init(model: model),
            runtimeTools: []
        ) { _, aiContext in
            XCTAssertEqual(aiContext.messages.count, 1)
            let s = PiAIAssistantMessageEventStream()
            Task {
                await s.push(.done(reason: .stop, message: .init(
                    content: [.text(.init(text: "Response"))],
                    api: "openai-responses",
                    provider: "openai",
                    model: "gpt-4o-mini",
                    usage: .zero,
                    stopReason: .stop,
                    timestamp: 2
                )))
            }
            return s
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        let messageEndEvents = events.compactMap { event -> PiAgentMessage? in
            guard case .messageEnd(let message) = event else { return nil }
            return message
        }
        XCTAssertEqual(messageEndEvents.count, 1)
        XCTAssertEqual(messageEndEvents.first?.role, "assistant")

        let result = await stream.result()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.role, "assistant")
    }

    func testRunContinueAllowsCustomLastMessageWhenUsingCustomConverter() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let custom = PiAgentMessage.custom(.init(
            role: "custom",
            content: .object(["text": .string("Hook content")]),
            timestamp: 1
        ))
        let context = PiAgentContext(systemPrompt: "You are helpful.", messages: [custom], tools: [])

        let stream = try PiAgentLoop.runContinue(
            context: context,
            config: .init(
                model: model,
                convertToLLM: { messages in
                    messages.compactMap { message in
                        switch message {
                        case .custom(let customMessage):
                            guard case .object(let object) = customMessage.content,
                                  case .string(let text)? = object["text"] else {
                                return nil
                            }
                            return .user(.init(content: .text(text), timestamp: customMessage.timestamp))
                        default:
                            return message.asAIMessage
                        }
                    }
                }
            ),
            runtimeTools: []
        ) { _, _ in
            let s = PiAIAssistantMessageEventStream()
            Task {
                await s.push(.done(reason: .stop, message: .init(
                    content: [.text(.init(text: "Response to custom message"))],
                    api: "openai-responses",
                    provider: "openai",
                    model: "gpt-4o-mini",
                    usage: .zero,
                    stopReason: .stop,
                    timestamp: 2
                )))
            }
            return s
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        XCTAssertFalse(events.contains { event in
            if case .messageStart(let message) = event {
                return message.role == "user"
            }
            return false
        })

        let result = await stream.result()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.role, "assistant")
    }
}
