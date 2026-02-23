import XCTest
import PiAI
@testable import PiAgentCore

final class PiAgentLoopSingleTurnTests: XCTestCase {
    func testSingleTurnLoopEmitsExpectedEventOrderAndReturnsPromptPlusAssistant() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let context = PiAgentContext(systemPrompt: "You are helpful.", messages: [])
        let prompt = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))

        let stream = PiAgentLoop.runSingleTurn(
            prompts: [prompt],
            context: context,
            config: .init(model: model)
        ) { _, aiContext in
            XCTAssertEqual(aiContext.systemPrompt, "You are helpful.")
            XCTAssertEqual(aiContext.messages.count, 1)

            let s = PiAIAssistantMessageEventStream()
            let partial = PiAIAssistantMessage(
                content: [.text(.init(text: ""))],
                api: "openai-responses",
                provider: "openai",
                model: "gpt-4o-mini",
                usage: .zero,
                stopReason: .stop,
                timestamp: 2
            )
            let final = PiAIAssistantMessage(
                content: [.text(.init(text: "Hi there"))],
                api: "openai-responses",
                provider: "openai",
                model: "gpt-4o-mini",
                usage: .zero,
                stopReason: .stop,
                timestamp: 2
            )
            Task {
                s.push(.start(partial: partial))
                s.push(.textStart(contentIndex: 0, partial: partial))
                let partial1 = PiAIAssistantMessage(
                    content: [.text(.init(text: "Hi "))],
                    api: partial.api,
                    provider: partial.provider,
                    model: partial.model,
                    usage: partial.usage,
                    stopReason: partial.stopReason,
                    timestamp: partial.timestamp
                )
                s.push(.textDelta(contentIndex: 0, delta: "Hi ", partial: partial1))
                s.push(.textDelta(contentIndex: 0, delta: "there", partial: final))
                s.push(.textEnd(contentIndex: 0, content: "Hi there", partial: final))
                s.push(.done(reason: .stop, message: final))
            }
            return s
        }

        var eventTypes: [String] = []
        for await event in stream {
            eventTypes.append(eventTypeName(event))
        }

        XCTAssertEqual(eventTypes, [
            "agent_start",
            "turn_start",
            "message_start",
            "message_end",
            "message_start",
            "message_update",
            "message_update",
            "message_update",
            "message_update",
            "message_end",
            "turn_end",
            "agent_end",
        ])

        let result = await stream.result()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], prompt)
        guard case .assistant(let assistant) = result[1] else {
            return XCTFail("Expected assistant result")
        }
        guard case .text(let text)? = assistant.content.first else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text.text, "Hi there")
    }

    func testSingleTurnLoopHandlesTerminalAssistantMessageWithoutStartEvent() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let stream = PiAgentLoop.runSingleTurn(
            prompts: [prompt],
            context: .init(systemPrompt: "", messages: []),
            config: .init(model: model)
        ) { _, _ in
            let s = PiAIAssistantMessageEventStream()
            let final = PiAIAssistantMessage(
                content: [.text(.init(text: "Fallback final"))],
                api: "openai-responses",
                provider: "openai",
                model: "gpt-4o-mini",
                usage: .zero,
                stopReason: .stop,
                timestamp: 2
            )
            Task {
                s.push(.done(reason: .stop, message: final))
            }
            return s
        }

        var messageStartCount = 0
        for await event in stream {
            if case .messageStart = event {
                messageStartCount += 1
            }
        }

        let result = await stream.result()
        XCTAssertEqual(messageStartCount, 2) // prompt + synthesized assistant message_start
        XCTAssertEqual(result.count, 2)
    }

    private func eventTypeName(_ event: PiAgentEvent) -> String {
        switch event {
        case .agentStart: return "agent_start"
        case .agentEnd: return "agent_end"
        case .turnStart: return "turn_start"
        case .turnEnd: return "turn_end"
        case .messageStart: return "message_start"
        case .messageUpdate: return "message_update"
        case .messageEnd: return "message_end"
        case .toolExecutionStart: return "tool_execution_start"
        case .toolExecutionUpdate: return "tool_execution_update"
        case .toolExecutionEnd: return "tool_execution_end"
        }
    }
}
