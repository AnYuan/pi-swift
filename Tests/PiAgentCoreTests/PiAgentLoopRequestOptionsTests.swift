import XCTest
import PiAI
@testable import PiAgentCore

final class PiAgentLoopRequestOptionsTests: XCTestCase {
    func testRunSingleTurnPassesSessionIdThinkingBudgetsAndReasoningToFactoryOptions() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let expectedBudgets = PiAgentThinkingBudgets(minimal: 128, low: 512, medium: 2048, high: 4096)

        let stream = PiAgentLoop.runSingleTurn(
            prompts: [prompt],
            context: .init(systemPrompt: "", messages: []),
            config: .init(
                model: model,
                thinkingLevel: .high,
                sessionId: "session-123",
                thinkingBudgets: expectedBudgets
            )
        ) { _, _, options in
            XCTAssertEqual(options.reasoning, .high)
            XCTAssertEqual(options.sessionId, "session-123")
            XCTAssertEqual(options.thinkingBudgets, expectedBudgets)

            let s = PiAIAssistantMessageEventStream()
            Task {
                await s.push(.done(reason: .stop, message: .init(
                    content: [.text(.init(text: "ok"))],
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

        for await _ in stream {
            // consume
        }
        let result = await stream.result()
        XCTAssertEqual(result.count, 2)
    }

    func testRunSingleTurnOmitsReasoningWhenThinkingLevelIsOff() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))

        let stream = PiAgentLoop.runSingleTurn(
            prompts: [prompt],
            context: .init(systemPrompt: "", messages: []),
            config: .init(
                model: model,
                thinkingLevel: .off,
                sessionId: "session-off"
            )
        ) { _, _, options in
            XCTAssertNil(options.reasoning)
            XCTAssertEqual(options.sessionId, "session-off")
            XCTAssertNil(options.thinkingBudgets)

            let s = PiAIAssistantMessageEventStream()
            Task {
                await s.push(.done(reason: .stop, message: .init(
                    content: [.text(.init(text: "ok"))],
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

        for await _ in stream {}
        _ = await stream.result()
    }
}
