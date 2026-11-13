// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// How a file changed, as far as the diff header tells.
public enum DiffFileStatus: Sendable, Equatable {
    case modified
    case added
    case deleted
    case renamed
    case copied
    case modeChange
    case binary
    case submodule
    case unmerged
}

/// One classified line of `git diff-tree -p --cc` output.
///
/// Content payloads are raw bytes (file encoding is applied later by the
/// renderer). For `.add`, `.remove`, `.context` and `.combined` the payload
/// excludes the marker column(s).
public enum DiffLine: Sendable, Equatable {
    /// Start of a file section. Paths are only the ones known at the
    /// `diff` line; renames and copies learn them from later lines, so the
    /// final values live in `DiffParser.sections`.
    case fileHeader(old: String?, new: String?, status: DiffFileStatus)
    /// Extended header line inside a file section (index, mode, rename, ---, +++ ...).
    case headerLine(Data)
    /// `@@ ... @@` line. `newStart` is the first line number on the new side.
    case hunkHeader(Data, newStart: Int?)
    case add(Data)
    case remove(Data)
    case context(Data)
    /// A line of a merge diff, one marker (" ", "-" or "+") per parent.
    case combined(markers: [Character], text: Data)
    case binary(Data)
    case submodule(Data)
    case other(Data)
}

/// A file section of a diff, in output order.
public struct DiffFileSection: Sendable, Equatable {
    /// Index (in the stream of lines fed to the parser) of the first line of the section.
    public var startLine: Int
    public var oldPath: String?
    public var newPath: String?
    public var status: DiffFileStatus
    public var isBinary: Bool
}

/// Streaming line classifier for `diff-tree -p --cc` output.
///
/// Port of gitk procs `makediffhdr` and `parseblobdiffline` (gitk/gitk 8272–8542).
/// Pure: feed it lines (without the trailing newline) and it returns typed values
/// and records file sections.
public struct DiffParser: Sendable {
    public private(set) var sections: [DiffFileSection] = []
    public private(set) var lineCount = 0

    private var inHeader = false
    private var nParents = 1
    private var currentSubmodule = ""

    public init() {}

    /// Splits `data` on newlines and classifies every line.
    public static func parse(output data: Data) -> (lines: [DiffLine], sections: [DiffFileSection]) {
        var parser = DiffParser()
        var lines: [DiffLine] = []
        let bytes = [UInt8](data)
        var start = 0
        for i in 0..<bytes.count where bytes[i] == 0x0A {
            lines.append(parser.parse(line: Data(bytes[start..<i])))
            start = i + 1
        }
        if start < bytes.count { lines.append(parser.parse(line: Data(bytes[start...]))) }
        return (lines, parser.sections)
    }

    public mutating func parse(lines: [Data]) -> [DiffLine] {
        lines.map { parse(line: $0) }
    }

    /// Classifies one line (no trailing newline).
    public mutating func parse(line data: Data) -> DiffLine {
        let index = lineCount
        lineCount += 1
        let line = [UInt8](data)

        if line.starts(with: Array("diff ".utf8)) {
            guard let type = diffType(line) else {
                return .other(data)
            }
            inHeader = true
            currentSubmodule = ""
            var old: String?
            var new: String?
            if type == .cc {
                let name = Self.path(Array(line.dropFirst(10)))
                old = name
                new = name
                nParents = 1
            } else {
                // The name is only reliable when unchanged: then the two halves are
                // "a/name" and "b/name" around a middle space (spaces are not escaped).
                let rest = Array(line.dropFirst(11))
                let l = rest.count
                let i = l / 2
                if (l & 1) == 1, l >= 5, rest[i] == 0x20, Array(rest[2..<i]) == Array(rest[(i + 3)...]) {
                    let name: String
                    if rest[0] == 0x22 {
                        name = String(Self.unquote(Array(rest[0..<i])).dropFirst(2))
                    } else {
                        name = String(decoding: rest[2..<i], as: UTF8.self)
                    }
                    old = name
                    new = name
                }
            }
            sections.append(DiffFileSection(startLine: index, oldPath: old, newPath: new,
                                            status: .modified, isBinary: false))
            return .fileHeader(old: old, new: new, status: .modified)
        }

        if line.starts(with: Array("* Unmerged path ".utf8)) {
            let name = String(decoding: line.dropFirst(16), as: UTF8.self)
            sections.append(DiffFileSection(startLine: index, oldPath: name, newPath: name,
                                            status: .unmerged, isBinary: false))
            inHeader = false
            return .fileHeader(old: name, new: name, status: .unmerged)
        }

        if line.starts(with: [0x40, 0x40]) { // "@@"
            var ats = 0
            while ats < line.count, line[ats] == 0x40 { ats += 1 }
            nParents = ats - 1
            inHeader = false
            return .hunkHeader(data, newStart: Self.newStart(line))
        }

        if line.starts(with: Array("Submodule ".utf8)) {
            let name = Self.submoduleName(line)
            if currentSubmodule != name {
                sections.append(DiffFileSection(startLine: index, oldPath: name, newPath: name,
                                                status: .submodule, isBinary: false))
                currentSubmodule = name
                inHeader = false
                return .fileHeader(old: name, new: name, status: .submodule)
            }
            return .submodule(data)
        }
        if !currentSubmodule.isEmpty,
           line.starts(with: Array("  >".utf8)) || line.starts(with: Array("  <".utf8)) {
            return .submodule(data)
        }

        if inHeader {
            return parseHeaderLine(line, data)
        }

        guard !sections.isEmpty else { return .other(data) }

        // Body line: one marker per parent.
        let prefix = line.prefix(nParents)
        if prefix.allSatisfy({ $0 == 0x20 || $0 == 0x2D || $0 == 0x2B }) {
            let payload = Data(line.dropFirst(prefix.count))
            if nParents > 1 {
                return .combined(markers: prefix.map { Character(UnicodeScalar($0)) }, text: payload)
            }
            switch prefix.first {
            case 0x2D: return .remove(payload)
            case 0x2B: return .add(payload)
            default: return .context(payload)
            }
        }
        return .other(data)
    }

