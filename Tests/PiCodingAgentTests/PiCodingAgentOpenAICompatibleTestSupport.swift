import Foundation
import PiAI

actor PiCodingAgentRecordingOpenAICompatibleTransport: PiAIOpenAICompatibleHTTPTransport {
    private var queuedResponses: [PiAIOpenAICompatibleHTTPResponse]
    private(set) var requests: [PiAIOpenAICompatibleHTTPRequest] = []

    init(responses: [PiAIOpenAICompatibleHTTPResponse]) {
        self.queuedResponses = responses
    }

    func perform(_ request: PiAIOpenAICompatibleHTTPRequest) async throws -> PiAIOpenAICompatibleHTTPResponse {
        requests.append(request)
        if queuedResponses.isEmpty {
            return .init(statusCode: 500, body: Data("{\"error\":\"missing fixture\"}".utf8))
        }
        return queuedResponses.removeFirst()
    }

    func lastRequest() -> PiAIOpenAICompatibleHTTPRequest? {
        requests.last
    }
}

func makeOpenAICompatibleChatCompletionResponse(content: String) -> PiAIOpenAICompatibleHTTPResponse {
    let body = """
    {
      "id": "chatcmpl-local",
      "object": "chat.completion",
      "created": 1710000000,
      "model": "mlx-community/Qwen3.5-35B-A3B-bf16",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "\(content)"
          },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 12,
        "completion_tokens": 8,
        "total_tokens": 20
      }
    }
    """
    return .init(statusCode: 200, body: Data(body.utf8))
}
