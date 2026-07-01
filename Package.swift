// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "llmTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "llmTools",
            targets: ["LLMToolsApp"]
        ),
        .executable(
            name: "LLMToolsChecks",
            targets: ["LLMToolsChecks"]
        ),
        .executable(
            name: "LLMToolsSmoke",
            targets: ["LLMToolsSmoke"]
        ),
        .executable(
            name: "LLMToolsNativeHost",
            targets: ["LLMToolsNativeHost"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/llama.swift", .upToNextMajor(from: "2.9804.0")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "LLMToolsCore",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .executableTarget(
            name: "LLMToolsApp",
            dependencies: [
                "LLMToolsCore"
            ]
        ),
        .executableTarget(
            name: "LLMToolsChecks",
            dependencies: [
                "LLMToolsCore"
            ]
        ),
        .executableTarget(
            name: "LLMToolsSmoke",
            dependencies: [
                "LLMToolsCore"
            ]
        ),
        .executableTarget(
            name: "LLMToolsNativeHost",
            dependencies: [
                "LLMToolsCore"
            ]
        )
    ]
)
