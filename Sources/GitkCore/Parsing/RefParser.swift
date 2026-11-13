// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Reads refs and HEAD (port of gitk proc `readrefs`, gitk/gitk 2014–2092).
public enum RefParser {
    /// Parses `git show-ref -d` output. Lines that are not `<hex id> refs/...`
    /// are skipped. `refs/remotes/*/HEAD` is always skipped, and all remotes
    /// when `hideRemotes`; other refs matching `refsToHide` are skipped.
    public static func parse(
        showRef: Data, hideRemotes: Bool = false, refsToHide: String = ""
    ) -> RefSet {
        var set = RefSet()
        for lineBytes in showRef.split(separator: UInt8(ascii: "\n")) {
            let line = String(decoding: lineBytes, as: UTF8.self)
            guard let space = line.firstIndex(of: " "),
                  let id = ObjectID(hex: String(line[..<space])) else { continue }
            let ref = String(line[line.index(after: space)...])
            guard ref.hasPrefix("refs/") else { continue }
            var name = String(ref.dropFirst(5))
            if name.hasPrefix("remotes/") {
                if !name.hasSuffix("/HEAD") && !hideRemotes { set.addHead(name, id) }
            } else if name.hasPrefix("heads/") {
                set.addHead(String(name.dropFirst(6)), id)
            } else if name.hasPrefix("tags/") {
                name = String(name.dropFirst(5))
                if name.hasSuffix("^{}") {
                    set.addTag(String(name.dropLast(3)), id, peeled: true)
                } else {
                    set.addTag(name, id, peeled: false)
                }
            } else if RefSet.isOtherRefVisible(name, refsToHide: refsToHide) {
                set.addOtherRef(name, id)
            }
        }
        return set
    }

    /// Runs `show-ref -d`, `rev-parse HEAD` and `symbolic-ref -q HEAD`.
    /// Like gitk, a failing `show-ref` (no refs) gives an empty set, and when
    /// `rev-parse HEAD` fails (unborn HEAD) both main head fields stay nil.
    public static func load(
        runner: GitRunner, hideRemotes: Bool = false, refsToHide: String = ""
    ) async -> RefSet {
        var set = RefSet()
        if let out = try? await runner.run(["show-ref", "-d"]) {
            set = parse(showRef: out.stdout, hideRemotes: hideRemotes, refsToHide: refsToHide)
        }
        if let out = try? await runner.run(["rev-parse", "HEAD"]) {
            set.mainHeadID = ObjectID(hex: trimmed(out.stdout))
            if let sym = try? await runner.run(["symbolic-ref", "-q", "HEAD"]) {
                let head = trimmed(sym.stdout)
                if head.hasPrefix("refs/heads/") { set.mainHeadName = String(head.dropFirst(11)) }
            }
        }
        return set
    }

    private static func trimmed(_ d: Data) -> String {
        String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
