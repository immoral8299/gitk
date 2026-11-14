// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Test helpers shared by the `VarcOrdering*Tests` suites.
enum VarcTestSupport {
    /// Test ids are 0x1000 + n so that none of them is gitk's nullid.
    static func oid(_ n: Int) -> ObjectID {
        let text = String(0x1000 + n, radix: 16)
        return ObjectID(hex: String(repeating: "0", count: 40 - text.count) + text)!
    }

    /// Small deterministic random numbers.
    struct LCG {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        mutating func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
    }

    struct RandomGraph {
        var parentsOf: [[Int]]
        var dates: [Int64]
        /// The order in which git's default (date-ordered) walk would print the commits.
        var order: [Int]
    }

    /// A random DAG of `n` commits. Commit i may only have parents with larger numbers, but
    /// dates are skewed so that they do not always agree with the topology.
    static func randomGraph(n: Int, rng: inout LCG) -> RandomGraph {
        var parentsOf: [[Int]] = []
        var dates: [Int64] = []
        for i in 0..<n {
            var ps: [Int] = []
            if i < n - 1 {
                ps.append(i + 1 + rng.next(min(3, n - 1 - i)))
                if rng.next(4) == 0 {
                    let q = i + 1 + rng.next(n - 1 - i)
                    if !ps.contains(q) { ps.append(q) }
                }
            }
            parentsOf.append(ps)
            dates.append(Int64(1_000_000 + (n - i) * 100 + rng.next(500) - 250))
        }
        var hasChild = Set<Int>()
        for ps in parentsOf { for p in ps { hasChild.insert(p) } }
        // Simulate git's date-ordered walk from the tips.
        var queue = (0..<n).filter { !hasChild.contains($0) }
        var queued = Set(queue)
        var order: [Int] = []
        while !queue.isEmpty {
            let best = queue.indices.max { dates[queue[$0]] < dates[queue[$1]] }!
            let c = queue.remove(at: best)
            order.append(c)
            for p in parentsOf[c] where queued.insert(p).inserted { queue.append(p) }
        }
        return RandomGraph(parentsOf: parentsOf, dates: dates, order: order)
    }

    static func commit(_ n: Int, parents: [Int] = [], date: Int64) -> ParsedCommit {
        ParsedCommit(
            id: oid(n), parents: parents.map(oid), isBoundary: false, isUninteresting: false,
            side: nil, tree: oid(0xFFFF), authorName: Data("A".utf8), authorEmail: Data("a@x".utf8),
            authorEpoch: date, authorTZ: "+0000",
            committerName: Data("C".utf8), committerEmail: Data("c@x".utf8),
            committerEpoch: date, committerTZ: "+0000", encoding: nil,
            headline: Data("s".utf8), message: Data("s".utf8), notes: nil)
    }
}

extension VarcOrdering {
    /// Test-only: the part of getcommitlines that is needed before arcs are
    /// joined (store the commit, record parents and children, make a new arc
    /// for it). Does not join arcs and does not call `fixReversal`.
    @discardableResult
    func seeNewArc(_ n: Int, parents olds: [Int], date: Int64) -> CommitIndex {
        let id = store.insert(VarcTestSupport.commit(n, parents: olds, date: date))
        let olds = olds.map { store.intern(VarcTestSupport.oid($0)) }
        self.parents[id] = olds
        cmitListed[id] = 1
        if children[id] == nil { children[id] = [] }
        let a = newVarc(id)
        varcID[id] = a
        varcCommits[a].append(id)
        commitIdx += 1
        for p in olds { children[p, default: []].append(id) }
        return id
    }
}

extension VarcOrdering {
    func feed(_ n: Int, parents olds: [Int], date: Int64, listed: Int = 1) {
        var commit = VarcTestSupport.commit(n, parents: olds, date: date)
        commit.isBoundary = listed == 0
        commit.isUninteresting = listed == 2
        commit.side = listed == 3 ? .left : (listed == 4 ? .right : nil)
        add(commit)
    }

