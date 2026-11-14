// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Tcl `string compare` for the ASCII-only tokens of the varc machinery:
/// -1, 0 or 1. Swift compares ASCII strings byte by byte, which is what Tcl
/// does for them.
@inline(__always)
func tclStringCompare(_ a: String, _ b: String) -> Int {
    a < b ? -1 : (a == b ? 0 : 1)
}

/// Port of gitk proc `strrep` (gitk/gitk 858–867): a string form of a
/// non-negative integer that sorts, as a string, in numerical order. Negative
/// values print as Tcl 9's `format` does, i.e. as the low 32 bits.
func strrep(_ n: Int64) -> String {
    func hex(_ value: Int64, minWidth: Int) -> String {
        let bits: UInt64 = value < 0 ? UInt64(UInt32(truncatingIfNeeded: value)) : UInt64(value)
        let digits = String(bits, radix: 16)
        return String(repeating: "0", count: max(0, minWidth - digits.count)) + digits
    }
    if n < 16 {
        return hex(n, minWidth: 1)
    } else if n < 256 {
        return "x" + hex(n, minWidth: 2)
    } else if n < 65536 {
        return "y" + hex(n, minWidth: 4)
    }
    return "z" + hex(n, minWidth: 8)
}

func strrep(_ n: Int) -> String { strrep(Int64(n)) }

/// gitk's display-ordering machinery for `git log` output that is not
/// `--topo-order`: commits are grouped into "virtual arcs" (chains of commits
/// with one child and one parent), the arcs form a tree ordered by string
/// tokens, and a depth-first walk of that tree gives the display order
/// (design D5, gitk/gitk 858–1616).
///
/// This holds ONE view's state, so the `$view` index of every gitk array is
/// dropped (`varcid($view,$id)` is `varcID[id]`). Arc 0 is gitk's sentinel,
/// so every array indexed by arc number has an element 0 (`varcStart` holds
/// nil and `varcCommits` an empty list there). Commit ids are
/// ``CommitIndex`` values interned in ``store``; gitk's `{}` for "no commit"
/// or "no row" is `nil`.
///
/// Not `Sendable`: owned by a `@MainActor` session (design D3).
public final class VarcOrdering {
    public let store: CommitStore

    // MARK: per-view state (gitk `varcinit`)

    /// gitk `varcstart($view)`: first commit of each arc; element 0 is nil.
    var varcStart: [CommitIndex?] = [nil]
    /// gitk `vupptr($view)`: the arc above (the one this arc hangs from).
    var vupPtr: [Int] = [0]
    /// gitk `vdownptr($view)`: first arc hanging below this one.
    var vdownPtr: [Int] = [0]
    /// gitk `vleftptr($view)`: next sibling arc.
    var vleftPtr: [Int] = [0]
    /// gitk `vbackptr($view)`: previous sibling arc, or 0 if first.
    var vbackPtr: [Int] = [0]
    /// gitk `varctok($view)`: ordering token of each arc.
    var varcTok: [String] = [""]
    /// gitk `varcrow($view)`: row of the arc's first commit, nil when unknown.
    var varcRow: [Int?] = [nil]
    /// gitk `vtokmod($view)`.
    var vtokMod: String = ""
    /// gitk `varcmod($view)`.
    var varcMod: Int = 0
    /// gitk `vrowmod($view)`.
    var vrowMod: Int = 0
    /// gitk `varcix($view)`: index of the arc in ``varcOrder``, nil when unknown.
    var varcIx: [Int?] = [nil]
    /// gitk `vlastins($view)`: last child arc inserted below this arc.
    var vlastIns: [Int] = [0]

    // MARK: arrays keyed by commit or arc (gitk `$view,$id`)

    /// gitk `varcid($view,$id)`: the arc a commit is on (absent until seen).
    var varcID: [CommitIndex: Int] = [:]
    /// gitk `varccommits($view,$a)`: commits of each arc, in order. Element 0
    /// is unused (gitk has no `varccommits($view,0)`).
    var varcCommits: [[CommitIndex]] = [[]]
    /// gitk `parents($view,$id)`.
    var parents: [CommitIndex: [CommitIndex]] = [:]
    /// gitk `children($view,$id)`. A key can exist for a commit that has not
    /// been seen yet but already has children.
    var children: [CommitIndex: [CommitIndex]] = [:]
    /// gitk `cmitlisted($view,$id)`: 1 listed, 0 not listed (boundary), or
    /// 2, 3, 4 for `^`, `<`, `>` prefixes.
    var cmitListed: [CommitIndex: Int] = [:]
    /// gitk `vshortids($view,<first 4 hex digits>)`.
    var vshortIDs: [String: [CommitIndex]] = [:]
    /// gitk `vseedcount($view,$cdate)`.
    var vseedCount: [Int64: Int] = [:]
    /// gitk `vdatemode($view)`: true for `--date-order`.
    public var vdateMode = false
    /// gitk `commitidx($view)`: number of commits known to the view.
    public internal(set) var commitIdx = 0
    /// gitk global `ordertok`, owned by the layout code (`ordertoken`); only
    /// reset here.
    var orderTok: [CommitIndex: String] = [:]

