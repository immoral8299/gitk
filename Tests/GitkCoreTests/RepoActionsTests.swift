// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RepoActionsTests {
    private static let ident = ["-c", "user.name=T", "-c", "user.email=t@example.com"]

    @discardableResult
    private func git(_ repo: URL, _ args: [String]) async throws -> String {
        let out = try await GitRunner(cwd: repo).run(Self.ident + args)
        return String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ repo: URL, _ name: String, _ text: String) throws {
        try text.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func commitFile(_ repo: URL, _ name: String, _ text: String, _ msg: String) async throws -> String {
        try write(repo, name, text)
        try await git(repo, ["add", name])
        try await git(repo, ["commit", "-q", "-m", msg])
        return try await git(repo, ["rev-parse", "HEAD"])
    }

    /// `linear` plus branch `side` (edits x.txt line 2) and `main` (edits the same line differently).
    private func conflictingRepo() async throws -> (repo: URL, side: String, main: String) {
        let repo = try FixtureRepo.makeCopy("linear")
        let base = try await commitFile(repo, "x.txt", "a\nb\nc\n", "base x")
        try await git(repo, ["checkout", "-q", "-b", "side"])
        let side = try await commitFile(repo, "x.txt", "a\nSIDE\nc\n", "side edit")
        try await git(repo, ["checkout", "-q", "main"])
        let main = try await commitFile(repo, "x.txt", "a\nMAIN\nc\n", "main edit")
        #expect(base != main)
        return (repo, side, main)
    }

    // MARK: branches

    @Test func createRenameDeleteBranch() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        let head = try await git(repo, ["rev-parse", "HEAD"])
        let parent = try await git(repo, ["rev-parse", "HEAD~1"])

        try await actions.createBranch(name: "topic", at: head)
        #expect(try await git(repo, ["rev-parse", "topic"]) == head)

        // Overwriting needs force.
        await #expect(throws: RepoActionError.self) {
            try await actions.createBranch(name: "topic", at: parent)
        }
        try await actions.createBranch(name: "topic", at: parent, force: true)
        #expect(try await git(repo, ["rev-parse", "topic"]) == parent)

        try await actions.renameBranch(from: "topic", to: "topic2")
        #expect(try await git(repo, ["branch", "--list", "topic*", "--format=%(refname:short)"]) == "topic2")

        try await actions.deleteBranch("topic2")
        #expect(try await git(repo, ["branch", "--list", "topic*"]) == "")
    }

    @Test func branchFailuresCarryStderr() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        do {
            try await actions.deleteBranch("nonexistent")
            Issue.record("expected failure")
        } catch RepoActionError.git(let e) {
            #expect(e.args == ["branch", "-D", "nonexistent"])
            #expect(!e.stderr.isEmpty)
        }
        do {
            try await actions.renameBranch(from: "nonexistent", to: "x")
            Issue.record("expected failure")
        } catch RepoActionError.git(let e) {
            #expect(!e.stderr.isEmpty)
        }
    }

    // MARK: tags

    @Test func createLightweightAndAnnotatedTag() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        let head = try await git(repo, ["rev-parse", "HEAD"])

        try await actions.createTag(name: "light", at: head)
        #expect(try await git(repo, ["cat-file", "-t", "light"]) == "commit")

        try await actions.createTag(name: "v2.0", at: head, message: "Release 2.0")
        #expect(try await git(repo, ["cat-file", "-t", "v2.0"]) == "tag")
        #expect(try await git(repo, ["tag", "-n1", "--list", "v2.0"]).contains("Release 2.0"))
        #expect(try await git(repo, ["rev-parse", "v2.0^{commit}"]) == head)
    }

    @Test func duplicateTagFails() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        try await actions.createTag(name: "t", at: "HEAD")
        await #expect(throws: RepoActionError.self) {
            try await actions.createTag(name: "t", at: "HEAD")
        }
    }

    // MARK: checkout and reset

    @Test func checkoutBranchAndRemoteTrack() async throws {
        let repo = try FixtureRepo.makeCopy("tags-notes")
        let actions = RepoActions(repo: repo)
        #expect(try await actions.checkout(head: "release") == "release")
        #expect(try await git(repo, ["symbolic-ref", "--short", "HEAD"]) == "release")

        // A local "main" exists, so tracking remotes/origin/main is refused.
        await #expect(throws: RepoActionError.localBranchExists("main")) {
            try await actions.checkout(head: "remotes/origin/main", localHeads: ["main"])
        }
        // With the local "release" gone, remotes/origin/release creates it.
        try await git(repo, ["checkout", "-q", "main"])
        try await git(repo, ["branch", "-D", "release"])
        try await git(repo, ["config", "remote.origin.url", "https://example.invalid/r.git"])
        try await git(repo, ["config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"])
        #expect(try await actions.checkout(head: "remotes/origin/release") == "release")
        #expect(try await git(repo, ["symbolic-ref", "--short", "HEAD"]) == "release")
        #expect(try await git(repo, ["config", "branch.release.remote"]) == "origin")
    }

    @Test func checkoutFailsWithLocalChanges() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        let first = try await git(repo, ["rev-list", "--max-parents=0", "HEAD"])
        let file = try await git(repo, ["ls-tree", "--name-only", "HEAD"]).split(separator: "\n").first.map(String.init) ?? ""
        try await git(repo, ["checkout", "-q", "-b", "other", first])
        try await git(repo, ["checkout", "-q", "main"])
        let headBefore = try await git(repo, ["rev-parse", "HEAD"])
        // Make `other` differ from main in `file`, then dirty it on main.
        try await git(repo, ["checkout", "-q", "other"])
        _ = try await commitFile(repo, file, "other content\n", "other edit")
        try await git(repo, ["checkout", "-q", "main"])
        try write(repo, file, "dirty\n")
        do {
            try await actions.checkout(head: "other")
            Issue.record("expected failure")
        } catch RepoActionError.git(let e) {
            #expect(e.stderr.contains(file))
        }
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == headBefore)
        #expect(try await git(repo, ["symbolic-ref", "--short", "HEAD"]) == "main")
    }

    @Test func resetSoftMixedHard() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        let head = try await git(repo, ["rev-parse", "HEAD"])
        let p1 = try await git(repo, ["rev-parse", "HEAD~1"])
        let p2 = try await git(repo, ["rev-parse", "HEAD~2"])
        let p3 = try await git(repo, ["rev-parse", "HEAD~3"])

        try await actions.reset(to: p1, type: .soft)
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == p1)
        #expect(!(try await git(repo, ["diff", "--cached", "--name-only"])).isEmpty)

        try await actions.reset(to: p2, type: .mixed)
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == p2)
        #expect(try await git(repo, ["diff", "--cached", "--name-only"]) == "")
        #expect(!(try await git(repo, ["diff", "--name-only"])).isEmpty)

        try await actions.reset(to: p3, type: .hard)
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == p3)
        #expect(try await git(repo, ["status", "--porcelain", "--untracked-files=no"]) == "")
        #expect(p3 != head)
    }

    @Test func resetToBadIDFails() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        do {
            try await RepoActions(repo: repo).reset(to: "deadbeef", type: .hard)
            Issue.record("expected failure")
        } catch RepoActionError.git(let e) {
            #expect(e.args == ["reset", "--hard", "deadbeef"])
            #expect(!e.stderr.isEmpty)
        }
    }

    // MARK: cherry-pick and revert

    @Test func cherryPickSuccess() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        let old = try await git(repo, ["rev-parse", "HEAD"])
        try await git(repo, ["checkout", "-q", "-b", "side"])
        let picked = try await commitFile(repo, "new.txt", "new\n", "side add")
        try await git(repo, ["checkout", "-q", "main"])

        let outcome = try await actions.cherryPick(picked)
        guard case .committed(let oldHead, let newHead) = outcome else {
            Issue.record("expected committed, got \(outcome)")
            return
        }
        #expect(oldHead == old)
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == newHead)
        #expect(try await git(repo, ["rev-parse", "HEAD~1"]) == old)
        #expect(try await git(repo, ["log", "-1", "--format=%s"]) == "side add")
    }

    @Test func cherryPickConflict() async throws {
        let (repo, side, _) = try await conflictingRepo()
        do {
            _ = try await RepoActions(repo: repo).cherryPick(side)
            Issue.record("expected conflict")
        } catch RepoActionError.conflict(let output) {
            #expect(output.contains("CONFLICT"))
        }
    }

    @Test func cherryPickLocalChanges() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        _ = try await commitFile(repo, "x.txt", "a\nb\nc\n", "base x")
        try await git(repo, ["checkout", "-q", "-b", "side"])
        let side = try await commitFile(repo, "x.txt", "a\nSIDE\nc\n", "side edit")
        try await git(repo, ["checkout", "-q", "main"])
        try write(repo, "x.txt", "a\nb\nc\ndirty\n")
        do {
            _ = try await RepoActions(repo: repo).cherryPick(side)
            Issue.record("expected local-changes failure")
        } catch RepoActionError.localChanges(let files, let output) {
            #expect(files == ["x.txt"])
            #expect(output.contains("x.txt"))
        }
    }

    @Test func cherryPickNoChanges() async throws {
        // Picking a commit whose change is already in HEAD: git applies it
        // cleanly but, with an empty result, refuses to commit.
        let repo = try FixtureRepo.makeCopy("linear")
        _ = try await commitFile(repo, "x.txt", "a\n", "base x")
        try await git(repo, ["checkout", "-q", "-b", "side"])
        let side = try await commitFile(repo, "x.txt", "a\nb\n", "side edit")
        try await git(repo, ["checkout", "-q", "main"])
        _ = try await commitFile(repo, "x.txt", "a\nb\n", "same edit")
        let head = try await git(repo, ["rev-parse", "HEAD"])
        do {
            let outcome = try await RepoActions(repo: repo).cherryPick(side)
            #expect(outcome == .noChanges)
        } catch RepoActionError.git {
            // Older/newer git versions stop with "The previous cherry-pick is now empty".
        }
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == head)
    }

    @Test func revertSuccessAndNoChangesFree() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let old = try await git(repo, ["rev-parse", "HEAD"])
        let outcome = try await RepoActions(repo: repo).revert(old)
        guard case .committed(let oldHead, let newHead) = outcome else {
            Issue.record("expected committed, got \(outcome)")
            return
        }
        #expect(oldHead == old)
        #expect(try await git(repo, ["rev-parse", "HEAD~1"]) == old)
        #expect(try await git(repo, ["rev-parse", "HEAD"]) == newHead)
        #expect(try await git(repo, ["log", "-1", "--format=%s"]).hasPrefix("Revert"))
    }

    @Test func revertConflict() async throws {
        let (repo, side, _) = try await conflictingRepo()
        // Reverting the base-to-main change after `side` landed: revert the main edit
        // on a tree where the same line has changed again.
        try await git(repo, ["merge", "-q", "--no-edit", "-X", "theirs", side])
        _ = try await commitFile(repo, "x.txt", "a\nLATER\nc\n", "later edit")
        let mainEdit = try await git(repo, ["log", "--format=%H", "--grep=main edit", "-1"])
        do {
            _ = try await RepoActions(repo: repo).revert(mainEdit)
            Issue.record("expected conflict")
        } catch RepoActionError.conflict(let output) {
            #expect(output.contains("could not revert"))
        }
    }

    @Test func revertLocalChanges() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let touched = try await git(repo, ["diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"])
            .split(separator: "\n").map(String.init)
        let file = try #require(touched.first)
        try write(repo, file, "dirty\n")
        do {
            _ = try await RepoActions(repo: repo).revert("HEAD")
            Issue.record("expected local-changes failure")
        } catch RepoActionError.localChanges(let files, _) {
            #expect(files == [file])
        }
    }

    // MARK: patches

    @Test func patchIDMatchesAcrossCherryPick() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        try await git(repo, ["checkout", "-q", "-b", "side"])
        let original = try await commitFile(repo, "new.txt", "new\n", "side add")
        try await git(repo, ["checkout", "-q", "main"])
        _ = try await actions.cherryPick(original)
        let copy = try await git(repo, ["rev-parse", "HEAD"])
        #expect(copy != original)

        let a = try await actions.patchID(of: original)
        let b = try await actions.patchID(of: copy)
        #expect(a.count == 40)
        #expect(a == b)
        let other = try await actions.patchID(of: "HEAD~1")
        #expect(other != a)
    }

    @Test func patchIDOfBadIDFails() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        await #expect(throws: RepoActionError.self) {
            _ = try await RepoActions(repo: repo).patchID(of: "nope")
        }
    }

    @Test func makePatchAppliesAndReverses() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let actions = RepoActions(repo: repo)
        let head = try await git(repo, ["rev-parse", "HEAD"])
        let parent = try await git(repo, ["rev-parse", "HEAD~1"])

        let forward = try await actions.makePatch(from: parent, to: head)
        #expect(!forward.isEmpty)
        let reversed = try await actions.makePatch(from: parent, to: head, reverse: true)
        #expect(reversed == (try await actions.makePatch(from: head, to: parent)))
        #expect(reversed != forward)

        // Both patches apply to HEAD's tree: the reverse one directly, the forward one with -R.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repoactions-patch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fwdFile = dir.appendingPathComponent("f.patch")
        let revFile = dir.appendingPathComponent("r.patch")
        try forward.write(to: fwdFile)
        try reversed.write(to: revFile)
        try await git(repo, ["apply", "--check", "-R", fwdFile.path])
        try await git(repo, ["apply", "--check", revFile.path])
    }
}
