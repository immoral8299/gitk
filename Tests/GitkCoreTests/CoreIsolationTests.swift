// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing

/// GitkCore must stay UI-free (design D1) so it can be unit-tested headless.
/// This scans the module's sources and fails on any UI framework import.
@Suite struct CoreIsolationTests {
    static let forbiddenModules = ["AppKit", "SwiftUI", "Cocoa", "UIKit"]

    static var coreSourcesDirectory: URL {
        // <repo>/Tests/GitkCoreTests/CoreIsolationTests.swift → <repo>/Sources/GitkCore
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/GitkCore", isDirectory: true)
    }

    /// Returns "relative/path:line: text" for every forbidden import in `source`.
    static func violations(in source: String, file: String) -> [String] {
        var found: [String] = []
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let tokens = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
            // Accept attributes such as `@preconcurrency import AppKit` and
            // kinds such as `import class AppKit.NSView`.
            guard let importAt = tokens.firstIndex(of: "import"),
                  tokens[..<importAt].allSatisfy({ $0.hasPrefix("@") }) else { continue }
            var rest = tokens[(importAt + 1)...]
            if let kind = rest.first, ["class", "struct", "enum", "protocol", "func", "var", "let", "typealias"].contains(String(kind)) {
                rest = rest.dropFirst()
            }
            guard let target = rest.first else { continue }
            let module = target.split(separator: ".").first.map(String.init) ?? ""
            if forbiddenModules.contains(module) {
                found.append("\(file):\(index + 1): \(rawLine.trimmingCharacters(in: .whitespaces))")
            }
        }
        return found
    }

    @Test func detectorCatchesForbiddenImports() {
        let sample = """
        import Foundation
        import AppKit
        @preconcurrency import SwiftUI
        import class Cocoa.NSObject
        // import AppKit (comment, ignored)
        let note = "import AppKit" // string, ignored
        """
        #expect(Self.violations(in: sample, file: "x.swift").count == 3)
    }

    @Test func coreDoesNotImportUIFrameworks() throws {
        let root = Self.coreSourcesDirectory
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            checked += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            let relative = String(url.path.dropFirst(root.path.count + 1))
            violations += Self.violations(in: source, file: relative)
        }
        #expect(checked > 0, "no Swift files found under \(root.path)")
        #expect(violations.isEmpty, "GitkCore must not import UI frameworks:\n\(violations.joined(separator: "\n"))")
    }
}