    // MARK: row mapping (gitk `update_arcrows` and friends)

    /// gitk `vrownum($view)`: first row of the n-th arc in display order.
    var vrowNum: [Int] = []
    /// gitk `varcorder($view)`: arcs in display order.
    var varcOrder: [Int] = []

    // MARK: current-view globals

    /// gitk `$v == $curview`. A session whose view is not on screen sets this
    /// to false: `modify_arc` then does not touch layout state.
    var isCurrentView = true
    /// gitk `displayorder`: commit per row; nil entries are not yet filled in
    /// (see `makeDisporder`).
    var displayOrder: [CommitIndex?] = []
    /// gitk `parentlist`, parallel to ``displayOrder``.
    var parentList: [[CommitIndex]] = []
    /// gitk `cached_commitrow`.
    var cachedCommitRow: [CommitIndex: Int] = [:]
    /// gitk `numcommits`.
    var numCommits = 0
    /// gitk `currentid`.
    var currentID: CommitIndex?
    /// gitk `selectedline`.
    var selectedLine: Int?
    /// gitk `targetid`.
    var targetID: CommitIndex?
    /// gitk `targetrow`.
    var targetRow = 0

    // MARK: pseudo commits

    /// gitk `nullid`: the "local uncommitted changes" pseudo commit.
    let nullID: ObjectID?
    /// gitk `nullid2`: the "local changes checked in to index" pseudo commit.
    let nullID2: ObjectID?

    // MARK: hooks (procs outside gitk 858–1616; the layout port wires them)

    /// gitk `undolayout $r` (layout invalidation), called by `modifyArc`
    /// for the current view. Default: no-op.
    var undoLayout: (Int) -> Void = { _ in }
    /// gitk `setcanvscroll`. Default: no-op.
    var setCanvScroll: () -> Void = {}
    /// gitk `drawvisible`. Default: no-op.
    var drawVisible: () -> Void = {}
    /// gitk `check_interest $id $scripts`: returns the scripts to run for a
    /// newly seen commit (`closeVarcs` runs them after all missing parents
    /// were added). Default: none.
    var checkInterest: (CommitIndex) -> [() -> Void] = { _ in [] }
    /// gitk `puts "oops ..."` diagnostics. Default: discarded.
    var diagnostic: (String) -> Void = { _ in }

    /// - Parameter hashLength: 40 or 64, selects the length of the pseudo
    ///   commit ids (gitk `hashlength`).
    public init(store: CommitStore, hashLength: Int = 40) {
        self.store = store
        self.nullID = ObjectID.localUnstaged(hashLength: hashLength)
        self.nullID2 = ObjectID.localStaged(hashLength: hashLength)
    }

    // MARK: - gitk 872–999

    /// Port of gitk proc `varcinit` (gitk/gitk 872–888). Also clears the row
    /// arrays that gitk leaves unset until the first `update_arcrows`.
    func varcInit() {
        varcStart = [nil]
        vupPtr = [0]
        vdownPtr = [0]
        vleftPtr = [0]
        vbackPtr = [0]
        varcTok = [""]
        varcRow = [nil]
        vtokMod = ""
        varcMod = 0
        vrowMod = 0
        varcIx = [nil]
        vlastIns = [0]
        vrowNum = []
        varcOrder = []
    }

    /// Port of gitk proc `resetvarcs` (gitk/gitk 890–913). Like gitk it leaves
    /// `cmitlisted`, `commitidx` and the arc arrays alone; call `varcInit()`
    /// for those. `varcCommits` keeps its sentinel element 0.
    func resetVarcs() {
        varcID.removeAll()
        children.removeAll()
        parents.removeAll()
        vshortIDs.removeAll()
        varcCommits = [[]]
        vseedCount.removeAll()
        orderTok.removeAll()
    }

    /// Port of gitk proc `seeds` (gitk/gitk 916–926): the commits with no
    /// children.
    func seeds() -> [CommitIndex] {
        var ret: [CommitIndex] = []
        var a = vdownPtr[0]
        while a != 0 {
            if let id = varcStart[a] { ret.append(id) }
            a = vleftPtr[a]
        }
        return ret
    }

