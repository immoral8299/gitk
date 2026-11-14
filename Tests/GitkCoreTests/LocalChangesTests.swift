// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct LocalChangesTests {
    @Test func stagedAndUnstagedRespectPathsAndDisappearAfterCommit() async throws {
        let repo = try FixtureRepo.makeCopy("local-changes")
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = GitRunner(cwd: repo)
        let context = try await RepoContext.discover(cwd: repo)
        #expect(try await LocalChanges.read(repo: context, files: [], runner: runner)
                == LocalChanges(staged: true, unstaged: true))
        #expect(try await LocalChanges.read(repo: context, files: ["missing-dir/"], runner: runner)
                == LocalChanges())
        _ = try await runner.run(["add", "."])
        _ = try await runner.run(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "resolved"])
        #expect(try await LocalChanges.read(repo: context, files: [], runner: runner) == LocalChanges())
    }

    @Test func syntheticRowsConnectWorktreeToIndexToHead() async throws {
        let repo = try FixtureRepo.make("linear")
        let runner = GitRunner(cwd: repo)
        let out = try await runner.run(["log", "-1", "--pretty=raw", "--parents"])
        let head = try RawLogParser.parse(record: out.stdout)
        let rows = LocalChanges(staged: true, unstaged: true).commits(head: head.id, tree: head.tree, hashLength: 40)
        #expect(rows.count == 2)
        #expect(rows[0].parents == [head.id])
        #expect(rows[1].parents == [rows[0].id])
        let store = CommitStore()
        let ordering = VarcOrdering(store: store, hashLength: 40)
        ordering.add(head)
        ordering.closeVarcs()
        for row in rows {
            let index = store.insert(row)
            ordering.insertFakeRow(index, store.intern(row.parents[0]))
        }
        #expect((0..<3).compactMap { ordering.commitOnRow($0) }.map { store.id(at: $0) }
                == [rows[1].id, rows[0].id, head.id])
    }

    @Test func bareHasNoRows() async throws {
        let source = try FixtureRepo.make("linear")
        let bare = FileManager.default.temporaryDirectory.appendingPathComponent("gitk-bare-\(UUID())")
        defer { try? FileManager.default.removeItem(at: bare) }
        _ = try await GitRunner().run(["clone", "--bare", source.path, bare.path])
        let context = try await RepoContext.discover(cwd: bare)
        #expect(try await LocalChanges.read(repo: context, files: [], runner: GitRunner(cwd: bare)) == LocalChanges())
    }
}
