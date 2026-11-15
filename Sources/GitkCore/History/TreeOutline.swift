// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The commit's tree as an expandable outline (the sidebar's Tree mode).
///
/// Port of the data side of gitk procs `treeview`, `treeopendir`,
/// `treeclosedir` and `linetoelt` (gitk/gitk 3293–3504): `treecontents`
/// becomes `contents`, `treediropen` becomes `open`. Directories start closed
/// and keep git's `ls-tree` order; a row's `path` is the full path, with a
/// trailing `/` for a directory as in gitk.
public struct TreeOutline: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// Full path from the root; directories end in `/`.
        public var path: String
        /// The last path component (directories keep the `/`, as gitk shows them).
        public var name: String
        public var depth: Int
        public var isDirectory: Bool
        public var isOpen: Bool
        /// The blob's object name; nil for a directory.
        public var objectID: ObjectID?
    }

    /// gitk `treecontents`: the entries of each directory prefix (`""` is the root).
    private var contents: [String: [String]] = [:]
    private var blobs: [String: ObjectID] = [:]
    /// gitk `treediropen`.
    private var open: Set<String> = []

    public init() { contents[""] = [] }

    /// Builds the outline from `ls-tree -r` entries. Like gitk's `gettreeline`,
    /// only blobs are kept (it skips trees and submodule commits).
    init(entries: [TreeEntry]) {
        contents[""] = []
        for entry in entries where entry.type == "blob" {
            var prefix = ""
            var tail = Substring(entry.path)
            while let slash = tail.firstIndex(of: "/") {
                let dir = String(tail[tail.startIndex...slash])
                if contents[prefix + dir] == nil {
                    contents[prefix + dir] = []
                    contents[prefix, default: []].append(dir)
                }
                prefix += dir
                tail = tail[tail.index(after: slash)...]
            }
            if !tail.isEmpty {
                contents[prefix, default: []].append(String(tail))
                blobs[entry.path] = entry.objectID
            }
        }
    }

    /// The blob for a file path, if the outline has it.
    public func objectID(ofFile path: String) -> ObjectID? { blobs[path] }

    public func isOpen(_ directory: String) -> Bool { open.contains(directory) }

    /// Port of gitk procs `treeopendir`/`treeclosedir`: flips a directory
    /// (`dir/` form). Unknown paths and files are ignored.
    public mutating func toggle(_ directory: String) {
        guard !directory.isEmpty, contents[directory] != nil else { return }
        if open.contains(directory) { open.remove(directory) } else { open.insert(directory) }
    }

    /// The visible rows, top to bottom (gitk `linetoelt` walks the same order).
    public var rows: [Row] {
        var result: [Row] = []
        func walk(_ prefix: String, depth: Int) {
            for entry in contents[prefix] ?? [] {
                let path = prefix + entry
                if entry.hasSuffix("/") {
                    let isOpen = open.contains(path)
                    result.append(Row(path: path, name: entry, depth: depth, isDirectory: true, isOpen: isOpen, objectID: nil))
                    if isOpen { walk(path, depth: depth + 1) }
                } else {
                    result.append(Row(path: path, name: entry, depth: depth, isDirectory: false, isOpen: false,
                                      objectID: blobs[path]))
                }
            }
        }
        walk("", depth: 0)
        return result
    }

    /// Opens every directory above `path`, so its row is visible.
    public mutating func reveal(_ path: String) {
        var prefix = ""
        for part in path.split(separator: "/", omittingEmptySubsequences: true).dropLast() {
            prefix += part + "/"
            open.insert(prefix)
        }
    }

    /// Runs `git ls-tree -r -z --full-name <id>` (gitk/gitk 7840–7850).
    public static func load(id: ObjectID, runner: GitRunner) async throws -> TreeOutline {
        let output = try await runner.run(["ls-tree", "-r", "-z", "--full-name", id.description])
        return TreeOutline(entries: TreeParser.parseLsTree(output.stdout))
    }

    /// Port of gitk proc `showfile` (gitk/gitk 7900–7940): the blob's text,
    /// decoded with the path's encoding, without the final newline gitk drops.
    public static func blobText(_ blob: ObjectID, path: String, runner: GitRunner, attributes: GitAttributes,
                                guiEncoding: String, perFileAttrs: Bool) async throws -> String {
        let output = try await runner.run(["cat-file", "blob", blob.description])
        var text = await attributes.decode(output.stdout, path: path, guiEncoding: guiEncoding,
                                           perFileAttrs: perFileAttrs)
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}