    /// Port of gitk proc `newvarc` (gitk/gitk 928–999). Creates a new arc
    /// starting at `id` and returns its number.
    ///
    /// Deviation: gitk reads the committer date from `commitinfo($id)`, which
    /// it parses from `commitdata($id)` (an error if the commit was never
    /// read). Here the date comes from ``store`` and is 0 when the commit is
    /// not loaded there, which is also what gitk uses for a non-integer date.
    /// Callers must insert the commit into ``store`` before calling, as
    /// getcommitlines sets `commitdata` first.
    @discardableResult
    func newVarc(_ id: CommitIndex) -> Int {
        let a = varcTok.count
        var tok: String
        let kids = children[id] ?? []
        if kids.isEmpty || vdateMode {
            var cdate: Int64 = store.isLoaded(id) ? store.committerEpoch(of: id) : 0
            let c = (vseedCount[cdate] ?? -1) + 1
            vseedCount[cdate] = c
            cdate = cdate ^ 0xffffffff
            tok = "s" + strrep(cdate) + strrep(c)
        } else {
            tok = ""
        }
        var ka = 0
        var ki: CommitIndex?
        if let kid = kids.last {
            let k = varcID[kid] ?? 0
            if tclStringCompare(varcTok[k], tok) > 0 {
                ki = kid
                ka = k
                tok = varcTok[k]
            }
        }
        if ka != 0, let ki {
            let kiParents = parents[ki] ?? []
            let i = kiParents.firstIndex(of: id) ?? -1
            let j = kiParents.count - 1 - i
            tok += strrep(j)
        }
        var c = vlastIns[ka]
        var b: Int
        if c == 0 || tclStringCompare(tok, varcTok[c]) < 0 {
            c = ka
            b = vdownPtr[ka]
        } else {
            b = vleftPtr[c]
        }
        while b != 0 && tclStringCompare(tok, varcTok[b]) >= 0 {
            c = b
            b = vleftPtr[c]
        }
        if c == ka {
            vdownPtr[ka] = a
            vbackPtr.append(0)
        } else {
            vleftPtr[c] = a
            vbackPtr.append(c)
        }
        vlastIns[ka] = a
        vupPtr.append(ka)
        vleftPtr.append(b)
        if b != 0 {
            vbackPtr[b] = a
        }
        varcTok.append(tok)
        varcStart.append(id)
        vdownPtr.append(0)
        varcRow.append(nil)
        varcIx.append(nil)
        setVarcCommits(a, [])
        vlastIns.append(0)
        return a
    }

    /// gitk `set varccommits($view,$a) ...`: gitk's array is sparse, ours is
    /// dense, so a new arc extends ``varcCommits`` (element 0 stays the
    /// unused sentinel).
    func setVarcCommits(_ a: Int, _ commits: [CommitIndex]) {
        while varcCommits.count <= a { varcCommits.append([]) }
        varcCommits[a] = commits
    }

    // MARK: - gitk 1001–1183

    /// Port of gitk proc `splitvarc` (gitk/gitk 1001–1035): splits the arc
    /// containing `p` so that `p` starts a new arc. Does nothing if `p` is
    /// already the first commit of its arc.
    func splitVarc(_ p: CommitIndex) {
        let oa = varcID[p] ?? 0
        let otok = varcTok[oa]
        let ac = varcCommits[oa]
        let i = ac.firstIndex(of: p) ?? -1
        if i <= 0 { return }
        let na = varcTok.count
        // "%" sorts before "0"...
        let tok = otok + "%" + strrep(i)
        varcTok.append(tok)
        varcRow.append(nil)
        varcIx.append(nil)
        varcCommits[oa] = Array(ac[0..<i])
        setVarcCommits(na, Array(ac[i...]))
        varcStart.append(p)
        for id in varcCommits[na] {
            varcID[id] = na
        }
        vdownPtr.append(vdownPtr[oa])
        vlastIns.append(vlastIns[oa])
        vdownPtr[oa] = na
        vlastIns[oa] = 0
        vupPtr.append(oa)
        vleftPtr.append(0)
        vbackPtr.append(0)
        var b = vdownPtr[na]
        while b != 0 {
            vupPtr[b] = na
            b = vleftPtr[b]
        }
        if tclStringCompare(otok, vtokMod) <= 0 {
            modifyArc(oa)
        }
    }

