// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptViz",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PromptViz", targets: ["PromptViz"]),
        .executable(name: "PromptVizContractRunner", targets: ["PromptVizContractRunner"])
    ],
    targets: [
        .target(
            name: "PromptVizCore",
            path: "Sources/PromptVizCore"
        ),
        .executableTarget(
            name: "PromptViz",
            dependencies: ["PromptVizCore"],
            path: "Sources/PromptViz"
        ),
        .executableTarget(
            name: "PromptVizContractRunner",
            dependencies: ["PromptVizCore"],
            path: "Sources/PromptVizContractRunner"
        )
    ]
)
