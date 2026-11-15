// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The text behind a clicked graph line: its parent and the parent's children
/// (gitk proc `lineclick`, gitk/gitk 9068–9120) and the hover tooltip.
public struct LineDetails: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var id: ObjectID
        public var headline: String
        public var author: String
        public var date: String
    }
    public var parent: Entry
    public var children: [Entry]

    /// Nil while the parent's commit is not loaded (gitk: `getcommit` fails).
    @MainActor public static func build(parent: CommitIndex, session: ViewSession,
                                        dateFormat: String = "%Y-%m-%d %H:%M:%S") -> LineDetails? {
        let store = session.store
        guard store.isLoaded(parent) else { return nil }
        func entry(_ index: CommitIndex) -> Entry {
            Entry(id: store.id(at: index), headline: store.headline(at: index), author: store.author(at: index),
                  date: TclDateFormat.format(epoch: store.authorEpoch(of: index), tzOffsetSeconds: store.authorTZOffset(of: index),
                                             format: dateFormat))
        }
        let children = (session.ordering.children[parent] ?? []).filter { store.isLoaded($0) }.map(entry)
        return LineDetails(parent: entry(parent), children: children)
    }

    /// Port of proc `linehover`'s text: the parent's headline.
    @MainActor public static func tooltip(parent: CommitIndex, session: ViewSession) -> String? {
        session.store.isLoaded(parent) ? session.store.headline(at: parent) : nil
    }
}