    /// Port of gitk proc `renumbervarc` (gitk/gitk 1037–1164). Recomputes the
    /// tokens of arc `a` and of the arcs related to it and moves them in the
    /// arc tree as needed. (gitk's `clock clicks` timing is dropped.)
    func renumberVarc(_ a0: Int) {
        var a = a0
        var todo: [Int] = []
        var isRelated: Set<Int> = [a]
        var kidChanged: Set<Int> = [a]
        while a != 0 {
            if isRelated.contains(a) {
                todo.append(a)
                if let id = varcCommits[a].last {
                    for p in parents[id] ?? [] {
                        if let pa = varcID[p] {
                            isRelated.insert(pa)
                        }
                    }
                }
            }
            var b = vdownPtr[a]
            if b == 0 {
                while a != 0 {
                    b = vleftPtr[a]
                    if b != 0 { break }
                    a = vupPtr[a]
                }
            }
            a = b
        }
        var sortKids: Set<CommitIndex> = []
        for a in todo {
            if !kidChanged.contains(a) { continue }
            guard let startID = varcStart[a] else { continue }
            if (children[startID]?.count ?? 0) > 1 {
                children[startID] = sortedByToken(children[startID] ?? [])
            }
            let oldtok = varcTok[a]
            var tok = vdateMode ? oldtok : ""
            var ka = 0
            var ki: CommitIndex?
            if let kid = lastRealChild(startID) {
                let k = varcID[kid] ?? 0
                if tclStringCompare(varcTok[k], tok) > 0 {
                    ki = kid
                    ka = k
                    tok = varcTok[k]
                }
            }
            if ka != 0, let ki {
                let kiParents = parents[ki] ?? []
                let i = kiParents.firstIndex(of: startID) ?? -1
                let j = kiParents.count - 1 - i
                tok += strrep(j)
            }
            if tok == oldtok {
                continue
            }
            if let lastID = varcCommits[a].last {
                for p in parents[lastID] ?? [] {
                    if let pa = varcID[p] {
                        kidChanged.insert(pa)
                    } else {
                        sortKids.insert(p)
                    }
                }
            }
            varcTok[a] = tok
            var b = vupPtr[a]
            if b != ka {
                if tclStringCompare(varcTok[ka], vtokMod) < 0 {
                    modifyArc(ka)
                }
                if tclStringCompare(varcTok[b], vtokMod) < 0 {
                    modifyArc(b)
                }
                var c = vbackPtr[a]
                let d = vleftPtr[a]
                if c == 0 {
                    vdownPtr[b] = d
                } else {
                    vleftPtr[c] = d
                }
                if d != 0 {
                    vbackPtr[d] = c
                }
                if vlastIns[b] == a {
                    vlastIns[b] = c
                }
                vupPtr[a] = ka
                c = vlastIns[ka]
                if c == 0 || tclStringCompare(tok, varcTok[c]) < 0 {
                    c = ka
                    b = vdownPtr[ka]
                } else {
                    b = vleftPtr[c]
                }
                while b != 0 && tclStringCompare(tok, varcTok[b]) >= 0 {
                    c = b
                    b = vleftPtr[c]
                }
                if c == ka {
                    vdownPtr[ka] = a
                    vbackPtr[a] = 0
                } else {
                    vleftPtr[c] = a
                    vbackPtr[a] = c
                }
                vleftPtr[a] = b
                if b != 0 {
                    vbackPtr[b] = a
                }
                vlastIns[ka] = a
            }
        }
        for id in sortKids {
            if (children[id]?.count ?? 0) > 1 {
                children[id] = sortedByToken(children[id] ?? [])
            }
        }
    }

    /// Port of gitk proc `fix_reversal` (gitk/gitk 1169–1183): fixes up the
    /// graph after finding out that `p` (a commit already seen) is actually
    /// the parent of the last commit in arc `a`.
    func fixReversal(_ p: CommitIndex, _ a: Int) {
        var pa = varcID[p] ?? 0
        if p != varcStart[pa] {
            splitVarc(p)
            pa = varcID[p] ?? 0
        }
        // seeds always need to be renumbered
        if vupPtr[pa] == 0 || tclStringCompare(varcTok[a], varcTok[pa]) > 0 {
            renumberVarc(pa)
        }
    }

    // MARK: - procs from later tasks that 6.2 needs (ported with them)

    /// Port of gitk proc `vtokcmp` (gitk/gitk 1324–1329), with the view
    /// argument dropped. Task 6.4 lists it; it is needed by `renumberVarc`.
    func vtokcmp(_ a: CommitIndex, _ b: CommitIndex) -> Int {
        tclStringCompare(varcTok[varcID[a] ?? 0], varcTok[varcID[b] ?? 0])
    }

