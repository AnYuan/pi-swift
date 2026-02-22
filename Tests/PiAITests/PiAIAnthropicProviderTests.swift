import XCTest
@testable import PiAI
import PiCoreTypes

final class PiAIAnthropicProviderTests: XCTestCase {
    func testStreamsThinkingTextAndToolCallEventsInOrderFromMockSource() async throws {
        let provider = PiAIAnthropicMessagesProvider()
        let model = PiAIAnthropicMessagesModel(id: "claude-sonnet-4-5")
        let context = PiAIContext(
            messages: [
                .user(.init(content: .text("Add a todo"), timestamp: 1)),
            ],
            tools: [
                .init(
                    name: "todowrite",
                    description: "Write a todo",
                    parameters: .init(
                        type: .object,
                        properties: ["task": .init(type: .string)],
                        required: ["task"]
                    )
                ),
            ]
        )

        let stream = provider.streamMock(model: model, context: context, oauthToolNaming: true) {
            [
                .messageStart(usage: .init(inputTokens: 10, outputTokens: 0, cacheReadInputTokens: 1, cacheCreationInputTokens: 2)),
                .contentBlockStart(index: 0, block: .thinking),
                .contentBlockDelta(index: 0, delta: .thinkingDelta("Need a todo tool.")),
                .contentBlockDelta(index: 0, delta: .signatureDelta("sig-1")),
                .contentBlockStop(index: 0),
                .contentBlockStart(index: 1, block: .text),
                .contentBlockDelta(index: 1, delta: .textDelta("I'll use a tool.")),
                .contentBlockStop(index: 1),
                .contentBlockStart(index: 2, block: .toolUse(id: "toolu_1", name: "TodoWrite", input: [:])),
                .contentBlockDelta(index: 2, delta: .inputJSONDelta("{\"task\":\"buy milk\"")),
                .contentBlockDelta(index: 2, delta: .inputJSONDelta("}")),
                .contentBlockStop(index: 2),
                .messageDelta(
                    delta: .init(stopReason: .toolUse),
                    usage: .init(outputTokens: 20)
                ),
                .messageStop,
            ]
        }

        var seenTypes: [String] = []
        for await event in stream {
            seenTypes.append(eventTypeName(event))
        }

        XCTAssertEqual(seenTypes, [
            "start",
            "thinking_start",
            "thinking_delta",
            "thinking_end",
            "text_start",
            "text_delta",
            "text_end",
            "toolcall_start",
            "toolcall_delta",
            "toolcall_delta",
            "toolcall_end",
            "done",
        ])

        let final = await stream.result()
        XCTAssertEqual(final.stopReason, .toolUse)
        XCTAssertEqual(final.usage.input, 10)
        XCTAssertEqual(final.usage.output, 20)
        XCTAssertEqual(final.usage.cacheRead, 1)
        XCTAssertEqual(final.usage.cacheWrite, 2)
        XCTAssertEqual(final.usage.totalTokens, 33)
        XCTAssertEqual(final.content.count, 3)

        guard case .thinking(let thinking) = final.content[0] else {
            return XCTFail("Expected thinking block")
        }
        XCTAssertEqual(thinking.thinking, "Need a todo tool.")
        XCTAssertEqual(thinking.thinkingSignature, "sig-1")

        guard case .text(let text) = final.content[1] else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(text.text, "I'll use a tool.")

        guard case .toolCall(let toolCall) = final.content[2] else {
            return XCTFail("Expected tool call block")
        }
        XCTAssertEqual(toolCall.id, "toolu_1")
        XCTAssertEqual(toolCall.name, "todowrite")
        XCTAssertEqual(toolCall.arguments, ["task": .string("buy milk")])
    }

    func testOAuthToolNameNormalizationKeepsCanonicalRoundTripAndDoesNotMapFindToGlob() {
        XCTAssertEqual(PiAIAnthropicMessagesProvider.normalizeOutboundToolNameForOAuth("read"), "Read")
        XCTAssertEqual(PiAIAnthropicMessagesProvider.normalizeOutboundToolNameForOAuth("todowrite"), "TodoWrite")
        XCTAssertEqual(PiAIAnthropicMessagesProvider.normalizeOutboundToolNameForOAuth("find"), "find")
        XCTAssertEqual(PiAIAnthropicMessagesProvider.normalizeOutboundToolNameForOAuth("my_custom_tool"), "my_custom_tool")

        let tools: [PiAITool] = [
            .init(name: "read", description: "Read", parameters: .init(type: .object)),
            .init(name: "todowrite", description: "TodoWrite", parameters: .init(type: .object)),
            .init(name: "find", description: "Find", parameters: .init(type: .object)),
        ]

        XCTAssertEqual(
            PiAIAnthropicMessagesProvider.normalizeInboundToolNameFromOAuth("Read", tools: tools),
            "read"
        )
        XCTAssertEqual(
            PiAIAnthropicMessagesProvider.normalizeInboundToolNameFromOAuth("TodoWrite", tools: tools),
            "todowrite"
        )
        XCTAssertEqual(
            PiAIAnthropicMessagesProvider.normalizeInboundToolNameFromOAuth("find", tools: tools),
            "find"
        )
        XCTAssertEqual(
            PiAIAnthropicMessagesProvider.normalizeInboundToolNameFromOAuth("Glob", tools: tools),
            "Glob"
        )
        XCTAssertEqual(
            PiAIAnthropicMessagesProvider.normalizeInboundToolNameFromOAuth("my_custom_tool", tools: tools),
            "my_custom_tool"
        )
    }

    func testEmitsErrorTerminalEventWhenMockSourceThrows() async throws {
        let provider = PiAIAnthropicMessagesProvider()
        let model = PiAIAnthropicMessagesModel(id: "claude-sonnet-4-5")
        let context = PiAIContext(messages: [])

        let stream = provider.streamMock(model: model, context: context) {
            throw PiAIAnthropicMessagesSourceError.mocked("boom")
        }

        var terminalError: PiAIAssistantMessage?
        for await event in stream {
            if case .error(_, let error) = event {
                terminalError = error
            }
        }

        XCTAssertEqual(terminalError?.stopReason, .error)
        XCTAssertTrue(terminalError?.errorMessage?.contains("boom") ?? false)

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
