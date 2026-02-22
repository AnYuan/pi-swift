import XCTest
import PiCoreTypes
@testable import PiAI

final class PiAIGoogleFamilyProviderTests: XCTestCase {
    func testThinkingSignatureHelpersMatchGoogleSemantics() {
        XCTAssertTrue(PiAIGoogleStreamingSemantics.isThinkingPart(thought: true, thoughtSignature: nil))
        XCTAssertTrue(PiAIGoogleStreamingSemantics.isThinkingPart(thought: true, thoughtSignature: "sig-1"))

        XCTAssertFalse(PiAIGoogleStreamingSemantics.isThinkingPart(thought: nil, thoughtSignature: "sig-1"))
        XCTAssertFalse(PiAIGoogleStreamingSemantics.isThinkingPart(thought: false, thoughtSignature: "sig-1"))
        XCTAssertFalse(PiAIGoogleStreamingSemantics.isThinkingPart(thought: nil, thoughtSignature: nil))

        let first = PiAIGoogleStreamingSemantics.retainThoughtSignature(existing: nil, incoming: "sig-1")
        XCTAssertEqual(first, "sig-1")
        XCTAssertEqual(PiAIGoogleStreamingSemantics.retainThoughtSignature(existing: first, incoming: nil), "sig-1")
        XCTAssertEqual(PiAIGoogleStreamingSemantics.retainThoughtSignature(existing: first, incoming: ""), "sig-1")
        XCTAssertEqual(PiAIGoogleStreamingSemantics.retainThoughtSignature(existing: first, incoming: "sig-2"), "sig-2")
    }

    func testDefaultsMissingToolCallArgumentsToEmptyObject() async throws {
        let provider = PiAIGoogleFamilyProvider()
        let model = PiAIGoogleFamilyModel(provider: "google-gemini-cli", id: "gemini-2.5-flash", api: "google-gemini-cli")
        let context = PiAIContext(messages: [.user(.init(content: .text("Check status"), timestamp: 1))])

        let stream = provider.streamMock(model: model, context: context) {
            [
                .init(
                    parts: [
                        .functionCall(name: "get_status", id: nil, args: nil, thoughtSignature: nil),
                    ],
                    finishReason: .stop,
                    usage: .init(promptTokenCount: 10, candidatesTokenCount: 5, thoughtsTokenCount: 0, cachedContentTokenCount: 0, totalTokenCount: 15)
                ),
            ]
        }

        for await _ in stream {}
        let result = await stream.result()

        XCTAssertEqual(result.stopReason, PiAIStopReason.toolUse)
        XCTAssertEqual(result.content.count, 1)

        guard case .toolCall(let toolCall) = result.content[0] else {
            return XCTFail("Expected tool call")
        }
        XCTAssertEqual(toolCall.name, "get_status")
        XCTAssertEqual(toolCall.arguments, [String: JSONValue]())
        XCTAssertFalse(toolCall.id.isEmpty)
    }

    func testRetriesEmptyStreamWithoutDuplicateStart() async throws {
        let provider = PiAIGoogleFamilyProvider()
        let model = PiAIGoogleFamilyModel(provider: "google-gemini-cli", id: "gemini-2.5-flash", api: "google-gemini-cli")
        let context = PiAIContext(messages: [.user(.init(content: .text("Say hello"), timestamp: 1))])

        let stream = provider.streamMockRetryingEmptyAttempts(model: model, context: context, maxAttempts: 2) {
            [
                [],
                [
                    .init(
                        parts: [.text(text: "Hello", thought: false, thoughtSignature: nil)],
                        finishReason: .stop,
                        usage: .init(promptTokenCount: 1, candidatesTokenCount: 1, thoughtsTokenCount: 0, cachedContentTokenCount: 0, totalTokenCount: 2)
                    ),
                ],
            ]
        }

        var startCount = 0
        var doneCount = 0
        var text = ""
        for await event in stream {
            switch event {
            case .start:
                startCount += 1
            case .done:
                doneCount += 1
            case .textDelta(_, let delta, _):
                text += delta
            default:
                break
            }
        }

        let result = await stream.result()
        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(result.stopReason, PiAIStopReason.stop)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(doneCount, 1)
    }

    func testStreamsThinkingTextAndToolCallEventsAndPreservesThinkingSignature() async throws {
        let provider = PiAIGoogleFamilyProvider()
        let model = PiAIGoogleFamilyModel(provider: "google", id: "gemini-3-flash", api: "google-generative-ai")
        let context = PiAIContext(messages: [.user(.init(content: .text("Plan and call tool"), timestamp: 1))])

        let stream = provider.streamMock(model: model, context: context) {
            [
                .init(
                    parts: [
                        .text(text: "Think 1", thought: true, thoughtSignature: "sig-1"),
                        .text(text: "Think 2", thought: true, thoughtSignature: nil),
                        .text(text: "Answer", thought: false, thoughtSignature: "text-sig"),
                        .functionCall(name: "search_docs", id: "fc_1", args: ["q": .string("swift")], thoughtSignature: "tool-sig"),
                    ],
                    finishReason: .stop,
                    usage: .init(promptTokenCount: 2, candidatesTokenCount: 3, thoughtsTokenCount: 4, cachedContentTokenCount: 0, totalTokenCount: 9)
                ),
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
            "thinking_delta",
            "thinking_end",
            "text_start",
            "text_delta",
            "text_end",
            "toolcall_start",
            "toolcall_delta",
            "toolcall_end",
            "done",
        ])

        let result = await stream.result()
        XCTAssertEqual(result.stopReason, PiAIStopReason.toolUse)
        XCTAssertEqual(result.usage.input, 2)
        XCTAssertEqual(result.usage.output, 7) // candidates + thoughts
        XCTAssertEqual(result.usage.totalTokens, 9)
        XCTAssertEqual(result.content.count, 3)

        guard case .thinking(let thinking) = result.content[0] else {
            return XCTFail("Expected thinking block")
        }
        XCTAssertEqual(thinking.thinking, "Think 1Think 2")
        XCTAssertEqual(thinking.thinkingSignature, "sig-1")

        guard case .text(let textBlock) = result.content[1] else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(textBlock.text, "Answer")
        XCTAssertEqual(textBlock.textSignature, "text-sig")

        guard case .toolCall(let toolCall) = result.content[2] else {
            return XCTFail("Expected tool call block")
        }
        XCTAssertEqual(toolCall.name, "search_docs")
        XCTAssertEqual(toolCall.arguments, ["q": JSONValue.string("swift")])
        XCTAssertEqual(toolCall.thoughtSignature, "tool-sig")
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
