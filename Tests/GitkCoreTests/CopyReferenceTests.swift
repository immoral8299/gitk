// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct CopyReferenceTests {
    /// HEAD of the `linear` fixture ("Linear commit 10", committed 2020-01-01).
    private static let headHex = "b7729902a3f81cc7da12ad56b4af698ee6ad444c"

    @Test func abbreviatesToCopyLength() async throws {
        let repo = try FixtureRepo.make("linear")
        let actions = RepoActions(repo: repo)
        let id = try #require(ObjectID(hex: Self.headHex))

        let text = try await actions.copyReference(id, abbrevLength: 7, hashLength: 40)
        #expect(text == "b772990 (\"Linear commit 10\", 2020-01-01)")
    }

    @Test func fullLengthPassesNoAbbrevOption() async throws {
        let repo = try FixtureRepo.make("linear")
        let actions = RepoActions(repo: repo)
        let id = try #require(ObjectID(hex: Self.headHex))

        // Equal to the hash length: no --abbrev, so git's default (7 here) is used.
        let text = try await actions.copyReference(id, abbrevLength: 40, hashLength: 40)
        #expect(text == "b772990 (\"Linear commit 10\", 2020-01-01)")
    }

    @Test func longerCopyLengthIsHonoured() async throws {
        let repo = try FixtureRepo.make("linear")
        let actions = RepoActions(repo: repo)
        let id = try #require(ObjectID(hex: Self.headHex))

        let text = try await actions.copyReference(id, abbrevLength: 12, hashLength: 40)
        #expect(text == "b7729902a3f8 (\"Linear commit 10\", 2020-01-01)")
    }
}
