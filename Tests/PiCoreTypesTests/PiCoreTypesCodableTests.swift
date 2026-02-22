import Foundation
import XCTest
import PiTestSupport
@testable import PiCoreTypes

final class PiCoreTypesCodableTests: XCTestCase {
    func testJSONValueRoundTripForNestedObject() throws {
        let value: JSONValue = .object([
            "name": .string("pi-swift"),
            "flags": .array([.bool(true), .null]),
            "meta": .object([
                "version": .number(1),
                "stable": .bool(false),
            ]),
        ])

        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)

        XCTAssertEqual(decoded, value)
    }

    func testMessageAndToolSchemaRoundTrip() throws {
        let schema = PiToolParameterSchema(
            type: .object,
            description: "Read a file",
            properties: [
                "path": .init(type: .string, description: "Absolute path"),
                "encoding": .init(type: .string, enumValues: ["utf8", "ascii"]),
            ],
            required: ["path"],
            additionalProperties: false
        )
        let toolCall = PiToolCall(
            id: "call_1",
            name: "read",
            arguments: .object([
                "path": .string("/tmp/demo.txt"),
                "encoding": .string("utf8"),
            ])
        )
        let toolResult = PiToolResult(
            toolCallID: "call_1",
            content: .object(["content": .string("hello")])
        )
        let message = PiMessage(
            id: "msg_1",
            role: .assistant,
            parts: [
                .text("Reading file..."),
                .toolCall(toolCall),
                .toolResult(toolResult),
            ]
        )
        struct Envelope: Codable, Equatable {
            var schema: PiToolParameterSchema
            var message: PiMessage
        }

        let encoded = try JSONEncoder().encode(Envelope(schema: schema, message: message))
        let decoded = try JSONDecoder().decode(Envelope.self, from: encoded)

        XCTAssertEqual(decoded.schema, schema)
        XCTAssertEqual(decoded.message, message)
    }

    func testStreamEventEncodingMatchesGoldenFixture() throws {
        let events: [PiStreamEvent] = [
            .start(modelID: "openai/gpt-4o-mini"),
            .textStart,
            .textDelta("Hello"),
            .toolCall(.init(
                id: "call_1",
                name: "get_time",
                arguments: .object(["timezone": .string("UTC")])
            )),
            .toolResult(.init(
                toolCallID: "call_1",
                content: .object(["time": .string("12:00")]),
                isError: false
            )),
            .textEnd,
            .finish(stopReason: "stop"),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(events), as: UTF8.self)

        let loader = try FixtureLoader(callerFilePath: #filePath)
        let result = try GoldenFile.verifyText(
            json + "\n",
            fixturePath: "core-types/stream-events.json",
            loader: loader,
            updateMode: .never
        )

        XCTAssertEqual(result, .matched)

        let roundTrip = try JSONDecoder().decode([PiStreamEvent].self, from: Data(json.utf8))
        XCTAssertEqual(roundTrip, events)
    }
}
