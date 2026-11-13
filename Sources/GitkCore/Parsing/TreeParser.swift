// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One record of `git ls-tree -r -z --full-name <id>`.
struct TreeEntry: Equatable, Sendable {
    /// Octal file mode as git prints it, e.g. `100644` or `100755`.
    let mode: String
    /// `blob`, `tree` or `commit` (a submodule).
    let type: String
    let objectID: ObjectID
    let path: String
}

/// One record of `git diff-tree -r -z --name-status -C --no-commit-id <id>`.
struct ChangedFile: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case added
        case modified
        case deleted
        /// `R<score>`: similarity percentage from git's rename detection.
        case renamed(score: Int)
        /// `C<score>`: similarity percentage from git's copy detection.
        case copied(score: Int)
        case typeChanged
        case unmerged
        /// Any other letter (`X`, `B`, or one this parser does not know).
        case unknown
    }

    let status: Status
    /// The path after the change. For a rename or copy, the new path.
    let path: String
    /// The source path of a rename or copy; nil otherwise.
    let oldPath: String?
}

/// Parsers for the two git plumbing outputs that gitk's file lists are built
/// from. Both formats are NUL-separated, so paths are never C-quoted and may
/// contain tabs, spaces and newlines.
///
/// Behaviour follows gitk proc `gettreeline` (gitk/gitk 7861–7890) and
/// `gettreediffline` (gitk/gitk 8103–8169). Differences from gitk:
/// - gitk reads `ls-tree` without `-z` and undoes C-quoting with Tcl list
///   parsing; the NUL form needs no unquoting.
/// - gitk's `diff-tree` call has no `-z`, `--name-status` or `-C`. It reads
///   only the text after the first TAB of the raw format. This parser
///   implements the form requested for task 3.6 instead.
/// - gitk drops non-blob entries from the `ls-tree` file list (except in the
///   staged-changes view). This parser returns every entry, and the caller
///   filters by `type`.
/// - Merge commits: `diff-tree` without `-m` or `--cc` prints nothing for a
///   merge. gitk never asks for a merge's file list this way; it uses
///   `mergediff` (gitk/gitk 7975) instead. An empty result is therefore the
///   right answer for merges.
enum TreeParser {
    /// Parses `git ls-tree -r -z --full-name <id>` output.
    ///
    /// Each record is `<mode> SP <type> SP <object> TAB <path> NUL`. Records
    /// that do not match this shape, or whose object name is not a valid
    /// hex object ID, are skipped.
    static func parseLsTree(_ data: Data) -> [TreeEntry] {
        var entries: [TreeEntry] = []
        for record in data.split(separator: 0, omittingEmptySubsequences: true) {
            guard let tab = record.firstIndex(of: 0x09) else { continue }
            let header = String(decoding: record[record.startIndex..<tab], as: UTF8.self)
            let fields = header.split(separator: " ", omittingEmptySubsequences: false)
            guard fields.count == 3, let objectID = ObjectID(hex: String(fields[2])) else { continue }
            let path = String(decoding: record[record.index(after: tab)...], as: UTF8.self)
            entries.append(TreeEntry(mode: String(fields[0]),
                                     type: String(fields[1]),
                                     objectID: objectID,
                                     path: path))
        }
        return entries
    }

    /// Parses `git diff-tree -r -z --name-status -C --no-commit-id <id>` output.
    ///
    /// Each change is `<status> NUL <path> NUL`. For `R` and `C` the status
    /// carries a score (`R097`) and the record is
    /// `<status> NUL <old path> NUL <new path> NUL`. A trailing record cut
    /// short by a missing field is dropped.
    static func parseNameStatus(_ data: Data) -> [ChangedFile] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var files: [ChangedFile] = []
        var index = 0
        while index < fields.count {
            let token = String(decoding: fields[index], as: UTF8.self)
            index += 1
            guard let letter = token.first else { continue }

            if letter == "R" || letter == "C" {
                guard index + 1 < fields.count else { break }
                let oldPath = String(decoding: fields[index], as: UTF8.self)
                let newPath = String(decoding: fields[index + 1], as: UTF8.self)
                index += 2
                let score = Int(token.dropFirst()) ?? 0
                let status: ChangedFile.Status = letter == "R"
                    ? .renamed(score: score)
                    : .copied(score: score)
                files.append(ChangedFile(status: status, path: newPath, oldPath: oldPath))
            } else {
                guard index < fields.count else { break }
                let path = String(decoding: fields[index], as: UTF8.self)
                index += 1
                files.append(ChangedFile(status: status(for: letter), path: path, oldPath: nil))
            }
        }
        return files
    }

    private static func status(for letter: Character) -> ChangedFile.Status {
        switch letter {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "T": return .typeChanged
        case "U": return .unmerged
        default: return .unknown
        }
    }
}
