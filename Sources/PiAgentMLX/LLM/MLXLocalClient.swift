import Foundation
import PiCoreTypes
import PiAI
import MLXLMCommon

/// A local client that delegats to MLXModelEngine for MLX native inference
public actor MLXLocalClient {
    public let provider: String = "mlx-native"
    public let engine: MLXModelEngine
    
    public init(engine: MLXModelEngine) {
        self.engine = engine
    }
    
    public func streamResponse(
        messages: [ChatMessage],
        tools: [ToolSpec]
    ) -> AsyncThrowingStream<LLMChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Start generation
                    try await engine.load(modelId: self.modelID)
                    
                    let prompt = buildPrompt(from: messages, tools: tools)
                    let generationStream = try await engine.generateStream(prompt: prompt, maxTokens: 1024)
                    
                    var buffer = ""
                    var inToolBlock = false
                    let startTag = "<tool_code>"
                    let endTag = "</tool_code>"
                    
                    for try await generation in generationStream {
                        guard case .chunk(let chunk) = generation else { continue }
                        buffer += chunk
                        
                        if !inToolBlock {
                            if let startIndex = buffer.range(of: startTag) {
                                let before = String(buffer[..<startIndex.lowerBound])
                                if !before.isEmpty {
                                    continuation.yield(.textDelta(before))
                                }
                                inToolBlock = true
                                buffer = String(buffer[startIndex.upperBound...])
                            } else {
                                var matched = false
                                let maxSuffixLen = min(buffer.count, startTag.count - 1)
                                if maxSuffixLen > 0 {
                                    for i in stride(from: maxSuffixLen, through: 1, by: -1) {
                                        let tempSuffix = String(buffer.suffix(i))
                                        if startTag.hasPrefix(tempSuffix) {
                                            let safeCount = buffer.count - i
                                            if safeCount > 0 {
                                                continuation.yield(.textDelta(String(buffer.prefix(safeCount))))
                                                buffer = tempSuffix
                                            }
                                            matched = true
                                            break
                                        }
                                    }
                                }
                                
                                if !matched {
                                    continuation.yield(.textDelta(buffer))
                                    buffer = ""
                                }
                            }
                        } else {
                            if let endIndex = buffer.range(of: endTag) {
                                let toolBody = String(buffer[..<endIndex.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                if let openParen = toolBody.firstIndex(of: "("),
                                   let closeParen = toolBody.lastIndex(of: ")") {
                                    
                                    let toolName = String(toolBody[..<openParen]).trimmingCharacters(in: .whitespaces)
                                    let argsString = String(toolBody[toolBody.index(after: openParen)..<closeParen])
                                    
                                    var arguments: [String: String] = [:]
                                    var currentArg = ""
                                    var inQuotes = false
                                    for char in argsString {
                                        if char == "\"" || char == "'" {
                                            inQuotes.toggle()
                                            currentArg.append(char)
                                        } else if char == "," && !inQuotes {
                                            parseAndAddArgument(currentArg, to: &arguments)
                                            currentArg = ""
                                        } else {
                                            currentArg.append(char)
                                        }
                                    }
                                    if !currentArg.isEmpty {
                                        parseAndAddArgument(currentArg, to: &arguments)
                                    }
                                    
                                    continuation.yield(.toolCall(ToolCall(id: UUID(), name: toolName, arguments: arguments)))
                                }
                                
                                inToolBlock = false
                                buffer = String(buffer[endIndex.upperBound...])
                            }
                        }
                    }
                    
                    if !buffer.isEmpty && !inToolBlock {
                        continuation.yield(.textDelta(buffer))
                    }
                    
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func buildPrompt(from messages: [ChatMessage], tools: [ToolSpec]) -> String {
        var prompt = ""
        var systemContent = ""
        
        if !tools.isEmpty {
            systemContent += "You have the following tools available. To use a tool, output exactly:\n<tool_code> tool_name(arg_name=\"arg_value\") </tool_code>\n\nTools:\n"
            for tool in tools {
                systemContent += "- \(tool.name): \(tool.description)\n"
                systemContent += "  Arguments: " + tool.argumentSchema.keys.joined(separator: ", ") + "\n"
            }
            systemContent += "\n"
        }

        for message in messages {
            let roleName = message.role == .system ? "system" : 
                           (message.role == .user ? "user" : 
                           (message.role == .tool ? "tool" : "assistant"))
            
            let content = message.role == .system ? (systemContent + message.content) : message.content
            
            prompt += "<|im_start|>\(roleName)\n\(content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
    
    private func parseAndAddArgument(_ argString: String, to arguments: inout [String: String]) {
        let components = argString.components(separatedBy: "=")
        if components.count >= 2 {
            let key = components[0].trimmingCharacters(in: .whitespaces)
            var value = components[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'") && value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                arguments[key] = value
            }
        }
    }
}
