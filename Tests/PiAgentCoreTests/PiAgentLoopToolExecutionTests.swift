import XCTest
import PiAI
import PiCoreTypes
@testable import PiAgentCore

final class PiAgentLoopToolExecutionTests: XCTestCase {
    actor TestState {
        private var callIndex = 0
        private var executedArgs: [[String: JSONValue]] = []

        func nextCallIndex() -> Int {
            defer { callIndex += 1 }
            return callIndex
        }

        func recordExecutedArgs(_ args: [String: JSONValue]) {
            executedArgs.append(args)
        }

        func snapshot() -> (callIndex: Int, executedArgs: [[String: JSONValue]]) {
            (callIndex, executedArgs)
        }
    }

    func testRunExecutesToolCallEmitsToolEventsAndContinuesToNextTurn() async throws {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let prompt = PiAgentMessage.user(.init(content: .text("echo hello"), timestamp: 1))
        let toolSchema = PiToolParameterSchema(
            type: .object,
            properties: ["value": .init(type: .string)],
            required: ["value"],
            additionalProperties: false
        )
        let tool = PiAgentTool(name: "echo", label: "Echo", description: "Echo tool", parameters: toolSchema)

        let state = TestState()
        let runtimeTool = PiAgentRuntimeTool(tool: tool) { toolCallID, args, onProgress in
            XCTAssertEqual(toolCallID, "tool-1")
            await state.recordExecutedArgs(args)
            onProgress(.init(
                content: [.text(.init(text: "working"))],
                details: .object(["phase": .string("running")])
            ))
            return .init(
                content: [.text(.init(text: "echoed: hello"))],
                details: .object(["value": .string("hello")])
            )
        }

        let context = PiAgentContext(systemPrompt: "", messages: [], tools: [tool])

        let stream = PiAgentLoop.run(
            prompts: [prompt],
            context: context,
            config: .init(model: model),
            runtimeTools: [runtimeTool]
        ) { _, aiContext in
            let callIndex = await state.nextCallIndex()
            if callIndex == 0 {
                XCTAssertEqual(aiContext.messages.count, 1)
            } else if callIndex == 1 {
                XCTAssertEqual(aiContext.messages.count, 3)
                if case .toolResult(let toolResult) = aiContext.messages[2] {
                    XCTAssertEqual(toolResult.toolCallId, "tool-1")
                    XCTAssertEqual(toolResult.toolName, "echo")
                    XCTAssertFalse(toolResult.isError)
                } else {
                    XCTFail("Expected toolResult message in second-turn context")
                }
            } else {
                XCTFail("Unexpected LLM call count \(callIndex)")
            }

            let s = PiAIAssistantMessageEventStream()
            let turn = callIndex
            Task {
                if turn == 0 {
                    let toolCall = PiAIToolCallContent(
                        id: "tool-1",
                        name: "echo",
                        arguments: ["value": .string("hello")]
                    )
                    let message = PiAIAssistantMessage(
                        content: [.toolCall(toolCall)],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .toolUse,
                        timestamp: 2
                    )
                    s.push(.done(reason: .toolUse, message: message))
                } else {
                    let message = PiAIAssistantMessage(
                        content: [.text(.init(text: "done"))],
                        api: "openai-responses",
                        provider: "openai",
                        model: "gpt-4o-mini",
                        usage: .zero,
                        stopReason: .stop,
                        timestamp: 3
                    )
                    s.push(.done(reason: .stop, message: message))
                }
            }
            return s
        }

        var events: [PiAgentEvent] = []
        for await event in stream {
            events.append(event)
        }

        let snapshot = await state.snapshot()
        XCTAssertEqual(snapshot.callIndex, 2)
        XCTAssertEqual(snapshot.executedArgs, [["value": .string("hello")]])

        XCTAssertEqual(events.filter { if case .turnStart = $0 { return true }; return false }.count, 2)
        XCTAssertEqual(events.filter { if case .turnEnd = $0 { return true }; return false }.count, 2)
        XCTAssertEqual(events.filter { if case .toolExecutionStart = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(events.filter { if case .toolExecutionUpdate = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(events.filter { if case .toolExecutionEnd = $0 { return true }; return false }.count, 1)

        guard let toolExecutionEnd = events.first(where: {
            if case .toolExecutionEnd = $0 { return true }
            return false
        }) else {
            return XCTFail("Missing tool_execution_end")
        }
        if case .toolExecutionEnd(_, _, let result, let isError) = toolExecutionEnd {
            XCTAssertFalse(isError)
            guard case .text(let text)? = result.content.first else {
                return XCTFail("Expected text content in tool result")
            }
            XCTAssertEqual(text.text, "echoed: hello")
        }

        let result = await stream.result()
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], prompt)
        guard case .assistant(let firstAssistant) = result[1] else {
            return XCTFail("Expected assistant tool call message")
        }
        guard case .toolCall(let toolCall)? = firstAssistant.content.first else {
            return XCTFail("Expected tool call content in first assistant message")
        }
        XCTAssertEqual(toolCall.id, "tool-1")
        guard case .toolResult(let toolResultMessage) = result[2] else {
            return XCTFail("Expected tool result message")
        }
        XCTAssertEqual(toolResultMessage.toolName, "echo")
        XCTAssertFalse(toolResultMessage.isError)
        guard case .assistant(let finalAssistant) = result[3] else {
            return XCTFail("Expected final assistant message")
        }
        guard case .text(let finalText)? = finalAssistant.content.first else {
            return XCTFail("Expected final assistant text")
        }
        XCTAssertEqual(finalText.text, "done")
    }
}
