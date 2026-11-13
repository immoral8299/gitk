// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import PackageDescription

let package = Package(
    name: "gitk-swift",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gitk-swift", targets: ["gitk-swift"]),
        .library(name: "GitkCore", targets: ["GitkCore"]),
    ],
    targets: [
        // UI-free core. Must import Foundation only (enforced by CoreIsolationTests).
        .target(name: "GitkCore"),
        // AppKit user interface.
        .target(name: "GitkUI", dependencies: ["GitkCore"]),
        // The app executable.
        .executableTarget(name: "gitk-swift", dependencies: ["GitkCore", "GitkUI"]),
        // Dev tool: prints ordering + layout JSON for differential tests.
        .executableTarget(name: "gitk-core-dump", dependencies: ["GitkCore"]),
        // Dev tool: converts po/*.po into localized resources.
        .executableTarget(name: "po2strings"),
        .testTarget(name: "GitkCoreTests", dependencies: ["GitkCore"]),
        .testTarget(name: "GitkUITests", dependencies: ["GitkUI", "GitkCore"]),
    ],
    swiftLanguageModes: [.v6]
)
