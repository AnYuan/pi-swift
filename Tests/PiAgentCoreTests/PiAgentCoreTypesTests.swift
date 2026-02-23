import Foundation
import XCTest
import PiAI
import PiCoreTypes
import PiTestSupport
@testable import PiAgentCore

final class PiAgentCoreTypesTests: XCTestCase {
    func testAgentStateEmptyInitializationMatchesExpectedDefaults() {
        let model = PiAIModel(provider: "openai", id: "gpt-4o-mini")
        let state = PiAgentState.empty(model: model)

        XCTAssertEqual(state.systemPrompt, "")
        XCTAssertEqual(state.model, model)
        XCTAssertEqual(state.thinkingLevel, .off)
        XCTAssertEqual(state.tools, [])
        XCTAssertEqual(state.messages, [])
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.streamMessage)
        XCTAssertEqual(state.pendingToolCalls, [])
        XCTAssertNil(state.error)
    }

    func testAgentMessageRoundTripAndStandardMessageConversion() throws {
        let user = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let assistant = PiAgentMessage.assistant(.init(
            content: [.text(.init(text: "Hi"))],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .zero,
            stopReason: .stop,
            timestamp: 2
        ))
        let toolResult = PiAgentMessage.toolResult(.init(
            toolCallId: "call_1",
            toolName: "read",
            content: [.text(.init(text: "content"))],
            isError: false,
            timestamp: 3
        ))
        let custom = PiAgentMessage.custom(.init(
            role: "notification",
            content: .object(["text": .string("Build started")]),
            timestamp: 4
        ))

        XCTAssertNotNil(user.asAIMessage)
        XCTAssertNotNil(assistant.asAIMessage)
        XCTAssertNotNil(toolResult.asAIMessage)
        XCTAssertNil(custom.asAIMessage)
        XCTAssertEqual(custom.role, "notification")

        let payload: [PiAgentMessage] = [user, assistant, toolResult, custom]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let decoded = try JSONDecoder().decode([PiAgentMessage].self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testAgentEventsRoundTripAndGoldenEncoding() throws {
        let user = PiAgentMessage.user(.init(content: .text("Hello"), timestamp: 1))
        let assistant = PiAgentMessage.assistant(.init(
            content: [.text(.init(text: "Hi"))],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .zero,
            stopReason: .stop,
            timestamp: 2
        ))
        let toolResult = PiAIToolResultMessage(
            toolCallId: "call_1",
            toolName: "read",
            content: [.text(.init(text: "result"))],
            isError: false,
            timestamp: 3
        )
        let execResult = PiAgentToolExecutionResult(
            content: [.text(.init(text: "partial output"))],
            details: .object(["progress": .number(0.5)])
        )

        let assistantEvent = PiAIAssistantMessageEvent.textDelta(
            contentIndex: 0,
            delta: "Hi",
            partial: {
                if case .assistant(let message) = assistant { return message }
                fatalError("Expected assistant")
            }()
        )

        let events: [PiAgentEvent] = [
            .agentStart,
            .turnStart,
            .messageStart(message: user),
            .messageStart(message: assistant),
            .messageUpdate(message: assistant, assistantMessageEvent: assistantEvent),
            .toolExecutionStart(toolCallID: "call_1", toolName: "read", args: .object(["path": .string("/tmp/x")])),
            .toolExecutionUpdate(toolCallID: "call_1", toolName: "read", args: .object(["path": .string("/tmp/x")]), partialResult: execResult),
            .toolExecutionEnd(toolCallID: "call_1", toolName: "read", result: execResult, isError: false),
            .messageEnd(message: .toolResult(toolResult)),
            .turnEnd(message: assistant, toolResults: [toolResult]),
            .agentEnd(messages: [user, assistant, .toolResult(toolResult)]),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(events), as: UTF8.self)

        let loader = try FixtureLoader(callerFilePath: #filePath)
        let verify = try GoldenFile.verifyText(
            json + "\n",
            fixturePath: "pi-agent-core/agent-events.json",
            loader: loader,
            updateMode: .never
        )
        XCTAssertEqual(verify, .matched)

        let roundTrip = try JSONDecoder().decode([PiAgentEvent].self, from: Data(json.utf8))
        XCTAssertEqual(roundTrip, events)
    }
}
