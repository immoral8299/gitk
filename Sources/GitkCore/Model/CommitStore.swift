// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Interns object ids to dense ``CommitIndex`` values and keeps the commit
/// fields in parallel arrays (design D4). Text is kept as raw bytes and
/// decoded on first access, then cached.
///
/// Not thread-safe and deliberately not `Sendable`: one store is owned by a
/// `@MainActor` view session (design D3). Parse off the main actor into
/// ``ParsedCommit`` values and insert them from the main actor.
public final class CommitStore {
    /// Encoding used for commits that have no `encoding` header: the caller
    /// resolves `i18n.logOutputEncoding`, then `i18n.commitEncoding`; nil
    /// means UTF-8. Changing it does not invalidate text already decoded.
    public var fallbackEncoding: String?

    private var indexByID: [ObjectID: CommitIndex] = [:]
    private var ids: [ObjectID] = []
    private var loaded: [Bool] = []
    private var parentsOf: [[CommitIndex]] = []
    private var trees: [ObjectID?] = []
    private var flags: [UInt8] = []
    private var authorNames: [Data] = []
    private var authorEmails: [Data] = []
    private var authorEpochs: [Int64] = []
    private var authorTZs: [Int32] = []
    private var committerNames: [Data] = []
    private var committerEmails: [Data] = []
    private var committerEpochs: [Int64] = []
    private var committerTZs: [Int32] = []
    private var encodings: [String?] = []
    private var headlines: [Data] = []
    private var messages: [Data] = []
    private var notes: [Data?] = []

    private struct Decoded {
        var headline: String?
        var author: String?
        var committer: String?
        var message: String?
        var notes: String??
    }
    private var decoded: [CommitIndex: Decoded] = [:]
    private var warnedEncodings: Set<String> = []
    /// Number of text decodes performed so far (for tests).
    private(set) var decodeCount = 0

    private static let boundaryFlag: UInt8 = 1
    private static let uninterestingFlag: UInt8 = 2
    private static let leftFlag: UInt8 = 4
    private static let rightFlag: UInt8 = 8

    public init(fallbackEncoding: String? = nil) {
        self.fallbackEncoding = fallbackEncoding
    }

    /// Number of interned ids (including parents not yet loaded).
    public var count: Int { ids.count }

    // MARK: interning

    /// Returns the index of `id`, adding an empty (not yet loaded) entry if it
    /// is new. Idempotent.
    @discardableResult
    public func intern(_ id: ObjectID) -> CommitIndex {
        if let existing = indexByID[id] { return existing }
        let index = CommitIndex(ids.count)
        indexByID[id] = index
        ids.append(id)
        loaded.append(false)
        parentsOf.append([])
        trees.append(nil)
        flags.append(0)
        authorNames.append(Data())
        authorEmails.append(Data())
        authorEpochs.append(0)
        authorTZs.append(0)
        committerNames.append(Data())
        committerEmails.append(Data())
        committerEpochs.append(0)
        committerTZs.append(0)
        encodings.append(nil)
        headlines.append(Data())
        messages.append(Data())
        notes.append(nil)
        return index
    }

    public func index(of id: ObjectID) -> CommitIndex? { indexByID[id] }

    public func id(at index: CommitIndex) -> ObjectID { ids[Int(index)] }

    /// True once fields were inserted for `index` (as opposed to only being
    /// interned as somebody's parent).
    public func isLoaded(_ index: CommitIndex) -> Bool { loaded[Int(index)] }

    // MARK: insertion

    /// Stores `commit` under its id, interning the id and its parents.
    /// Inserting the same id again replaces the fields and drops cached text.
    /// Parents are `commit.parents` as git printed them; apply
    /// ``ParsedCommit/listedParents`` first when gitk's rule for unlisted
    /// commits is wanted.
    @discardableResult
    public func insert(_ commit: ParsedCommit) -> CommitIndex {
        let index = intern(commit.id)
        let i = Int(index)
        parentsOf[i] = commit.parents.map { intern($0) }
        loaded[i] = true
        trees[i] = commit.tree
        var f: UInt8 = 0
        if commit.isBoundary { f |= Self.boundaryFlag }
        if commit.isUninteresting { f |= Self.uninterestingFlag }
        if commit.side == .left { f |= Self.leftFlag }
        if commit.side == .right { f |= Self.rightFlag }
        flags[i] = f
        authorNames[i] = commit.authorName
        authorEmails[i] = commit.authorEmail
        authorEpochs[i] = commit.authorEpoch
        authorTZs[i] = Int32(truncatingIfNeeded: commit.authorTZOffset)
        committerNames[i] = commit.committerName
        committerEmails[i] = commit.committerEmail
        committerEpochs[i] = commit.committerEpoch
        committerTZs[i] = Int32(truncatingIfNeeded: commit.committerTZOffset)
        encodings[i] = commit.encoding
        headlines[i] = commit.headline
        messages[i] = commit.message
        notes[i] = commit.notes
        decoded[index] = nil
        return index
    }

