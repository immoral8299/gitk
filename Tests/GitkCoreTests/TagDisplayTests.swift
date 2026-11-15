// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct TagDisplayTests {
    @Test func annotatedTagShowsTaggerMessageAndObject() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let runner = GitRunner(cwd: repo)
        let info = try await TagInfo.load(name: "v1.0", runner: runner, dateFormat: "%Y-%m-%d %H:%M:%S %z")
        let target = try await runner.run(["rev-parse", "v1.0^{commit}"])
        let targetHex = String(decoding: target.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(info.name == "v1.0")
        #expect(info.isAnnotated)
        #expect(info.object?.hex == targetHex)
        #expect(info.message == "Release 1.0")
        #expect(info.taggerName?.isEmpty == false)
        #expect(info.taggerEmail?.isEmpty == false)
        #expect(info.taggerDate?.isEmpty == false)
    }

    @Test func lightweightTagShowsItsCommitOnly() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let runner = GitRunner(cwd: repo)
        let info = try await TagInfo.load(name: "v0.1", runner: runner)
        let target = try await runner.run(["rev-parse", "v0.1^{commit}"])
        let targetHex = String(decoding: target.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(info.name == "v0.1")
        #expect(!info.isAnnotated)
        #expect(info.object?.hex == targetHex)
        #expect(info.taggerName == nil)
        #expect(info.taggerDate == nil)
        #expect(info.message.isEmpty)
    }

    @Test func unknownTagThrowsGitError() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let runner = GitRunner(cwd: repo)
        do {
            _ = try await TagInfo.load(name: "no-such-tag", runner: runner)
            Issue.record("loading a missing tag should throw")
        } catch {
            #expect(error is GitError)
        }
    }

    @Test func parsesTagObjectHeadersAndMultiLineMessage() {
        let raw = """
        object 0123456789abcdef0123456789abcdef01234567
        type commit
        tag rel
        tagger Jane Doe <jane@example.com> 1700000000 +0200

        Subject line

        Body line one
        Body line two

        """
        let info = TagInfo.parse(name: "rel", raw: raw, dateFormat: "%Y-%m-%d %H:%M:%S %z")

        #expect(info.object?.hex == "0123456789abcdef0123456789abcdef01234567")
        #expect(info.isAnnotated)
        #expect(info.taggerName == "Jane Doe")
        #expect(info.taggerEmail == "jane@example.com")
        // 1700000000 is 2023-11-14 22:13:20 UTC, which is 00:13:20 on the 15th at +0200.
        #expect(info.taggerDate == "2023-11-15 00:13:20 +0200")
        #expect(info.message == "Subject line\n\nBody line one\nBody line two")
    }

    @Test func tagWithoutTaggerOrMessageParses() {
        let raw = "object 0123456789abcdef0123456789abcdef01234567\ntype commit\ntag bare\n"
        let info = TagInfo.parse(name: "bare", raw: raw)

        #expect(info.object != nil)
        #expect(info.taggerName == nil)
        #expect(info.taggerDate == nil)
        #expect(info.message.isEmpty)
    }

    @Test func malformedObjectHeaderYieldsNoObject() {
        let info = TagInfo.parse(name: "bad", raw: "object not-a-hash\ntype commit\ntag bad\n\nmsg\n")

        #expect(info.object == nil)
        #expect(info.message == "msg")
    }
}
