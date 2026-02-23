import XCTest
import PiCoreTypes
@testable import PiAI

final class PiAIRegressionCoverageTests: XCTestCase {
    func testValidationCoversUnknownToolAndScalarSchemaBranches() {
        let scalarTool = PiAITool(
            name: "scalar_tool",
            description: "Validates many schema branches",
            parameters: .init(
                type: .object,
                properties: [
                    "mode": .init(type: .string, enumValues: ["fast", "slow"]),
                    "count": .init(type: .integer),
                    "ratio": .init(type: .number),
                    "flag": .init(type: .boolean),
                    "payload": .init(type: .null),
                    "tags": .init(type: .array, items: .init(type: .string)),
                ],
                required: ["mode", "count", "ratio", "flag", "payload", "tags"],
                additionalProperties: false
            )
        )

        let validCall = PiAIToolCallContent(
            id: "1",
            name: "scalar_tool",
            arguments: [
                "mode": .string("fast"),
                "count": .number(3),
                "ratio": .number(0.5),
                "flag": .bool(true),
                "payload": .null,
                "tags": .array([.string("swift"), .string("tests")]),
            ]
        )

        XCTAssertNoThrow(try PiAIValidation.validateToolCall(tools: [scalarTool], toolCall: validCall))

        let unknownTool = PiAIToolCallContent(id: "2", name: "missing", arguments: [:])
        XCTAssertThrowsError(try PiAIValidation.validateToolCall(tools: [scalarTool], toolCall: unknownTool)) { error in
            XCTAssertTrue(String(describing: error).contains("not found"))
        }

        var invalidEnum = validCall
        invalidEnum.arguments["mode"] = .string("turbo")
        XCTAssertThrowsError(try PiAIValidation.validateToolArguments(tool: scalarTool, toolCall: invalidEnum)) { error in
            XCTAssertTrue(String(describing: error).contains("must be one of"))
        }

        var invalidInteger = validCall
        invalidInteger.arguments["count"] = .number(3.14)
        XCTAssertThrowsError(try PiAIValidation.validateToolArguments(tool: scalarTool, toolCall: invalidInteger)) { error in
            XCTAssertTrue(String(describing: error).contains("count"))
        }

        var invalidNull = validCall
        invalidNull.arguments["payload"] = .string("oops")
        XCTAssertThrowsError(try PiAIValidation.validateToolArguments(tool: scalarTool, toolCall: invalidNull))

        var unexpectedProperty = validCall
        unexpectedProperty.arguments["extra"] = .string("x")
        XCTAssertThrowsError(try PiAIValidation.validateToolArguments(tool: scalarTool, toolCall: unexpectedProperty)) { error in
            XCTAssertTrue(String(describing: error).contains("unexpected property"))
        }
    }

    func testOverflowCoversNoBodyStatusAndNonOverflowPaths() {
        let noBody413 = PiAIAssistantMessage(
            content: [],
            api: "test",
            provider: "test",
            model: "test",
            usage: .zero,
            stopReason: .error,
            errorMessage: "413 status code (no body)",
            timestamp: 1
        )
        XCTAssertTrue(PiAIOverflow.isContextOverflow(noBody413))

        let nonOverflowError = PiAIAssistantMessage(
            content: [],
            api: "test",
            provider: "test",
            model: "test",
            usage: .zero,
            stopReason: .error,
            errorMessage: "network timeout",
            timestamp: 1
        )
        XCTAssertFalse(PiAIOverflow.isContextOverflow(nonOverflowError))

        let equalWindow = PiAIAssistantMessage(
            content: [],
            api: "test",
            provider: "test",
            model: "test",
            usage: .init(input: 100, output: 0, cacheRead: 20, cacheWrite: 0, totalTokens: 120, cost: .zero),
            stopReason: .stop,
            timestamp: 1
        )
        XCTAssertFalse(PiAIOverflow.isContextOverflow(equalWindow, contextWindow: 120))
        XCTAssertTrue(PiAIOverflow.patterns().contains(where: { $0.contains("too many tokens") }))
    }

    func testStreamingJSONParsesNestedArraysAndQuotedStrings() {
        let parsed = PiAIJSON.parseStreamingJSON(#"{"items":[1,2,{"k":"v"}],"text":"a\"b"}"#)
        guard case .object(let object) = parsed else {
            return XCTFail("Expected object")
        }
        XCTAssertEqual(object["text"], .string("a\"b"))
        guard case .array(let items)? = object["items"] else {
            return XCTFail("Expected items array")
        }
        XCTAssertEqual(items.count, 3)

        let repaired = PiAIJSON.parseStreamingJSON(#"{"items":[1,2"#)
        guard case .object(let repairedObject) = repaired else {
            return XCTFail("Expected repaired object")
        }
        guard case .array(let repairedItems)? = repairedObject["items"] else {
            return XCTFail("Expected repaired items")
        }
        XCTAssertEqual(repairedItems.count, 2)
    }

    func testAssistantMessageEventStreamEndWithResultAndIgnoresLaterPushes() async throws {
        let stream = PiAIAssistantMessageEventStream()
        let resultMessage = makeAssistantMessage(stopReason: .stop)

        stream.end(with: resultMessage)
        stream.push(.done(reason: .error, message: makeAssistantMessage(stopReason: .error)))

        var seenEvents = 0
        for await _ in stream {
            seenEvents += 1
        }

        let final = await stream.result()
        XCTAssertEqual(seenEvents, 0)
        XCTAssertEqual(final, resultMessage)
    }

    func testAssistantMessageEventStreamResultAwaitsTerminalError() async throws {
        let stream = PiAIAssistantMessageEventStream()
        let errorMessage = makeAssistantMessage(stopReason: .error, errorMessage: "boom")

        let task = Task { await stream.result() }
        stream.push(.error(reason: .error, error: errorMessage))
        let result = await task.value

        XCTAssertEqual(result.stopReason, .error)
        XCTAssertEqual(result.errorMessage, "boom")
    }

    private func makeAssistantMessage(stopReason: PiAIStopReason, errorMessage: String? = nil) -> PiAIAssistantMessage {
        PiAIAssistantMessage(
            content: [],
            api: "test",
            provider: "test",
            model: "test-model",
            usage: .zero,
            stopReason: stopReason,
            errorMessage: errorMessage,
            timestamp: 1
        )
    }
}
