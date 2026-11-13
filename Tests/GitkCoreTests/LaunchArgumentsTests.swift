// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct LaunchArgumentsTests {
    private func parse(_ argv: [String], in repo: URL) async throws -> LaunchArguments {
        try await LaunchArguments.parse(argv: argv, repo: repo, environment: isolatedGitEnvironment())
    }

    @Test func revisionRangeAndPaths() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let a = try await parse(["v1.0..v2.0", "--", "src/"], in: repo)
        #expect(a.revisionArgs == ["v1.0..v2.0"])
        #expect(a.paths == ["src/"])
        #expect(a.selectCommit == nil)
        #expect(a.argsCmd == nil)
    }

    @Test func selectCommit() async throws {
        let repo = try FixtureRepo.make("linear")
        let a = try await parse(["--select-commit=abc123"], in: repo)
        #expect(a.selectCommit == "abc123")
        #expect(a.revisionArgs.isEmpty)
        #expect(a.paths.isEmpty)
    }

    @Test func headAsSelectCommit() async throws {
        let repo = try FixtureRepo.make("linear")
        let a = try await parse(["--select-commit=HEAD"], in: repo)
        #expect(a.selectCommit == nil)
    }

    @Test func argsCommandAndEmptyArguments() async throws {
        let repo = try FixtureRepo.make("linear")
        let a = try await parse(["", "--argscmd=echo hi", "", "--", "", "x"], in: repo)
        #expect(a.argsCmd == "echo hi")
        #expect(a.revisionArgs.isEmpty)
        #expect(a.paths == ["", "x"])
    }

    @Test func bareRevisionAndPath() async throws {
        let repo = try FixtureRepo.make("linear")
        let a = try await parse(["HEAD~2", "f1.txt"], in: repo)
        #expect(a.revisionArgs == ["HEAD~2"])
        #expect(a.paths == ["f1.txt"])
    }

    @Test func barePathArgument() async throws {
        let repo = try FixtureRepo.make("linear")
        let a = try await parse(["f1.txt"], in: repo)
        #expect(a.revisionArgs.isEmpty)
        #expect(a.paths == ["f1.txt"])
    }

    @Test func onlyRevisionHasNoPaths() async throws {
        let repo = try FixtureRepo.make("linear")
        let a = try await parse(["--all", "main"], in: repo)
        #expect(a.revisionArgs == ["--all", "main"])
        #expect(a.paths.isEmpty)
    }

    @Test func ambiguousArgument() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        try Data().write(to: repo.appendingPathComponent("main"))
        await #expect(throws: LaunchArgumentsError.ambiguousArgument("main")) {
            _ = try await parse(["main"], in: repo)
        }
        let e = LaunchArgumentsError.ambiguousArgument("main")
        #expect(e.msgid == "Ambiguous argument '%s': both revision and filename")
        #expect(e.arguments == ["main"])
    }

    @Test func badRevision() async throws {
        let repo = try FixtureRepo.make("linear")
        do {
            _ = try await parse(["no-such-rev"], in: repo)
            Issue.record("expected an error")
        } catch let e as LaunchArgumentsError {
            guard case .badArguments(let text) = e else {
                Issue.record("wrong error \(e)")
                return
            }
            #expect(e.msgid == "Bad arguments to gitk:")
            #expect(!text.contains("fatal:"))
            #expect(text.contains("ambiguous argument 'no-such-rev'"))
            #expect(!text.hasSuffix("\n"))
        }
    }
}
