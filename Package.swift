// swift-tools-version:5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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
