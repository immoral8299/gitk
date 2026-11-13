// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import PoConvert
import Testing

/// Every `L("…")` key in Sources/GitkUI must be a gitk msgid (so it has
/// translations) or be listed under "New strings" in docs/architecture.md.
@Suite struct L10nCoverageTests {
    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Unescapes the body of a Swift string literal (the common escapes only).
    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "0": out.append("\0")
            default: out.append(n)
            }
        }
        return out
    }

    /// Returns the literal keys of all `L("…")` calls in `source`.
    static func keys(inSource source: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])L\(\s*"((?:[^"\\\n]|\\.)*)""#) else {
            return []
        }
        let ns = source as NSString
        return re.matches(in: source, range: NSRange(location: 0, length: ns.length)).map {
            unescape(ns.substring(with: $0.range(at: 1)))
        }
    }

    static func swiftFiles(under dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return (e.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    static func gitkMsgids() throws -> Set<String> {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("po/de.po"))
        let catalog = try PoParser.parse(data: data)
        return Set(catalog.entries.filter { !$0.id.isEmpty }.map { PoConverter.stripMnemonics($0.id) })
    }

    /// Bullet items under the "## New strings" heading of docs/architecture.md.
    static func newStrings() throws -> Set<String> {
        let text = try String(contentsOf: repoRoot.appendingPathComponent("docs/architecture.md"), encoding: .utf8)
        var inSection = false
        var result = Set<String>()
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { inSection = line.hasPrefix("## New strings"); continue }
            guard inSection, line.hasPrefix("- ") else { continue }
            var item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if item == "(none yet)" { continue }
            for q in ["`", "\""] where item.count >= 2 && item.hasPrefix(q) && item.hasSuffix(q) {
                item = String(item.dropFirst().dropLast())
            }
            result.insert(item)
        }
        return result
    }

    @Test func scannerHandlesEscapesAndIgnoresOtherCalls() {
        let src = #"""
        let a = L("Say \"hi\"\n%s")
        let b = NSL("not me")
        let c = x.L("not me either")
        func L(_ key: String) {}
        let d = L( "spaced" , 1)
        """#
        #expect(Self.keys(inSource: src) == ["Say \"hi\"\n%s", "spaced"])
    }

    @Test func everyKeyIsAGitkMsgidOrANewString() throws {
        let sources = Self.repoRoot.appendingPathComponent("Sources/GitkUI")
        let known = try Self.gitkMsgids().union(Self.newStrings())
        #expect(known.contains("File"))
        var scanned = 0
        var unknown: [String] = []
        for file in Self.swiftFiles(under: sources) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for key in Self.keys(inSource: text) {
                scanned += 1
                if !known.contains(key) {
                    unknown.append("\(file.lastPathComponent): \(key)")
                }
            }
        }
        #expect(scanned > 0)
        #expect(unknown.isEmpty, "Keys that are not gitk msgids or listed under New strings: \(unknown)")
    }
}
