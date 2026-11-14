// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RepositoryArgumentTests {
    private func emptyDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gitk-repoarg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func repositoryRootFromOutsideARepository() async throws {
        let repo = try FixtureRepo.make("linear")
        let outside = try emptyDirectory()
        let result = await RepositoryArgument.extract([repo.path, "--all"], cwd: outside)
        #expect(result.cwd.resolvingSymlinksInPath() == repo.resolvingSymlinksInPath())
        #expect(result.arguments == ["--all"])
    }

    @Test func relativeRepositoryRootFromAnotherRepository() async throws {
        let repo = try FixtureRepo.make("linear")
        // A second repository next to the fixture, so "../<fixture>" reaches it.
        let other = repo.deletingLastPathComponent().appendingPathComponent("other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try await GitRunner(cwd: other).run(["init", "-q"])
        let result = await RepositoryArgument.extract(["../" + repo.lastPathComponent], cwd: other)
        #expect(result.cwd.resolvingSymlinksInPath() == repo.resolvingSymlinksInPath())
        #expect(result.arguments.isEmpty)
    }

    /// A subdirectory of the current repository is a path limit, as in `gitk src/`.
    @Test func subdirectoryOfCurrentRepositoryStaysAPath() async throws {
        let repo = try FixtureRepo.make("linear")
        let sub = repo.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let result = await RepositoryArgument.extract(["sub"], cwd: repo)
        #expect(result.cwd == repo)
        #expect(result.arguments == ["sub"])
    }

    @Test func revisionsOptionsAndPlainDirectoriesAreLeftAlone() async throws {
        let repo = try FixtureRepo.make("linear")
        let outside = try emptyDirectory()
        for args in [["HEAD~2"], ["--all"], ["--", repo.path], [outside.path]] {
            let result = await RepositoryArgument.extract(args, cwd: repo)
            #expect(result.cwd == repo)
            #expect(result.arguments == args)
        }
    }
}
