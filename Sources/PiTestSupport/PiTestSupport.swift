import Foundation

public enum PiTestSupportModule {
    public static let moduleName = "PiTestSupport"
}

public struct RepositoryLayout: Sendable {
    public let rootURL: URL

    public init(callerFilePath: String) throws {
        let startingDirectory = URL(fileURLWithPath: callerFilePath)
            .deletingLastPathComponent()
            .standardizedFileURL

        guard let rootURL = Self.findRepositoryRoot(startingAt: startingDirectory) else {
            throw PiTestSupportError.repositoryRootNotFound(startingDirectory.path)
        }
        self.rootURL = rootURL
    }

    public var fixturesRootURL: URL {
        rootURL.appendingPathComponent("Tests/Fixtures", isDirectory: true)
    }

    private static func findRepositoryRoot(startingAt directory: URL) -> URL? {
        let fileManager = FileManager.default
        var cursor = directory

        while true {
            let packageManifest = cursor.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifest.path) {
                return cursor
            }

            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                return nil
            }
            cursor = parent
        }
    }
}

public enum PiTestSupportError: Error, Sendable, CustomStringConvertible {
    case repositoryRootNotFound(String)
    case fixtureMissing(String)
    case goldenMismatch(fixturePath: String, diff: String)

    public var description: String {
        switch self {
        case .repositoryRootNotFound(let path):
            return "Could not find repository root (Package.swift) while walking up from: \(path)"
        case .fixtureMissing(let path):
            return "Fixture file not found: \(path)"
        case .goldenMismatch(let fixturePath, let diff):
            return """
            Golden file mismatch at: \(fixturePath)
            Diff:
            \(diff)
            """
        }
    }
}

public struct FixtureLoader: Sendable {
    public let fixturesRootURL: URL

    public init(callerFilePath: String = #filePath) throws {
        let layout = try RepositoryLayout(callerFilePath: callerFilePath)
        self.fixturesRootURL = layout.fixturesRootURL
    }

    public init(fixturesRootURL: URL) {
        self.fixturesRootURL = fixturesRootURL
    }

    public func fixtureURL(_ relativePath: String) -> URL {
        fixturesRootURL.appendingPathComponent(relativePath)
    }

    public func loadText(_ relativePath: String, encoding: String.Encoding = .utf8) throws -> String {
        let url = fixtureURL(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PiTestSupportError.fixtureMissing(url.path)
        }
        return try String(contentsOf: url, encoding: encoding)
    }

    public func loadData(_ relativePath: String) throws -> Data {
        let url = fixtureURL(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PiTestSupportError.fixtureMissing(url.path)
        }
        return try Data(contentsOf: url)
    }

    @discardableResult
    public func writeText(_ text: String, to relativePath: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = fixtureURL(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: encoding)
        return url
    }
}

public enum GoldenUpdateMode: Sendable {
    case never
    case fromEnvironment
    case always

    var shouldUpdate: Bool {
        switch self {
        case .never:
            return false
        case .always:
            return true
        case .fromEnvironment:
            let raw = ProcessInfo.processInfo.environment["UPDATE_GOLDENS"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = raw?.lowercased() else { return false }
            return normalized == "1" || normalized == "true" || normalized == "yes"
        }
    }
}

public enum GoldenVerificationResult: Equatable, Sendable {
    case matched
    case created
    case updated
}

public enum GoldenFile {
    @discardableResult
    public static func verifyText(
        _ actual: String,
        fixturePath: String,
        loader: FixtureLoader,
        updateMode: GoldenUpdateMode = .fromEnvironment
    ) throws -> GoldenVerificationResult {
        let url = loader.fixtureURL(fixturePath)
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: url.path)

        if !exists {
            if updateMode.shouldUpdate {
                _ = try loader.writeText(actual, to: fixturePath)
                return .created
            }
            throw PiTestSupportError.fixtureMissing(url.path)
        }

        let expected = try loader.loadText(fixturePath)
        if expected == actual {
            return .matched
        }

        if updateMode.shouldUpdate {
            _ = try loader.writeText(actual, to: fixturePath)
            return .updated
        }

        throw PiTestSupportError.goldenMismatch(
            fixturePath: url.path,
            diff: lineDiff(expected: expected, actual: actual)
        )
    }

    public static func lineDiff(expected: String, actual: String) -> String {
        let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxCount = max(expectedLines.count, actualLines.count)
        var lines: [String] = []

        for index in 0..<maxCount {
            let expectedLine = index < expectedLines.count ? expectedLines[index] : nil
            let actualLine = index < actualLines.count ? actualLines[index] : nil

            switch (expectedLine, actualLine) {
            case let (e?, a?) where e == a:
                lines.append(" \(index + 1)| \(e)")
            case let (e?, a?):
                lines.append("-\(index + 1)| \(e)")
                lines.append("+\(index + 1)| \(a)")
            case let (e?, nil):
                lines.append("-\(index + 1)| \(e)")
            case let (nil, a?):
                lines.append("+\(index + 1)| \(a)")
            case (nil, nil):
                break
            }
        }

        return lines.joined(separator: "\n")
    }
}

