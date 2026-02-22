import XCTest
@testable import PiAI

final class PiAIOpenAIResponsesProviderTests: XCTestCase {
    func testStreamsTextAndToolCallEventsInOrderFromMockSource() async throws {
        let provider = PiAIOpenAIResponsesProvider()
        let model = PiAIOpenAIResponsesModel(id: "gpt-4o-mini")
        let context = PiAIContext(messages: [
            .user(.init(content: .text("What time is it?"), timestamp: 1)),
        ])

        let stream = provider.streamMock(model: model, context: context) {
            [
                .responseOutputItemAdded(item: .message),
                .responseOutputTextDelta(delta: "Checking..."),
                .responseOutputItemAdded(item: .functionCall(id: "call_1", name: "get_time", arguments: "{")),
                .responseFunctionCallArgumentsDelta(delta: "\"timezone\":\"UTC\"}"),
                .responseFunctionCallArgumentsDone,
                .responseCompleted(
                    stopReason: .toolUse,
                    usage: .init(input: 10, output: 5, cacheRead: 0, cacheWrite: 0, totalTokens: 15, cost: .zero)
                ),
            ]
        }

        var seenTypes: [String] = []
        for await event in stream {
            seenTypes.append(eventTypeName(event))
        }

        XCTAssertEqual(seenTypes, [
            "start",
            "text_start",
            "text_delta",
            "toolcall_start",
            "toolcall_delta",
            "toolcall_end",
            "done",
        ])

        let final = await stream.result()
        XCTAssertEqual(final.stopReason, .toolUse)
        XCTAssertEqual(final.usage.totalTokens, 15)
        XCTAssertEqual(final.content.count, 2)

        guard case .text(let text)? = final.content.first else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(text.text, "Checking...")

        guard case .toolCall(let toolCall)? = final.content.last else {
            return XCTFail("Expected tool call block")
        }
        XCTAssertEqual(toolCall.id, "call_1")
        XCTAssertEqual(toolCall.name, "get_time")
        XCTAssertEqual(toolCall.arguments, ["timezone": .string("UTC")])
    }

    func testEmitsErrorTerminalEventWhenMockSourceThrows() async throws {
        let provider = PiAIOpenAIResponsesProvider()
        let model = PiAIOpenAIResponsesModel(id: "gpt-4o-mini")
        let context = PiAIContext(messages: [])

        let stream = provider.streamMock(model: model, context: context) {
            throw PiAIOpenAIResponsesSourceError.mocked("network down")
        }

        var terminalError: PiAIAssistantMessage?
        for await event in stream {
            if case .error(_, let error) = event {
                terminalError = error
            }
        }

        XCTAssertEqual(terminalError?.stopReason, .error)
        XCTAssertNotNil(terminalError?.errorMessage)
        XCTAssertTrue(terminalError?.errorMessage?.contains("network down") ?? false)

        let result = await stream.result()
        XCTAssertEqual(result.stopReason, .error)
    }

    private func eventTypeName(_ event: PiAIAssistantMessageEvent) -> String {
        switch event {
        case .start: return "start"
        case .textStart: return "text_start"
        case .textDelta: return "text_delta"
        case .textEnd: return "text_end"
        case .thinkingStart: return "thinking_start"
        case .thinkingDelta: return "thinking_delta"
        case .thinkingEnd: return "thinking_end"
        case .toolCallStart: return "toolcall_start"
        case .toolCallDelta: return "toolcall_delta"
        case .toolCallEnd: return "toolcall_end"
        case .done: return "done"
        case .error: return "error"
        }
    }
}