    // MARK: plain fields

    public func parents(of index: CommitIndex) -> [CommitIndex] { parentsOf[Int(index)] }
    public func tree(of index: CommitIndex) -> ObjectID? { trees[Int(index)] }
    public func isBoundary(_ index: CommitIndex) -> Bool { flags[Int(index)] & Self.boundaryFlag != 0 }
    public func isUninteresting(_ index: CommitIndex) -> Bool { flags[Int(index)] & Self.uninterestingFlag != 0 }
    public func side(of index: CommitIndex) -> ParsedCommit.Side? {
        let f = flags[Int(index)]
        return f & Self.leftFlag != 0 ? .left : (f & Self.rightFlag != 0 ? .right : nil)
    }
    public func authorEpoch(of index: CommitIndex) -> Int64 { authorEpochs[Int(index)] }
    /// Seconds east of UTC.
    public func authorTZOffset(of index: CommitIndex) -> Int { Int(authorTZs[Int(index)]) }
    public func committerEpoch(of index: CommitIndex) -> Int64 { committerEpochs[Int(index)] }
    public func committerTZOffset(of index: CommitIndex) -> Int { Int(committerTZs[Int(index)]) }
    public func encoding(of index: CommitIndex) -> String? { encodings[Int(index)] }
    public func hasNotes(_ index: CommitIndex) -> Bool { notes[Int(index)] != nil }

    // MARK: lazily decoded text

    public func headline(at index: CommitIndex) -> String {
        if let cached = decoded[index]?.headline { return cached }
        let text = decode(headlines[Int(index)], index)
        decoded[index, default: Decoded()].headline = text
        return text
    }

    /// `Name <email>`.
    public func author(at index: CommitIndex) -> String {
        if let cached = decoded[index]?.author { return cached }
        let i = Int(index)
        let text = decode(identityBytes(authorNames[i], authorEmails[i]), index)
        decoded[index, default: Decoded()].author = text
        return text
    }

    /// `Name <email>`.
    public func committer(at index: CommitIndex) -> String {
        if let cached = decoded[index]?.committer { return cached }
        let i = Int(index)
        let text = decode(identityBytes(committerNames[i], committerEmails[i]), index)
        decoded[index, default: Decoded()].committer = text
        return text
    }

    public func message(at index: CommitIndex) -> String {
        if let cached = decoded[index]?.message { return cached }
        let text = decode(messages[Int(index)], index)
        decoded[index, default: Decoded()].message = text
        return text
    }

    public func notes(at index: CommitIndex) -> String? {
        if let cached = decoded[index]?.notes { return cached }
        let text = notes[Int(index)].map { decode($0, index) }
        decoded[index, default: Decoded()].notes = .some(text)
        return text
    }

    /// All decoded text of one commit.
    public func text(at index: CommitIndex) -> CommitText {
        CommitText(headline: headline(at: index), author: author(at: index),
                   committer: committer(at: index), message: message(at: index),
                   notes: notes(at: index))
    }

    // MARK: helpers

    private func identityBytes(_ name: Data, _ email: Data) -> Data {
        if email.isEmpty { return name }
        var out = name
        out.append(contentsOf: [0x20, 0x3C])
        out.append(email)
        out.append(0x3E)
        return out
    }

    /// Decodes with the commit's own encoding, else ``fallbackEncoding``. An
    /// unknown encoding name gets one stderr warning, then UTF-8.
    private func decode(_ data: Data, _ index: CommitIndex) -> String {
        decodeCount += 1
        let name = encodings[Int(index)].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackEncoding
        let result = TextDecoder.decodeReporting(data, encodingName: name)
        if result.unknownEncoding, let name, warnedEncodings.insert(name).inserted {
            FileHandle.standardError.write(Data("gitk-swift: unknown encoding \"\(name)\", using utf-8\n".utf8))
        }
        return result.text
    }
}
