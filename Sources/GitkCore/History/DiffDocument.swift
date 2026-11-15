// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum DiffDisplayMode: Sendable { case diff, old, new }

public struct DiffDocument: Sendable {
    public private(set) var lines: [DiffLine] = []
    public private(set) var rawLines: [Data] = []
    public private(set) var parser = DiffParser()
    public var lineLimit: Int = 200_000
    public init() {}
    public var sections: [DiffFileSection] { parser.sections }
    public var hiddenLineCount: Int { max(0, lines.count - lineLimit) }
    /// Lines added and removed in each file section, aligned with `sections`.
    /// For a combined diff a line counts as added if any parent marker is `+`,
    /// else as removed if any is `-`.
    public private(set) var addedPerFile: [Int] = []
    public private(set) var removedPerFile: [Int] = []
    public var totalAdded: Int { addedPerFile.reduce(0, +) }
    public var totalRemoved: Int { removedPerFile.reduce(0, +) }

    /// Port of gitk proc `parseblobdiffline` (gitk/gitk 8231–8542): classify one
    /// streamed line and record file sections.
    public mutating func append(_ raw: Data) {
        let line = parser.parse(line: raw)
        lines.append(line)
        rawLines.append(raw)
        while addedPerFile.count < parser.sections.count {
            addedPerFile.append(0)
            removedPerFile.append(0)
        }
        guard !addedPerFile.isEmpty else { return }
        switch line {
        case .add: addedPerFile[addedPerFile.count - 1] += 1
        case .remove: removedPerFile[removedPerFile.count - 1] += 1
        case .combined(let markers, _):
            if markers.contains("+") { addedPerFile[addedPerFile.count - 1] += 1 }
            else if markers.contains("-") { removedPerFile[removedPerFile.count - 1] += 1 }
        default: break
        }
    }

    /// Ports of gitk procs `nextfile` and `prevfile` (gitk/gitk 8574–8603): the
    /// file start to scroll to from `offset` (the top of the pane). Forward is
    /// the first start after `offset` (nil at the last file); backward is the
    /// last start before it, or the top of the text.
    public static func fileJump(from offset: Int, sectionStarts: [Int], forward: Bool) -> Int? {
        if forward { return sectionStarts.first { $0 > offset } }
        return sectionStarts.last { $0 < offset } ?? 0
    }

    /// Port of gitk proc `highlightfile_for_scrollpos` (gitk/gitk 8560–8572): the
    /// file whose section starts at or above `offset` (a character offset or a
    /// line number, matching `sectionStarts`); nil above the first file.
    public static func section(at offset: Int, sectionStarts: [Int]) -> Int? {
        var low = 0, high = sectionStarts.count
        while low < high {
            let mid = (low + high) / 2
            if sectionStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    public func visibleIndices(mode: DiffDisplayMode) -> [Int] {
        lines.prefix(lineLimit).enumerated().compactMap { index, line in
            switch (mode, line) {
            case (.old, .add), (.new, .remove): nil
            default: index
            }
        }
    }

    /// Port of gitk procs `nextfile`, `prevfile` (gitk/gitk 8574–8603).
    public func fileSection(at line: Int) -> Int? { sections.lastIndex { $0.startLine <= line } }
    public func fileJump(from line: Int, forward: Bool) -> Int? {
        forward ? sections.first(where: { $0.startLine > line })?.startLine
            : sections.last(where: { $0.startLine < line })?.startLine
    }

    /// The path whose attributes decide the encoding of line `index`: the new
    /// path of its file section, else the old one.
    public func path(ofLine index: Int) -> String? {
        guard let section = fileSection(at: index).map({ sections[$0] }) else { return nil }
        return section.newPath ?? section.oldPath
    }

    /// Text of line `index` (without its marker) decoded with the per-file
    /// encoding, as gitk does through `get_path_encoding` (gitk/gitk 12504–12514).
    public func text(ofLine index: Int, attributes: GitAttributes, guiEncoding: String,
                     perFileAttrs: Bool) async -> String {
        guard lines.indices.contains(index) else { return "" }
        let data: Data
        switch lines[index] {
        case .add(let d), .remove(let d), .context(let d), .headerLine(let d), .hunkHeader(let d, _),
             .binary(let d), .submodule(let d), .other(let d): data = d
        case .combined(_, let d): data = d
        case .fileHeader: data = rawLines[index]
        }
        return await attributes.decode(data, path: path(ofLine: index), guiEncoding: guiEncoding,
                                       perFileAttrs: perFileAttrs)
    }
}
