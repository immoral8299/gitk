// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A tag as the details sidebar shows it (commit-details "Click a tag"): the
/// tag name, the object it tags, and for an annotated tag its tagger and
/// message. Port of gitk proc `add_tag_ctext` (gitk/gitk 11556–11571), which
/// shows `git cat-file -p` output; the fields are parsed here instead.
public struct TagInfo: Sendable, Equatable {
    public var name: String
    /// The tagged object: the `object` header of an annotated tag, or the
    /// commit a lightweight tag names.
    public var object: ObjectID?
    /// False for a lightweight tag, which has no tag object, tagger or message.
    public var isAnnotated: Bool
    public var taggerName: String?
    public var taggerEmail: String?
    /// The tagger's date, formatted like the commit header dates.
    public var taggerDate: String?
    /// The tag message without trailing newlines.
    public var message: String

    public static let defaultDateFormat = "%Y-%m-%d %H:%M:%S"

    /// Loads `name` with `git cat-file tag` (through `refs/tags/` so a branch
    /// of the same name cannot shadow it). A lightweight tag is not a tag
    /// object, so `cat-file` fails and the commit it names is resolved instead.
    /// Throws the `GitError` from git when the tag does not exist.
    public static func load(name: String, runner: some GitRunning,
                            dateFormat: String = defaultDateFormat) async throws -> TagInfo {
        let ref = "refs/tags/" + name
        do {
            let output = try await runner.run(["cat-file", "tag", ref], stdin: nil, cwd: nil)
            return parse(name: name, raw: String(decoding: output.stdout, as: UTF8.self), dateFormat: dateFormat)
        } catch is GitError {
            let output = try await runner.run(["rev-parse", "--verify", ref + "^{commit}"], stdin: nil, cwd: nil)
            let hex = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return TagInfo(name: name, object: ObjectID(hex: hex), isAnnotated: false,
                           taggerName: nil, taggerEmail: nil, taggerDate: nil, message: "")
        }
    }

    /// Parses the raw content of a tag object: header lines (`object`, `type`,
    /// `tag`, `tagger`), a blank line, then the message.
    public static func parse(name: String, raw: String, dateFormat: String = defaultDateFormat) -> TagInfo {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var object: ObjectID?
        var tagger: Substring?
        var index = 0
        while index < lines.count, !lines[index].isEmpty {
            let line = lines[index]
            if line.hasPrefix("object ") {
                object = ObjectID(hex: String(line.dropFirst("object ".count)))
            } else if line.hasPrefix("tagger ") {
                tagger = line.dropFirst("tagger ".count)
            }
            index += 1
        }
        let message = lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
        var info = TagInfo(name: name, object: object, isAnnotated: true,
                           taggerName: nil, taggerEmail: nil, taggerDate: nil, message: message)
        if let tagger, let close = tagger.lastIndex(of: ">") {
            let person = DetailsHeaderBuilder.splitPerson(String(tagger[...close]))
            info.taggerName = person.name
            info.taggerEmail = person.email
            // The remainder is "<epoch> <tz>", as git writes every identity line.
            let fields = tagger[tagger.index(after: close)...].split(separator: " ")
            if let first = fields.first, let epoch = Int64(first) {
                let offset = fields.count > 1 ? TclDateFormat.offsetSeconds(fromGitTZ: String(fields[1])) ?? 0 : 0
                info.taggerDate = TclDateFormat.format(epoch: epoch, tzOffsetSeconds: offset, format: dateFormat)
            }
        }
        return info
    }
}
