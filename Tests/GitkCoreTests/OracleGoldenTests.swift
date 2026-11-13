// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing

@Suite struct OracleGoldenTests {
    static let fixtures = [
        "linear", "merge-simple", "octopus", "criss-cross", "many-branches",
        "long-lines", "renames", "encodings", "tags-notes", "sha256",
        "local-changes", "conflict", "random-dag",
    ]

    @Test func goldenFilesExistForEveryFixture() throws {
        let names = try OracleGolden.fixtureNames()
        #expect(names == Self.fixtures.sorted())
    }

    @Test(arguments: fixtures) func goldenFileDecodesAndIsConsistent(_ fixture: String) throws {
        let golden = try OracleGolden.load(fixture)
        #expect(!golden.order.isEmpty)
        #expect(golden.rows.count == golden.order.count)
        #expect(golden.rows.map(\.id) == golden.order)
        #expect(Set(golden.ranges.keys) == Set(golden.order))
        #expect(Set(golden.colors.keys) == Set(golden.order))
        for row in golden.rows {
            #expect(row.idlist.indices.contains(row.col))
            #expect(row.idlist[row.col] == row.id)
        }
        #expect(golden.colors.values.allSatisfy { (0..<7).contains($0) })
        let arcs = golden.varcs.varctok.count
        #expect(golden.varcs.varcstart.count == arcs)
        #expect(golden.varcs.varccommits.count == arcs)
        #expect(golden.varcs.vupptr.count == arcs)
        #expect(golden.varcs.varcrow.count == arcs)
    }

    @Test func linearHasOnlyColumnZero() throws {
        let golden = try OracleGolden.load("linear")
        #expect(golden.rows.count == 10)
        #expect(golden.rows.allSatisfy { $0.col == 0 })
    }

    @Test func mergeSimpleSecondParentIsInColumnOne() throws {
        let golden = try OracleGolden.load("merge-simple")
        #expect(golden.rows.map(\.col).contains(1))
        // The second row is the merge; its second parent is the next commit
        // that sits in column 1.
        let secondParent = golden.rows[2]
        #expect(secondParent.col == 1)
    }

    @Test(.enabled(if: OracleRunner.liveAvailable))
    func liveOracleEqualsGolden() throws {
        for fixture in ["linear", "merge-simple", "random-dag"] {
            #expect(try OracleRunner.live(fixture) == OracleGolden.load(fixture), "fixture \(fixture)")
        }
    }

    @Test func runnerResultDecodes() throws {
        let result = try OracleRunner.result(for: "octopus")
        #expect(result.order.count == result.rows.count)
    }
}
