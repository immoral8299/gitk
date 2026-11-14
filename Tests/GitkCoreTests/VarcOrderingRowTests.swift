// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct VarcOrderingRowTests {
    private func idx(_ o: VarcOrdering, _ n: Int) -> CommitIndex {
        o.store.intern(VarcTestSupport.oid(n))
    }

    private func build(_ g: VarcTestSupport.RandomGraph, upTo count: Int? = nil) -> VarcOrdering {
        let o = VarcOrdering(store: CommitStore())
        for c in g.order.prefix(count ?? g.order.count) {
            o.feed(c, parents: g.parentsOf[c], date: g.dates[c])
        }
        return o
    }

    @Test func bsearchFindsTheLastElementNotAboveTheTarget() {
        let o = VarcOrdering(store: CommitStore())
        #expect(o.bsearch([], 5) == 0)
        #expect(o.bsearch([0], 5) == 0)
        let l = [0, 3, 3, 7, 12]
        #expect(o.bsearch(l, -1) == 0)
        #expect(o.bsearch(l, 0) == 0)
        #expect(o.bsearch(l, 2) == 0)
        #expect(o.bsearch(l, 4) == 2)
        #expect(o.bsearch(l, 7) == 3)
        #expect(o.bsearch(l, 11) == 3)
        #expect(o.bsearch(l, 12) == 4)
        #expect(o.bsearch(l, 99) == 4)
        // an exact hit returns whichever index the search lands on, as in gitk
        #expect([3, 2].contains(o.bsearch([0, 3, 3, 5], 3)))
    }

    @Test func vtokcmpComparesArcTokens() {
        let o = VarcOrdering(store: CommitStore())
        o.feed(1, parents: [], date: 500)
        o.feed(2, parents: [], date: 400)
        let a = idx(o, 1), b = idx(o, 2)
        #expect(o.vtokcmp(a, b) < 0)
        #expect(o.vtokcmp(b, a) > 0)
        #expect(o.vtokcmp(a, a) == 0)
    }

    @Test func commitInView() {
        let o = VarcOrdering(store: CommitStore())
        o.feed(1, parents: [2], date: 500)
        #expect(o.commitInView(idx(o, 1)))
        #expect(!o.commitInView(idx(o, 2)))  // parent not seen yet
        #expect(!o.commitInView(idx(o, 77)))
    }

    /// 50 commits with merges and clock skew: rowofcommit and commitonrow are inverses.
    @Test func rowOfCommitAndCommitOnRowAreInverses() {
        var rng = VarcTestSupport.LCG(seed: 12345)
        let g = VarcTestSupport.randomGraph(n: 50, rng: &rng)
        let o = build(g)
        #expect(o.commitIdx == 50)
        var seenRows = Set<Int>()
        for c in 0..<50 {
            let id = idx(o, c)
            guard let row = o.rowOfCommit(id) else {
                Issue.record("no row for commit \(c)")
                continue
            }
            #expect(row >= 0 && row < 50)
            #expect(seenRows.insert(row).inserted)
            #expect(o.commitOnRow(row) == id)
        }
        #expect(seenRows.count == 50)
        for row in 0..<50 {
            let id = o.commitOnRow(row)
            #expect(id != nil)
            if let id { #expect(o.rowOfCommit(id) == row) }
        }
        #expect(o.commitOnRow(50) == nil)
        #expect(o.commitOnRow(-1) == nil)
        // displayorder and parentlist are parallel and complete
        #expect(o.displayOrder.count == 50 && o.parentList.count == 50)
        for row in 0..<50 {
            if let id = o.displayOrder[row] { #expect(o.parentList[row] == (o.parents[id] ?? [])) }
        }
        // parents come after children
        for row in 0..<50 {
            for p in o.parentList[row] { #expect((o.rowOfCommit(p) ?? -1) > row) }
        }
    }

    /// Rows queried while the log is still being read must agree with the rows of
    /// a graph built in one go (exercises modify_arc / update_arcrows invalidation).
    @Test func rowsStayCorrectWhileCommitsArrive() {
        for seed in [1, 2, 3, 4, 5, 6, 7, 8] {
            var rng = VarcTestSupport.LCG(seed: UInt64(seed) &* 7919)
            let g = VarcTestSupport.randomGraph(n: 30 + rng.next(30), rng: &rng)
            let fresh = build(g)
            let expected = (0..<g.parentsOf.count).map { fresh.commitOnRow($0) }
            let expectedIDs = expected.compactMap { $0 }.map { fresh.store.id(at: $0) }
            let o = VarcOrdering(store: CommitStore())
            for (n, c) in g.order.enumerated() {
                o.feed(c, parents: g.parentsOf[c], date: g.dates[c])
                // look at a few rows and commits after every arrival
                let rows = o.commitIdx
                _ = o.commitOnRow(rng.next(rows))
                _ = o.commitOnRow(0)
                if let id = o.commitOnRow(rows - 1) {
                    #expect(o.rowOfCommit(id) == rows - 1, "seed \(seed) after \(n)")
                }
                let sample = o.store.intern(VarcTestSupport.oid(g.order[rng.next(n + 1)]))
                if let r = o.rowOfCommit(sample) {
                    #expect(o.commitOnRow(r) == sample, "seed \(seed) after \(n)")
                }
            }
            let got = (0..<g.parentsOf.count).compactMap { o.commitOnRow($0) }.map { o.store.id(at: $0) }
            #expect(got == expectedIDs, "seed \(seed)")
            #expect(o.treeIsConsistent())
        }
    }

    @Test func makeDisporderFillsOnlyWhatWasAskedFor() {
        var rng = VarcTestSupport.LCG(seed: 99)
        let g = VarcTestSupport.randomGraph(n: 40, rng: &rng)
        let o = build(g)
        o.updateArcrows()
        let all = (0..<40).map { r -> CommitIndex in
            let arc = o.varcOrder[o.bsearch(o.vrowNum, r)]
            return o.varcCommits[arc][r - o.vrowNum[o.bsearch(o.vrowNum, r)]]
        }
        #expect(o.displayOrder.isEmpty)
        // Ask for a late row first: the earlier rows are padded with nil.
        let late = 30
        o.makeDisporder(late, late + 1)
        #expect(o.displayOrder.count >= late + 1)
        #expect(o.displayOrder[late] == all[late])
        #expect(o.displayOrder.count == o.parentList.count)
        #expect(o.displayOrder[0] == nil)
        // The skipped rows are filled in on demand.
        #expect(o.commitOnRow(0) == all[0])
        #expect(o.displayOrder[late] == all[late])
        for r in 0..<40 { #expect(o.commitOnRow(r) == all[r]) }
        #expect(o.displayOrder.compactMap { $0 } == all)
    }

    @Test func modifyArcInvalidatesLaterRowsOnly() {
        let o = VarcOrdering(store: CommitStore())
        o.feed(1, parents: [2], date: 500)
        o.feed(2, parents: [3], date: 400)
        o.feed(3, parents: [], date: 300)
        o.feed(4, parents: [], date: 100)  // a second seed, after the first arc
        var undone: [Int] = []
        o.undoLayout = { undone.append($0) }
        let c4 = idx(o, 4)
        #expect(o.rowOfCommit(c4) == 3)
        #expect(o.vrowMod == 4)
        // A new arrival that sorts between: arc of commit 4 is renumbered later;
        // here: modify the arc of commit 4 only, row 3 and below are invalid.
        o.modifyArc(o.varcID[c4]!, lim: 0)
        #expect(undone == [3])
        #expect(o.vrowMod == 3)
        #expect(o.varcMod == o.varcID[c4])
        // rows of the earlier arc are still cached and right
        #expect(o.rowOfCommit(idx(o, 1)) == 0)
        #expect(o.rowOfCommit(c4) == 3)
        #expect(o.vrowMod == 4)
    }

    @Test func modifyArcOnAnotherViewTouchesNoLayoutState() {
        let o = VarcOrdering(store: CommitStore())
        o.isCurrentView = false
        o.feed(1, parents: [], date: 500)
        var undone = 0
        o.undoLayout = { _ in undone += 1 }
        o.modifyArc(1)
        #expect(undone == 0)
        #expect(o.vtokMod == o.varcTok[1] && o.varcMod == 1)
    }

    @Test func closeVarcsAddsMissingParents() {
        let o = VarcOrdering(store: CommitStore())
        o.feed(1, parents: [2], date: 500)
        o.feed(3, parents: [4, 5], date: 400)
        var ran: [CommitIndex] = []
        o.checkInterest = { id in [{ ran.append(id) }] }
        o.closeVarcs()
        let c2 = idx(o, 2), c4 = idx(o, 4), c5 = idx(o, 5)
        // 2 is the only parent of 1 and 1 its only child: it joins arc of 1.
        #expect(o.varcID[c2] == o.varcID[idx(o, 1)])
        #expect(o.varcCommits[o.varcID[c2]!] == [idx(o, 1), c2])
        // 4 and 5 have a single child but it has two parents: new arcs.
        #expect(o.varcID[c4] != nil && o.varcID[c5] != nil)
        #expect(o.varcID[c4] != o.varcID[idx(o, 3)])
        #expect(o.varcID[c4] != o.varcID[c5])
        #expect(o.cmitListed[c2] == 0 && o.cmitListed[c4] == 0 && o.cmitListed[c5] == 0)
        #expect(o.parents[c2] == [] && o.parents[c4] == [])
        #expect(o.commitIdx == 5 && o.numCommits == 5)
        #expect(ran == [c2, c4, c5])
        #expect(o.treeIsConsistent())
        // rows: 1 and 2, then 3, then 5 before 4 (the first parent sorts last)
        let order = (0..<5).compactMap { o.commitOnRow($0) }
        #expect(order.count == 5)
        #expect(order.firstIndex(of: idx(o, 3))! < order.firstIndex(of: c4)!)
        #expect(order.firstIndex(of: idx(o, 3))! < order.firstIndex(of: c5)!)
        // nothing left to do the second time
        ran = []
        o.closeVarcs()
        #expect(ran.isEmpty && o.commitIdx == 5)
    }

    @Test func rewriteCommitReparentsChildren() {
        let o = VarcOrdering(store: CommitStore())
        o.feed(10, parents: [], date: 100)         // R, already known
        o.feed(11, parents: [12], date: 200)       // K, whose parent X (12) is not listed
        let r = idx(o, 10), k = idx(o, 11), x = idx(o, 12)
        #expect(o.children[x] == [k])
        o.rewriteCommit(x, r)
        #expect(o.parents[k] == [r])
        #expect(o.children[r] == [k])
        #expect(o.commitOnRow(0) == k)
        #expect(o.commitOnRow(1) == r)
        #expect(o.treeIsConsistent())
        // the last element of K's arc has its parentlist recomputed
        #expect(o.parentList[0] == [r])
    }

    @Test func rewriteCommitReportsAMissingParentLink() {
        let o = VarcOrdering(store: CommitStore())
        o.feed(10, parents: [], date: 100)
        o.feed(11, parents: [12], date: 200)
        let r = idx(o, 10), k = idx(o, 11), x = idx(o, 12)
        o.parents[k] = []  // corrupt on purpose
        var messages: [String] = []
        o.diagnostic = { messages.append($0) }
        o.rewriteCommit(x, r)
        #expect(messages.count == 1)
        #expect(o.parents[k] == [r])  // lreplace with index -1 inserts at the front
    }
}
