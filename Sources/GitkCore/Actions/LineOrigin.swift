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

    /// The new-file start and the old-file starts of a hunk header (the regexp at
    /// the top of `find_hunk_blamespec`).
    static func parseHunkHeader(_ header: String) -> (newLine: Int, old: [Int])? {
        guard header.hasPrefix("@@") else { return nil }
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
        return (newLine, old)
    }

    /// Port of gitk proc `find_hunk_blamespec` (gitk/gitk 3874–3940).
    /// `lines` excludes the hunk header; lineIndex is zero-based within it.
    public static func blameSpec(header: String, lines: [String], lineIndex: Int) -> BlameSpec? {
        guard lines.indices.contains(lineIndex), let parsed = parseHunkHeader(header) else { return nil }
        let bases = [parsed.newLine] + parsed.old
        let count = parsed.old.count
        var parent = 0
        var delta = 0
        if let first = lines[lineIndex].first, "-+ ".contains(first) {
            let markers = Array(lines[lineIndex].prefix(count))
            if let removed = markers.firstIndex(of: "-") { parent = removed }
            else if let unchanged = markers.firstIndex(of: " ") { parent = unchanged }
            else { parent = -1 }
            for line in lines.prefix(lineIndex) {
                let chunk = Array(line.prefix(count))
                let removed = chunk.contains("-")
                if parent >= 0 {
                    let code: Character? = parent < chunk.count ? chunk[parent] : nil
                    if code == "-" || (!removed && code != "+") { delta += 1 }
                } else if !removed { delta += 1 }
            }
            parent += 1
        }
        return BlameSpec(parentIndex: parent, line: bases[parent] + delta)
    }

    /// The `find_hunk_blamespec` lookup on a whole diff: `lines` are the diff's
    /// text lines and `index` the clicked one; the nearest `@@` line at or above
    /// it is the hunk header (`$ctext search -backwards -regexp ^@@`).
    public static func blameSpec(diffLines lines: [String], at index: Int) -> BlameSpec? {
        guard lines.indices.contains(index),
              let header = (0...index).reversed().first(where: { lines[$0].hasPrefix("@@") }) else { return nil }
        if header == index { return blameSpec(header: lines[header], lines: ["@"], lineIndex: 0) }
        return blameSpec(header: lines[header], lines: Array(lines[(header + 1)...index]), lineIndex: index - header - 1)
    }

    /// The index in `lines[range]` of the line that is line `target` of the new
    /// file (a line with no `-` marker in any parent column).
    public static func diffLineIndex(ofNewLine target: Int, in lines: [String], range: Range<Int>) -> Int? {
        var current = 0, count = 0, inHunk = false
        for i in range where lines.indices.contains(i) {
            let line = lines[i]
            if line.hasPrefix("@@") {
                guard let parsed = parseHunkHeader(line) else { inHunk = false; continue }
                current = parsed.newLine; count = parsed.old.count; inHunk = true
            } else if inHunk, let first = line.first, "-+ ".contains(first) {
                if line.prefix(count).contains("-") { continue }
                if current == target { return i }
                current += 1
            }
        }
        return nil
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
            let sha = try await indexSHA1(path, runner: runner)
            guard !sha.isEmpty else { return nil }
            stdin = try await runner.run(["cat-file", "blob", sha]).stdout
            args += ["--contents", "-"]
        case .worktree: break
        case .absent: return nil
        }
        args += ["--", path]
        return parseBlame(try await runner.run(args, stdin: stdin).stdout, hashLength: hashLength)
    }

    /// Port of gitk proc `index_sha1` (gitk/gitk 3955–3968): the blob id of
    /// `path` in the index at stage 0 or 2, or empty.
    public static func indexSHA1(_ path: String, runner: GitRunner) async throws -> String {
        let output = try await runner.run(["ls-files", "-s", path]).stdout
        for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
            let info = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)[0].split(separator: " ")
            if info.count > 2, info[2] == "0" || info[2] == "2" { return String(info[1]) }
        }
        return ""
    }

    /// gitk `parents($curview,$id)`: the parents of `id` in the session's view.
    @MainActor
    public static func parents(of id: ObjectID, in session: ViewSession) -> [ObjectID] {
        guard let index = session.store.index(of: id) else { return [] }
        return (session.ordering.parents[index] ?? []).map { session.store.id(at: $0) }
    }

    /// Port of gitk proc `external_blame` (gitk/gitk 4003–4031).
    public static func guiArguments(revision: String?, path: String, line: Int?) -> [String] {
        var args = ["gui", "blame"]
        if let line, line > 1 { args += ["--line=\(line)"] }
        if let revision { args.append(revision) }
        return args + [path]
    }
}
