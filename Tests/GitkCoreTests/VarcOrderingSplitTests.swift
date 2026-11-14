// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct VarcOrderingSplitTests {
    private func makeOrdering() -> VarcOrdering {
        VarcOrdering(store: CommitStore())
    }

    private func tok(_ date: Int64) -> String { "s" + strrep(date ^ 0xffffffff) + "0" }

    /// Commits of the arcs in depth-first order of the arc tree.
    private func walkedCommits(_ o: VarcOrdering) -> [CommitIndex] {
        o.arcWalk().flatMap { o.varcCommits[$0] }
    }

    @Test func chainJoinsIntoOneArc() {
        let o = makeOrdering()
        o.feed(1, parents: [2], date: 500)
        o.feed(2, parents: [3], date: 400)
        o.feed(3, parents: [], date: 300)
        #expect(o.varcTok == ["", tok(500)])
        #expect(o.varcCommits[1].count == 3)
        #expect(o.commitIdx == 3)
    }

    @Test func splitVarcAtMiddleOfArc() {
        let o = makeOrdering()
        o.feed(1, parents: [2], date: 500)
        o.feed(2, parents: [3], date: 400)
        o.feed(3, parents: [], date: 300)
        let b = o.store.index(of: VarcTestSupport.oid(2))!
        let c = o.store.index(of: VarcTestSupport.oid(3))!
        let a = o.store.index(of: VarcTestSupport.oid(1))!
        o.splitVarc(b)
        #expect(o.varcCommits == [[], [a], [b, c]])
        #expect(o.varcTok == ["", tok(500), tok(500) + "%1"])
        #expect(o.varcStart == [nil, a, b])
        #expect(o.varcID[a] == 1 && o.varcID[b] == 2 && o.varcID[c] == 2)
        #expect(o.vupPtr == [0, 0, 1])
        #expect(o.vdownPtr == [1, 2, 0])
        #expect(o.vlastIns == [1, 0, 0])
        #expect(o.treeIsConsistent())
        // Splitting at the start of an arc is a no-op.
        o.splitVarc(b)
        o.splitVarc(a)
        #expect(o.varcCommits == [[], [a], [b, c]])
    }

    @Test func splitVarcReparentsChildArcsOfTheTail() {
        let o = makeOrdering()
        // 1 -> 2 -> 3 in one arc; 3 has a second parent 4 (a separate arc below).
        o.feed(1, parents: [2], date: 500)
        o.feed(2, parents: [3, 4], date: 400)
        o.feed(4, parents: [], date: 350)
        o.feed(3, parents: [], date: 300)
        let c2 = o.store.index(of: VarcTestSupport.oid(2))!
        let arcOf2 = o.varcID[c2]!
        let below = o.arcWalk().filter { o.vupPtr[$0] == arcOf2 }
        #expect(below.count == 2)
        o.splitVarc(c2)
        // The arcs that hung from the old arc now hang from the new tail arc.
        let tail = o.varcID[c2]!
        #expect(tail != arcOf2)
        #expect(Set(o.arcWalk().filter { o.vupPtr[$0] == tail }) == Set(below))
        #expect(o.vdownPtr[arcOf2] == tail)
        #expect(o.treeIsConsistent())
    }

    /// The parent is read before its child (clock skew): the child's arc becomes
    /// the parent arc's upper neighbour.
    @Test func childArrivingAfterParentReversesTheSeed() {
        let o = makeOrdering()
        o.feed(1, parents: [], date: 500)   // parent P, seen first, newer date
        o.feed(2, parents: [1], date: 400)  // child K
        let p = o.store.index(of: VarcTestSupport.oid(1))!
        let k = o.store.index(of: VarcTestSupport.oid(2))!
        #expect(o.varcTok == ["", tok(400) + "0", tok(400)])
        #expect(o.vupPtr == [0, 2, 0])
        #expect(o.vdownPtr == [2, 0, 1])
        #expect(o.vleftPtr == [0, 0, 0])
        #expect(o.vbackPtr == [0, 0, 0])
        #expect(o.vlastIns == [2, 0, 1])
        #expect(o.seeds() == [k])
        #expect(walkedCommits(o) == [k, p])
        #expect(o.treeIsConsistent())
    }

    /// A child of a mid-arc commit arrives later: the arc is split and the tail is
    /// renumbered below the new child.
    @Test func lateChildSplitsTheParentArc() {
        let o = makeOrdering()
        o.feed(1, parents: [2], date: 500)  // A
        o.feed(2, parents: [3], date: 400)  // B
        o.feed(3, parents: [], date: 300)   // C
        o.feed(4, parents: [2], date: 100)  // X, a second child of B
        let a = o.store.index(of: VarcTestSupport.oid(1))!
        let b = o.store.index(of: VarcTestSupport.oid(2))!
        let c = o.store.index(of: VarcTestSupport.oid(3))!
        let x = o.store.index(of: VarcTestSupport.oid(4))!
        #expect(o.varcTok == ["", tok(500), tok(100), tok(100) + "0"])
        #expect(o.varcCommits == [[], [a], [x], [b, c]])
        #expect(o.varcStart == [nil, a, x, b])
        #expect(o.vupPtr == [0, 0, 0, 2])
        #expect(o.vdownPtr == [1, 0, 3, 0])
        #expect(o.vleftPtr == [0, 2, 0, 0])
        #expect(o.vbackPtr == [0, 0, 1, 0])
        #expect(o.vlastIns == [2, 0, 3, 0])
        #expect(o.children[b] == [a, x])
        #expect(walkedCommits(o) == [a, x, b, c])
        #expect(o.treeIsConsistent())
    }

    /// fixReversal on the parent of a merge: the parent ends up below its
    /// last (largest-token) child.
    @Test func mergeParentSitsBelowItsLastChild() {
        let o = makeOrdering()
        o.feed(1, parents: [3], date: 500)
        o.feed(2, parents: [3], date: 450)
        o.feed(3, parents: [], date: 100)
        let c3 = o.store.index(of: VarcTestSupport.oid(3))!
        let a3 = o.varcID[c3]!
        // Child 2 has the larger token (older), so it is the last child.
        #expect(o.vupPtr[a3] == o.varcID[o.store.index(of: VarcTestSupport.oid(2))!]!)
        #expect(o.treeIsConsistent())
    }

    /// Random DAGs read in git's default order (newest first, a commit only after
    /// one of its children): the arc tree stays consistent, the walk visits tokens in
    /// ascending order, and every commit comes before its parents.
    @Test func randomGraphsStayConsistent() {
        var rng = VarcTestSupport.LCG()
        for round in 0..<60 {
            let g = VarcTestSupport.randomGraph(n: 5 + rng.next(40), rng: &rng)
            let n = g.parentsOf.count
            let parentsOf = g.parentsOf, dates = g.dates, order = g.order
            let o = makeOrdering()
            for c in order {
                o.feed(c, parents: parentsOf[c], date: dates[c])
                #expect(o.treeIsConsistent(), "round \(round) after commit \(c)")
            }
            let walk = o.arcWalk()
            let toks = walk.map { o.varcTok[$0] }
            #expect(toks == toks.sorted(), "round \(round): tokens not ascending in walk")
            let flat = walk.flatMap { o.varcCommits[$0] }
            #expect(flat.count == n, "round \(round)")
            var position: [CommitIndex: Int] = [:]
            for (i, id) in flat.enumerated() { position[id] = i }
            for (id, ps) in o.parents {
                for p in ps {
                    #expect((position[id] ?? 0) < (position[p] ?? 0), "round \(round): parent before child")
                }
            }
        }
    }
}
