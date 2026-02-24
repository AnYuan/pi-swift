import Foundation
import PiCoreTypes

public enum PiCodingAgentSettingsScope: String, Codable, Equatable, Sendable {
    case global
    case project
}

public struct PiCodingAgentSettingsErrorRecord: Equatable, Sendable {
    public var scope: PiCodingAgentSettingsScope
    public var message: String

    public init(scope: PiCodingAgentSettingsScope, message: String) {
        self.scope = scope
        self.message = message
    }
}

public protocol PiCodingAgentSettingsStorage: Sendable {
    func read(scope: PiCodingAgentSettingsScope) throws -> String?
    func write(scope: PiCodingAgentSettingsScope, content: String) throws
}

public final class PiCodingAgentFileSettingsStorage: PiCodingAgentSettingsStorage, @unchecked Sendable {
    private let globalPath: String
    private let projectPath: String
    private let lock = NSLock()

    public init(globalPath: String, projectPath: String) {
        self.globalPath = globalPath
        self.projectPath = projectPath
    }

    public func read(scope: PiCodingAgentSettingsScope) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let path = path(for: scope)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    public func write(scope: PiCodingAgentSettingsScope, content: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let path = path(for: scope)
        let parent = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func path(for scope: PiCodingAgentSettingsScope) -> String {
        scope == .global ? globalPath : projectPath
    }
}

public final class PiCodingAgentInMemorySettingsStorage: PiCodingAgentSettingsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var global: String?
    private var project: String?

    public init(global: String? = nil, project: String? = nil) {
        self.global = global
        self.project = project
    }

    public func read(scope: PiCodingAgentSettingsScope) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return scope == .global ? global : project
    }

    public func write(scope: PiCodingAgentSettingsScope, content: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if scope == .global {
            global = content
        } else {
            project = content
        }
    }
}

public final class PiCodingAgentSettingsManager: @unchecked Sendable {
    private let storage: PiCodingAgentSettingsStorage

    private var globalSettings: [String: JSONValue]
    private var projectSettings: [String: JSONValue]
    private var modifiedGlobalKeys: Set<String> = []
    private var modifiedProjectKeys: Set<String> = []
    private var errors: [PiCodingAgentSettingsErrorRecord] = []

    public init(storage: PiCodingAgentSettingsStorage) {
        self.storage = storage
        self.globalSettings = [:]
        self.projectSettings = [:]
        self.globalSettings = Self.loadSettings(scope: .global, storage: storage, errors: &errors) ?? [:]
        self.projectSettings = Self.loadSettings(scope: .project, storage: storage, errors: &errors) ?? [:]
    }

    public func reload() {
        if let loaded = Self.loadSettings(scope: .global, storage: storage, errors: &errors) {
            globalSettings = loaded
        }
        if let loaded = Self.loadSettings(scope: .project, storage: storage, errors: &errors) {
            projectSettings = loaded
        }
    }

    public func flush() throws {
        try flush(scope: .global)
        try flush(scope: .project)
    }

    public func drainErrors() -> [PiCodingAgentSettingsErrorRecord] {
        let drained = errors
        errors.removeAll()
        return drained
    }

    public func getTheme() -> String? {
        stringValue(forKey: "theme")
    }

    public func setTheme(_ theme: String?, scope: PiCodingAgentSettingsScope = .global) {
        set(theme.map(JSONValue.string), forKey: "theme", scope: scope)
    }

    public func getDefaultModel() -> String? {
        stringValue(forKey: "defaultModel")
    }

    public func getDefaultProvider() -> String? {
        stringValue(forKey: "defaultProvider")
    }

    public func setDefaultProvider(_ value: String?, scope: PiCodingAgentSettingsScope = .global) {
        set(value.map(JSONValue.string), forKey: "defaultProvider", scope: scope)
    }

    public func setDefaultModel(_ value: String?, scope: PiCodingAgentSettingsScope = .global) {
        set(value.map(JSONValue.string), forKey: "defaultModel", scope: scope)
    }