    /// `lsort -command [list vtokcmp $v] $ids`: a stable merge sort in Tcl,
    /// so ties keep their order.
    func sortedByToken(_ ids: [CommitIndex]) -> [CommitIndex] {
        ids.enumerated().sorted { x, y in
            let c = vtokcmp(x.element, y.element)
            return c < 0 || (c == 0 && x.offset < y.offset)
        }.map(\.element)
    }

    /// Port of gitk proc `modify_arc` (gitk/gitk 1333–1361), with the view
    /// argument dropped. Task 6.4 lists it; it is needed by `splitVarc` and
    /// `renumberVarc`.
    ///
    /// This assumes that if `lim` is not given, the caller has checked that
    /// arc `a`'s token is less than ``vtokMod``.
    func modifyArc(_ a0: Int, lim lim0: Int? = nil) {
        var a = a0
        var lim = lim0
        if let l = lim {
            let c = tclStringCompare(varcTok[a], vtokMod)
            if c > 0 { return }
            if c == 0 {
                if let r = varcRow[a], vrowMod <= r + l { return }
            }
        }
        vtokMod = varcTok[a]
        varcMod = a
        if isCurrentView {
            while a != 0 && varcRow[a] == nil {
                a = vupPtr[a]
                lim = nil
            }
            var r = 0
            if a != 0 {
                let l = lim ?? varcCommits[a].count
                r = (varcRow[a] ?? 0) + l
            }
            vrowMod = r
            undoLayout(r)
        }
    }

    /// Port of gitk proc `last_real_child` (gitk/gitk 1311–1322): the last
    /// child that is not one of the local-changes pseudo commits. Task 6.3
    /// lists it; it is needed by `renumberVarc`.
    func lastRealChild(_ id: CommitIndex) -> CommitIndex? {
        let kids = children[id] ?? []
        for kid in kids.reversed() where isRealCommit(kid) {
            return kid
        }
        return nil
    }

    /// True unless `id` is gitk's `nullid` or `nullid2`.
    func isRealCommit(_ id: CommitIndex) -> Bool {
        let oid = store.id(at: id)
        return oid != nullID && oid != nullID2
    }

    // MARK: - gitk 1185–1322

    /// Port of gitk proc `insertrow` (gitk/gitk 1185–1218): adds the new
    /// commit `id` as a child of `p` (used after cherry-pick and revert), with
    /// the view argument dropped.
    ///
    /// Deviation: gitk calls `readcommit $id` first, which loads the commit
    /// with `git log -1`. Here the caller must have inserted `id` into
    /// ``store`` already (`newVarc` reads its committer date there).
    public func insertRow(_ id: CommitIndex, _ p: CommitIndex) {
        cmitListed[id] = 1
        children[id] = []
        parents[id] = [p]
        let a = newVarc(id)
        varcID[id] = a
        vshortIDs[store.id(at: id).abbreviated(4), default: []].append(id)
        if tclStringCompare(varcTok[a], vtokMod) < 0 {
            modifyArc(a)
        }
        varcCommits[a].append(id)
        children[p, default: []].append(id)
        if (children[p]?.count ?? 0) > 1 {
            children[p] = sortedByToken(children[p] ?? [])
            orderTok.removeAll()
        }
        fixReversal(p, a)
        commitIdx += 1
        if isCurrentView {
            numCommits = commitIdx
            setCanvScroll()
            if let targetID {
                if !comesBefore(targetID, p) {
                    targetRow += 1
                }
            }
        }
    }

    /// Port of gitk proc `insertfakerow` (gitk/gitk 1220–1247): inserts the
    /// pseudo commit `id` (local changes) in front of `p`, on `p`'s arc, in
    /// the current view.
    public func insertFakeRow(_ id: CommitIndex, _ p: CommitIndex) {
        let a = varcID[p] ?? 0
        let i = varcCommits[a].firstIndex(of: p) ?? -1
        if i < 0 {
            diagnostic("oops: insertfakerow can't find \(shortID(p)) on arc \(a)")
            return
        }
        children[id] = []
        parents[id] = [p]
        varcID[id] = a
        children[p, default: []].append(id)
        cmitListed[id] = 1
        commitIdx += 1
        numCommits = commitIdx
        // note we deliberately don't update varcstart even if i == 0
        varcCommits[a].insert(id, at: i)
        modifyArc(a, lim: i)
        if let targetID {
            if !comesBefore(targetID, p) {
                targetRow += 1
            }
        }
        setCanvScroll()
        drawVisible()
    }

