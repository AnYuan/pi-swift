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
                errorMessage: nil,
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
                let startTag = "```json\n"
                let endTag = "```"
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
                            
                            var toolName: String?
                            var jsonArgs: [String: PiCoreTypes.JSONValue] = [:]
                            
                            if let data = toolBody.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                
                                toolName = (dict["tool_name"] as? String) ?? (dict["name"] as? String) ?? (dict["tool"] as? String)
                                
                                if let argsDict = dict["arguments"] as? [String: Any] {
                                    for (k, v) in argsDict {
                                        if let strVal = v as? String {
                                            jsonArgs[k] = .string(strVal)
                                        } else if let intVal = v as? Int {
                                            jsonArgs[k] = .integer(intVal)
                                        } else if let doubleVal = v as? Double {
                                            jsonArgs[k] = .number(doubleVal)
                                        } else if let boolVal = v as? Bool {
                                            jsonArgs[k] = .boolean(boolVal)
                                        }
                                    }
                                }
                            }
                            
                            if let name = toolName {
                                let toolCallId = UUID().uuidString
                                let toolCallContent = PiAIToolCallContent(id: toolCallId, name: name, arguments: jsonArgs)
                                
                                await stream.push(.textEnd(contentIndex: contentIndex, content: "", partial: output))
                                contentIndex += 1
                                await stream.push(.toolCallStart(contentIndex: contentIndex, partial: output))
                                await stream.push(.toolCallEnd(contentIndex: contentIndex, toolCall: toolCallContent, partial: output))
                                contentIndex += 1
                                await stream.push(.textStart(contentIndex: contentIndex, partial: output))
                            } else {
                                // If it wasn't a valid tool JSON or we couldn't parse it, yield it as normal text.
                                await stream.push(.textDelta(contentIndex: contentIndex, delta: startTag + toolBody + endTag, partial: output))
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
            systemContent += "You are a helpful assistant with access to tools. To use a tool, YOU MUST output EXACTLY in the following JSON format inside a markdown block:\n"
            systemContent += "```json\n"
            systemContent += "{\n"
            systemContent += "  \"tool_name\": \"shell\",\n"
            systemContent += "  \"arguments\": {\n"
            systemContent += "    \"command\": \"ls -la\"\n"
            systemContent += "  }\n"
            systemContent += "}\n"
            systemContent += "```\n\n"
            systemContent += "You may think step-by-step before calling the tool. Do NOT output plain text commands.\n\n"
            systemContent += "Available Tools:\n"
            for tool in tools {
                systemContent += "- \(tool.name): \(tool.description)\n"
                let argKeys = tool.parameters.properties?.keys.map { String($0) } ?? []
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
