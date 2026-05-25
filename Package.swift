// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
        .executable(name: "claude-usage", targets: ["claude-usage"]),
    ],
    targets: [
        // Shared logic: models, parsing, cache, keychain, OAuth client. No dependencies.
        .target(
            name: "ClaudeUsageCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // CLI: doubles as the Claude Code statusLine command and a scripting entry point.
        .executableTarget(
            name: "claude-usage",
            dependencies: ["ClaudeUsageCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu bar app.
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
