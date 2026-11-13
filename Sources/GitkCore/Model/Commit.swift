// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// Dense index of a commit inside a ``CommitStore`` (design D4). All graph
/// code works with indices rather than object ids.
public typealias CommitIndex = Int32

/// Decoded text of one commit, as cached by ``CommitStore``.
public struct CommitText: Sendable, Equatable {
    public var headline: String
    /// `Name <email>`, as gitk shows it.
    public var author: String
    public var committer: String
    public var message: String
    public var notes: String?
}
