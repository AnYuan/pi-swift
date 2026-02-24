import Foundation
import PiAI
import PiAgentCore
import PiCoreTypes

public enum PiCodingAgentHTMLExporterError: Error, Equatable, CustomStringConvertible {
    case unsupportedInputFormat(String)
    case readFailed(String)
    case decodeFailed(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unsupportedInputFormat(let path): return "Unsupported export input format: \(path)"
        case .readFailed(let path): return "Failed to read export input: \(path)"
        case .decodeFailed(let path): return "Failed to decode session file: \(path)"
        case .writeFailed(let path): return "Failed to write export output: \(path)"
        }
    }
}

public enum PiCodingAgentHTMLExporter {
    public static func render(session: PiCodingAgentSessionRecord) -> String {
        let title = session.id
        let subtitle = session.title?.isEmpty == false ? session.title! : session.state.model.qualifiedID
        let messageBlocks = session.state.messages.map(renderMessage).joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            :root { color-scheme: light; }
            body { margin: 0; font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, sans-serif; background: #f5f7fb; color: #101828; }
            .wrap { max-width: 920px; margin: 0 auto; padding: 24px 16px 80px; }
            .head { margin-bottom: 20px; }
            .head h1 { margin: 0 0 6px; font-size: 20px; }
            .head .meta { color: #475467; font-size: 13px; }
            .sys { margin: 0 0 16px; padding: 12px; border-radius: 10px; background: #eef2ff; white-space: pre-wrap; font-family: ui-monospace, Menlo, monospace; }
            .msg { background: white; border: 1px solid #e4e7ec; border-radius: 12px; padding: 12px; margin-bottom: 12px; }
            .msg.user { border-left: 4px solid #1570ef; }
            .msg.assistant { border-left: 4px solid #12b76a; }
            .msg.toolResult { border-left: 4px solid #f79009; }
            .msg.custom { border-left: 4px solid #667085; }
            .label { font-size: 12px; color: #475467; margin-bottom: 8px; }
            .chunk { margin: 0 0 8px; white-space: pre-wrap; }
            .chunk.thinking { color: #475467; font-style: italic; }
            .tool-meta { font-size: 12px; color: #475467; margin-bottom: 8px; }
            .json { background: #0b1020; color: #d0d5dd; border-radius: 8px; padding: 8px 10px; overflow-x: auto; font-size: 12px; }
            img.inline-image { max-width: min(420px, 100%); border: 1px solid #e4e7ec; border-radius: 8px; display: block; background: #fff; }
            .image-meta { font-size: 12px; color: #475467; margin: 4px 0 8px; }
          </style>
        </head>
        <body>
          <div class="wrap">
            <div class="head">
              <h1>\(escapeHTML(title))</h1>
              <div class="meta">\(escapeHTML(subtitle)) · model \(escapeHTML(session.state.model.qualifiedID))</div>
            </div>
            <div class="sys">\(escapeHTML(session.state.systemPrompt))</div>
            \(messageBlocks)
          </div>
        </body>
        </html>
        """
    }

    @discardableResult
    public static func exportSessionFile(at inputPath: String, outputPath: String? = nil) throws -> String {
        guard (inputPath as NSString).pathExtension.lowercased() == "json" else {
            throw PiCodingAgentHTMLExporterError.unsupportedInputFormat(inputPath)
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        } catch {
            throw PiCodingAgentHTMLExporterError.readFailed(inputPath)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session: PiCodingAgentSessionRecord
        do {
            session = try decoder.decode(PiCodingAgentSessionRecord.self, from: data)
        } catch {
            throw PiCodingAgentHTMLExporterError.decodeFailed(inputPath)
        }

        let html = render(session: session)
        let resolvedOutput = outputPath ?? defaultOutputPath(for: inputPath)
        let parent = (resolvedOutput as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try html.write(toFile: resolvedOutput, atomically: true, encoding: .utf8)
        } catch {
            throw PiCodingAgentHTMLExporterError.writeFailed(resolvedOutput)
        }
        return resolvedOutput
    }
}

private func renderMessage(_ message: PiAgentMessage) -> String {
    switch message {
    case .user(let value):
        return """
        <section class="msg user">
          <div class="label">user</div>
          \(renderUserContent(value.content))
        </section>
        """
    case .assistant(let value):
        let chunks = value.content.map { part -> String in
            switch part {
            case .text(let text):
                return "<div class=\"chunk\">\(escapeHTML(text.text))</div>"
            case .thinking(let thinking):
                return "<div class=\"chunk thinking\">thinking: \(escapeHTML(thinking.thinking))</div>"
            case .toolCall(let toolCall):
                let args = prettyJSONString(.object(toolCall.arguments))
                return """
                <div class="tool-meta">toolCall: \(escapeHTML(toolCall.name)) (\(escapeHTML(toolCall.id)))</div>
                <pre class="json">\(escapeHTML(args))</pre>
                """
            }
        }.joined(separator: "\n")
        return """
        <section class="msg assistant">
          <div class="label">assistant · \(escapeHTML(value.provider))/\(escapeHTML(value.model)) · \(escapeHTML(value.stopReason.rawValue))</div>
          \(chunks)
        </section>
        """
    case .toolResult(let value):
        let content = value.content.map(renderUserContentPart).joined(separator: "\n")
        let details = value.details.map { "<pre class=\"json\">\(escapeHTML(prettyJSONString($0)))</pre>" } ?? ""
        return """
        <section class="msg toolResult">
          <div class="label">toolResult</div>
          <div class="tool-meta">tool: \(escapeHTML(value.toolName)) · id: \(escapeHTML(value.toolCallId))\(value.isError ? " · error" : "")</div>
          \(content)
          \(details)
        </section>
        """
    case .custom(let value):
        return """
        <section class="msg custom">
          <div class="label">\(escapeHTML(value.role))</div>
          <pre class="json">\(escapeHTML(prettyJSONString(value.content)))</pre>
        </section>
        """
    }
}

private func renderUserContent(_ content: PiAIUserContent) -> String {
    switch content {
    case .text(let text):
        return "<div class=\"chunk\">\(escapeHTML(text))</div>"
    case .parts(let parts):
        return parts.map(renderUserContentPart).joined(separator: "\n")
    }
}

private func renderUserContentPart(_ part: PiAIUserContentPart) -> String {
    switch part {
    case .text(let text):
        return "<div class=\"chunk\">\(escapeHTML(text.text))</div>"
    case .image(let image):
        return """
        <div class="image-meta">image: \(escapeHTML(image.mimeType))</div>
        <img class="inline-image" alt="attachment" src="data:\(escapeHTML(image.mimeType));base64,\(image.data)">
        """
    }
}

private func prettyJSONString(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

private func escapeHTML(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    for ch in text {
        switch ch {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        case "'": result += "&#39;"
        default: result.append(ch)
        }
    }
    return result
}

private func defaultOutputPath(for inputPath: String) -> String {
    let url = URL(fileURLWithPath: inputPath)
    let base = url.deletingPathExtension().lastPathComponent
    return url.deletingLastPathComponent().appendingPathComponent("\(base).html").path
}
