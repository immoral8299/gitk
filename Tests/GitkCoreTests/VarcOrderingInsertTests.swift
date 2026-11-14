// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct VarcOrderingInsertTests {
    /// HEAD (1) merges 2 and 3, which both descend from 4, which descends from 5.
    private func makeGraph() -> VarcOrdering {
        let o = VarcOrdering(store: CommitStore())
        o.feed(1, parents: [2, 3], date: 600)
        o.feed(2, parents: [4], date: 500)
        o.feed(3, parents: [4], date: 450)
        o.feed(4, parents: [5], date: 400)
        o.feed(5, parents: [], date: 300)
        return o
    }

    private func idx(_ o: VarcOrdering, _ n: Int) -> CommitIndex {
        o.store.intern(VarcTestSupport.oid(n))
    }

    /// Commits in display order, found through `rowOfCommit` (and cross-checked
    /// against the arc walk).
    private func order(_ o: VarcOrdering) -> [CommitIndex] {
        let byWalk = o.arcWalk().flatMap { o.varcCommits[$0] }
        var byRow = [CommitIndex?](repeating: nil, count: byWalk.count)
        for id in byWalk {
            if let r = o.rowOfCommit(id), r < byRow.count { byRow[r] = id }
        }
        #expect(byRow.compactMap { $0 } == byWalk)
        return byWalk
    }

    private func pseudoCommit(_ o: VarcOrdering, staged: Bool) -> CommitIndex {
        o.store.intern(staged ? o.nullID2! : o.nullID!)
    }

    @Test func fakeRowUnderHeadIsInsertedAndRemoved() {
        let o = makeGraph()
        let head = idx(o, 1)
        let before = order(o)
        #expect(before.first == head)
        let childrenBefore = o.children
        let arcsBefore = o.varcCommits

        let fake = pseudoCommit(o, staged: false)
        var scrolled = 0
        var drawn = 0
        o.setCanvScroll = { scrolled += 1 }
        o.drawVisible = { drawn += 1 }
        o.insertFakeRow(fake, head)
        #expect(order(o) == [fake] + before)
        #expect(o.rowOfCommit(fake) == 0)
        #expect(o.rowOfCommit(head) == 1)
        #expect(o.commitIdx == 6 && o.numCommits == 6)
        #expect(o.children[head] == [fake])
        #expect(o.parents[fake] == [head])
        #expect(o.cmitListed[fake] == 1)
        #expect(o.realChildren(head).isEmpty)
        #expect(o.firstRealChild(head) == nil && o.lastRealChild(head) == nil)
        #expect(scrolled == 1 && drawn == 1)

        o.removeFakeRow(fake)
        #expect(order(o) == before)
        #expect(o.commitIdx == 5 && o.numCommits == 5)
        #expect(o.varcID[fake] == nil && o.parents[fake] == nil && o.children[fake] == nil)
        #expect(o.cmitListed[fake] == nil)
        #expect(o.children[head] == [])
        #expect(o.children[fake] == nil)
        #expect(o.varcCommits == arcsBefore)
        #expect(o.children.filter { $0.key != head } == childrenBefore.filter { $0.key != head })
        for (n, id) in before.enumerated() {
            #expect(o.rowOfCommit(id) == n)
        }
        #expect(scrolled == 2 && drawn == 2)
    }

    @Test func fakeRowInMiddleOfArcGoesBeforeItsParent() {
        let o = makeGraph()
        let before = order(o)
        // Find a commit that is not the first of its arc.
        let (a, i) = o.arcWalk().lazy.compactMap { a in
            o.varcCommits[a].count > 1 ? (a, 1) : nil
        }.first!
        let p = o.varcCommits[a][i]
        let fake = pseudoCommit(o, staged: true)
        o.insertFakeRow(fake, p)
        var expected = before
        expected.insert(fake, at: before.firstIndex(of: p)!)
        #expect(order(o) == expected)
        #expect(o.varcID[fake] == a)
        o.removeFakeRow(fake)
        #expect(order(o) == before)
    }

    @Test func fakeRowShiftsTheTargetRow() {
        let o = makeGraph()
        let head = idx(o, 1)
        let c4 = idx(o, 4)
        o.targetID = c4
        o.targetRow = 3
        o.currentID = c4
        _ = o.rowOfCommit(c4)
        let fake = pseudoCommit(o, staged: false)
        o.insertFakeRow(fake, head)  // c4 does not come before head
        #expect(o.targetRow == 4)
        #expect(o.rowOfCommit(c4) == 4)
        #expect(o.selectedLine == 4)
        o.targetID = fake
        o.removeFakeRow(fake)
        #expect(o.targetID == head)
        o.currentID = fake
        o.insertFakeRow(fake, head)
        o.removeFakeRow(fake)
        #expect(o.currentID == nil && o.selectedLine == nil)
    }

    @Test func removeFakeRowRejectsNonPseudoCommit() {
        let o = makeGraph()
        var messages: [String] = []
        o.diagnostic = { messages.append($0) }
        let merge = idx(o, 1)  // two parents
        o.removeFakeRow(merge)
        #expect(messages.count == 1 && messages[0].hasPrefix("oops: removefakerow"))
        #expect(messages[0].contains("2 parents"))
        #expect(o.commitIdx == 5)
        let stranger = o.store.intern(VarcTestSupport.oid(99))
        o.insertFakeRow(idx(o, 2), stranger)
        #expect(messages.count == 2 && messages[1].hasPrefix("oops: insertfakerow can't find"))
    }

    @Test func insertRowOnTopOfHead() {
        let o = makeGraph()
        let head = idx(o, 1)
        let before = order(o)
        let new = o.store.insert(VarcTestSupport.commit(50, parents: [1], date: 700))
        o.targetID = head
        o.targetRow = 0
        var scrolled = 0
        o.setCanvScroll = { scrolled += 1 }
        o.insertRow(new, head)
        #expect(order(o) == [new] + before)
        #expect(o.rowOfCommit(new) == 0)
        #expect(o.rowOfCommit(head) == 1)
        #expect(o.children[head] == [new])
        #expect(o.parents[new] == [head])
        #expect(o.children[new] == [])
        #expect(o.cmitListed[new] == 1)
        #expect(o.commitIdx == 6 && o.numCommits == 6)
        #expect(o.vshortIDs[VarcTestSupport.oid(50).abbreviated(4)]?.last == new)
        #expect(o.targetRow == 1)  // head does not come before itself
        #expect(scrolled == 1)
        #expect(o.treeIsConsistent())
    }

    /// The new commit has an older date than its parent: the parent arc is
    /// renumbered below it all the same.
    @Test func insertRowWithClockSkew() {
        let o = makeGraph()
        let head = idx(o, 1)
        let before = order(o)
        let new = o.store.insert(VarcTestSupport.commit(51, parents: [1], date: 100))
        o.insertRow(new, head)
        #expect(order(o) == [new] + before)
        #expect(o.treeIsConsistent())
    }

    @Test func insertRowOnNonCurrentViewLeavesNumCommits() {
        let o = makeGraph()
        o.isCurrentView = false
        let head = idx(o, 1)
        let new = o.store.insert(VarcTestSupport.commit(52, parents: [1], date: 700))
        o.insertRow(new, head)
        #expect(o.commitIdx == 6)
        #expect(o.numCommits == 5)
    }

    @Test func realChildHelpersSkipPseudoCommits() {
        let o = makeGraph()
        let c5 = idx(o, 5)
        let c4 = idx(o, 4)
        let unstaged = pseudoCommit(o, staged: false)
        let staged = pseudoCommit(o, staged: true)
        o.children[c5] = [unstaged, c4, staged]
        #expect(o.realChildren(c5) == [c4])
        #expect(o.firstRealChild(c5) == c4)
        #expect(o.lastRealChild(c5) == c4)
        o.children[c5] = [unstaged, staged]
        #expect(o.realChildren(c5).isEmpty)
        #expect(o.firstRealChild(c5) == nil)
        #expect(o.lastRealChild(c5) == nil)
        o.children[c5] = [c4, unstaged, idx(o, 2), staged]
        #expect(o.realChildren(c5) == [c4, idx(o, 2)])
        #expect(o.firstRealChild(c5) == c4)
        #expect(o.lastRealChild(c5) == idx(o, 2))
        #expect(o.realChildren(idx(o, 77)).isEmpty)
    }
}
