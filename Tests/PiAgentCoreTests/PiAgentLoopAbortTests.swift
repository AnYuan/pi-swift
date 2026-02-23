import XCTest
import PiAI
@testable import PiAgentCore

final class PiAgentLoopAbortTests: XCTestCase {
    func testRunContinuePreAbortedStopsWithoutCallingAssistantFactory() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let user = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let context = PiAgentContext(systemPrompt: "", messages: [user], tools: [])
        let abort = PiAgentAbortController()
        abort.abort()

        let stream = try PiAgentLoop.runContinue(
            context: context,
            config: .init(model: model),
            runtimeTools: [],
            abortController: abort
        ) { _, _ in
            XCTFail("assistantStreamFactory should not be called when pre-aborted")
            return PiAIAssistantMessageEventStream()
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        XCTAssertTrue(events.contains { if case .agentStart = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .turnStart = $0 { return true }; return false })

        let messageEnds = events.compactMap { event -> PiAgentMessage? in
            guard case .messageEnd(let message) = event else { return nil }
            return message
        }
        XCTAssertEqual(messageEnds.count, 1)
        guard case .assistant(let assistant)? = messageEnds.first else {
            return XCTFail("Expected assistant error/abort message")
        }
        XCTAssertEqual(assistant.stopReason, .aborted)

        let result = await stream.result()
        XCTAssertEqual(result.count, 1)
        guard case .assistant(let finalAssistant) = result[0] else {
            return XCTFail("Expected assistant result")
        }
        XCTAssertEqual(finalAssistant.stopReason, .aborted)
    }
}
