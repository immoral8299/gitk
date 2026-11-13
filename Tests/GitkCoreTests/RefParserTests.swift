// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RefParserTests {
    private func git(_ repo: URL, _ args: [String]) async throws -> String {
        let o = try await GitRunner(cwd: repo).run(args)
        return String(decoding: o.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func annotatedTagAttachesToCommit() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let refs = await RefParser.load(runner: GitRunner(cwd: repo))
        let commit = try #require(ObjectID(hex: try await git(repo, ["rev-parse", "v1.0^{commit}"])))
        let obj = try #require(ObjectID(hex: try await git(repo, ["rev-parse", "v1.0"])))
        #expect(obj != commit)
        #expect(refs.tagIDs["v1.0"] == commit)
        #expect(refs.tagObjectIDs["v1.0"] == obj)
        #expect(refs.tags(of: commit).contains("v1.0"))
        // lightweight: gitk sets tagobjid for every unpeeled line
        #expect(refs.tagObjectIDs["v0.1"] == refs.tagIDs["v0.1"])
        #expect(refs.tagIDs["v0.1"] != nil)
    }

    @Test func classifiesRefs() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let refs = await RefParser.load(runner: GitRunner(cwd: repo))
        #expect(refs.headIDs["main"] != nil)
        #expect(refs.headIDs["release"] != nil)
        #expect(refs.headIDs["remotes/origin/main"] != nil)
        #expect(refs.headIDs["remotes/origin/release"] != nil)
        #expect(refs.otherRefIDs["notes/commits"] != nil)
        for t in ["t1", "t2", "t3", "t4"] { #expect(refs.tagIDs[t] != nil) }
        #expect(refs.mainHeadName == "main")
        let head = try await git(repo, ["rev-parse", "HEAD"])
        #expect(refs.mainHeadID?.hex == head)
    }

    @Test func detachedHead() async throws {
        let repo = try FixtureRepo.makeCopy("tags-notes")
        _ = try await git(repo, ["checkout", "--detach", "HEAD~1"])
        let refs = await RefParser.load(runner: GitRunner(cwd: repo))
        #expect(refs.mainHeadName == nil)
        let head = try await git(repo, ["rev-parse", "HEAD"])
        #expect(refs.mainHeadID?.hex == head)
    }

    @Test func hideRemotesAndGlobs() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let r = GitRunner(cwd: repo)
        let noRemotes = await RefParser.load(runner: r, hideRemotes: true)
        #expect(noRemotes.headIDs.keys.allSatisfy { !$0.hasPrefix("remotes/") })
        #expect(noRemotes.headIDs["main"] != nil)
        let hidden = await RefParser.load(runner: r, refsToHide: "notes/*  stash")
        #expect(hidden.otherRefIDs["notes/commits"] == nil)
        #expect(hidden.headIDs["remotes/origin/main"] != nil)
        let shown = await RefParser.load(runner: r, refsToHide: "tags/*")
        #expect(shown.otherRefIDs["notes/commits"] != nil)
        let full = await RefParser.load(runner: r)
        let viaParse = await RefParser.load(runner: r, hideRemotes: true, refsToHide: "notes/*")
        #expect(full.filtered(hideRemotes: true, refsToHide: "notes/*") == viaParse)
    }

    @Test func parseSkipsRemoteHEADAndMovesHeads() {
        let a = ObjectID(hex: String(repeating: "a", count: 40))!
        let b = ObjectID(hex: String(repeating: "b", count: 40))!
        let text = """
        \(a) refs/heads/main
        \(a) refs/remotes/origin/HEAD
        \(a) refs/remotes/origin/main
        garbage
        \(b) refs/tags/x
        \(a) refs/tags/x^{}
        """
        var s = RefParser.parse(showRef: Data(text.utf8))
        #expect(s.headIDs["remotes/origin/HEAD"] == nil)
        #expect(s.heads(of: a) == ["main", "remotes/origin/main"])
        #expect(s.tagIDs["x"] == a)
        #expect(s.tagObjectIDs["x"] == b)
        s.moveHead(b, "main")
        #expect(s.heads(of: a) == ["remotes/origin/main"])
        #expect(s.heads(of: b) == ["main"])
        s.removeHead(b, "main")
        #expect(s.idHeads[b] == nil && s.headIDs["main"] == nil)
    }

    @Test func refsToHideGlobs() {
        #expect(RefSet.isOtherRefVisible("stash", refsToHide: ""))
        #expect(!RefSet.isOtherRefVisible("stash", refsToHide: "stash"))
        #expect(!RefSet.isOtherRefVisible("notes/commits", refsToHide: "x notes/*"))
        #expect(RefSet.isOtherRefVisible("notes/commits", refsToHide: "note"))
    }
}
