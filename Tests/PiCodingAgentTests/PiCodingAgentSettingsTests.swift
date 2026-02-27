import XCTest
import Foundation
@testable import PiCodingAgent

final class PiCodingAgentSettingsTests: XCTestCase {
    private var tempDir: URL!
    private var globalPath: String!
    private var projectPath: String!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        globalPath = tempDir.appendingPathComponent("agent/settings.json").path
        projectPath = tempDir.appendingPathComponent("project/.pi/settings.json").path
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testLoadsAndDeepMergesGlobalAndProjectSettings() throws {
        try writeJSON([
            "theme": "dark",
            "shellCommandPrefix": "source ~/.zshrc",
            "compaction": [
                "enabled": true,
                "reserveTokens": 1000
            ]
        ], to: globalPath)
        try writeJSON([
            "theme": "light",
            "compaction": [
                "keepRecentTokens": 8000
            ]
        ], to: projectPath)

        let manager = PiCodingAgentSettingsManager(storage: PiCodingAgentFileSettingsStorage(
            globalPath: globalPath,
            projectPath: projectPath
        ))

        XCTAssertEqual(manager.getTheme(), "light")
        XCTAssertEqual(manager.getShellCommandPrefix(), "source ~/.zshrc")
        XCTAssertEqual(manager.objectValue(forKey: "compaction")?["enabled"]?.boolValue, true)
        XCTAssertEqual(manager.objectValue(forKey: "compaction")?["reserveTokens"]?.intValue, 1000)
        XCTAssertEqual(manager.objectValue(forKey: "compaction")?["keepRecentTokens"]?.intValue, 8000)
    }

    func testFlushPreservesExternallyAddedSettingsWhileApplyingInMemoryChanges() throws {
        try writeJSON([
            "theme": "dark",
            "defaultModel": "claude-sonnet"
        ], to: globalPath)

        let manager = PiCodingAgentSettingsManager(storage: PiCodingAgentFileSettingsStorage(
            globalPath: globalPath,
            projectPath: projectPath
        ))

        try writeJSON([
            "theme": "dark",
            "defaultModel": "claude-sonnet",
            "enabledModels": ["claude-opus", "gpt-5"]
        ], to: globalPath)

        manager.setDefaultThinkingLevel("high")
        try manager.flush()

        let saved = try loadJSON(from: globalPath)
        XCTAssertEqual(saved["enabledModels"] as? [String], ["claude-opus", "gpt-5"])
        XCTAssertEqual(saved["defaultThinkingLevel"] as? String, "high")
        XCTAssertEqual(saved["defaultModel"] as? String, "claude-sonnet")
        XCTAssertEqual(saved["theme"] as? String, "dark")
    }

    func testReloadKeepsPreviousSettingsWhenGlobalFileIsInvalidAndTracksError() throws {
        try writeJSON([
            "theme": "dark",
            "extensions": ["/before.ts"]
        ], to: globalPath)

        let manager = PiCodingAgentSettingsManager(storage: PiCodingAgentFileSettingsStorage(
            globalPath: globalPath,
            projectPath: projectPath
        ))
        XCTAssertEqual(manager.getTheme(), "dark")
        XCTAssertEqual(manager.getExtensionPaths(), ["/before.ts"])

        try writeRaw("{ invalid json", to: globalPath)
        manager.reload()

        XCTAssertEqual(manager.getTheme(), "dark")
        XCTAssertEqual(manager.getExtensionPaths(), ["/before.ts"])

        let errors = manager.drainErrors()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.scope, .global)
        XCTAssertTrue(manager.drainErrors().isEmpty)
    }

    func testShellCommandPrefixGetterAndProjectScopedThemeOverride() throws {
        try writeJSON([
            "shellCommandPrefix": "shopt -s expand_aliases",
            "theme": "dark"
        ], to: globalPath)

        let manager = PiCodingAgentSettingsManager(storage: PiCodingAgentFileSettingsStorage(
            globalPath: globalPath,
            projectPath: projectPath
        ))

        XCTAssertEqual(manager.getShellCommandPrefix(), "shopt -s expand_aliases")
        XCTAssertEqual(manager.getTheme(), "dark")

        manager.setTheme("light", scope: .project)
        try manager.flush()

        XCTAssertEqual(manager.getTheme(), "light")
        let projectSaved = try loadJSON(from: projectPath)
        XCTAssertEqual(projectSaved["theme"] as? String, "light")

        let globalSaved = try loadJSON(from: globalPath)
        XCTAssertEqual(globalSaved["theme"] as? String, "dark")
        XCTAssertEqual(globalSaved["shellCommandPrefix"] as? String, "shopt -s expand_aliases")
    }

    func testImageSettingsBlockImagesDefaultsAndPersists() throws {
        let storage = PiCodingAgentInMemorySettingsStorage()
        let manager = PiCodingAgentSettingsManager(storage: storage)

        XCTAssertEqual(manager.getImageAutoResize(), true)
        XCTAssertEqual(manager.getBlockImages(), false)

        manager.setBlockImages(true)
        manager.setImageAutoResize(false)
        try manager.flush()

        XCTAssertEqual(manager.getBlockImages(), true)
        XCTAssertEqual(manager.getImageAutoResize(), false)

        let reloaded = PiCodingAgentSettingsManager(storage: storage)
        XCTAssertEqual(reloaded.getBlockImages(), true)
        XCTAssertEqual(reloaded.getImageAutoResize(), false)
    }

    func testImageSettingsDeepMergeAcrossScopes() throws {
        try writeJSON([
            "images": [
                "autoResize": true,
                "blockImages": false
            ]
        ], to: globalPath)
        try writeJSON([
            "images": [
                "blockImages": true
            ]
        ], to: projectPath)

        let manager = PiCodingAgentSettingsManager(storage: PiCodingAgentFileSettingsStorage(
            globalPath: globalPath,
            projectPath: projectPath
        ))

        XCTAssertEqual(manager.getImageAutoResize(), true)
        XCTAssertEqual(manager.getBlockImages(), true)
    }

    func testLocalOpenAISettingsPersistAndReload() throws {
        let storage = PiCodingAgentInMemorySettingsStorage()
        let manager = PiCodingAgentSettingsManager(storage: storage)

        manager.setLocalOpenAIBaseURL("http://127.0.0.1:1234")
        manager.setLocalOpenAIModelID("mlx-community/Qwen3.5-35B-A3B-bf16")
        try manager.flush()

        XCTAssertEqual(manager.getLocalOpenAIBaseURL(), "http://127.0.0.1:1234")
        XCTAssertEqual(manager.getLocalOpenAIModelID(), "mlx-community/Qwen3.5-35B-A3B-bf16")

        let reloaded = PiCodingAgentSettingsManager(storage: storage)
        XCTAssertEqual(reloaded.getLocalOpenAIBaseURL(), "http://127.0.0.1:1234")
        XCTAssertEqual(reloaded.getLocalOpenAIModelID(), "mlx-community/Qwen3.5-35B-A3B-bf16")
    }

    private func writeJSON(_ object: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func writeRaw(_ string: String, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try string.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func loadJSON(from path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
