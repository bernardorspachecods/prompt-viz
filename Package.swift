// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptWiz",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PromptWiz", targets: ["PromptWiz"]),
        .executable(name: "PromptWizContractRunner", targets: ["PromptWizContractRunner"])
    ],
    targets: [
        .target(
            name: "PromptWizCore",
            path: "Sources/PromptWizCore",
            exclude: ["CONTEXT.md"]
        ),
        .executableTarget(
            name: "PromptWiz",
            dependencies: ["PromptWizCore"],
            path: "Sources/PromptWiz",
            exclude: ["CONTEXT.md"]
        ),
        .executableTarget(
            name: "PromptWizContractRunner",
            dependencies: ["PromptWizCore"],
            path: "Sources/PromptWizContractRunner",
            exclude: ["CONTEXT.md"]
        )
    ]
)
