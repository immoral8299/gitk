// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// All refs of one repository, indexed both ways as in gitk (`headids`/`idheads`,
/// `tagids`/`idtags`, `otherrefids`/`idotherrefs`, `tagobjid`, `mainhead`,
/// `mainheadid`).
///
/// Names within one commit keep the order they were added, which is the order
/// of `git show-ref` (sorted by full ref name); gitk does not sort them again.
public struct RefSet: Sendable, Equatable {
    /// Local branches by name (`main`) and remote-tracking branches with gitk's
    /// `remotes/` prefix (`remotes/origin/main`) → commit.
    public private(set) var headIDs: [String: ObjectID] = [:]
    public private(set) var idHeads: [ObjectID: [String]] = [:]
    /// Tag name → commit (peeled for annotated tags).
    public private(set) var tagIDs: [String: ObjectID] = [:]
    public private(set) var idTags: [ObjectID: [String]] = [:]
    /// Tag name → id on the unpeeled ref line (gitk's `tagobjid`): the tag
    /// object for annotated tags, the commit for lightweight ones.
    public private(set) var tagObjectIDs: [String: ObjectID] = [:]
    /// Refs outside heads/remotes/tags, named without `refs/` (`notes/commits`).
    public private(set) var otherRefIDs: [String: ObjectID] = [:]
    public private(set) var idOtherRefs: [ObjectID: [String]] = [:]
    /// Current branch name; nil when HEAD is detached or unreadable.
    public var mainHeadName: String?
    /// The commit HEAD points at; set even when HEAD is detached.
    public var mainHeadID: ObjectID?

    public init() {}

    public func heads(of id: ObjectID) -> [String] { idHeads[id] ?? [] }
    public func tags(of id: ObjectID) -> [String] { idTags[id] ?? [] }
    public func otherRefs(of id: ObjectID) -> [String] { idOtherRefs[id] ?? [] }

    /// Head branch of gitk proc `readrefs`: `headids($name)`, `idheads($id)`.
    mutating func addHead(_ name: String, _ id: ObjectID) {
        headIDs[name] = id
        idHeads[id, default: []].append(name)
    }

    /// Tag branch of `readrefs`. A peeled line (`foo^{}`) overwrites
    /// `tagIDs[foo]`; like gitk, the name is appended to the list of every id
    /// it was seen with (tag object and commit).
    mutating func addTag(_ name: String, _ id: ObjectID, peeled: Bool) {
        if !peeled { tagObjectIDs[name] = id }
        tagIDs[name] = id
        idTags[id, default: []].append(name)
    }

    mutating func addOtherRef(_ name: String, _ id: ObjectID) {
        otherRefIDs[name] = id
        idOtherRefs[id, default: []].append(name)
    }

    /// Port of gitk proc `movehead` (gitk/gitk 2105–2112).
    mutating func moveHead(_ id: ObjectID, _ name: String) {
        if let old = headIDs[name] { removeHead(old, name) }
        headIDs[name] = id
        idHeads[id, default: []].append(name)
    }

    /// Port of gitk proc `removehead` (gitk/gitk 2114–2128).
    mutating func removeHead(_ id: ObjectID, _ name: String) {
        if var list = idHeads[id] {
            if let i = list.firstIndex(of: name) { list.remove(at: i) }
            idHeads[id] = list.isEmpty ? nil : list
        }
        headIDs[name] = nil
    }

    /// Port of gitk proc `is_other_ref_visible` (gitk/gitk 12518–12530).
    /// `refsToHide` is split on spaces; each non-empty word is a Tcl glob.
    public static func isOtherRefVisible(_ ref: String, refsToHide: String) -> Bool {
        for pat in refsToHide.split(separator: " ", omittingEmptySubsequences: true) {
            if TclGlob.matches(pattern: String(pat), ref) { return false }
        }
        return true
    }

    /// Drops remote-tracking branches (`hideremotes`) and other refs matching
    /// `refsToHide`, as `readrefs` would have when reading. Name order within
    /// a commit is kept.
    public func filtered(hideRemotes: Bool, refsToHide: String) -> RefSet {
        var out = self
        if hideRemotes {
            for (name, id) in headIDs where name.hasPrefix("remotes/") {
                out.removeHead(id, name)
            }
        }
        for (name, id) in otherRefIDs where !RefSet.isOtherRefVisible(name, refsToHide: refsToHide) {
            out.otherRefIDs[name] = nil
            out.idOtherRefs[id]?.removeAll { $0 == name }
            if out.idOtherRefs[id]?.isEmpty == true { out.idOtherRefs[id] = nil }
        }
        return out
    }
}
