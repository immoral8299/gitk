// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum LineOrigin {
    public struct BlameSpec: Sendable, Equatable {
        /// 0 is the selected revision, 1 is its first parent, etc.
        public let parentIndex: Int
        public let line: Int
    }

    public struct Result: Sendable, Equatable {
        public let commitID: ObjectID
        public let line: Int
        public let path: String
    }

    /// Port of gitk proc `find_hunk_blamespec` (gitk/gitk 3874–3940).
    /// `lines` excludes the hunk header; lineIndex is zero-based within it.
    public static func blameSpec(header: String, lines: [String], lineIndex: Int) -> BlameSpec? {
        guard lines.indices.contains(lineIndex), header.hasPrefix("@@") else { return nil }
        let fields = header.split(separator: " ")
        let ranges = fields.dropFirst().prefix { $0.first != "@" }
        func start(_ range: Substring) -> Int? {
            range.dropFirst().split(separator: ",").first.flatMap { Int($0) }
        }
        let oldRanges = ranges.filter { $0.first == "-" }
        let old = oldRanges.compactMap(start)
        guard !old.isEmpty, old.count == oldRanges.count,
              let newRange = ranges.first(where: { $0.first == "+" }),
              let newLine = start(newRange) else { return nil }
        let bases = [newLine] + old
        let count = old.count
        let markers = Array(lines[lineIndex].prefix(count))
        guard markers.count == count else { return BlameSpec(parentIndex: 0, line: newLine) }
        let parent: Int
        if let removed = markers.firstIndex(of: "-") { parent = removed }
        else if let unchanged = markers.firstIndex(of: " ") { parent = unchanged }
        else { parent = -1 }
        var delta = 0
        for line in lines.prefix(lineIndex) {
            let chunk = Array(line.prefix(count))
            guard chunk.count == count else { continue }
            let removed = chunk.contains("-")
            if parent >= 0 {
                let code = chunk[parent]
                if code == "-" || (!removed && code != "+") { delta += 1 }
            } else if !removed { delta += 1 }
        }
        return BlameSpec(parentIndex: parent + 1, line: bases[parent + 1] + delta)
    }

    /// Port of gitk proc `read_line_source` (gitk/gitk 4108–4162).
    public static func parseBlame(_ data: Data, hashLength: Int = 40) -> Result? {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let fields = first.split(separator: " ")
        guard fields.count >= 3, fields[0].count == hashLength,
              let original = ObjectID(hex: String(fields[0])), let line = Int(fields[1]), line > 0,
              let filename = lines.first(where: { $0.hasPrefix("filename ") }) else { return nil }
        let raw = String(filename.dropFirst(9))
        let path = raw.hasPrefix("\"") ? (try? TclList.split(raw).first) ?? raw : raw
        let commitID = original == ObjectID.localUnstaged(hashLength: hashLength)
            ? ObjectID.localStaged(hashLength: hashLength) ?? original : original
        return Result(commitID: commitID, line: line, path: path)
    }

    /// Port of gitk proc `show_line_source` (gitk/gitk 4033–4105).
    /// For an added line (parentIndex 0), UI highlights the current line directly.
    public static func blame(revision: FileRevision, path: String, line: Int,
                             runner: GitRunner, hashLength: Int = 40) async throws -> Result? {
        guard line > 0 else { return nil }
        var args = ["blame", "-p", "-L\(line),+1"]
        var stdin: Data?
        switch revision {
        case .commit(let id): args.append(id.hex)
        case .index:
            stdin = try await runner.run(["show", ":" + path, "--"]).stdout
            args += ["--contents", "-"]
        case .worktree: break
        case .absent: return nil
        }
        args += ["--", path]
        return parseBlame(try await runner.run(args, stdin: stdin).stdout, hashLength: hashLength)
    }

    /// Port of gitk proc `external_blame` (gitk/gitk 4003–4031).
    public static func guiArguments(revision: String?, path: String, line: Int?) -> [String] {
        var args = ["gui", "blame"]
        if let line, line > 1 { args += ["--line=\(line)"] }
        if let revision { args.append(revision) }
        return args + [path]
    }
}
