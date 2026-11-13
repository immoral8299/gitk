// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One commit as read from `git log --pretty=raw --parents --boundary -z`.
///
/// Text fields are kept as raw bytes because the commit's own `encoding`
/// header decides how they are decoded; use the `…String` accessors (backed by
/// ``TextDecoder``) when text is needed.
public struct ParsedCommit: Sendable, Equatable {
    /// Which side of a symmetric difference a commit is on (`git log --left-right`).
    public enum Side: Sendable, Equatable {
        case left   // "<"
        case right  // ">"
    }

    public var id: ObjectID
    /// Parents exactly as git printed them on the `commit` line. With path
    /// limiting these are the rewritten (simplified) parents, so they may
    /// differ from the `parent` headers. See ``listedParents`` for the rule
    /// gitk applies to unlisted commits.
    public var parents: [ObjectID]
    /// `-` prefix: a boundary commit (gitk `listed == 0`).
    public var isBoundary: Bool
    /// `^` prefix: an uninteresting commit (gitk `listed == 2`).
    public var isUninteresting: Bool
    /// `<` / `>` prefix from `--left-right`.
    public var side: Side?
    public var tree: ObjectID
    public var authorName: Data
    public var authorEmail: Data
    public var authorEpoch: Int64
    /// Raw timezone text such as `+0530`.
    public var authorTZ: String
    public var committerName: Data
    public var committerEmail: Data
    public var committerEpoch: Int64
    public var committerTZ: String
    /// The `encoding` header, if the commit has one.
    public var encoding: String?
    /// First non-blank message line, trimmed (gitk `headline`), raw bytes.
    public var headline: Data
    /// Message bytes with git log's 4-space indentation removed and trailing
    /// newlines trimmed. Does not include notes.
    public var message: Data
    /// Text of the `Notes:` / `Notes (ref):` block (indentation removed,
    /// including the `Notes…:` title lines), or nil if the commit has no notes.
    public var notes: Data?

    /// gitk keeps no parents for commits that are not listed (boundary or
    /// uninteresting): `if {$listed} {set olds [lrange $ids 1 end]} else {set olds {}}`.
    public var listedParents: [ObjectID] {
        (isBoundary || isUninteresting) ? [] : parents
    }

    /// Encoding name to use: the commit's own, else `fallback`.
    public func effectiveEncoding(fallback: String?) -> String? {
        if let encoding, !encoding.isEmpty { return encoding }
        return fallback
    }

    public func headlineString(fallbackEncoding: String? = nil) -> String {
        TextDecoder.decode(headline, encodingName: effectiveEncoding(fallback: fallbackEncoding))
    }

    public func messageString(fallbackEncoding: String? = nil) -> String {
        TextDecoder.decode(message, encodingName: effectiveEncoding(fallback: fallbackEncoding))
    }

    public func notesString(fallbackEncoding: String? = nil) -> String? {
        notes.map { TextDecoder.decode($0, encodingName: effectiveEncoding(fallback: fallbackEncoding)) }
    }

    public func authorNameString(fallbackEncoding: String? = nil) -> String {
        TextDecoder.decode(authorName, encodingName: effectiveEncoding(fallback: fallbackEncoding))
    }

    public func committerNameString(fallbackEncoding: String? = nil) -> String {
        TextDecoder.decode(committerName, encodingName: effectiveEncoding(fallback: fallbackEncoding))
    }

    /// Author timezone offset in seconds east of UTC (0 if malformed).
    public var authorTZOffset: Int { TclDateFormat.offsetSeconds(fromGitTZ: authorTZ) ?? 0 }
    public var committerTZOffset: Int { TclDateFormat.offsetSeconds(fromGitTZ: committerTZ) ?? 0 }
}

/// A record that is not valid `git log --pretty=raw` output.
public enum RawLogParseError: Error, Equatable, Sendable {
    case emptyRecord
    /// The first line is not `commit <ids>`; carries a short snippet.
    case badCommitLine(String)
    case badObjectID(String)
    case missingHeader(String)
    case badIdentity(String)
}

