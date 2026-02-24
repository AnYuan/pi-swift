import Foundation

public enum PiCodingAgentResourceType: String, Codable, Equatable, Sendable {
    case skill
    case prompt
    case theme
    case `extension`
}

public enum PiCodingAgentResourceDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

public struct PiCodingAgentResourceDiagnostic: Codable, Equatable, Sendable {
    public var severity: PiCodingAgentResourceDiagnosticSeverity
    public var resourceType: PiCodingAgentResourceType
    public var path: String
    public var message: String

    public init(severity: PiCodingAgentResourceDiagnosticSeverity, resourceType: PiCodingAgentResourceType, path: String, message: String) {
        self.severity = severity
        self.resourceType = resourceType
        self.path = path
        self.message = message
    }
}

public struct PiCodingAgentSkillResource: Equatable, Sendable {
    public var name: String
    public var description: String
    public var content: String
    public var path: String
    public var disableModelInvocation: Bool
}

public struct PiCodingAgentPromptTemplateResource: Equatable, Sendable {
    public var name: String
    public var description: String
    public var content: String
    public var path: String
}

public struct PiCodingAgentThemeResource: Equatable, Sendable {
    public var name: String
    public var colors: [String: String]
    public var path: String
}

public struct PiCodingAgentExtensionResource: Equatable, Sendable {
    public var name: String
    public var entryPaths: [String]
    public var skillsPaths: [String]
    public var promptPaths: [String]
    public var themePaths: [String]
    public var tools: [String]
    public var commands: [String]
    public var flags: [String]
    public var path: String
}

public struct PiCodingAgentLoadedResources: Equatable, Sendable {
    public var skills: [PiCodingAgentSkillResource]
    public var prompts: [PiCodingAgentPromptTemplateResource]
    public var themes: [PiCodingAgentThemeResource]
    public var extensions: [PiCodingAgentExtensionResource]
    public var diagnostics: [PiCodingAgentResourceDiagnostic]

    public init(
        skills: [PiCodingAgentSkillResource] = [],
        prompts: [PiCodingAgentPromptTemplateResource] = [],
        themes: [PiCodingAgentThemeResource] = [],
        extensions: [PiCodingAgentExtensionResource] = [],
        diagnostics: [PiCodingAgentResourceDiagnostic] = []
    ) {
        self.skills = skills
        self.prompts = prompts
        self.themes = themes
        self.extensions = extensions
        self.diagnostics = diagnostics
    }
}

public struct PiCodingAgentResourcePaths: Equatable, Sendable {
    public var skillPaths: [String]
    public var promptPaths: [String]
    public var themePaths: [String]
    public var extensionPaths: [String]

    public init(skillPaths: [String] = [], promptPaths: [String] = [], themePaths: [String] = [], extensionPaths: [String] = []) {
        self.skillPaths = skillPaths
        self.promptPaths = promptPaths
        self.themePaths = themePaths
        self.extensionPaths = extensionPaths
    }
}

public struct PiCodingAgentFrontmatterDocument: Equatable, Sendable {
    public var attributes: [String: String]
    public var body: String
}

public enum PiCodingAgentFrontmatterParser {
    public static func parse(_ markdown: String) -> PiCodingAgentFrontmatterDocument {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return .init(attributes: [:], body: markdown)
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let endIndex = lines.dropFirst().firstIndex(of: "---"), endIndex > 0 else {
            return .init(attributes: [:], body: markdown)
        }

        var attrs: [String: String] = [:]
        for line in lines[1..<endIndex] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            attrs[key] = value
        }

        let body = Array(lines[(endIndex + 1)...]).joined(separator: "\n")
        return .init(attributes: attrs, body: body)
    }
}

public final class PiCodingAgentResourceLoader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(paths: PiCodingAgentResourcePaths) -> PiCodingAgentLoadedResources {
        var result = PiCodingAgentLoadedResources()

        let skills = loadSkills(paths: paths.skillPaths, diagnostics: &result.diagnostics)
        result.skills = dedupe(skills, type: .skill, diagnostics: &result.diagnostics, keyPath: \.name)

        let prompts = loadPrompts(paths: paths.promptPaths, diagnostics: &result.diagnostics)
        result.prompts = dedupe(prompts, type: .prompt, diagnostics: &result.diagnostics, keyPath: \.name)

