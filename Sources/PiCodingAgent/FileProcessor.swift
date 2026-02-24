import Foundation
import PiAI

public struct PiCodingAgentProcessedFiles: Equatable, Sendable {
    public var text: String
    public var images: [PiAIImageContent]

    public init(text: String, images: [PiAIImageContent]) {
        self.text = text
        self.images = images
    }
}

public struct PiCodingAgentFileProcessorOptions: Equatable, Sendable {
    public var autoResizeImages: Bool

    public init(autoResizeImages: Bool = true) {
        self.autoResizeImages = autoResizeImages
    }
}

public enum PiCodingAgentFileProcessorError: Error, Equatable, CustomStringConvertible {
    case fileNotFound(String)
    case readFailed(String)
    case unsupportedTextEncoding(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .readFailed(let path): return "Failed to read file: \(path)"
        case .unsupportedTextEncoding(let path): return "Unsupported text encoding: \(path)"
        }
    }
}

public enum PiCodingAgentFileProcessor {
    public static func processFileArguments(
        _ fileArgs: [String],
        options: PiCodingAgentFileProcessorOptions = .init(),
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) throws -> PiCodingAgentProcessedFiles {
        _ = options // Reserved for future image resizing parity slice.

        var text = ""
        var images: [PiAIImageContent] = []

        for fileArg in fileArgs {
            let absolutePath = resolveFileArgumentPath(fileArg, currentDirectory: currentDirectory)
            guard FileManager.default.fileExists(atPath: absolutePath) else {
                throw PiCodingAgentFileProcessorError.fileNotFound(absolutePath)
            }

            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: absolutePath))
            } catch {
                throw PiCodingAgentFileProcessorError.readFailed(absolutePath)
            }

            if data.isEmpty {
                continue
            }

            if let mimeType = detectSupportedImageMimeType(from: data, path: absolutePath) {
                images.append(.init(data: data.base64EncodedString(), mimeType: mimeType))
                text += "<file name=\"\(absolutePath)\"></file>\n"
                continue
            }

            guard let content = String(data: data, encoding: .utf8) else {
                throw PiCodingAgentFileProcessorError.unsupportedTextEncoding(absolutePath)
            }
            text += "<file name=\"\(absolutePath)\">\n\(content)\n</file>\n"
        }

        return .init(text: text, images: images)
    }
}

private func resolveFileArgumentPath(_ path: String, currentDirectory: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
    return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: currentDirectory))
        .standardizedFileURL
        .path
}

private func detectSupportedImageMimeType(from data: Data, path: String) -> String? {
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if data.starts(with: Array("GIF87a".utf8)) || data.starts(with: Array("GIF89a".utf8)) { return "image/gif" }
    if data.starts(with: Array("BM".utf8)) { return "image/bmp" }
    if data.count >= 12 {
        let riff = data.prefix(4)
        let webp = data.dropFirst(8).prefix(4)
        if riff.elementsEqual(Array("RIFF".utf8)), webp.elementsEqual(Array("WEBP".utf8)) {
            return "image/webp"
        }
    }

    switch (path as NSString).pathExtension.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "bmp": return "image/bmp"
    default: return nil
    }
}
