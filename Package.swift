// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeUsage", targets: ["ClaudeUsage"]),
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
    ],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: ["ClaudeUsageCore", .product(name: "StatusItemKit", package: "StatusItemKit")]
        ),
        .testTarget(name: "ClaudeUsageCoreTests", dependencies: ["ClaudeUsageCore"]),
    ]
)