    /// Port of gitk proc `removefakerow` (gitk/gitk 1249–1286): removes a
    /// pseudo commit added by `insertFakeRow`.
    public func removeFakeRow(_ id: CommitIndex) {
        let parentCount = parents[id]?.count ?? 0
        if parentCount != 1 {
            diagnostic("oops: removefakerow \(shortID(id)) has \(parentCount) parents")
            return
        }
        let p = parents[id]?[0] ?? id
        let a = varcID[id] ?? 0
        guard let i = varcCommits[a].firstIndex(of: id) else {
            diagnostic("oops: removefakerow can't find \(shortID(id)) on arc \(a)")
            return
        }
        varcID[id] = nil
        varcCommits[a].remove(at: i)
        parents[id] = nil
        children[id] = nil
        cmitListed[id] = nil
        commitIdx -= 1
        numCommits = commitIdx
        if let j = children[p]?.firstIndex(of: id) {
            children[p]?.remove(at: j)
        }
        modifyArc(a, lim: i)
        if let currentID, id == currentID {
            self.currentID = nil
            selectedLine = nil
        }
        if let targetID, targetID == id {
            self.targetID = p
        }
        setCanvScroll()
        drawVisible()
    }

    /// Port of gitk proc `real_children` (gitk/gitk 1288–1298): the children
    /// of `id` that are not local-changes pseudo commits.
    func realChildren(_ id: CommitIndex) -> [CommitIndex] {
        (children[id] ?? []).filter { isRealCommit($0) }
    }

    /// Port of gitk proc `first_real_child` (gitk/gitk 1300–1309).
    func firstRealChild(_ id: CommitIndex) -> CommitIndex? {
        for kid in children[id] ?? [] where isRealCommit(kid) {
            return kid
        }
        return nil
    }

    /// First 8 hex digits, for diagnostics (gitk `shortids`).
    func shortID(_ id: CommitIndex) -> String {
        store.id(at: id).abbreviated(8)
    }

    // MARK: - procs from task 6.4 that insertrow and insertfakerow need

    /// Port of gitk proc `update_arcrows` (gitk/gitk 1363–1428), with the
    /// view argument dropped: recomputes the arc order and the first row of
    /// each arc from ``varcMod`` on.
    func updateArcrows() {
        if vrowMod == commitIdx { return }
        if isCurrentView {
            if displayOrder.count > vrowMod {
                displayOrder = Array(displayOrder.prefix(vrowMod))
                parentList = Array(parentList.prefix(vrowMod))
            }
            cachedCommitRow.removeAll()
        }
        var a = varcMod
        while a != 0 && varcIx[a] == nil {
            // go up the tree until we find something that has a row number,
            // or we get to a seed
            a = vupPtr[a]
        }
        var arcn: Int
        var row: Int
        if a == 0 {
            a = vdownPtr[0]
            if a == 0 { return }
            vrowNum = [0]
            varcOrder = [a]
            varcIx[a] = 0
            varcRow[a] = 0
            arcn = 0
            row = 0
        } else {
            arcn = varcIx[a] ?? 0
            if vrowNum.count > arcn + 1 {
                vrowNum = Array(vrowNum.prefix(arcn + 1))
                varcOrder = Array(varcOrder.prefix(arcn + 1))
            }
            row = varcRow[a] ?? 0
        }
        var p = a
        while true {
            p = a
            row += varcCommits[a].count
            // go down if possible
            var b = vdownPtr[a]
            if b == 0 {
                // if not, go left, or go up until we can go left
                while a != 0 {
                    b = vleftPtr[a]
                    if b != 0 { break }
                    a = vupPtr[a]
                }
                if a == 0 { break }
            }
            a = b
            arcn += 1
            vrowNum.append(row)
            varcOrder.append(a)
            varcIx[a] = arcn
            varcRow[a] = row
        }
        vtokMod = varcTok[p]
        varcMod = p
        vrowMod = row
        if let currentID {
            selectedLine = rowOfCommit(currentID)
        }
    }

    /// Port of gitk proc `rowofcommit` (gitk/gitk 1438–1462): the row of
    /// commit `id` in the current view, or nil (gitk prints an "oops" and
    /// returns `{}`).
    public func rowOfCommit(_ id: CommitIndex) -> Int? {
        guard let a = varcID[id] else {
            diagnostic("oops rowofcommit no arc for \(shortID(id))")
            return nil
        }
        if tclStringCompare(varcTok[a], vtokMod) >= 0 {
            updateArcrows()
        }
        if let cached = cachedCommitRow[id] {
            return cached
        }
        guard let i = varcCommits[a].firstIndex(of: id) else {
            diagnostic("oops didn't find commit \(shortID(id)) in arc \(a)")
            return nil
        }
        guard let base = varcRow[a] else { return nil }
        let row = i + base
        cachedCommitRow[id] = row
        return row
    }

