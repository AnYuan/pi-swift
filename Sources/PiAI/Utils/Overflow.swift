import Foundation

public enum PiAIOverflow {
    private static let overflowPatterns: [String] = [
        "prompt is too long",
        "input is too long for requested model",
        "exceeds the context window",
        "input token count.*exceeds the maximum",
        "maximum prompt length is \\d+",
        "reduce the length of the messages",
        "maximum context length is \\d+ tokens",
        "exceeds the limit of \\d+",
        "exceeds the available context size",
        "greater than the context length",
        "context window exceeds limit",
        "exceeded model token limit",
        "context[_ ]length[_ ]exceeded",
        "too many tokens",
        "token limit exceeded",
    ]

    public static func isContextOverflow(_ message: PiAIAssistantMessage, contextWindow: Int? = nil) -> Bool {
        if message.stopReason == .error, let errorMessage = message.errorMessage {
            if overflowPatterns.contains(where: { errorMessage.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
                return true
            }
            if errorMessage.range(of: #"^4(00|13)\s*(status code)?\s*\(no body\)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }

        if let contextWindow, message.stopReason == .stop {
            let inputTokens = message.usage.input + message.usage.cacheRead
            if inputTokens > contextWindow {
                return true
            }
        }

        return false
    }

    public static func patterns() -> [String] {
        overflowPatterns
    }
}

