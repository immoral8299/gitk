// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct GraphRowGeometryTests {
    @Test func linearRowsHaveVerticalSegmentsAndColumnZero() async throws {
        let layout = try await LayoutTestSupport.graph("linear")
        let colors = GraphColors(layout: layout)
        layout.ensureLaid(visibleRows: 0..<50)
        for row in 0..<layout.ordering.commitIdx {
            let geometry = try #require(GraphRowGeometry.make(row: row, layout: layout, colors: colors))
            #expect(geometry.dotColumn == 0)
            #expect(geometry.segments.allSatisfy { $0.from.column == 0 && $0.to.column == 0 })
            #expect(geometry.segments.allSatisfy { (0...1).contains($0.from.y) && (0...1).contains($0.to.y) })
            #expect(geometry.arrows.isEmpty)
        }
    }

    @Test func mergeConnectsBothParents() async throws {
        let layout = try await LayoutTestSupport.graph("merge-simple")
        let colors = GraphColors(layout: layout)
        layout.ensureLaid(visibleRows: 0..<50)
        let geometry = try #require(GraphRowGeometry.make(row: 1, layout: layout, colors: colors))
        let parents = Set(layout.parents(1))
        #expect(parents.count == 2)
        #expect(parents.isSubset(of: Set(geometry.segments.map(\.id))))
    }

    @Test func longLinesHavePairedArrowsAtRangeEnds() async throws {
        let layout = try await LayoutTestSupport.graph("long-lines")
        let colors = GraphColors(layout: layout)
        for row in stride(from: 0, to: layout.ordering.commitIdx, by: 50) { layout.ensureLaid(visibleRows: row..<(row + 50)) }
        var arrows: [GraphRowGeometry.Arrow] = []
        for row in 0..<layout.ordering.commitIdx {
            arrows += try #require(GraphRowGeometry.make(row: row, layout: layout, colors: colors)).arrows
        }
        #expect(arrows.contains { $0.direction == .up })
        #expect(arrows.contains { $0.direction == .down })
        for arrow in arrows {
            let geometry = try #require(GraphRowGeometry.make(row: arrow.targetRow, layout: layout, colors: colors))
            #expect(geometry.arrows.contains { $0.id == arrow.id && $0.direction != arrow.direction })
        }
    }

    @Test func graphTextRespectsBothLimits() async throws {
        let layout = try await LayoutTestSupport.graph("many-branches")
        let colors = GraphColors(layout: layout)
        layout.ensureLaid(visibleRows: 0..<50)
        for row in 0..<layout.ordering.commitIdx {
            let geometry = try #require(GraphRowGeometry.make(row: row, layout: layout, colors: colors,
                columnWidth: 1000, maxWidth: 16, maxGraphPct: 50))
            #expect(geometry.textX <= 12 + 16 * 18)
            let narrow = try #require(GraphRowGeometry.make(row: row, layout: layout, colors: colors,
                columnWidth: 100, maxWidth: 16, maxGraphPct: 50))
            #expect(narrow.textX <= 62)
        }
    }

    @Test func headAndLocalChangesHaveDistinctDotStyles() {
        let ordering = VarcOrdering(store: CommitStore())
        ordering.feed(1, parents: [], date: 500)
        let head = ordering.store.intern(VarcTestSupport.oid(1))
        let staged = ordering.store.intern(ObjectID.localStaged(hashLength: 40)!)
        let unstaged = ordering.store.intern(ObjectID.localUnstaged(hashLength: 40)!)
        ordering.insertFakeRow(staged, head)
        ordering.insertFakeRow(unstaged, staged)
        let layout = GraphLayout(ordering: ordering)
        let colors = GraphColors(layout: layout)
        var refs = RefSet()
        refs.mainHeadID = ordering.store.id(at: head)
        #expect(GraphRowGeometry.make(row: 0, layout: layout, colors: colors, refs: refs)?.dotStyle == .unstaged)
        #expect(GraphRowGeometry.make(row: 1, layout: layout, colors: colors, refs: refs)?.dotStyle == .staged)
        #expect(GraphRowGeometry.make(row: 2, layout: layout, colors: colors, refs: refs)?.dotStyle == .mainHead)
    }
}

@Suite struct RefLabelLayoutTests {
    @Test func labelsKeepTagHeadOtherOrderAndRemotePrefix() async throws {
        let layout = try await LayoutTestSupport.graph("linear")
        let colors = GraphColors(layout: layout)
        let id = try #require(layout.ordering.commitOnRow(0))
        let oid = layout.ordering.store.id(at: id)
        var refs = RefSet()
        refs.addTag("v1", oid, peeled: false)
        refs.addHead("main", oid)
        refs.addHead("remotes/origin/main", oid)
        refs.addOtherRef("notes/commits", oid)
        refs.mainHeadName = "main"
        let geometry = try #require(GraphRowGeometry.make(row: 0, layout: layout, colors: colors))
            .addingRefLabels(refs: refs, store: layout.ordering.store, columnWidth: 1000, measure: { text, _ in Double(text.count * 7) })
        #expect(geometry.labels.map(\.kind) == [.tag, .head, .remote, .other])
        #expect(geometry.labels[1].isBold)
        #expect(geometry.labels[2].remotePrefix == "remotes/origin/")
        #expect(geometry.labels[2].text == "remotes/origin/main")
        #expect(geometry.labels[0].x < geometry.labels[1].x)
    }

    @Test func manyTagsOrWideTagsCollapse() async throws {
        let layout = try await LayoutTestSupport.graph("linear")
        let colors = GraphColors(layout: layout)
        let id = try #require(layout.ordering.commitOnRow(0))
        let oid = layout.ordering.store.id(at: id)
        var refs = RefSet()
        for tag in ["v1", "v2", "v3", "v4"] { refs.addTag(tag, oid, peeled: false) }
        let base = try #require(GraphRowGeometry.make(row: 0, layout: layout, colors: colors))
        let many = base.addingRefLabels(refs: refs, store: layout.ordering.store, columnWidth: 1000, measure: { _, _ in 10 })
        #expect(many.labels.count == 1)
        #expect(many.labels[0].kind == .collapsedTags && many.labels[0].tagCount == 4)
        var one = RefSet()
        one.addTag("a-very-wide-tag", oid, peeled: false)
        let wide = base.addingRefLabels(refs: one, store: layout.ordering.store, columnWidth: 100, measure: { _, _ in 100 })
        #expect(wide.labels[0].text == "tag...")
        #expect(wide.labels[0].tagCount == 1)
    }
}