    /// Port of gitk proc `comes_before` (gitk/gitk 1465–1478): true if `a` is
    /// on an earlier row than `b`.
    public func comesBefore(_ a: CommitIndex, _ b: CommitIndex) -> Bool {
        guard a != b, let aa = varcID[a], let ba = varcID[b] else {
            return false
        }
        if aa != ba {
            return tclStringCompare(varcTok[aa], varcTok[ba]) < 0
        }
        guard let ra = rowOfCommit(a), let rb = rowOfCommit(b) else { return false }
        return ra < rb
    }

    // MARK: - gitk 1431–1616 (the rest of task 6.4)

    /// Port of gitk proc `commitinview` (gitk/gitk 1431–1435): true if the
    /// view contains commit `id`.
    public func commitInView(_ id: CommitIndex) -> Bool {
        varcID[id] != nil
    }

    /// Port of gitk proc `bsearch` (gitk/gitk 1480–1498): the index of the
    /// last element of the ascending integer list `l` that is not greater than
    /// `elt` (0 if there is none or the list is empty).
    func bsearch(_ l: [Int], _ elt: Int) -> Int {
        if l.isEmpty || elt <= l[0] {
            return 0
        }
        var lo = 0
        var hi = l.count
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            let t = l[mid]
            if elt < t {
                hi = mid
            } else if elt > t {
                lo = mid
            } else {
                return mid
            }
        }
        return lo
    }

    /// Port of gitk proc `make_disporder` (gitk/gitk 1501–1539): makes sure
    /// rows `start..<end` are valid in ``displayOrder`` and ``parentList``.
    func makeDisporder(_ start: Int, _ end: Int) {
        if end > vrowMod {
            updateArcrows()
        }
        var ai = bsearch(vrowNum, start)
        // gitk: with no arcs `lindex` gives {} and the loop below never runs
        guard vrowNum.indices.contains(ai) else { return }
        let narc = vrowNum.count
        var r = vrowNum[ai]
        while ai < narc && r < end {
            let a = varcOrder[ai]
            let l = displayOrder.count
            let al = varcCommits[a].count
            if l < r + al {
                if l < r {
                    let pad = r - l
                    displayOrder.append(contentsOf: [CommitIndex?](repeating: nil, count: pad))
                    parentList.append(contentsOf: [[CommitIndex]](repeating: [], count: pad))
                } else if l > r {
                    displayOrder = Array(displayOrder.prefix(r))
                    parentList = Array(parentList.prefix(r))
                }
                for id in varcCommits[a] {
                    displayOrder.append(id)
                    parentList.append(parents[id] ?? [])
                }
            } else if r + al - 1 < 0 || displayOrder[r + al - 1] == nil {
                var i = r
                for id in varcCommits[a] {
                    displayOrder[i] = id
                    parentList[i] = parents[id] ?? []
                    i += 1
                }
            }
            r += al
            ai += 1
        }
    }

    /// Port of gitk proc `commitonrow` (gitk/gitk 1541–1550): the commit shown
    /// on `row` of the current view, nil if there is none.
    public func commitOnRow(_ row: Int) -> CommitIndex? {
        func lookup() -> CommitIndex? {
            displayOrder.indices.contains(row) ? displayOrder[row] : nil
        }
        var id = lookup()
        if id == nil {
            makeDisporder(row, row + 1)
            id = lookup()
        }
        return id
    }

    /// Port of gitk proc `closevarcs` (gitk/gitk 1552–1590): adds the parents
    /// that were listed but never appeared in the log output as commits of
    /// their own, once the whole log has been read. Runs the scripts that
    /// ``checkInterest`` returned for them afterwards.
    ///
    /// gitk reads a missing parent's committer date for a date-order seed
    /// token from `commitinfo`, which does not exist for it (a Tcl error);
    /// here ``newVarc(_:)`` uses date 0 for a commit that is not in the store.
    public func closeVarcs() {
        var missingParents = 0
        var scripts: [() -> Void] = []
        let narcs = varcTok.count
        var a = 1
        while a < narcs {
            defer { a += 1 }
            guard let id = varcCommits[a].last else { continue }
            for p in parents[id] ?? [] {
                if varcID[p] != nil { continue }
                // add p as a new commit
                missingParents += 1
                cmitListed[p] = 0
                parents[p] = []
                let b: Int
                if (children[p]?.count ?? 0) == 1 && (parents[id]?.count ?? 0) == 1 {
                    b = a
                } else {
                    b = newVarc(p)
                }
                varcID[p] = b
                if tclStringCompare(varcTok[b], vtokMod) < 0 {
                    modifyArc(b)
                }
                varcCommits[b].append(p)
                commitIdx += 1
                if isCurrentView {
                    numCommits = commitIdx
                }
                scripts += checkInterest(p)
            }
        }
        if missingParents > 0 {
            for s in scripts {
                s()
            }
        }
    }

    /// Port of gitk proc `rewrite_commit` (gitk/gitk 1594–1616): uses `rwid`
    /// as a substitute for `id`, i.e. reparents `id`'s children to `rwid`.
    /// Assumes we already have an arc for `rwid`.
    func rewriteCommit(_ id: CommitIndex, _ rwid: CommitIndex) {
        for ch in children[id] ?? [] {
            // make rwid be ch's parent in place of id
            var chParents = parents[ch] ?? []
            if let i = chParents.firstIndex(of: id) {
                chParents[i] = rwid
            } else {
                diagnostic("oops rewrite_commit didn't find \(id) in parent list for \(ch)")
                // Tcl: lreplace $l -1 -1 $rwid inserts at the front
                chParents.insert(rwid, at: 0)
            }
            parents[ch] = chParents
            // add ch to rwid's children and sort the list if necessary
            children[rwid, default: []].append(ch)
            if (children[rwid]?.count ?? 0) > 1 {
                children[rwid] = sortedByToken(children[rwid] ?? [])
            }
            // fix the graph after joining id to rwid
            let a = varcID[ch] ?? 0
            fixReversal(rwid, a)
            // parentlist is wrong for the last element of arc a
            // even if displayorder is right, hence the 3rd arg here
            modifyArc(a, lim: varcCommits[a].count - 1)
        }
    }

    /// Port of gitk proc `getcommitlines` (gitk/gitk 1767–1850): the graph
    /// bookkeeping for one parsed log record. Process I/O belongs to HistoryLoader.
    /// During path-limited updates, the caller may supply the rewritten parent
    /// found by `git rev-list --first-parent --max-count=1 <id> -- <paths>`.
    public func add(_ commit: ParsedCommit, rewrittenParent: ObjectID? = nil) {
        let listed = commit.isBoundary ? 0 : (commit.isUninteresting ? 2 :
            (commit.side == .left ? 3 : (commit.side == .right ? 4 : 1)))
        let id = store.intern(commit.id)
        vshortIDs[commit.id.abbreviated(4), default: []].append(id)
        if listed == 0, varcID[id] == nil, let rewrittenParent,
           let replacement = store.index(of: rewrittenParent), varcID[replacement] != nil {
            rewriteCommit(id, replacement)
            return
        }
        var a = 0
        if let existing = varcID[id] {
            if (cmitListed[id] ?? 0) != 0 || listed == 0 { return }
            a = existing
        }
        let olds = listed != 0 ? commit.parents.map { store.intern($0) } : []
        store.insert(commit)
        cmitListed[id] = listed
        parents[id] = olds
        if children[id] == nil {
            children[id] = []
        } else if a == 0, let kids = children[id], kids.count == 1 {
            let k = kids[0]
            if parents[k]?.count == 1 && (!vdateMode || varcID[k] == varcTok.count - 1) {
                a = varcID[k] ?? 0
            }
        }
        if a == 0 { a = newVarc(id) }
        if tclStringCompare(varcTok[a], vtokMod) < 0 { modifyArc(a) }
        if varcID[id] == nil {
            varcID[id] = a
            varcCommits[a].append(id)
            commitIdx += 1
        }
        for (i, p) in olds.enumerated() where i == 0 || olds.firstIndex(of: p) == i {
            children[p, default: []].append(id)
            let kids = children[p] ?? []
            if kids.count > 1 && vtokcmp(kids[kids.count - 2], id) > 0 {
                children[p] = sortedByToken(kids)
                orderTok.removeAll()
            }
            if varcID[p] != nil { fixReversal(p, a) }
        }
        if isCurrentView { numCommits = commitIdx }
        for script in checkInterest(id) { script() }
    }

    /// Port of gitk proc `chewcommits` (gitk/gitk 1855–1884), without UI
    /// scheduling: update the row map after a batch. ViewSession drives lazy
    /// graph layout and the pending selection after this returns.
    public func chewCommits() {
        updateArcrows()
    }
}