    // MARK: - Header handling

    private enum DiffKind { case cc, git }

    private func diffType(_ line: [UInt8]) -> DiffKind? {
        if line.starts(with: Array("diff --cc ".utf8)) { return .cc }
        if line.starts(with: Array("diff --git ".utf8)) { return .git }
        return nil
    }

    private mutating func parseHeaderLine(_ line: [UInt8], _ data: Data) -> DiffLine {
        let last = sections.count - 1
        func starts(_ s: String) -> Bool { line.starts(with: Array(s.utf8)) }
        func value(after s: String) -> String {
            let rest = Array(line.dropFirst(s.utf8.count))
            return rest.first == 0x22 ? Self.unquote(rest) : String(decoding: rest, as: UTF8.self)
        }
        if starts("rename from ") {
            sections[last].oldPath = value(after: "rename from ")
            sections[last].status = .renamed
        } else if starts("rename to ") {
            sections[last].newPath = value(after: "rename to ")
            sections[last].status = .renamed
        } else if starts("copy from ") {
            sections[last].oldPath = value(after: "copy from ")
            sections[last].status = .copied
        } else if starts("copy to ") {
            sections[last].newPath = value(after: "copy to ")
            sections[last].status = .copied
        } else if starts("new file mode") {
            sections[last].status = .added
        } else if starts("deleted file mode") {
            sections[last].status = .deleted
        } else if starts("old mode") || starts("new mode") {
            if sections[last].status == .modified { sections[last].status = .modeChange }
        } else if starts("Binary files ") || starts("GIT binary patch") {
            sections[last].isBinary = true
            if sections[last].status == .modified || sections[last].status == .modeChange {
                sections[last].status = .binary
            }
            return .binary(data)
        } else if starts("+++") {
            inHeader = false
        }
        return .headerLine(data)
    }

    // MARK: - Helpers

    private static func path(_ bytes: [UInt8]) -> String {
        bytes.first == 0x22 ? unquote(bytes) : String(decoding: bytes, as: UTF8.self)
    }

    /// Decodes a git C-quoted path (`"a\303\251.txt"`) to a String.
    static func unquote(_ bytes: [UInt8]) -> String {
        var b = bytes
        if b.first == 0x22 { b.removeFirst() }
        if b.last == 0x22 { b.removeLast() }
        var out: [UInt8] = []
        var i = 0
        while i < b.count {
            let c = b[i]
            guard c == 0x5C, i + 1 < b.count else { out.append(c); i += 1; continue }
            let n = b[i + 1]
            switch n {
            case 0x30...0x37:
                var v = 0
                var j = i + 1
                while j < b.count, j < i + 4, (0x30...0x37).contains(b[j]) {
                    v = v * 8 + Int(b[j] - 0x30)
                    j += 1
                }
                out.append(UInt8(truncatingIfNeeded: v))
                i = j
                continue
            case UInt8(ascii: "a"): out.append(0x07)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "v"): out.append(0x0B)
            default: out.append(n)
            }
            i += 2
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Regex ` \+(\d+),\d+ @@` from gitk.
    private static func newStart(_ line: [UInt8]) -> Int? {
        let s = String(decoding: line, as: UTF8.self)
        guard let r = s.range(of: #" \+[0-9]+,[0-9]+ @@"#, options: .regularExpression) else { return nil }
        return Int(s[r].dropFirst(2).prefix { $0 != "," })
    }

    /// Submodule name from a `Submodule <name> <old>..<new>:` or `Submodule <name> contains ...` line.
    private static func submoduleName(_ line: [UInt8]) -> String {
        let s = String(decoding: line, as: UTF8.self)
        let body = s.dropFirst(10)
        if let r = body.range(of: #"[0-9a-f]+\.\."#, options: .regularExpression) {
            return String(body[body.startIndex..<body.index(before: r.lowerBound)])
        }
        if let r = body.range(of: "contains ") {
            return String(body[body.startIndex..<body.index(before: r.lowerBound)])
        }
        return String(body)
    }
}
