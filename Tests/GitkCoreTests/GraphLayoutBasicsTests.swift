// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct GraphLayoutBasicsTests {
    @Test func linearTokensAndNeighbourUses() {
        let ordering = VarcOrdering(store: CommitStore())
        ordering.feed(1, parents: [2], date: 500)
        ordering.feed(2, parents: [3], date: 400)
        ordering.feed(3, parents: [], date: 300)
        let graph = GraphLayout(ordering: ordering)
        let a = ordering.store.intern(VarcTestSupport.oid(1))
        let b = ordering.store.intern(VarcTestSupport.oid(2))
        let c = ordering.store.intern(VarcTestSupport.oid(3))
        #expect(graph.orderToken(a) == graph.orderToken(b))
        #expect(graph.orderToken(c) == graph.orderToken(a))
        #expect(graph.nextUse(c, 0) == 1)
        #expect(graph.nextUse(c, 1) == 2)
        #expect(graph.prevUse(c, 2) == 1)
        #expect(graph.prevUse(a, 2) == -1)
        #expect(graph.idCol([], a) == 0)
        #expect(graph.idCol([a], b, 10) == 1)
        #expect(graph.idCol([a], b, -10) == 0)
        #expect(graph.scrollHeight(lineSpacing: 18) == 50)
    }

    @Test func paddingDoesNotChangeLogicalRowEquality() {
        let graph = GraphLayout(ordering: VarcOrdering(store: CommitStore()))
        #expect(graph.rowsEqual([1, nil, 2], [nil, 1, 2, nil]))
        #expect(!graph.rowsEqual([1, 2], [2, 1]))
    }

    @Test func resetsLaneAndTokenState() {
        let ordering = VarcOrdering(store: CommitStore())
        ordering.feed(1, parents: [], date: 500)
        let graph = GraphLayout(ordering: ordering)
        graph.ensureLaid(visibleRows: 0..<1)
        #expect(!graph.rowIDList.isEmpty)
        graph.reset()
        #expect(graph.rowIDList.isEmpty)
        #expect(graph.rowFinal.isEmpty)
        #expect(ordering.orderTok.isEmpty)
        #expect(ordering.commitIdx == 1)
    }
}

enum LayoutTestSupport {
    static func graph(_ fixture: String) async throws -> GraphLayout {
        let ordering = try await OrderingParityTests.load(fixture, args: fixture == "random-dag" ? ["--all"] : [])
        return GraphLayout(ordering: ordering)
    }

    static func checkRows(_ graph: GraphLayout, _ expected: OracleResult) {
        for (r, row) in expected.rows.enumerated() {
            let list = graph.ids(on: r)
            let ids = list.map { $0.map { graph.ordering.store.id(at: $0).hex } ?? "" }
            #expect(ids == row.idlist, "row \(r), \(row.id)")
            #expect(list.firstIndex(of: graph.ordering.commitOnRow(r)) == row.col, "column on row \(r)")
        }
    }
}

@Suite struct LayoutRowsParityTests {
    @Test(arguments: ["linear", "merge-simple", "octopus"])
    func rowsMatchOracle(_ fixture: String) async throws {
        let graph = try await LayoutTestSupport.graph(fixture)
        graph.layoutRows(0, graph.ordering.commitIdx)
        graph.optimizeRows(0, 0, graph.ordering.commitIdx)
        LayoutTestSupport.checkRows(graph, try OracleGolden.load(fixture))
    }
}

@Suite struct LayoutParityTests {
    @Test(arguments: OracleGoldenTests.fixtures.filter { $0 != "random-dag" })
    func optimizedRowsMatchOracle(_ fixture: String) async throws {
        let graph = try await LayoutTestSupport.graph(fixture)
        graph.drawCommits(0, graph.ordering.commitIdx - 1)
        LayoutTestSupport.checkRows(graph, try OracleGolden.load(fixture))
    }
}

@Suite struct RowRangesParityTests {
    @Test(arguments: OracleGoldenTests.fixtures)
    func chunkedViewportRowsAndRangesMatchOracle(_ fixture: String) async throws {
        let graph = try await LayoutTestSupport.graph(fixture)
        for start in stride(from: 0, to: graph.ordering.commitIdx, by: 50) {
            graph.ensureLaid(visibleRows: start..<(start + 50))
        }
        let expected = try OracleGolden.load(fixture)
        LayoutTestSupport.checkRows(graph, expected)
        for id in expected.order {
            let objectID = try #require(ObjectID(hex: id))
            let index = try #require(graph.ordering.store.index(of: objectID))
            #expect(graph.rowRanges(index) == expected.ranges[id], "ranges for \(id)")
        }
    }

    @Test func firstViewportLeavesLaterRowsUnlaid() async throws {
        let graph = try await LayoutTestSupport.graph("many-branches")
        graph.ensureLaid(visibleRows: 0..<10)
        #expect(graph.rowIDList.count < graph.ordering.commitIdx)
        #expect(graph.ids(on: graph.ordering.commitIdx - 1).isEmpty)
    }

    @Test func lateArrivalInvalidatesPreviouslyLaidRows() {
        let ordering = VarcOrdering(store: CommitStore())
        ordering.feed(1, parents: [], date: 500)
        let graph = GraphLayout(ordering: ordering)
        graph.ensureLaid(visibleRows: 0..<1)
        #expect(graph.rowIDList.count == 1)
        ordering.feed(2, parents: [1], date: 400)
        #expect(graph.rowIDList.isEmpty)
        graph.ensureLaid(visibleRows: 0..<2)
        #expect(graph.ids(on: 0) == [ordering.store.index(of: VarcTestSupport.oid(2))])
        #expect(graph.ids(on: 1) == [ordering.store.index(of: VarcTestSupport.oid(1))])
    }
}
