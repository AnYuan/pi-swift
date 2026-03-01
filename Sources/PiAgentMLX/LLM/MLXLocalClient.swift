import Foundation
import PiCoreTypes
import PiAI
import MLXLMCommon

/// A local client that delegats to MLXModelEngine for MLX native inference
public actor MLXLocalClient {
    public let provider: String = "mlx-native"
    public var engine: MLXModelEngine?
    public let modelID: String
    
    public init(modelID: String, engine: MLXModelEngine? = nil) {
        self.modelID = modelID
        self.engine = engine
    }
    
    public func getAvailableModels() async -> [PiAIModel] {
        return [
            PiAIModel(
                provider: provider,
                id: modelID,
                displayName: modelID,
                supportsTools: true
            )
        ]
    }
    
    public func stream(
        model: PiAIModel,
        context: PiAIContext
    ) -> PiAIAssistantMessageEventStream {
        let stream = PiAIAssistantMessageEventStream()
        
        Task {
            let output = PiAIAssistantMessage(
                content: [],
                api: provider,
                provider: model.provider,
                model: model.id,
                usage: .zero,
                stopReason: .stop,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            
            do {
                await stream.push(.start(partial: output))
                
                let targetEngine: MLXModelEngine
                if let existing = self.engine {
                    targetEngine = existing
                } else {
                    targetEngine = await MLXModelEngine()
                    self.engine = targetEngine
                }
                
                try await targetEngine.load(modelId: model.id)
                
                let prompt = buildPrompt(from: context.messages, tools: context.tools ?? [])
                let generationStream = try await targetEngine.generateStream(prompt: prompt, maxTokens: 2048)
                
                var buffer = ""
                var inToolBlock = false
                let startTag = "<tool_code>"
                let endTag = "</tool_code>"
                var contentIndex = 0
                
                await stream.push(.textStart(contentIndex: contentIndex, partial: output))
                
                for try await generation in generationStream {
                    guard case .chunk(let chunk) = generation else { continue }
                    buffer += chunk
                    
                    if !inToolBlock {
                        if let startIndex = buffer.range(of: startTag) {
                            let before = String(buffer[..<startIndex.lowerBound])
                            if !before.isEmpty {
                                await stream.push(.textDelta(contentIndex: contentIndex, delta: before, partial: output))
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
                                            await stream.push(.textDelta(contentIndex: contentIndex, delta: String(buffer.prefix(safeCount)), partial: output))
                                            buffer = tempSuffix
                                        }
                                        matched = true
                                        break
                                    }
                                }
                            }
                            
                            if !matched {
                                await stream.push(.textDelta(contentIndex: contentIndex, delta: buffer, partial: output))
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
                                
                                var jsonArgs: [String: JSONValue] = [:]
                                for (k, v) in arguments {
                                    jsonArgs[k] = .string(v)
                                }
                                
                                let toolCallId = UUID().uuidString
                                let toolCallContent = PiAIToolCallContent(id: toolCallId, name: toolName, arguments: jsonArgs)
                                
                                await stream.push(.textEnd(contentIndex: contentIndex, content: "", partial: output))
                                contentIndex += 1
                                await stream.push(.toolCallStart(contentIndex: contentIndex, partial: output))
                                // Assuming we pass an empty delta or JSON representation if needed, 
                                // but for PiCoreTypes, toolCallEnd with the actual toolCall is sufficient.
                                await stream.push(.toolCallEnd(contentIndex: contentIndex, toolCall: toolCallContent, partial: output))
                                contentIndex += 1
                                await stream.push(.textStart(contentIndex: contentIndex, partial: output))
                            }
                            
                            inToolBlock = false
                            buffer = String(buffer[endIndex.upperBound...])
                        }
                    }
                }
                
                if !buffer.isEmpty && !inToolBlock {
                    await stream.push(.textDelta(contentIndex: contentIndex, delta: buffer, partial: output))
                }
                await stream.push(.textEnd(contentIndex: contentIndex, content: "", partial: output))
                await stream.push(.done(reason: .stop, message: output))
                
            } catch {
                let errOutput = PiAIAssistantMessage(
                    content: [], api: provider, provider: model.provider, model: model.id,
                    usage: .zero, stopReason: .error, errorMessage: error.localizedDescription,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000)
                )
                await stream.push(.error(reason: .error, error: errOutput))
            }
        }
        
        return stream
    }
    
    private func buildPrompt(from messages: [PiAIMessage], tools: [PiToolDefinition]) -> String {
        var prompt = ""
        var systemContent = ""
        
        if !tools.isEmpty {
            systemContent += "You have the following tools available. To use a tool, output exactly:\n<tool_code> tool_name(arg_name=\"arg_value\") </tool_code>\n\nTools:\n"
            for tool in tools {
                systemContent += "- \(tool.name): \(tool.description)\n"
                let argKeys = tool.inputSchema?["properties"]?.objectValue?.keys.map { String($0) } ?? []
                systemContent += "  Arguments: " + argKeys.joined(separator: ", ") + "\n"
            }
            systemContent += "\n"
        }

        for message in messages {
            switch message {
            case .user(let u):
                if case .text(let t) = u.content {
                    prompt += "<|im_start|>user\n\(t)<|im_end|>\n"
                }
            case .assistant(let a):
                var text = ""
                for part in a.content {
                    if case .text(let t) = part {
                        text += t.text
                    }
                }
                prompt += "<|im_start|>assistant\n\(text)<|im_end|>\n"
            case .toolResult(let tr):
                var text = ""
                for part in tr.content {
                    if case .text(let t) = part {
                        text += t.text
                    }
                }
                prompt += "<|im_start|>tool\n\(text)<|im_end|>\n"
            }
        }
        
        if !systemContent.isEmpty {
            prompt = "<|im_start|>system\n\(systemContent)<|im_end|>\n" + prompt
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
    
    private func parseAndAddArgument(_ argString: String, to arguments: inout [String: String]) {
        let components = argString.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if components.count >= 2 {
            let key = components[0].trimmingCharacters(in: .whitespaces)
            var value = components[1].trimmingCharacters(in: .whitespaces)
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