/// Parses one NUL-separated record of `git log --no-color -z --pretty=raw
/// --show-notes --parents --boundary [--left-right]`.
public enum RawLogParser {
    private static let nl = UInt8(ascii: "\n")
    private static let space = UInt8(ascii: " ")

    /// Port of the record framing in gitk proc `getcommitlines` (gitk/gitk
    /// 1651–1700, the `commit [-^<>]ids` line) and of gitk proc `parsecommit`
    /// (1907–1972, header, headline and notes handling).
    ///
    /// `record` is the bytes between two NULs. `hashLength` (40 or 64), when
    /// given, makes every id on the first line be checked against it, as gitk
    /// does with `$hashlength`.
    public static func parse(record: Data, hashLength: Int? = nil) throws -> ParsedCommit {
        let bytes = [UInt8](record)
        guard !bytes.isEmpty else { throw RawLogParseError.emptyRecord }

        // First line: "commit [-^<>]<id> <parent>..."
        guard let lineEnd = bytes.firstIndex(of: nl),
              bytes.starts(with: Array("commit ".utf8)) else {
            throw RawLogParseError.badCommitLine(snippet(bytes))
        }
        var idsText = String(decoding: bytes[7..<lineEnd], as: UTF8.self)
        var isBoundary = false
        var isUninteresting = false
        var side: ParsedCommit.Side?
        if let mark = idsText.first, "-^<>".contains(mark) {
            switch mark {
            case "-": isBoundary = true
            case "^": isUninteresting = true
            case "<": side = .left
            default: side = .right
            }
            idsText.removeFirst()
        }
        var ids = [ObjectID]()
        for word in idsText.split(separator: " ", omittingEmptySubsequences: true) {
            if let hashLength, word.utf8.count != hashLength {
                throw RawLogParseError.badCommitLine(snippet(bytes))
            }
            guard let id = ObjectID(hex: String(word)) else {
                throw RawLogParseError.badObjectID(String(word))
            }
            ids.append(id)
        }
        guard let id = ids.first else { throw RawLogParseError.badCommitLine(snippet(bytes)) }

        // Header ends at the first blank line.
        let body = lineEnd + 1
        var headerEnd = bytes.count
        var messageStart = bytes.count
        var pos = body
        while pos < bytes.count {
            let end = bytes[pos...].firstIndex(of: nl) ?? bytes.count
            if end == pos {  // blank line
                headerEnd = pos
                messageStart = min(pos + 1, bytes.count)
                break
            }
            pos = end + 1
        }

        var tree: ObjectID?
        var author: Identity?
        var committer: Identity?
        var encoding: String?
        pos = body
        while pos < headerEnd {
            let end = min(bytes[pos...].firstIndex(of: nl) ?? headerEnd, headerEnd)
            let line = bytes[pos..<end]
            pos = end + 1
            // mergetag / gpgsig continuation lines start with a space.
            if line.first == space || line.isEmpty { continue }
            let key: ArraySlice<UInt8>
            let value: ArraySlice<UInt8>
            if let sp = line.firstIndex(of: space) {
                key = line[line.startIndex..<sp]
                value = line[(sp + 1)...]
            } else {
                key = line
                value = []
            }
            switch String(decoding: key, as: UTF8.self) {
            case "tree":
                let text = String(decoding: value, as: UTF8.self)
                guard let t = ObjectID(hex: text) else { throw RawLogParseError.badObjectID(text) }
                tree = t
            case "author":
                author = try Identity(value)
            case "committer":
                committer = try Identity(value)
            case "encoding":
                encoding = String(decoding: value, as: UTF8.self)
            default:
                break
            }
        }
        guard let tree else { throw RawLogParseError.missingHeader("tree") }
        guard let author else { throw RawLogParseError.missingHeader("author") }
        guard let committer else { throw RawLogParseError.missingHeader("committer") }

        // Message: indented by 4 spaces; notes follow as "\nNotes:\n    ...".
        var lines = [ArraySlice<UInt8>]()
        pos = messageStart
        while pos < bytes.count {
            let end = bytes[pos...].firstIndex(of: nl) ?? bytes.count
            lines.append(bytes[pos..<end])
            pos = end + 1
        }
        var notesStart: Int?
        for (i, line) in lines.enumerated() where i > 0 && lines[i - 1].isEmpty {
            if isNotesTitle(line) { notesStart = i; break }
        }
        if notesStart == nil, let first = lines.first, isNotesTitle(first) { notesStart = 0 }
        let messageLines = (notesStart.map { Array(lines[..<$0]) } ?? lines).map(unindent)
        let message = joinTrimmed(messageLines)
        let notes = notesStart.map { joinTrimmed(lines[$0...].map(unindent)) }

        // Headline: first non-blank line, trimmed (gitk lines 1934–1944).
        var headline = [UInt8]()
        for line in messageLines {
            let trimmed = trimRight(line)
            if let first = trimmed.firstIndex(where: { !isSpaceLike($0) }) {
                headline = Array(trimmed[first...])
                break
            }
        }

        return ParsedCommit(
            id: id, parents: Array(ids.dropFirst()), isBoundary: isBoundary,
            isUninteresting: isUninteresting, side: side, tree: tree,
            authorName: author.name, authorEmail: author.email,
            authorEpoch: author.epoch, authorTZ: author.tz,
            committerName: committer.name, committerEmail: committer.email,
            committerEpoch: committer.epoch, committerTZ: committer.tz,
            encoding: encoding, headline: Data(headline), message: Data(message),
            notes: notes.map { Data($0) })
    }

