// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "llmTranslate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "llmTranslate",
            targets: ["LLMTranslateApp"]
        ),
        .executable(
            name: "LLMTranslateChecks",
            targets: ["LLMTranslateChecks"]
        ),
        .executable(
            name: "LLMTranslateSmoke",
            targets: ["LLMTranslateSmoke"]
        ),
        .executable(
            name: "LLMTranslateNativeHost",
            targets: ["LLMTranslateNativeHost"]
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
            name: "LLMTranslateCore",
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
            name: "LLMTranslateApp",
            dependencies: [
                "LLMTranslateCore"
            ]
        ),
        .executableTarget(
            name: "LLMTranslateChecks",
            dependencies: [
                "LLMTranslateCore"
            ]
        ),
        .executableTarget(
            name: "LLMTranslateSmoke",
            dependencies: [
                "LLMTranslateCore"
            ]
        ),
        .executableTarget(
            name: "LLMTranslateNativeHost",
            dependencies: [
                "LLMTranslateCore"
            ]
        )
    ]
)
