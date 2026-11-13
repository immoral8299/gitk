// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct ViewSpecTests {
    @Test func parseClassifiesArguments() {
        let r = ViewSpec.parseViewArgs(
            ["--all", "--author=x", "-5", "-d", "-p", "--raw", "-n", "3", "a...b", "--merge"])
        #expect(r.dateMode)
        #expect(r.mergeOnly)
        #expect(r.filtered)
        #expect(r.canOpt)
        #expect(r.diffFlags == ["-p"])
        #expect(r.flags == ["--author=x", "-5", "-n", "3"])
        #expect(r.revs == ["--all", "--gitk-symmetric-diff-marker", "a...b",
                           "--gitk-symmetric-diff-marker", "MERGE_HEAD...HEAD"])
        #expect(r.origArgs == ["--all", "--author=x", "-5", "-p", "--raw", "-n", "3", "a...b", "--merge"])
    }

    @Test func unknownOptionDisablesOptimization() {
        let r = ViewSpec.parseViewArgs(["--bogus", "-L1,2:f"])
        #expect(!r.canOpt)
        #expect(r.inlineDiff)
        #expect(r.flags == ["--bogus", "-L1,2:f"])
        #expect(ViewSpec.parseViewArgs(["--color-words"]).wordDiff == "Color words")
        #expect(ViewSpec.parseViewArgs(["--word-diff=plain"]).wordDiff == "Markup words")
        #expect(ViewSpec.parseViewArgs(["--no-replace-objects"]).noReplaceObjects)
        #expect(ViewSpec.parseViewArgs(["-20"]).filtered)
    }

    @Test func argsCmdLinesAreAppended() async throws {
        let repo = try FixtureRepo.make("linear")
        let runner = GitRunner(cwd: repo)
        let spec = ViewSpec(name: "v", args: ["--no-merges"], argsCmd: "printf 'HEAD~1\\nHEAD\\n'")
        // exec drops one trailing newline, so the lines are exactly the two revisions
        let lines = try await ViewSpec.runArgsCmd("printf 'HEAD~1\\nHEAD\\n'", runner: runner)
        #expect(lines == ["HEAD~1", "HEAD"])
        let r = try await spec.resolve(hashLength: 40, runner: runner)
        #expect(r.parsed.revs == ["HEAD~1", "HEAD"])
        #expect(r.logArgs == ["--no-merges"])
        #expect(r.revs.count == 2)
        #expect(r.posIDs.count == 2)
    }

    @Test func mergeOnConflictGivesUnmergedFiles() async throws {
        let repo = try FixtureRepo.make("conflict")
        let runner = GitRunner(cwd: repo)
        let r = try await ViewSpec(name: "v", args: ["--merge"]).resolve(hashLength: 40, runner: runner)
        #expect(r.fileLimit == ["conflict.txt"])
        #expect(r.parsed.mergeOnly)
        #expect(r.posIDs.count == 2)
        let limited = try await ViewSpec(name: "v", args: ["--merge"], files: ["conflict.txt"])
            .resolve(hashLength: 40, runner: runner)
        #expect(limited.fileLimit == ["conflict.txt"])
    }

    @Test func mergeWithPathLimitExcludingConflict() async throws {
        let repo = try FixtureRepo.make("conflict")
        do {
            _ = try await ViewSpec(name: "v", args: ["--merge"], files: ["other.txt"])
                .resolve(hashLength: 40, runner: GitRunner(cwd: repo))
            Issue.record("expected error")
        } catch let e as ViewArgsError {
            #expect(e.message == "No files selected: --merge specified but no unmerged files are within file limit.")
        }
    }

    @Test func mergeWithNoUnmergedFiles() async throws {
        let repo = try FixtureRepo.make("linear")
        do {
            _ = try await ViewSpec(name: "v", args: ["--merge"])
                .resolve(hashLength: 40, runner: GitRunner(cwd: repo))
            Issue.record("expected error")
        } catch let e as ViewArgsError {
            #expect(e.message == "No files selected: --merge specified but no files are unmerged.")
        }
    }

    @Test func unknownRevisionMessage() async throws {
        let repo = try FixtureRepo.make("linear")
        do {
            _ = try await ViewSpec.parseViewRevs(["nope"], hashLength: 40, runner: GitRunner(cwd: repo))
            Issue.record("expected error")
        } catch let e as ViewArgsError {
            #expect(e.prefix == "Error parsing revisions:")
            #expect(e.detail == "unknown revision nope")
        }
    }

    @Test func negativeRevisionsAreSplit() async throws {
        let repo = try FixtureRepo.make("linear")
        let p = try await ViewSpec.parseViewRevs(["HEAD~2..HEAD"], hashLength: 40, runner: GitRunner(cwd: repo))
        #expect(p.posIDs.count == 1)
        #expect(p.negIDs.count == 1)
        #expect(p.revs.count == 2)
        #expect(p.revs[1].hasPrefix("^"))
    }
}
