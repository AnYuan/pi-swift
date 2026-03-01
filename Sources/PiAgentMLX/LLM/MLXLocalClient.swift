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
            var output = PiAIAssistantMessage(
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
                let hasShellTool = (context.tools ?? []).contains { $0.name == "shell" }
                var startTags = ["```json\n"]
                if hasShellTool {
                    startTags.append(contentsOf: ["```bash\n", "```sh\n", "```shell\n"])
                }
                let endTag = "```"
                var contentIndex = 0
                var currentActiveBlockTag: String? = nil
                var currentTextAccumulator = ""
                
                await stream.push(.textStart(contentIndex: contentIndex, partial: output))
                
                for try await generation in generationStream {
                    guard case .chunk(let chunk) = generation else { continue }
                    buffer += chunk
                    
                    if !inToolBlock {
                        var bestRange: Range<String.Index>?
                        var bestTag: String?
                        for tag in startTags {
                            if let range = buffer.range(of: tag) {
                                if bestRange == nil || range.lowerBound < bestRange!.lowerBound {
                                    bestRange = range
                                    bestTag = tag
                                }
                            }
                        }
                        
                        if let range = bestRange, let tag = bestTag {
                            let before = String(buffer[..<range.lowerBound])
                            if !before.isEmpty {
                                currentTextAccumulator += before
                                await stream.push(.textDelta(contentIndex: contentIndex, delta: before, partial: output))
                            }
                            inToolBlock = true
                            currentActiveBlockTag = tag
                            buffer = String(buffer[range.upperBound...])
                        } else {
                            var matchedPartial = false
                            for tag in startTags {
                                let maxSuffixLen = min(buffer.count, tag.count - 1)
                                if maxSuffixLen > 0 {
                                    for i in stride(from: maxSuffixLen, through: 1, by: -1) {
                                        let tempSuffix = String(buffer.suffix(i))
                                        if tag.hasPrefix(tempSuffix) {
                                            let safeCount = buffer.count - i
                                            if safeCount > 0 {
                                                let emitText = String(buffer.prefix(safeCount))
                                                currentTextAccumulator += emitText
                                                await stream.push(.textDelta(contentIndex: contentIndex, delta: emitText, partial: output))
                                                buffer = tempSuffix
                                            }
                                            matchedPartial = true
                                            break
                                        }
                                    }
                                }
                                if matchedPartial { break }
                            }
                            
                            if !matchedPartial {
                                currentTextAccumulator += buffer
                                await stream.push(.textDelta(contentIndex: contentIndex, delta: buffer, partial: output))
                                buffer = ""
                            }
                        }
                    } else {
                        if let endIndex = buffer.range(of: endTag) {
                            let toolBody = String(buffer[..<endIndex.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            var toolName: String?
                            var jsonArgs: [String: PiCoreTypes.JSONValue] = [:]
                            
                            if currentActiveBlockTag == "```json\n" {
                                if let data = toolBody.data(using: .utf8),
                                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    toolName = (dict["tool_name"] as? String) ?? (dict["name"] as? String) ?? (dict["tool"] as? String)
                                    if let argsDict = dict["arguments"] as? [String: Any] {
                                        for (k, v) in argsDict {
                                            if let strVal = v as? String {
                                                jsonArgs[k] = .string(strVal)
                                            } else if let intVal = v as? Int {
                                                jsonArgs[k] = .number(Double(intVal))
                                            } else if let doubleVal = v as? Double {
                                                jsonArgs[k] = .number(doubleVal)
                                            } else if let boolVal = v as? Bool {
                                                jsonArgs[k] = .bool(boolVal)
                                            }
                                        }
                                    }
                                }
                            } else {
                                toolName = "shell"
                                jsonArgs["command"] = .string(toolBody)
                            }
                            
                            if let name = toolName {
                                // Finalize the current text segment
                                let trimmedText = currentTextAccumulator.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmedText.isEmpty {
                                    output.content.append(.text(.init(text: trimmedText)))
                                }
                                currentTextAccumulator = ""
                                
                                let toolCallId = UUID().uuidString
                                let toolCallContent = PiAIToolCallContent(id: toolCallId, name: name, arguments: jsonArgs)
                                output.content.append(.toolCall(toolCallContent))
                                output.stopReason = .toolUse
                                
                                await stream.push(.textEnd(contentIndex: contentIndex, content: "", partial: output))
                                contentIndex += 1
                                await stream.push(.toolCallStart(contentIndex: contentIndex, partial: output))
                                await stream.push(.toolCallEnd(contentIndex: contentIndex, toolCall: toolCallContent, partial: output))
                                contentIndex += 1
                                await stream.push(.textStart(contentIndex: contentIndex, partial: output))
                            } else {
                                let reconstructedTag = currentActiveBlockTag ?? "```json\n"
                                let fallbackText = reconstructedTag + toolBody + endTag
                                currentTextAccumulator += fallbackText
                                await stream.push(.textDelta(contentIndex: contentIndex, delta: fallbackText, partial: output))
                            }
                            
                            inToolBlock = false
                            currentActiveBlockTag = nil
                            buffer = String(buffer[endIndex.upperBound...])
                        }
                    }
                }
                
                if !buffer.isEmpty && !inToolBlock {
                    currentTextAccumulator += buffer
                    await stream.push(.textDelta(contentIndex: contentIndex, delta: buffer, partial: output))
                }
                
                // Finalize any remaining text
                let finalText = currentTextAccumulator.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalText.isEmpty {
                    output.content.append(.text(.init(text: finalText)))
                }
                
                await stream.push(.textEnd(contentIndex: contentIndex, content: "", partial: output))
                await stream.push(.done(reason: output.stopReason, message: output))
                
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
                    } else if case .toolCall(let tc) = part {
                        text += "```json\n"
                        var argDict: [String: Any] = [:]
                        for (k, v) in tc.arguments {
                            argDict[k] = jsonValueToAny(v)
                        }
                        let jsonDict: [String: Any] = [
                            "tool_name": tc.name, // Use 'tool_name' as instructed
                            "arguments": argDict
                        ]
                        if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .withoutEscapingSlashes]),
                           let jsonStr = String(data: data, encoding: .utf8) {
                            text += jsonStr + "\n"
                        } else {
                            text += "{\n  \"tool_name\": \"\(tc.name)\",\n  \"arguments\": {}\n}\n"
                        }
                        text += "```\n"
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
            default:
                break
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

    private func jsonValueToAny(_ value: PiCoreTypes.JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { jsonValueToAny($0) }
        case .object(let o): return o.mapValues { jsonValueToAny($0) }
        }
    }
}