    /// Test-only: ids of the arc tree in depth-first order (the order
    /// `update_arcrows` walks).
    func arcWalk() -> [Int] {
        var out: [Int] = []
        var a = vdownPtr[0]
        while a != 0 {
            out.append(a)
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
        return out
    }

    /// Test-only: checks the invariants of the arc tree and the maps.
    func treeIsConsistent() -> Bool {
        let n = varcTok.count
        guard [varcStart.count, vupPtr.count, vdownPtr.count, vleftPtr.count, vbackPtr.count,
               varcRow.count, varcIx.count, vlastIns.count, varcCommits.count].allSatisfy({ $0 == n })
        else { return false }
        var seen = Set<Int>()
        for a in arcWalk() {
            if !seen.insert(a).inserted { return false }
            // children list consistency
            let up = vupPtr[a]
            var b = vdownPtr[up]
            var prev = 0
            var found = false
            while b != 0 {
                if vbackPtr[b] != prev { return false }
                if b == a { found = true }
                if vupPtr[b] != up { return false }
                if prev != 0 && tclStringCompare(varcTok[prev], varcTok[b]) > 0 { return false }
                prev = b
                b = vleftPtr[b]
            }
            if !found { return false }
        }
        return seen.count == n - 1
    }
}

@Suite struct VarcOrderingInitTests {
    private func makeOrdering() -> VarcOrdering {
        let o = VarcOrdering(store: CommitStore())
        o.varcInit()
        return o
    }

    @Test func strrepSortsAsStringsInNumericOrder() {
        #expect(strrep(0) == "0")
        #expect(strrep(15) == "f")
        #expect(strrep(16) == "x10")
        #expect(strrep(255) == "xff")
        #expect(strrep(256) == "y0100")
        #expect(strrep(65535) == "yffff")
        #expect(strrep(65536) == "z00010000")
        #expect(strrep(0xfffffe0b) == "zfffffe0b")
        let values = [0, 1, 9, 10, 15, 16, 100, 255, 256, 4096, 65535, 65536, 1_000_000, 0xffffffff]
        let tokens = values.map { strrep($0) }
        #expect(tokens == tokens.sorted())
    }

    @Test func varcInitState() {
        let o = makeOrdering()
        #expect(o.varcStart == [nil])
        #expect(o.vupPtr == [0] && o.vdownPtr == [0] && o.vleftPtr == [0] && o.vbackPtr == [0])
        #expect(o.varcTok == [""])
        #expect(o.varcRow == [nil] && o.varcIx == [nil])
        #expect(o.vtokMod == "" && o.varcMod == 0 && o.vrowMod == 0)
        #expect(o.vlastIns == [0])
        #expect(o.seeds().isEmpty)
    }

    /// 1 -> 2 -> {3, 4}; 3 -> 5; 4 -> 5 (child -> parents). Dates descend with
    /// the numbers, except that 4 is newer than 3.
    @Test func fiveCommitGraphBuildsExpectedTree() {
        let o = makeOrdering()
        let c1 = o.seeNewArc(1, parents: [2], date: 500)
        let c2 = o.seeNewArc(2, parents: [3, 4], date: 400)
        let c4 = o.seeNewArc(4, parents: [5], date: 350)
        let c3 = o.seeNewArc(3, parents: [5], date: 300)
        let c5 = o.seeNewArc(5, parents: [], date: 100)

        let t1 = "s" + "zfffffe0b" + "0"   // 500 ^ 0xffffffff, first seed with that date
        let t2 = t1 + "0"                    // only parent of c1
        let t3 = t2 + "0"                    // c4 is the second parent of c2: j = 2 - 1 - 1
        let t4 = t2 + "1"                    // c3 is the first parent: j = 1
        let t5 = t4 + "0"
        #expect(o.varcTok == ["", t1, t2, t3, t4, t5])
        #expect(o.varcStart == [nil, c1, c2, c4, c3, c5])
        #expect(o.vupPtr == [0, 0, 1, 2, 2, 4])
        #expect(o.vdownPtr == [1, 2, 3, 0, 5, 0])
        #expect(o.vleftPtr == [0, 0, 0, 4, 0, 0])
        #expect(o.vbackPtr == [0, 0, 0, 0, 3, 0])
        #expect(o.vlastIns == [1, 2, 4, 0, 5, 0])
        #expect(o.varcRow == [Int?](repeating: nil, count: 6))
        #expect(o.varcIx == [Int?](repeating: nil, count: 6))
        #expect(o.varcCommits == [[], [c1], [c2], [c4], [c3], [c5]])
        #expect(o.seeds() == [c1])
        #expect(o.commitIdx == 5)
    }

