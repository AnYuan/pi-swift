import Foundation

public struct PiCodingAgentSessionNode: Codable, Equatable, Sendable {
    public var id: String
    public var parentID: String?
    public var childIDs: [String]
    public var createdAt: Date

    public init(id: String, parentID: String?, childIDs: [String] = [], createdAt: Date) {
        self.id = id
        self.parentID = parentID
        self.childIDs = childIDs
        self.createdAt = createdAt
    }
}

public struct PiCodingAgentSessionTreeIndex: Codable, Equatable, Sendable {
    public var nodes: [String: PiCodingAgentSessionNode]

    public init(nodes: [String: PiCodingAgentSessionNode] = [:]) {
        self.nodes = nodes
    }
}

public enum PiCodingAgentSessionTreeError: Error, Equatable, CustomStringConvertible {
    case nodeExists(String)
    case parentNotFound(String)
    case nodeNotFound(String)
    case io(String)

    public var description: String {
        switch self {
        case .nodeExists(let id): return "Session tree node already exists: \(id)"
        case .parentNotFound(let id): return "Session tree parent not found: \(id)"
        case .nodeNotFound(let id): return "Session tree node not found: \(id)"
        case .io(let message): return "Session tree I/O error: \(message)"
        }
    }
}

public final class PiCodingAgentSessionTreeStore {
    public typealias Clock = @Sendable () -> Date

    private let filePath: String
    private let fileManager: FileManager
    private let clock: Clock
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(filePath: String, fileManager: FileManager = .default, clock: @escaping Clock = { Date() }) {
        self.filePath = filePath
        self.fileManager = fileManager
        self.clock = clock
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadIndex() throws -> PiCodingAgentSessionTreeIndex {
        guard fileManager.fileExists(atPath: filePath) else {
            return .init()
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            return try decoder.decode(PiCodingAgentSessionTreeIndex.self, from: data)
        } catch {
            throw PiCodingAgentSessionTreeError.io("Failed to load tree index")
        }
    }

    public func createRoot(sessionID: String) throws {
        try mutate { index in
            guard index.nodes[sessionID] == nil else { throw PiCodingAgentSessionTreeError.nodeExists(sessionID) }
            index.nodes[sessionID] = .init(id: sessionID, parentID: nil, createdAt: clock())
        }
    }

    public func branch(from parentID: String, childID: String) throws {
        try mutate { index in
            guard index.nodes[childID] == nil else { throw PiCodingAgentSessionTreeError.nodeExists(childID) }
            guard var parent = index.nodes[parentID] else { throw PiCodingAgentSessionTreeError.parentNotFound(parentID) }
            parent.childIDs.append(childID)
            index.nodes[parentID] = parent
            index.nodes[childID] = .init(id: childID, parentID: parentID, createdAt: clock())
        }
    }

    public func node(id: String) throws -> PiCodingAgentSessionNode {
        let index = try loadIndex()
        guard let node = index.nodes[id] else { throw PiCodingAgentSessionTreeError.nodeNotFound(id) }
        return node
    }

    public func children(of id: String) throws -> [PiCodingAgentSessionNode] {
        let index = try loadIndex()
        guard let node = index.nodes[id] else { throw PiCodingAgentSessionTreeError.nodeNotFound(id) }
        return node.childIDs.compactMap { index.nodes[$0] }
    }

    public func ancestors(of id: String) throws -> [PiCodingAgentSessionNode] {
        let index = try loadIndex()
        guard let start = index.nodes[id] else { throw PiCodingAgentSessionTreeError.nodeNotFound(id) }
        var result: [PiCodingAgentSessionNode] = []
        var current = start
        while let parentID = current.parentID, let parent = index.nodes[parentID] {
            result.append(parent)
            current = parent
        }
        return result
    }

    public func pathToRoot(of id: String) throws -> [PiCodingAgentSessionNode] {
        let index = try loadIndex()
        guard let start = index.nodes[id] else { throw PiCodingAgentSessionTreeError.nodeNotFound(id) }
        var path: [PiCodingAgentSessionNode] = [start]
        var current = start
        while let parentID = current.parentID, let parent = index.nodes[parentID] {
            path.append(parent)
            current = parent
        }
        return path.reversed()
    }

    private func mutate(_ body: (inout PiCodingAgentSessionTreeIndex) throws -> Void) throws {
        var index = try loadIndex()
        try body(&index)
        try saveIndex(index)
    }

    private func saveIndex(_ index: PiCodingAgentSessionTreeIndex) throws {
        do {
            let dir = (filePath as NSString).deletingLastPathComponent
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(index)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            throw PiCodingAgentSessionTreeError.io("Failed to save tree index")
        }
    }
}
