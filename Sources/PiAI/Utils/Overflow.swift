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

    // Pre-compiled regex patterns — compiled once at first access instead of
    // re-compiling on every isContextOverflow call.
    private static let compiledPatterns: [NSRegularExpression] = {
        overflowPatterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }()

    private static let compiledStatusPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^4(00|13)\s*(status code)?\s*\(no body\)"#, options: .caseInsensitive)
    }()

    public static func isContextOverflow(_ message: PiAIAssistantMessage, contextWindow: Int? = nil) -> Bool {
        if message.stopReason == .error, let errorMessage = message.errorMessage {
            let range = NSRange(errorMessage.startIndex..., in: errorMessage)
            if compiledPatterns.contains(where: { $0.firstMatch(in: errorMessage, range: range) != nil }) {
                return true
            }
            if compiledStatusPattern?.firstMatch(in: errorMessage, range: range) != nil {
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