    public func getDefaultThinkingLevel() -> String? {
        stringValue(forKey: "defaultThinkingLevel")
    }

    public func setDefaultThinkingLevel(_ value: String?, scope: PiCodingAgentSettingsScope = .global) {
        set(value.map(JSONValue.string), forKey: "defaultThinkingLevel", scope: scope)
    }

    public func getShellCommandPrefix() -> String? {
        stringValue(forKey: "shellCommandPrefix")
    }

    public func getExtensionPaths() -> [String] {
        guard case .array(let array)? = effectiveSettings()["extensions"] else { return [] }
        return array.compactMap(\.stringValue)
    }

    public func getEnabledModels() -> [String] {
        guard case .array(let array)? = effectiveSettings()["enabledModels"] else { return [] }
        return array.compactMap(\.stringValue)
    }

    func objectValue(forKey key: String) -> [String: JSONValue]? {
        guard case .object(let object)? = effectiveSettings()[key] else { return nil }
        return object
    }

    private func flush(scope: PiCodingAgentSettingsScope) throws {
        let modifiedKeys = scope == .global ? modifiedGlobalKeys : modifiedProjectKeys
        guard !modifiedKeys.isEmpty else { return }

        var current = (scope == .global ? globalSettings : projectSettings)
        if let latest = Self.loadSettings(scope: scope, storage: storage, errors: &errors) {
            current = latest
        }

        let source = scope == .global ? globalSettings : projectSettings
        for key in modifiedKeys {
            if let value = source[key] {
                current[key] = value
            } else {
                current.removeValue(forKey: key)
            }
        }

        let encoded = try Self.encode(settings: current)
        try storage.write(scope: scope, content: encoded)

        if scope == .global {
            globalSettings = current
            modifiedGlobalKeys.removeAll()
        } else {
            projectSettings = current
            modifiedProjectKeys.removeAll()
        }
    }

    private func effectiveSettings() -> [String: JSONValue] {
        Self.deepMerge(base: globalSettings, overrides: projectSettings)
    }

    private func stringValue(forKey key: String) -> String? {
        effectiveSettings()[key]?.stringValue
    }

    private func set(_ value: JSONValue?, forKey key: String, scope: PiCodingAgentSettingsScope) {
        switch scope {
        case .global:
            if let value {
                globalSettings[key] = value
            } else {
                globalSettings.removeValue(forKey: key)
            }
            modifiedGlobalKeys.insert(key)
        case .project:
            if let value {
                projectSettings[key] = value
            } else {
                projectSettings.removeValue(forKey: key)
            }
            modifiedProjectKeys.insert(key)
        }
    }

    private static func loadSettings(
        scope: PiCodingAgentSettingsScope,
        storage: PiCodingAgentSettingsStorage,
        errors: inout [PiCodingAgentSettingsErrorRecord]
    ) -> [String: JSONValue]? {
        do {
            let content = try storage.read(scope: scope)
            guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return [:]
            }
            let data = Data(content.utf8)
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            guard case .object(let object) = value else {
                errors.append(.init(scope: scope, message: "Settings file must contain a JSON object"))
                return nil
            }
            return object
        } catch {
            errors.append(.init(scope: scope, message: String(describing: error)))
            return nil
        }
    }

    private static func encode(settings: [String: JSONValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(JSONValue.object(settings))
        var text = String(decoding: data, as: UTF8.self)
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    private static func deepMerge(base: [String: JSONValue], overrides: [String: JSONValue]) -> [String: JSONValue] {
        var result = base
        for (key, value) in overrides {
            if case .object(let overrideObject) = value,
               case .object(let baseObject)? = result[key] {
                result[key] = .object(deepMerge(base: baseObject, overrides: overrideObject))
            } else {
                result[key] = value
            }
        }
        return result
    }
}

extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(exactly: value) }
        return nil
    }
}
