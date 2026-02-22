import Foundation

public struct PiAIModel: Codable, Equatable, Sendable {
    public var provider: String
    public var id: String
    public var displayName: String
    public var supportsTools: Bool

    public init(provider: String, id: String, displayName: String? = nil, supportsTools: Bool = true) {
        self.provider = provider
        self.id = id
        self.displayName = displayName ?? "\(provider)/\(id)"
        self.supportsTools = supportsTools
    }

    public var qualifiedID: String {
        "\(provider)/\(id)"
    }
}

public enum PiAIModelRegistryError: Error, Equatable, Sendable, CustomStringConvertible {
    case noMatches(query: String)
    case ambiguous(query: String, matches: [String])

    public var description: String {
        switch self {
        case .noMatches(let query):
            return "No models matched query: \(query)"
        case .ambiguous(let query, let matches):
            return "Ambiguous model query '\(query)'. Matches: \(matches.joined(separator: ", "))"
        }
    }
}

public struct PiAIModelRegistry: Sendable {
    private let models: [PiAIModel]

    public init(models: [PiAIModel]) {
        self.models = models
    }

    public func allModels() -> [PiAIModel] {
        models
    }

    public func model(provider: String, id: String) -> PiAIModel? {
        let providerKey = provider.lowercased()
        let idKey = id.lowercased()
        return models.first { $0.provider.lowercased() == providerKey && $0.id.lowercased() == idKey }
    }

    public func search(_ query: String) -> [PiAIModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowered = trimmed.lowercased()

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 {
                let providerPattern = parts[0]
                let modelPattern = parts[1]

                if !providerPattern.contains("*"), !modelPattern.contains("*"),
                   let exact = model(provider: providerPattern, id: modelPattern) {
                    return [exact]
                }

                let wildcardMatches = models.filter {
                    globMatch(pattern: providerPattern.lowercased(), text: $0.provider.lowercased())
                        && globMatch(pattern: modelPattern.lowercased(), text: $0.id.lowercased())
                }
                return wildcardMatches.sorted(by: sortByQualifiedID)
            }
        }

        let exactIDMatches = models.filter { $0.id.lowercased() == lowered }
        if !exactIDMatches.isEmpty {
            return exactIDMatches.sorted(by: sortByQualifiedID)
        }

        let scored = models.compactMap { model -> (PiAIModel, Int)? in
            guard let score = matchScore(query: lowered, model: model) else { return nil }
            return (model, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return sortByQualifiedID(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    public func resolve(_ query: String) throws -> PiAIModel {
        let matches = search(query)
        guard !matches.isEmpty else {
            throw PiAIModelRegistryError.noMatches(query: query)
        }
        guard matches.count == 1 else {
            throw PiAIModelRegistryError.ambiguous(query: query, matches: matches.map(\.qualifiedID))
        }
        return matches[0]
    }

    private func matchScore(query: String, model: PiAIModel) -> Int? {
        let id = model.id.lowercased()
        let qualified = model.qualifiedID.lowercased()
        let idTokens = searchTokens(from: id)
        let qualifiedTokens = searchTokens(from: qualified)

        if qualified == query { return 100 }
        if id == query { return 95 }
        if id.hasPrefix(query) { return 80 }
        if qualified.hasPrefix(query) { return 70 }
        if idTokens.contains(query) { return 68 }
        if idTokens.contains(where: { $0.hasPrefix(query) }) { return 62 }
        if qualifiedTokens.contains(query) { return 58 }
        if qualifiedTokens.contains(where: { $0.hasPrefix(query) }) { return 54 }
        return nil
    }

    private func sortByQualifiedID(_ lhs: PiAIModel, _ rhs: PiAIModel) -> Bool {
        lhs.qualifiedID.lowercased() < rhs.qualifiedID.lowercased()
    }

    private func globMatch(pattern: String, text: String) -> Bool {
        if pattern == "*" { return true }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        let regexPattern = "^\(escaped)$"
        return text.range(of: regexPattern, options: .regularExpression) != nil
    }

    private func searchTokens(from text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