    // MARK: helpers

    private struct Identity {
        var name: Data
        var email: Data
        var epoch: Int64
        var tz: String

        /// `Name <email> <epoch> <tz>`: the last two words are the date
        /// (gitk lines 1921–1927).
        init(_ value: ArraySlice<UInt8>) throws {
            let bad = RawLogParseError.badIdentity(String(decoding: value, as: UTF8.self))
            guard let tzSpace = value.lastIndex(of: UInt8(ascii: " ")), tzSpace > value.startIndex,
                  let epochSpace = value[value.startIndex..<tzSpace].lastIndex(of: UInt8(ascii: " ")),
                  let epoch = Int64(String(decoding: value[(epochSpace + 1)..<tzSpace], as: UTF8.self))
            else { throw bad }
            self.epoch = epoch
            tz = String(decoding: value[(tzSpace + 1)...], as: UTF8.self)
            let who = value[value.startIndex..<epochSpace]
            if let lt = who.lastIndex(of: UInt8(ascii: "<")), let gt = who.lastIndex(of: UInt8(ascii: ">")), lt < gt {
                var nameEnd = lt
                if nameEnd > who.startIndex, who[nameEnd - 1] == UInt8(ascii: " ") { nameEnd -= 1 }
                name = Data(who[who.startIndex..<nameEnd])
                email = Data(who[(lt + 1)..<gt])
            } else {
                name = Data(who)
                email = Data()
            }
        }
    }

    private static func isNotesTitle(_ line: ArraySlice<UInt8>) -> Bool {
        let s = String(decoding: line, as: UTF8.self)
        return s == "Notes:" || (s.hasPrefix("Notes (") && s.hasSuffix("):"))
    }

    private static func unindent(_ line: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var drop = 0
        for b in line.prefix(4) { if b == space { drop += 1 } else { break } }
        return line.dropFirst(drop)
    }

    private static func isSpaceLike(_ b: UInt8) -> Bool {
        b == space || b == 0x09 || b == 0x0D || b == 0x0A
    }

    private static func trimRight(_ s: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var end = s.endIndex
        while end > s.startIndex, isSpaceLike(s[end - 1]) { end -= 1 }
        return s[s.startIndex..<end]
    }

    /// Joins lines with "\n" and drops trailing blank lines.
    private static func joinTrimmed(_ lines: [ArraySlice<UInt8>]) -> [UInt8] {
        var end = lines.count
        while end > 0, lines[end - 1].isEmpty { end -= 1 }
        var out = [UInt8]()
        for i in 0..<end {
            if i > 0 { out.append(nl) }
            out.append(contentsOf: lines[i])
        }
        return out
    }

    private static func snippet(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.prefix(80), as: UTF8.self)
    }
}
