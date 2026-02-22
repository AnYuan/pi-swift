import XCTest
@testable import PiAI

final class PiAIUtilitiesTests: XCTestCase {
    func testSSEParserParsesSingleAndChunkedEvents() {
        var parser = PiAISSEParser()

        let first = parser.feed("event: message\ndata: hello\n\n")
        XCTAssertEqual(first, [
            .init(event: "message", data: "hello", id: nil),
        ])

        let secondPart1 = parser.feed("id: 42\ndata: line 1\n")
        XCTAssertTrue(secondPart1.isEmpty)

        let secondPart2 = parser.feed("data: line 2\n\n")
        XCTAssertEqual(secondPart2, [
            .init(event: nil, data: "line 1\nline 2", id: "42"),
        ])
    }

    func testParseStreamingJSONHandlesCompletePartialAndInvalidInput() {
        XCTAssertEqual(
            PiAIJSON.parseStreamingJSON("{\"a\":1,\"b\":[true,null]}"),
            .object([
                "a": .number(1),
                "b": .array([.bool(true), .null]),
            ])
        )

        XCTAssertEqual(
            PiAIJSON.parseStreamingJSON("{\"a\":{\"b\":1"),
            .object([
                "a": .object(["b": .number(1)]),
            ])
        )

        XCTAssertEqual(PiAIJSON.parseStreamingJSON("not-json"), .object([:]))
        XCTAssertEqual(PiAIJSON.parseStreamingJSON(nil), .object([:]))
    }

    func testValidateToolCallAcceptsValidArgumentsAndRejectsInvalid() throws {
        let tool = PiAITool(
            name: "read",
            description: "Read file",
            parameters: .init(
                type: .object,
                properties: [
                    "path": .init(type: .string),
                    "count": .init(type: .integer),
                ],
                required: ["path"],
                additionalProperties: false
            )
        )

        let valid = PiAIToolCallContent(
            id: "call_1",
            name: "read",
            arguments: [
                "path": .string("/tmp/a.txt"),
                "count": .number(3),
            ]
        )

        let validated = try PiAIValidation.validateToolCall(tools: [tool], toolCall: valid)
        XCTAssertEqual(validated["path"], .string("/tmp/a.txt"))
        XCTAssertEqual(validated["count"], .number(3))

        let invalid = PiAIToolCallContent(
            id: "call_2",
            name: "read",
            arguments: [
                "extra": .string("x"),
            ]
        )

        XCTAssertThrowsError(try PiAIValidation.validateToolCall(tools: [tool], toolCall: invalid)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("Validation failed"))
            XCTAssertTrue(message.contains("path"))
        }
    }

    func testContextOverflowDetectionForErrorPatternAndSilentOverflow() {
        let errorMessage = PiAIAssistantMessage(
            content: [.text(.init(text: "error"))],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .zero,
            stopReason: .error,
            errorMessage: "Your input exceeds the context window of this model",
            timestamp: 1
        )

        XCTAssertTrue(PiAIOverflow.isContextOverflow(errorMessage))

        let silentOverflow = PiAIAssistantMessage(
            content: [.text(.init(text: "ok"))],
            api: "zai",
            provider: "zai",
            model: "glm-4.5-flash",
            usage: .init(input: 120, output: 10, cacheRead: 5, cacheWrite: 0, totalTokens: 135, cost: .zero),
            stopReason: .stop,
            timestamp: 2
        )

        XCTAssertTrue(PiAIOverflow.isContextOverflow(silentOverflow, contextWindow: 100))
        XCTAssertFalse(PiAIOverflow.isContextOverflow(silentOverflow, contextWindow: 200))
    }
}

