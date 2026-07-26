// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PromptBar",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "PromptBar",
            path: "Sources/PromptBar",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PromptBarTests",
            dependencies: ["PromptBar"],
            path: "Tests/PromptBarTests"
        ),
    ]
)
