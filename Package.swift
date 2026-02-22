// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pi-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PiCoreTypes", targets: ["PiCoreTypes"]),
        .library(name: "PiAI", targets: ["PiAI"]),
        .library(name: "PiAgentCore", targets: ["PiAgentCore"]),
        .library(name: "PiTUI", targets: ["PiTUI"]),
        .library(name: "PiCodingAgent", targets: ["PiCodingAgent"]),
        .library(name: "PiMom", targets: ["PiMom"]),
        .library(name: "PiPods", targets: ["PiPods"]),
        .library(name: "PiWebUIBridge", targets: ["PiWebUIBridge"]),
        .executable(name: "pi-swift", targets: ["PiSwiftCLI"]),
    ],
    targets: [
        .target(name: "PiCoreTypes"),
        .target(
            name: "PiAI",
            dependencies: ["PiCoreTypes"]
        ),
        .target(
            name: "PiAgentCore",
            dependencies: ["PiCoreTypes", "PiAI"]
        ),
        .target(
            name: "PiTUI",
            dependencies: ["PiCoreTypes"]
        ),
        .target(
            name: "PiCodingAgent",
            dependencies: ["PiCoreTypes", "PiAI", "PiAgentCore", "PiTUI"]
        ),
        .target(
            name: "PiMom",
            dependencies: ["PiCoreTypes", "PiAI", "PiAgentCore", "PiCodingAgent"]
        ),
        .target(
            name: "PiPods",
            dependencies: ["PiCoreTypes", "PiAI", "PiAgentCore"]
        ),
        .target(
            name: "PiWebUIBridge",
            dependencies: ["PiCoreTypes", "PiAI", "PiAgentCore"]
        ),
        .executableTarget(
            name: "PiSwiftCLI",
            dependencies: ["PiCodingAgent"]
        ),
        .testTarget(name: "PiCoreTypesTests", dependencies: ["PiCoreTypes"]),
        .testTarget(name: "PiAITests", dependencies: ["PiAI"]),
        .testTarget(name: "PiAgentCoreTests", dependencies: ["PiAgentCore"]),
        .testTarget(name: "PiTUITests", dependencies: ["PiTUI"]),
        .testTarget(name: "PiCodingAgentTests", dependencies: ["PiCodingAgent"]),
        .testTarget(name: "PiMomTests", dependencies: ["PiMom"]),
        .testTarget(name: "PiPodsTests", dependencies: ["PiPods"]),
        .testTarget(name: "PiWebUIBridgeTests", dependencies: ["PiWebUIBridge"]),
    ]
)
