// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The changed files grouped by directory, for the Changed Files tree view.
/// Directories come before files at each level, both in path order; a chain of
/// directories with a single child directory is shown as one row (`a/b/c`).
public enum ChangedFileTree {
    public struct Row: Equatable, Sendable {
        public var depth: Int
        /// The directory chain or the file name.
        public var name: String
        /// The file's index in the diff (its section); nil for a directory.
        public var fileIndex: Int?
        public var isDirectory: Bool { fileIndex == nil }
    }

    private final class Node {
        var dirs: [String: Node] = [:]
        var files: [(name: String, index: Int)] = []
    }

    public static func rows(paths: [String]) -> [Row] {
        let root = Node()
        for (index, path) in paths.enumerated() {
            var parts = path.split(separator: "/").map(String.init)
            guard let file = parts.popLast() else { continue }
            var node = root
            for part in parts {
                if node.dirs[part] == nil { node.dirs[part] = Node() }
                node = node.dirs[part]!
            }
            node.files.append((file, index))
        }
        var result: [Row] = []
        func walk(_ node: Node, depth: Int) {
            for name in node.dirs.keys.sorted() {
                var label = name
                var child = node.dirs[name]!
                while child.files.isEmpty, child.dirs.count == 1, let (next, grandchild) = child.dirs.first {
                    label += "/" + next
                    child = grandchild
                }
                result.append(Row(depth: depth, name: label, fileIndex: nil))
                walk(child, depth: depth + 1)
            }
            for file in node.files.sorted(by: { $0.name < $1.name }) {
                result.append(Row(depth: depth, name: file.name, fileIndex: file.index))
            }
        }
        walk(root, depth: 0)
        return result
    }
}
