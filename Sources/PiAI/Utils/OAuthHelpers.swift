import Foundation
import PiCoreTypes

public struct PiAIOAuthCredentials: Codable, Equatable, Sendable {
    public var refresh: String
    public var access: String
    public var expires: Int64
    public var extra: [String: JSONValue]

    public init(
        refresh: String,
        access: String,
        expires: Int64,
        extra: [String: JSONValue] = [:]
    ) {
        self.refresh = refresh
        self.access = access
        self.expires = expires
        self.extra = extra
    }
}

public struct PiAIOAuthProvider: Sendable {
    public typealias RefreshToken = @Sendable (PiAIOAuthCredentials) async throws -> PiAIOAuthCredentials
    public typealias APIKey = @Sendable (PiAIOAuthCredentials) -> String

    public let id: String
    public let name: String
    public let refreshToken: RefreshToken
    public let apiKey: APIKey

    public init(
        id: String,
        name: String,
        refreshToken: @escaping RefreshToken,
        apiKey: @escaping APIKey
    ) {
        self.id = id
        self.name = name
        self.refreshToken = refreshToken
        self.apiKey = apiKey
    }
}

public struct PiAIOAuthProviderRegistry: Sendable {
    private var providersByID: [String: PiAIOAuthProvider]
    private var orderedIDs: [String]

    public init(_ providers: [PiAIOAuthProvider] = []) {
        self.providersByID = [:]
        self.orderedIDs = []
        for provider in providers {
            register(provider: provider)
        }
    }

    public mutating func register(provider: PiAIOAuthProvider) {
        if providersByID[provider.id] == nil {
            orderedIDs.append(provider.id)
        }
        providersByID[provider.id] = provider
    }

    public func provider(id: String) -> PiAIOAuthProvider? {
        providersByID[id]
    }

    public func providers() -> [PiAIOAuthProvider] {
        orderedIDs.compactMap { providersByID[$0] }
    }
}

public enum PiAIOAuthError: Error, Equatable, Sendable {
    case unknownProvider(String)
    case refreshFailed(providerID: String)
}

public struct PiAIOAuthAPIKeyResolution: Equatable, Sendable {
    public var newCredentials: PiAIOAuthCredentials
    public var apiKey: String

    public init(newCredentials: PiAIOAuthCredentials, apiKey: String) {
        self.newCredentials = newCredentials
        self.apiKey = apiKey
    }
}

public struct PiAIOAuthCredentialService: Sendable {
    public typealias Clock = @Sendable () async -> Int64

    public var registry: PiAIOAuthProviderRegistry
    public var now: Clock

    public init(
        registry: PiAIOAuthProviderRegistry = .init(),
        now: @escaping Clock = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.registry = registry
        self.now = now
    }

    public func getOAuthAPIKey(
        providerID: String,
        credentialsByProvider: [String: PiAIOAuthCredentials]
    ) async throws -> PiAIOAuthAPIKeyResolution? {
        guard let provider = registry.provider(id: providerID) else {
            throw PiAIOAuthError.unknownProvider(providerID)
        }

        guard var creds = credentialsByProvider[providerID] else {
            return nil
        }

        if await now() >= creds.expires {
            do {
                creds = try await provider.refreshToken(creds)
            } catch {
                throw PiAIOAuthError.refreshFailed(providerID: providerID)
            }
        }

        return .init(newCredentials: creds, apiKey: provider.apiKey(creds))
    }
}

public enum PiAIAPIKeyInjectionMode: Equatable, Sendable {
    case authorizationBearer
    case header(String)
}

public enum PiAIAPIKeyInjector {
    public static func inject(
        apiKey: String,
        intoHeaders headers: [String: String],
        using mode: PiAIAPIKeyInjectionMode
    ) -> [String: String] {
        var result = headers
        switch mode {
        case .authorizationBearer:
            result["Authorization"] = "Bearer \(apiKey)"
        case .header(let name):
            result[name] = apiKey
        }
        return result
    }
}
