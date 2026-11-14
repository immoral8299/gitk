// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct CoreDumpParityTests {
    @Test(arguments: OracleGoldenTests.fixtures)
    @MainActor func fullSessionMatchesGolden(_ fixture: String) async throws {
        let repo = try FixtureRepo.make(fixture)
        let args = fixture == "random-dag" ? ["--all"] : []
        let data = try await CoreDump.run(repoURL: repo, args: args)
        let actual = try JSONDecoder().decode(OracleResult.self, from: data)
        #expect(actual == (try OracleGolden.load(fixture)))
    }
}