    @Test func seedsAreOrderedNewestFirstThenBySeedCount() {
        let o = makeOrdering()
        let old = o.seeNewArc(1, parents: [], date: 100)
        let newer = o.seeNewArc(2, parents: [], date: 200)
        let sameA = o.seeNewArc(3, parents: [], date: 200)
        let sameB = o.seeNewArc(4, parents: [], date: 200)
        // Newer date -> smaller (xor) token -> earlier; equal dates keep arrival order.
        #expect(o.seeds() == [newer, sameA, sameB, old])
        let tok200 = "s" + strrep(Int64(200) ^ 0xffffffff)
        #expect(o.varcTok[2] == tok200 + "0")
        #expect(o.varcTok[3] == tok200 + "1")
        #expect(o.varcTok[4] == tok200 + "2")
        #expect(o.varcTok[1] == "s" + strrep(Int64(100) ^ 0xffffffff) + "0")
        // Sibling links in sorted order: arcs 2, 3, 4, 1.
        #expect(o.vdownPtr[0] == 2)
        #expect(o.vleftPtr[2] == 3 && o.vleftPtr[3] == 4 && o.vleftPtr[4] == 1 && o.vleftPtr[1] == 0)
        #expect(o.vbackPtr[2] == 0 && o.vbackPtr[3] == 2 && o.vbackPtr[4] == 3 && o.vbackPtr[1] == 4)
        #expect(o.vlastIns[0] == 4)  // the last arc inserted below the sentinel
    }

    @Test func dateModeGivesEveryArcASeedToken() {
        let o = makeOrdering()
        o.vdateMode = true
        let c1 = o.seeNewArc(1, parents: [2], date: 500)
        let c2 = o.seeNewArc(2, parents: [], date: 400)
        // In date mode the parent computes its own seed token first. It is larger than
        // the child's token, so it is not replaced by the child's: the parent stays a seed.
        let tok1 = "s" + strrep(Int64(500) ^ 0xffffffff) + "0"
        let tok2 = "s" + strrep(Int64(400) ^ 0xffffffff) + "0"
        #expect(tok1 < tok2)
        #expect(o.varcTok[2] == tok2)
        #expect(o.vupPtr[2] == 0)
        #expect(o.seeds() == [c1, c2])
    }

    @Test func unloadedCommitUsesDateZero() {
        let o = makeOrdering()
        let id = o.store.intern(VarcTestSupport.oid(9))
        let a = o.newVarc(id)
        #expect(o.varcTok[a] == "s" + strrep(Int64(0xffffffff)) + "0")
    }

    @Test func resetVarcsClearsPerCommitState() {
        let o = makeOrdering()
        o.seeNewArc(1, parents: [2], date: 500)
        o.orderTok[0] = "x"
        o.vshortIDs["0000"] = [0]
        o.resetVarcs()
        #expect(o.varcID.isEmpty && o.children.isEmpty && o.parents.isEmpty)
        #expect(o.vshortIDs.isEmpty && o.vseedCount.isEmpty && o.orderTok.isEmpty)
        #expect(o.varcCommits == [[]])
        o.varcInit()
        #expect(o.varcTok == [""] && o.vdownPtr == [0])
    }
}
