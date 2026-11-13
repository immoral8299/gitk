// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One token run of a `--word-diff=porcelain` line.
public enum WordRun: Sendable, Equatable {
    case same(Data)
    case added(Data)
    case removed(Data)
}

/// What `WordDiffParser` made of one input line.
public enum WordDiffOutput: Sendable, Equatable {
    /// A token was buffered; the display line is not complete yet.
    case pending
    /// A `~` newline completed a display line made of these runs.
    case line([WordRun])
    /// Not a word-diff body line (file or hunk header, binary, ...): pass it on unchanged.
    case passthrough(DiffLine)
}

/// Turns `git diff --word-diff=porcelain` body lines into token runs per display line.
///
/// In porcelain mode each token is on its own line prefixed by ` `, `-` or `+`, and a
/// lone `~` marks a newline in the file. Port of the `$dowords` branches of gitk proc
/// `parseblobdiffline` (gitk/gitk 8272–8542), which strip the one-column prefix of
/// single-parent diff lines, show tokens without a trailing newline, and emit the
/// newline on a `~` line. Word diff only applies to single-parent diffs.
///
/// Feed it the output of `DiffParser` (`feed(_ line: DiffLine)`) or raw lines
/// (`feed(rawLine:)`); header lines and hunk headers come back as `.passthrough`.
public struct WordDiffParser: Sendable {
    private var runs: [WordRun] = []

    public init() {}

    /// Runs buffered since the last `~` (a final line without trailing newline).
    /// Returns nil if nothing is pending.
    public mutating func finish() -> [WordRun]? {
        defer { runs = [] }
        return runs.isEmpty ? nil : runs
    }

    public mutating func feed(_ line: DiffLine) -> WordDiffOutput {
        switch line {
        case .context(let d):
            runs.append(.same(d))
            return .pending
        case .add(let d):
            runs.append(.added(d))
            return .pending
        case .remove(let d):
            runs.append(.removed(d))
            return .pending
        case .other(let d) where d == Data("~".utf8):
            let done = runs
            runs = []
            return .line(done)
        default:
            return .passthrough(line)
        }
    }

    /// Feeds one raw porcelain line (no trailing newline) including its prefix character.
    public mutating func feed(rawLine data: Data) -> WordDiffOutput {
        guard let first = data.first else { return .passthrough(.other(data)) }
        let payload = Data(data.dropFirst())
        switch first {
        case 0x20: return feed(.context(payload))
        case 0x2B: return feed(.add(payload))
        case 0x2D: return feed(.remove(payload))
        case 0x7E where data.count == 1: return feed(.other(data))
        default: return .passthrough(.other(data))
        }
    }
}
