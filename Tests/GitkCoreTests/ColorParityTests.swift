// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct ColorParityTests {
    @Test(arguments: OracleGoldenTests.fixtures)
    func drawingOrderMatchesOracle(_ fixture: String) async throws {
        let layout = try await LayoutTestSupport.graph(fixture)
        let colors = GraphColors(layout: layout)
        for row in stride(from: 0, to: layout.ordering.commitIdx, by: 50) {
            layout.ensureLaid(visibleRows: row..<(row + 50))
        }
        let expected = try OracleGolden.load(fixture)
        let actual = Dictionary(uniqueKeysWithValues: colors.colorMap.map {
            (layout.ordering.store.id(at: $0.key).hex, $0.value)
        })
        #expect(actual == expected.colors)
        LayoutTestSupport.checkRows(layout, expected)
    }

    @Test func straightBranchKeepsColor() async throws {
        let layout = try await LayoutTestSupport.graph("linear")
        let colors = GraphColors(layout: layout)
        layout.ensureLaid(visibleRows: 0..<50)
        #expect(Set(colors.colorMap.values).count == 1)
        #expect(colors.colorMap.count == layout.ordering.commitIdx)
    }
}
