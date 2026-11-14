// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct DetailsHeader: Sendable {
    public struct Run: Sendable {
        public var range: NSRange
        public var mergeColor: Int
    }
    public var text: String
    public var runs: [Run]
}

public enum DetailsHeaderBuilder {
    /// Port of gitk proc `selectline` (gitk/gitk 7590–7668), text only.
    @MainActor public static func build(commit: CommitIndex, session: ViewSession,
        dateFormat: String = "%Y-%m-%d %H:%M:%S", translate: (String) -> String = { $0 }) -> DetailsHeader {
        let store = session.store
        let id = store.id(at: commit)
        func date(_ epoch: Int64, _ offset: Int) -> String {
            TclDateFormat.format(epoch: epoch, tzOffsetSeconds: offset, format: dateFormat)
        }
        var text = "\(translate("Author")): \(store.author(at: commit))  \(date(store.authorEpoch(of: commit), store.authorTZOffset(of: commit)))\n"
        text += "\(translate("Committer")): \(store.committer(at: commit))  \(date(store.committerEpoch(of: commit), store.committerTZOffset(of: commit)))\n"
        let tags = session.refs.tags(of: id)
        if !tags.isEmpty { text += "\(translate("Tags:")) \(tags.joined(separator: " "))\n" }
        var runs: [DetailsHeader.Run] = []
        let parents = session.ordering.parents[commit] ?? []
        for (n, parent) in parents.enumerated() {
            let start = (text as NSString).length
            text += "\(translate("Parent")): \(store.id(at: parent).abbreviated(8)) \(store.headline(at: parent))\n"
            if parents.count > 1 { runs.append(.init(range: NSRange(location: start, length: (text as NSString).length - start), mergeColor: n)) }
        }
        for child in session.ordering.children[commit] ?? [] {
            text += "\(translate("Child")):  \(store.id(at: child).abbreviated(8)) \(store.headline(at: child))\n"
        }
        text += "\n" + store.message(at: commit) + "\n"
        if let notes = store.notes(at: commit) { text += "\n" + notes + "\n" }
        return DetailsHeader(text: text, runs: runs)
    }
}
