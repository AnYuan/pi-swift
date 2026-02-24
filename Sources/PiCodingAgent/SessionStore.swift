import Foundation
import PiAgentCore

public struct PiCodingAgentSessionRecord: Codable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var state: PiAgentState

    public init(id: String, title: String?, createdAt: Date, updatedAt: Date, state: PiAgentState) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
    }
}

public enum PiCodingAgentSessionStoreError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case io(String)

    public var description: String {
        switch self {
        case .notFound(let id):
            return "Session not found: \(id)"
        case .io(let message):
            return "Session store I/O error: \(message)"
        }
    }
}

public final class PiCodingAgentSessionStore {
    public typealias Clock = @Sendable () -> Date
    public typealias IDGenerator = @Sendable () -> String

    private let directory: String
    private let fileManager: FileManager
    private let clock: Clock
    private let idGenerator: IDGenerator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: String,
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() },
        idGenerator: @escaping IDGenerator = { UUID().uuidString.lowercased() }
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.clock = clock
        self.idGenerator = idGenerator
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func saveNew(state: PiAgentState, title: String? = nil) throws -> PiCodingAgentSessionRecord {
        let now = clock()
        let id = idGenerator()
        let record = PiCodingAgentSessionRecord(id: id, title: title, createdAt: now, updatedAt: now, state: state)
        try write(record)
        return record
    }

    public func save(id: String, state: PiAgentState, title: String? = nil) throws -> PiCodingAgentSessionRecord {
        let existing = try? load(id: id)
        let now = clock()
        let record = PiCodingAgentSessionRecord(
            id: id,
            title: title ?? existing?.title,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            state: state
        )
        try write(record)
        return record
    }

    public func load(id: String) throws -> PiCodingAgentSessionRecord {
        let path = sessionPath(for: id)
        guard fileManager.fileExists(atPath: path) else {
            throw PiCodingAgentSessionStoreError.notFound(id)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try decoder.decode(PiCodingAgentSessionRecord.self, from: data)
        } catch let error as PiCodingAgentSessionStoreError {
            throw error
        } catch {
            throw PiCodingAgentSessionStoreError.io("Failed to load session \(id)")
        }
    }

    public func listSessions() throws -> [PiCodingAgentSessionRecord] {
        try ensureDirectoryExists()
        let entries = try fileManager.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        var sessions: [PiCodingAgentSessionRecord] = []
        for entry in entries {
            let id = String(entry.dropLast(5))
            if let record = try? load(id: id) {
                sessions.append(record)
            }
        }
        return sessions.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public func latestSession() throws -> PiCodingAgentSessionRecord? {
        try listSessions().first
    }

    public func resolveContinue(sessionID: String?) throws -> PiCodingAgentSessionRecord {
        if let sessionID, !sessionID.isEmpty {
            return try load(id: sessionID)
        }
        if let latest = try latestSession() {
            return latest
        }
        throw PiCodingAgentSessionStoreError.io("No sessions available to continue")
    }

    private func write(_ record: PiCodingAgentSessionRecord) throws {
        try ensureDirectoryExists()
        do {
            let data = try encoder.encode(record)
            try data.write(to: URL(fileURLWithPath: sessionPath(for: record.id)), options: .atomic)
        } catch {
            throw PiCodingAgentSessionStoreError.io("Failed to save session \(record.id)")
        }
    }

    private func ensureDirectoryExists() throws {
        do {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw PiCodingAgentSessionStoreError.io("Failed to create session directory")
        }
    }

    private func sessionPath(for id: String) -> String {
        (directory as NSString).appendingPathComponent("\(id).json")
    }
}
