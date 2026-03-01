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
        .library(name: "PiTestSupport", targets: ["PiTestSupport"]),
        .library(name: "PiAgentMLX", targets: ["PiAgentMLX"]),
        .executable(name: "pi-swift", targets: ["PiSwiftCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main")
    ],
    targets: [
        .target(name: "PiCoreTypes"),
        .target(name: "PiTestSupport"),
        .target(
            name: "PiAI",
            dependencies: ["PiCoreTypes"]
        ),
        .target(
            name: "PiAgentCore",
            dependencies: ["PiCoreTypes", "PiAI"]
        ),
        .target(
            name: "PiAgentMLX",
            dependencies: [
                "PiCoreTypes",
                "PiAI",
                "PiAgentCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
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
            dependencies: ["PiCodingAgent", "PiAgentMLX"]
        ),
        .testTarget(name: "PiCoreTypesTests", dependencies: ["PiCoreTypes", "PiTestSupport"]),
        .testTarget(name: "PiAITests", dependencies: ["PiAI", "PiTestSupport"]),
        .testTarget(name: "PiAgentCoreTests", dependencies: ["PiAgentCore", "PiTestSupport"]),
        .testTarget(name: "PiTUITests", dependencies: ["PiTUI", "PiTestSupport"]),
        .testTarget(name: "PiCodingAgentTests", dependencies: ["PiCodingAgent", "PiTestSupport"]),
        .testTarget(name: "PiMomTests", dependencies: ["PiMom", "PiTestSupport"]),
        .testTarget(name: "PiPodsTests", dependencies: ["PiPods", "PiTestSupport"]),
        .testTarget(name: "PiWebUIBridgeTests", dependencies: ["PiWebUIBridge", "PiTestSupport"]),
        .testTarget(name: "PiTestSupportTests", dependencies: ["PiTestSupport"]),
    ]
)
