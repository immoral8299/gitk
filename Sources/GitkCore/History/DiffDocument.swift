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

    /// Port of gitk proc `parseblobdiffline` (gitk/gitk 8231–8542): classify one
    /// streamed line and record file sections.
    public mutating func append(_ raw: Data) {
        lines.append(parser.parse(line: raw))
        rawLines.append(raw)
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
}
