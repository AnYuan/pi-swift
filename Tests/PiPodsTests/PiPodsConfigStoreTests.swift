import XCTest
import Foundation
@testable import PiPods

final class PiPodsConfigStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-pods-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testLoadMissingConfigReturnsEmptyConfig() {
        let store = PiPodsConfigStore(configDirectory: tempDir.path)
        XCTAssertEqual(store.load(), .init())
        XCTAssertNil(store.getActivePod())
    }

    func testAddPodPersistsAndFirstPodBecomesActive() throws {
        let store = PiPodsConfigStore(configDirectory: tempDir.path)

        try store.addPod(name: "alpha", pod: .init(
            ssh: "ssh root@1.2.3.4",
            gpus: [.init(id: 0, name: "NVIDIA H100", memory: "80 GB")]
        ))

        let reloaded = PiPodsConfigStore(configDirectory: tempDir.path)
        let config = reloaded.load()
        XCTAssertEqual(config.active, "alpha")
        XCTAssertEqual(config.pods["alpha"]?.ssh, "ssh root@1.2.3.4")
        XCTAssertEqual(reloaded.getActivePod()?.name, "alpha")
    }

    func testSetActivePodValidatesExistence() throws {
        let store = PiPodsConfigStore(configDirectory: tempDir.path)
        try store.addPod(name: "alpha", pod: .init(ssh: "ssh root@1.2.3.4"))
        try store.addPod(name: "beta", pod: .init(ssh: "ssh root@5.6.7.8"))

        try store.setActivePod(name: "beta")
        XCTAssertEqual(store.load().active, "beta")

        XCTAssertThrowsError(try store.setActivePod(name: "missing")) { error in
            XCTAssertEqual(error as? PiPodsConfigStoreError, .podNotFound("missing"))
        }
    }

    func testRemoveActivePodClearsActiveSelection() throws {
        let store = PiPodsConfigStore(configDirectory: tempDir.path)
        try store.addPod(name: "alpha", pod: .init(ssh: "ssh root@1.2.3.4"))
        try store.removePod(name: "alpha")

        let config = store.load()
        XCTAssertTrue(config.pods.isEmpty)
        XCTAssertNil(config.active)
    }
}
