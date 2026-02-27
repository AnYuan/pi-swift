import XCTest
@testable import PiAI
@testable import PiCoreTypes

final class PiAIOpenAICompatibleHTTPProviderTests: XCTestCase {
    func testBuildsChatCompletionsRequestAndParsesTextAndToolCalls() async throws {
        let transport = RecordingOpenAICompatibleTransport()
        transport.next = .init(statusCode: 200, body: Data(
            """
            {
              "choices": [
                {
                  "finish_reason": "tool_calls",
                  "message": {
                    "content": "Checking weather...",
                    "tool_calls": [
                      {
                        "id": "call_1",
                        "function": {
                          "name": "get_weather",
                          "arguments": "{\\"city\\":\\"Berlin\\"}"
                        }
                      }
                    ]
                  }
                }
              ],
              "usage": {
                "prompt_tokens": 12,
                "completion_tokens": 8,
                "total_tokens": 20
              }
            }
            """.utf8
        ))

        let provider = PiAIOpenAICompatibleHTTPProvider(transport: transport)
        let context = PiAIContext(
            messages: [
                .user(.init(content: .text("Weather in Berlin?"), timestamp: 1)),
            ],
            tools: [
                .init(
                    name: "get_weather",
                    description: "Fetch weather by city",
                    parameters: .init(
                        type: .object,
                        properties: ["city": .init(type: .string)],
                        required: ["city"],
                        additionalProperties: false
                    )
                )
            ]
        )

        let stream = provider.stream(
            model: .init(id: "qwen3.5", baseURL: "http://localhost:1234"),
            context: context,
            apiKey: "test-key"
        )

        var events: [String] = []
        for await event in stream {
            events.append(eventTypeName(event))
        }
        XCTAssertEqual(events, [
            "start",
            "text_start",
            "text_delta",
            "text_end",
            "toolcall_start",
            "toolcall_delta",
            "toolcall_end",
            "done",
        ])

        let final = await stream.result()
        XCTAssertEqual(final.stopReason, .toolUse)
        XCTAssertEqual(final.usage.input, 12)
        XCTAssertEqual(final.usage.output, 8)
        XCTAssertEqual(final.usage.totalTokens, 20)
        XCTAssertEqual(final.content.count, 2)

        guard case .text(let textBlock)? = final.content.first else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(textBlock.text, "Checking weather...")

        guard case .toolCall(let toolCall)? = final.content.last else {
            return XCTFail("Expected tool call block")
        }
        XCTAssertEqual(toolCall.name, "get_weather")
        XCTAssertEqual(toolCall.arguments["city"], .string("Berlin"))

        XCTAssertEqual(transport.requests.count, 1)
        let request = transport.requests[0]
        XCTAssertEqual(request.url.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-key")

        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3.5")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "Weather in Berlin?")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        let function = try XCTUnwrap(tools[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "get_weather")
    }

    func testNonSuccessStatusEmitsTerminalErrorEvent() async throws {
        let transport = RecordingOpenAICompatibleTransport()
        transport.next = .init(
            statusCode: 401,
            body: Data("{\"error\":\"invalid api key\"}".utf8)
        )
        let provider = PiAIOpenAICompatibleHTTPProvider(transport: transport)

        let stream = provider.stream(
            model: .init(id: "qwen3.5", baseURL: "http://localhost:1234"),
            context: .init(messages: [])
        )

        var terminalError: PiAIAssistantMessage?
        for await event in stream {
            if case .error(_, let error) = event {
                terminalError = error
            }
        }

        XCTAssertEqual(terminalError?.stopReason, .error)
        XCTAssertTrue(terminalError?.errorMessage?.contains("401") ?? false)
        XCTAssertTrue(terminalError?.errorMessage?.contains("invalid api key") ?? false)
    }

    func testParsesArrayContentPayloadIntoTextBlock() async throws {
        let transport = RecordingOpenAICompatibleTransport()
        transport.next = .init(statusCode: 200, body: Data(
            """
            {
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {
                    "content": [
                      {"type":"text","text":"Line 1"},
                      {"type":"text","text":"Line 2"}
                    ]
                  }
                }
              ]
            }
            """.utf8
        ))
        let provider = PiAIOpenAICompatibleHTTPProvider(transport: transport)
        let stream = provider.stream(
            model: .init(id: "qwen3.5", baseURL: "http://localhost:1234"),
            context: .init(messages: [.user(.init(content: .text("hi"), timestamp: 1))])
        )

        var events: [String] = []
        for await event in stream {
            events.append(eventTypeName(event))
        }
        XCTAssertEqual(events, ["start", "text_start", "text_delta", "text_end", "done"])

        let final = await stream.result()
        guard case .text(let text)? = final.content.first else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(text.text, "Line 1\nLine 2")
        XCTAssertEqual(final.stopReason, .stop)
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

private final class RecordingOpenAICompatibleTransport: PiAIOpenAICompatibleHTTPTransport, @unchecked Sendable {
    var next: PiAIOpenAICompatibleHTTPResponse = .init(statusCode: 200, body: Data())
    private(set) var requests: [PiAIOpenAICompatibleHTTPRequest] = []

    func perform(_ request: PiAIOpenAICompatibleHTTPRequest) async throws -> PiAIOpenAICompatibleHTTPResponse {
        requests.append(request)
        return next
    }
}
