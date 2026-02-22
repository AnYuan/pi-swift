import Foundation
import XCTest
import PiTestSupport
@testable import PiAI

final class PiAITypesTests: XCTestCase {
    func testContextRoundTripWithUserAssistantAndToolResultMessages() throws {
        let tool = PiAITool(
            name: "read",
            description: "Read a file",
            parameters: .init(
                type: .object,
                properties: [
                    "path": .init(type: .string),
                ],
                required: ["path"],
                additionalProperties: false
            )
        )

        let user = PiAIUserMessage(
            content: .parts([
                .text(.init(text: "Read this image")),
                .image(.init(data: "ZmFrZQ==", mimeType: "image/png")),
            ]),
            timestamp: 1_700_000_000_000
        )

        let assistant = PiAIAssistantMessage(
            content: [
                .text(.init(text: "Calling tool")),
                .toolCall(.init(id: "call_1", name: "read", arguments: ["path": .string("/tmp/x")])),
            ],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .init(
                input: 10,
                output: 5,
                cacheRead: 0,
                cacheWrite: 0,
                totalTokens: 15,
                cost: .init(input: 0.001, output: 0.002, cacheRead: 0, cacheWrite: 0, total: 0.003)
            ),
            stopReason: .toolUse,
            timestamp: 1_700_000_000_001
        )

        let toolResult = PiAIToolResultMessage(
            toolCallId: "call_1",
            toolName: "read",
            content: [.text(.init(text: "file content"))],
            isError: false,
            timestamp: 1_700_000_000_002
        )

        let context = PiAIContext(
            systemPrompt: "You are a helpful assistant.",
            messages: [
                .user(user),
                .assistant(assistant),
                .toolResult(toolResult),
            ],
            tools: [tool]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        let decoded = try JSONDecoder().decode(PiAIContext.self, from: data)

        XCTAssertEqual(decoded, context)
    }

    func testAssistantMessageEventsRoundTripAndGoldenEncoding() throws {
        let partial = PiAIAssistantMessage(
            content: [
                .text(.init(text: "Hello")),
                .thinking(.init(thinking: "Need a tool")),
            ],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .zero,
            stopReason: .stop,
            timestamp: 1_700_000_000_100
        )

        let completed = PiAIAssistantMessage(
            content: [
                .text(.init(text: "Hello")),
                .thinking(.init(thinking: "Need a tool")),
                .toolCall(.init(id: "call_1", name: "get_time", arguments: ["timezone": .string("UTC")])),
            ],
            api: "openai-responses",
            provider: "openai",
            model: "gpt-4o-mini",
            usage: .init(
                input: 12,
                output: 8,
                cacheRead: 0,
                cacheWrite: 0,
                totalTokens: 20,
                cost: .zero
            ),
            stopReason: .toolUse,
            timestamp: 1_700_000_000_101
        )

        let events: [PiAIAssistantMessageEvent] = [
            .start(partial: partial),
            .textStart(contentIndex: 0, partial: partial),
            .textDelta(contentIndex: 0, delta: "Hello", partial: partial),
            .thinkingStart(contentIndex: 1, partial: partial),
            .thinkingDelta(contentIndex: 1, delta: "Need a tool", partial: partial),
            .toolCallStart(contentIndex: 2, partial: completed),
            .toolCallEnd(
                contentIndex: 2,
                toolCall: .init(id: "call_1", name: "get_time", arguments: ["timezone": .string("UTC")]),
                partial: completed
            ),
            .done(reason: .toolUse, message: completed),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(events), as: UTF8.self)

        let loader = try FixtureLoader(callerFilePath: #filePath)
        let result = try GoldenFile.verifyText(
            json + "\n",
            fixturePath: "pi-ai/assistant-message-events.json",
            loader: loader,
            updateMode: .never
        )

        XCTAssertEqual(result, .matched)

        let roundTrip = try JSONDecoder().decode([PiAIAssistantMessageEvent].self, from: Data(json.utf8))
        XCTAssertEqual(roundTrip, events)
    }
}

