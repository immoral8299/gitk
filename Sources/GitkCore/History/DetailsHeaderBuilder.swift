// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// What the details sidebar shows for one commit (design D16): the identity
/// header, gitk's header rows, then the message and notes.
public struct DetailsHeader: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case author, committer, tags, parent, child }
        public var kind: Kind
        /// The gitk msgid of the label ("Author", "Parent", ...).
        public var label: String
        /// The row text: a person and date, tag names, or a commit headline.
        public var value: String
        /// The linked commit (Parent and Child rows).
        public var commit: ObjectID?
        /// Index into `mergeColors` for the Parent rows of a merge.
        public var mergeColor: Int?
    }

    public var id: ObjectID
    public var authorName: String
    public var authorEmail: String
    public var authorDate: String
    /// Up to two initials from the author name, for the monogram.
    public var initials: String
    /// Branch and tag names on this commit, heads first.
    public var refs: [String]
    public var rows: [Row]
    public var message: String
    public var notes: String?
}

public enum DetailsHeaderBuilder {
    /// Splits gitk's `name <email>` into its two parts.
    public static func splitPerson(_ person: String) -> (name: String, email: String) {
        guard let open = person.lastIndex(of: "<"), let close = person.lastIndex(of: ">"), open < close else {
            return (person.trimmingCharacters(in: .whitespaces), "")
        }
        let name = person[..<open].trimmingCharacters(in: .whitespaces)
        return (name, String(person[person.index(after: open)..<close]))
    }

    /// First letters of the first and last words of `name` (or of the email).
    public static func initials(name: String, email: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" }).filter { !$0.isEmpty }
        if let first = words.first?.first {
            let last = words.count > 1 ? words.last?.first.map(String.init) ?? "" : ""
            return (String(first) + last).uppercased()
        }
        return email.first.map { String($0).uppercased() } ?? "?"
    }

    /// Port of gitk procs `selectline` (gitk/gitk 7590–7640) and
    /// `commit_descriptor` (7207–7217): the header lines without the widget work.
    /// Branch/Follows/Precedes come from `NearbyRefs` (task 12.5).
    @MainActor public static func build(commit: CommitIndex, session: ViewSession,
                                        dateFormat: String = "%Y-%m-%d %H:%M:%S") -> DetailsHeader {
        let store = session.store
        let id = store.id(at: commit)
        func date(_ epoch: Int64, _ offset: Int) -> String {
            TclDateFormat.format(epoch: epoch, tzOffsetSeconds: offset, format: dateFormat)
        }
        let author = store.author(at: commit)
        let authorDate = date(store.authorEpoch(of: commit), store.authorTZOffset(of: commit))
        let person = splitPerson(author)
        var rows: [DetailsHeader.Row] = [
            .init(kind: .author, label: "Author", value: "\(author)  \(authorDate)"),
            .init(kind: .committer, label: "Committer",
                  value: "\(store.committer(at: commit))  \(date(store.committerEpoch(of: commit), store.committerTZOffset(of: commit)))"),
        ]
        let tags = session.refs.tags(of: id)
        if !tags.isEmpty { rows.append(.init(kind: .tags, label: "Tags:", value: tags.joined(separator: " "))) }
        func descriptor(_ index: CommitIndex) -> String {
            store.isLoaded(index) ? store.headline(at: index) : "..."
        }
        let parents = session.ordering.parents[commit] ?? []
        for (n, parent) in parents.enumerated() {
            rows.append(.init(kind: .parent, label: "Parent", value: descriptor(parent), commit: store.id(at: parent),
                              mergeColor: parents.count > 1 && n < 16 ? n : nil))  // gitk mergemax
        }
        for child in session.ordering.children[commit] ?? [] {
            rows.append(.init(kind: .child, label: "Child", value: descriptor(child), commit: store.id(at: child)))
        }
        // gitk shows \r inside a comment as a line break plus indent.
        let message = store.message(at: commit).replacingOccurrences(of: "\r", with: "\n    ")
        return DetailsHeader(
            id: id, authorName: person.name, authorEmail: person.email, authorDate: authorDate,
            initials: initials(name: person.name, email: person.email),
            refs: session.refs.heads(of: id) + tags, rows: rows,
            message: message, notes: store.notes(at: commit))
    }
}
