import XCTest
import PiAI
import PiCoreTypes
@testable import PiAgentCore

final class PiAgentLoopSteeringTests: XCTestCase {
    actor TestState {
        private(set) var executed: [String] = []
        private(set) var queuedDelivered = false
        private(set) var llmCallIndex = 0

        func recordExecuted(_ value: String) {
            executed.append(value)
        }

        func nextLLMCallIndex() -> Int {
            defer { llmCallIndex += 1 }
            return llmCallIndex
        }

        func takeQueuedIfNeeded(afterExecutedCount count: Int) -> Bool {
            guard count == 1, !queuedDelivered else { return false }
            queuedDelivered = true
            return true
        }

        func snapshot() -> (executed: [String], llmCallIndex: Int, queuedDelivered: Bool) {
            (executed, llmCallIndex, queuedDelivered)
        }
    }

    func testQueuedSteeringMessageSkipsRemainingToolCallsAndIsInjectedBeforeNextTurn() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("start"), timestamp: 1))
        let queuedUserMessage = PiAgentMessage.user(.init(content: .text("interrupt"), timestamp: 2))
        let toolSchema = PiToolParameterSchema(
            type: .object,
            properties: ["value": .init(type: .string)],
            required: ["value"],
            additionalProperties: false
        )
        let tool = PiAgentTool(name: "echo", label: "Echo", description: "Echo tool", parameters: toolSchema)

        let state = TestState()
        let runtimeTool = PiAgentRuntimeTool(tool: tool) { _, args, _ in
            guard case .string(let value)? = args["value"] else {
                throw PiAIValidationError("missing value")
            }
            await state.recordExecuted(value)
            return .init(
                content: [.text(.init(text: "ok:\(value)"))],
                details: .object(["value": .string(value)])
            )
        }

        let context = PiAgentContext(systemPrompt: "", messages: [], tools: [tool])

        let stream = PiAgentLoop.run(
            prompts: [prompt],
            context: context,
            config: .init(
                model: model,
                getSteeringMessages: {
                    let snapshot = await state.snapshot()
                    if await state.takeQueuedIfNeeded(afterExecutedCount: snapshot.executed.count) {
                        return [queuedUserMessage]
                    }
                    return []
                }
            ),
            runtimeTools: [runtimeTool]
        ) { _, aiContext in
            let callIndex = await state.nextLLMCallIndex()
            let s = PiAIAssistantMessageEventStream()

            if callIndex == 1 {
                let hasInterrupt = aiContext.messages.contains { message in
                    guard case .user(let user) = message else { return false }
                    if case .text(let text) = user.content {
                        return text == "interrupt"
                    }
                    return false
                }
                XCTAssertTrue(hasInterrupt, "Queued steering message should be injected before second turn")
            }

            Task {
                if callIndex == 0 {
                    let first = PiAIToolCallContent(id: "tool-1", name: "echo", arguments: ["value": .string("first")])
                    let second = PiAIToolCallContent(id: "tool-2", name: "echo", arguments: ["value": .string("second")])
                    s.push(.done(reason: .toolUse, message: .init(
                        content: [.toolCall(first), .toolCall(second)],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .toolUse,
                        timestamp: 3
                    )))
                } else {
                    s.push(.done(reason: .stop, message: .init(
                        content: [.text(.init(text: "done"))],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .stop,
                        timestamp: 4
                    )))
                }
            }
            return s
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        let snapshot = await state.snapshot()
        XCTAssertEqual(snapshot.executed, ["first"])
        XCTAssertEqual(snapshot.llmCallIndex, 2)
        XCTAssertTrue(snapshot.queuedDelivered)

        let toolEnds = events.compactMap { event -> (PiAgentToolExecutionResult, Bool)? in
            guard case .toolExecutionEnd(_, _, let result, let isError) = event else { return nil }
            return (result, isError)
        }
        XCTAssertEqual(toolEnds.count, 2)
        XCTAssertFalse(toolEnds[0].1)
        XCTAssertTrue(toolEnds[1].1)
        guard case .text(let skippedText)? = toolEnds[1].0.content.first else {
            return XCTFail("Expected skipped tool error text")
        }
        XCTAssertTrue(skippedText.text.contains("Skipped due to queued user message"))

        let queuedMessageEvent = events.contains { event in
            guard case .messageStart(let message) = event else { return false }
            guard case .user(let user) = message else { return false }
            if case .text(let text) = user.content {
                return text == "interrupt"
            }
            return false
        }
        XCTAssertTrue(queuedMessageEvent)
    }

    func testFollowUpMessagesContinueAfterAgentWouldStop() async throws {
        actor FollowUpState {
            private var llmCalls = 0
            private var delivered = false

            func nextLLMCall() -> Int {
                defer { llmCalls += 1 }
                return llmCalls
            }

            func takeFollowUpIfNeeded() -> Bool {
                guard !delivered else { return false }
                delivered = true
                return true
            }

            func snapshot() -> (llmCalls: Int, delivered: Bool) {
                (llmCalls, delivered)
            }
        }

        let state = FollowUpState()
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("start"), timestamp: 1))
        let followUp = PiAgentMessage.user(.init(content: .text("follow-up"), timestamp: 2))

        let stream = PiAgentLoop.run(
            prompts: [prompt],
            context: .init(systemPrompt: "", messages: []),
            config: .init(
                model: model,
                getFollowUpMessages: {
                    if await state.takeFollowUpIfNeeded() {
                        return [followUp]
                    }
                    return []
                }
            ),
            runtimeTools: []
        ) { _, aiContext in
            let callIndex = await state.nextLLMCall()
            if callIndex == 1 {
                let hasFollowUp = aiContext.messages.contains { message in
                    guard case .user(let user) = message else { return false }
                    if case .text(let text) = user.content {
                        return text == "follow-up"
                    }
                    return false
                }
                XCTAssertTrue(hasFollowUp, "Follow-up message should be injected before second assistant call")
            }

            let s = PiAIAssistantMessageEventStream()
            Task {
                if callIndex == 0 {
                    s.push(.done(reason: .stop, message: .init(
                        content: [.text(.init(text: "first answer"))],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .stop,
                        timestamp: 3
                    )))
                } else {
                    s.push(.done(reason: .stop, message: .init(
                        content: [.text(.init(text: "second answer"))],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .stop,
                        timestamp: 4
                    )))
                }
            }
            return s
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        let snapshot = await state.snapshot()
        XCTAssertEqual(snapshot.llmCalls, 2)
        XCTAssertTrue(snapshot.delivered)
        XCTAssertEqual(events.filter { if case .turnStart = $0 { return true }; return false }.count, 2)

        let followUpEventSeen = events.contains { event in
            guard case .messageStart(let message) = event else { return false }
            guard case .user(let user) = message else { return false }
            if case .text(let text) = user.content {
                return text == "follow-up"
            }
            return false
        }
        XCTAssertTrue(followUpEventSeen)

        let result = await stream.result()
        XCTAssertEqual(result.map(\.role), ["user", "assistant", "user", "assistant"])
    }
}
