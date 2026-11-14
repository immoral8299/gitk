// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkUI
@testable import GitkCore

@Suite struct RefLabelHitTests {
    @Test @MainActor func adjacentLabelsUseHalfOpenBounds() throws {
        let oid = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let record = "commit \(oid.hex)\ntree \(String(repeating: "b", count: 40))\nauthor A <a@x> 1234567890 +0000\ncommitter A <a@x> 1234567890 +0000\n\n    Subject\n"
        let store = CommitStore()
        let ordering = VarcOrdering(store: store)
        ordering.add(try RawLogParser.parse(record: Data(record.utf8), hashLength: 40))
        let layout = GraphLayout(ordering: ordering)
        let colors = GraphColors(layout: layout)
        var refs = RefSet()
        refs.addHead("main", oid)
        refs.addTag("v1", oid, peeled: false)
        let geometry = try #require(GraphRowGeometry.make(row: 0, layout: layout, colors: colors))
            .addingRefLabels(refs: refs, store: store, columnWidth: 1000, measure: { _, _ in 20 })
        let tag = try #require(geometry.labels.first)
        let head = try #require(geometry.labels.last)
        #expect(RefLabelDrawing.hitTest(tag.x - 1, labels: geometry.labels) == nil)
        #expect(RefLabelDrawing.hitTest(tag.x, labels: geometry.labels)?.kind == .tag)
        #expect(RefLabelDrawing.hitTest(head.x, labels: geometry.labels)?.kind == .head)
        #expect(RefLabelDrawing.hitTest(head.x + head.width, labels: geometry.labels) == nil)
    }
}
