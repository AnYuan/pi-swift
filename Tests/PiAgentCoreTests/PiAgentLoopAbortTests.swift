import XCTest
import PiAI
import PiCoreTypes
@testable import PiAgentCore

final class PiAgentLoopAbortTests: XCTestCase {
    func testRunContinuePreAbortedStopsWithoutCallingAssistantFactory() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let user = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let context = PiAgentContext(systemPrompt: "", messages: [user], tools: [])
        let abort = PiAgentAbortController()
        await abort.abort()

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

    func testAbortTriggeredByToolPreventsNextAssistantCall() async throws {
        actor State {
            private(set) var llmCalls = 0

            func nextLLMCall() -> Int {
                defer { llmCalls += 1 }
                return llmCalls
            }

            func snapshot() -> Int { llmCalls }
        }

        let state = State()
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("start"), timestamp: 1))
        let toolSchema = PiToolParameterSchema(
            type: .object,
            properties: ["value": .init(type: .string)],
            required: ["value"],
            additionalProperties: false
        )
        let tool = PiAgentTool(name: "echo", label: "Echo", description: "Echo tool", parameters: toolSchema)
        let abort = PiAgentAbortController()

        let runtimeTool = PiAgentRuntimeTool(tool: tool) { _, args, passedAbortController, _ in
            XCTAssertTrue(passedAbortController === abort)
            XCTAssertEqual(args["value"], .string("hello"))
            await passedAbortController?.abort()
            return .init(
                content: [.text(.init(text: "ok"))],
                details: .object([:])
            )
        }

        let stream = PiAgentLoop.run(
            prompts: [prompt],
            context: .init(systemPrompt: "", messages: [], tools: [tool]),
            config: .init(model: model),
            runtimeTools: [runtimeTool],
            abortController: abort
        ) { _, _, _ in
            let callIndex = await state.nextLLMCall()
            let s = PiAIAssistantMessageEventStream()
            Task {
                if callIndex == 0 {
                    let toolCall = PiAIToolCallContent(id: "tool-1", name: "echo", arguments: ["value": .string("hello")])
                    await s.push(.done(reason: .toolUse, message: .init(
                        content: [.toolCall(toolCall)],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .toolUse,
                        timestamp: 2
                    )))
                } else {
                    XCTFail("Abort should prevent second assistant call")
                    await s.push(.done(reason: .stop, message: .init(
                        content: [],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .stop,
                        timestamp: 3
                    )))
                }
            }
            return s
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        let llmCallCount = await state.snapshot()
        XCTAssertEqual(llmCallCount, 1)
        let result = await stream.result()
        XCTAssertEqual(result.count, 4) // user + assistant(toolcall) + toolResult + aborted assistant
        guard case .assistant(let finalAssistant) = result.last else {
            return XCTFail("Expected final assistant")
        }
        XCTAssertEqual(finalAssistant.stopReason, PiAIStopReason.aborted)

        XCTAssertEqual(events.filter { if case .turnEnd = $0 { return true }; return false }.count, 2)
    }
}