        let themes = loadThemes(paths: paths.themePaths, diagnostics: &result.diagnostics)
        result.themes = dedupe(themes, type: .theme, diagnostics: &result.diagnostics, keyPath: \.name)

        let exts = loadExtensions(paths: paths.extensionPaths, diagnostics: &result.diagnostics)
        result.extensions = detectExtensionConflicts(exts, diagnostics: &result.diagnostics)

        return result
    }

    public static func parseCommandArgs(_ input: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuotes = false
        var escape = false

        for ch in input {
            if escape {
                current.append(ch)
                escape = false
                continue
            }
            if ch == "\\" {
                escape = true
                continue
            }
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { args.append(current) }
        return args
    }

    public static func substitutePromptArgs(template: String, args: [String]) -> String {
        var output = template
        for (index, arg) in args.enumerated() {
            output = output.replacingOccurrences(of: "$\(index + 1)", with: arg)
        }
        output = output.replacingOccurrences(of: "$@", with: args.joined(separator: " "))

        if let regex = try? NSRegularExpression(pattern: #"\$\{@:(\d+)\}"#) {
            let ns = output as NSString
            let matches = regex.matches(in: output, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                guard m.numberOfRanges == 2,
                      let range = Range(m.range(at: 1), in: output),
                      let idx = Int(output[range]),
                      idx >= 1 else { continue }
                let tail = Array(args.dropFirst(idx - 1)).joined(separator: " ")
                output = (output as NSString).replacingCharacters(in: m.range, with: tail)
            }
        }
        return output
    }

    private func loadSkills(paths: [String], diagnostics: inout [PiCodingAgentResourceDiagnostic]) -> [PiCodingAgentSkillResource] {
        var resources: [PiCodingAgentSkillResource] = []
        for path in paths {
            for file in enumerateMarkdownFiles(at: path, skillMode: true) {
                guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
                    diagnostics.append(.init(severity: .warning, resourceType: .skill, path: file, message: "Failed to read skill file"))
                    continue
                }
                let doc = PiCodingAgentFrontmatterParser.parse(text)
                let inferredName = inferSkillName(from: file)
                let name = (doc.attributes["name"]?.isEmpty == false ? doc.attributes["name"]! : inferredName)
                let description = doc.attributes["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard isValidResourceName(name) else {
                    diagnostics.append(.init(severity: .warning, resourceType: .skill, path: file, message: "Invalid skill name '\(name)'"))
                    continue
                }
                guard !description.isEmpty else {
                    diagnostics.append(.init(severity: .warning, resourceType: .skill, path: file, message: "Skill description is required"))
                    continue
                }
                if description.count > 1024 {
                    diagnostics.append(.init(severity: .warning, resourceType: .skill, path: file, message: "Skill description exceeds 1024 chars"))
                    continue
                }

                let disable = (doc.attributes["disable-model-invocation"] ?? "").lowercased() == "true"
                resources.append(.init(name: name, description: description, content: doc.body, path: file, disableModelInvocation: disable))
            }
        }
        return resources
    }

    private func loadPrompts(paths: [String], diagnostics: inout [PiCodingAgentResourceDiagnostic]) -> [PiCodingAgentPromptTemplateResource] {
        var resources: [PiCodingAgentPromptTemplateResource] = []
        for path in paths {
            for file in enumerateMarkdownFiles(at: path, skillMode: false) {
                guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
                    diagnostics.append(.init(severity: .warning, resourceType: .prompt, path: file, message: "Failed to read prompt template"))
                    continue
                }
                let doc = PiCodingAgentFrontmatterParser.parse(text)
                let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                let body = doc.body.trimmingCharacters(in: .whitespacesAndNewlines)
                let desc = (doc.attributes["description"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? doc.attributes["description"]!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : inferPromptDescription(from: body)
                resources.append(.init(name: name, description: desc, content: doc.body, path: file))
            }
        }
        return resources
    }

    private func loadThemes(paths: [String], diagnostics: inout [PiCodingAgentResourceDiagnostic]) -> [PiCodingAgentThemeResource] {
        var resources: [PiCodingAgentThemeResource] = []
        for path in paths {
            for file in enumerateJSONFiles(at: path) {
                guard let data = fileManager.contents(atPath: file) else {
                    diagnostics.append(.init(severity: .warning, resourceType: .theme, path: file, message: "Failed to read theme file"))
                    continue
                }
                guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    diagnostics.append(.init(severity: .warning, resourceType: .theme, path: file, message: "Invalid JSON theme"))
                    continue
                }
                guard let name = object["name"] as? String, !name.isEmpty else {
                    diagnostics.append(.init(severity: .warning, resourceType: .theme, path: file, message: "Theme missing name"))
                    continue
                }
                guard let colors = object["colors"] as? [String: String] else {
                    diagnostics.append(.init(severity: .warning, resourceType: .theme, path: file, message: "Theme missing colors object"))
                    continue
                }
                for required in ["text", "background"] where colors[required] == nil {
                    diagnostics.append(.init(severity: .warning, resourceType: .theme, path: file, message: "Theme missing required color '\(required)'"))
                    continue
                }
                if colors["text"] == nil || colors["background"] == nil {
                    continue
                }
                resources.append(.init(name: name, colors: colors, path: file))
            }
        }
        return resources
    }

    private func loadExtensions(paths: [String], diagnostics: inout [PiCodingAgentResourceDiagnostic]) -> [PiCodingAgentExtensionResource] {
        var resources: [PiCodingAgentExtensionResource] = []
        for base in paths {
            for entry in discoverExtensionEntries(at: base) {
                switch entry.kind {
                case .standalone:
                    resources.append(.init(
                        name: entry.name,
                        entryPaths: [entry.path],
                        skillsPaths: [],
                        promptPaths: [],
                        themePaths: [],
                        tools: [],
                        commands: [],
                        flags: [],
                        path: entry.path
                    ))
                case .package:
                    guard let data = fileManager.contents(atPath: entry.packageJSONPath),
                          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                        diagnostics.append(.init(severity: .warning, resourceType: .extension, path: entry.packageJSONPath, message: "Failed to parse package.json"))
                        continue
                    }
                    let pi = object["pi"] as? [String: Any] ?? [:]
                    let extEntries = stringArray(pi["extensions"]).map { (entry.path as NSString).appendingPathComponent($0) }
                    let skills = stringArray(pi["skills"]).map { (entry.path as NSString).appendingPathComponent($0) }
                    let prompts = stringArray(pi["prompts"]).map { (entry.path as NSString).appendingPathComponent($0) }
                    let themes = stringArray(pi["themes"]).map { (entry.path as NSString).appendingPathComponent($0) }
                    let tools = stringArray(pi["tools"])
                    let commands = stringArray(pi["commands"])
                    let flags = stringArray(pi["flags"])
                    resources.append(.init(
                        name: entry.name,
                        entryPaths: extEntries,
                        skillsPaths: skills,
                        promptPaths: prompts,
                        themePaths: themes,
                        tools: tools,
                        commands: commands,
                        flags: flags,
                        path: entry.path
                    ))
                }
            }
        }
        return resources
    }

    private func detectExtensionConflicts(
        _ extensions: [PiCodingAgentExtensionResource],
        diagnostics: inout [PiCodingAgentResourceDiagnostic]
    ) -> [PiCodingAgentExtensionResource] {
        var seenTools: [String: String] = [:]
        var seenCommands: [String: String] = [:]
        var seenFlags: [String: String] = [:]
        var accepted: [PiCodingAgentExtensionResource] = []

        for ext in extensions {
            var conflictMessage: String?

            for tool in ext.tools {
                if let other = seenTools[tool] {
                    conflictMessage = "Tool conflict '\(tool)' with \(other)"
                    break
                }
            }
            if conflictMessage == nil {
                for command in ext.commands {
                    if let other = seenCommands[command] {
                        conflictMessage = "Command conflict '\(command)' with \(other)"
                        break
                    }
                }
            }
            if conflictMessage == nil {
                for flag in ext.flags {
                    if let other = seenFlags[flag] {
                        conflictMessage = "Flag conflict '\(flag)' with \(other)"
                        break
                    }
                }
            }

            if let conflictMessage {
                diagnostics.append(.init(severity: .error, resourceType: .extension, path: ext.path, message: conflictMessage))
                continue
            }

            for tool in ext.tools { seenTools[tool] = ext.path }
            for command in ext.commands { seenCommands[command] = ext.path }
            for flag in ext.flags { seenFlags[flag] = ext.path }
            accepted.append(ext)
        }

        return accepted
    }

    private func inferSkillName(from path: String) -> String {
        let name = (path as NSString).lastPathComponent
        if name == "SKILL.md" {
            return ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        }
        return (name as NSString).deletingPathExtension
    }

    private func inferPromptDescription(from body: String) -> String {
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        if firstLine.count <= 60 { return firstLine }
        let idx = firstLine.index(firstLine.startIndex, offsetBy: 60)
        return String(firstLine[..<idx])
    }

    private func isValidResourceName(_ name: String) -> Bool {
        let pattern = #"^[a-z0-9][a-z0-9-]*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func enumerateMarkdownFiles(at path: String, skillMode: Bool) -> [String] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return path.hasSuffix(".md") ? [path] : []
        }

        var files: [String] = []
        let enumerator = fileManager.enumerator(atPath: path)
        while let next = enumerator?.nextObject() as? String {
            if next.contains("/node_modules/") || next.hasPrefix("node_modules/") {
                enumerator?.skipDescendants()
                continue
            }
            if next.hasSuffix(".md") {
                let full = (path as NSString).appendingPathComponent(next)
                let last = (next as NSString).lastPathComponent
                if skillMode {
                    let depth = next.split(separator: "/").count
                    if last == "SKILL.md" || depth == 1 {
                        files.append(full)
                    }
                } else {
                    files.append(full)
                }
            }
        }
        return files.sorted()
    }

    private func enumerateJSONFiles(at path: String) -> [String] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return path.hasSuffix(".json") ? [path] : [] }
        let enumerator = fileManager.enumerator(atPath: path)
        var files: [String] = []
        while let next = enumerator?.nextObject() as? String {
            if next.hasSuffix(".json") {
                files.append((path as NSString).appendingPathComponent(next))
            }
        }
        return files.sorted()
    }

    private enum ExtensionEntryKind { case standalone, package }
    private struct ExtensionEntryCandidate {
        var name: String
        var path: String
        var kind: ExtensionEntryKind
        var packageJSONPath: String
    }

    private func discoverExtensionEntries(at path: String) -> [ExtensionEntryCandidate] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return [] }

        if !isDir.boolValue {
            if path.hasSuffix(".js") || path.hasSuffix(".ts") {
                return [.init(name: (path as NSString).lastPathComponent, path: path, kind: .standalone, packageJSONPath: "")]
            }
            return []
        }

        var out: [ExtensionEntryCandidate] = []
        guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        for entry in entries.sorted() {
            let full = (path as NSString).appendingPathComponent(entry)
            var childIsDir: ObjCBool = false
            fileManager.fileExists(atPath: full, isDirectory: &childIsDir)

            if !childIsDir.boolValue, (entry.hasSuffix(".js") || entry.hasSuffix(".ts")) {
                out.append(.init(name: (entry as NSString).deletingPathExtension, path: full, kind: .standalone, packageJSONPath: ""))
                continue
            }

            guard childIsDir.boolValue else { continue }
            let indexJS = (full as NSString).appendingPathComponent("index.js")
            let indexTS = (full as NSString).appendingPathComponent("index.ts")
            let packageJSON = (full as NSString).appendingPathComponent("package.json")
            if fileManager.fileExists(atPath: packageJSON) {
                out.append(.init(name: entry, path: full, kind: .package, packageJSONPath: packageJSON))
            } else if fileManager.fileExists(atPath: indexJS) {
                out.append(.init(name: entry, path: indexJS, kind: .standalone, packageJSONPath: ""))
            } else if fileManager.fileExists(atPath: indexTS) {
                out.append(.init(name: entry, path: indexTS, kind: .standalone, packageJSONPath: ""))
            }
        }
        return out
    }

    private func dedupe<T>(
        _ values: [T],
        type: PiCodingAgentResourceType,
        diagnostics: inout [PiCodingAgentResourceDiagnostic],
        keyPath: KeyPath<T, String>
    ) -> [T] where T: Sendable {
        var seen: Set<String> = []
        var result: [T] = []
        for value in values {
            let key = value[keyPath: keyPath]
            if seen.contains(key) {
                diagnostics.append(.init(severity: .warning, resourceType: type, path: "", message: "Duplicate \(type.rawValue) '\(key)' ignored"))
                continue
            }
            seen.insert(key)
            result.append(value)
        }
        return result
    }
}

private func stringArray(_ value: Any?) -> [String] {
    (value as? [Any])?.compactMap { $0 as? String } ?? []
}
