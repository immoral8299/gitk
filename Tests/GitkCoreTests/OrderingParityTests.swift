// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct OrderingParityTests {
    static func load(_ fixture: String, args: [String] = []) async throws -> VarcOrdering {
        let repo = try FixtureRepo.make(fixture)
        let runner = GitRunner(cwd: repo)
        let hashLength = fixture == "sha256" ? 64 : 40
        let resolved = try await ViewSpec(name: "Test", args: args).resolve(
            hashLength: hashLength, runner: runner)
        let input = Data((resolved.revs + ["--"] + resolved.fileLimit).joined(separator: "\n").utf8)
        let output = try await runner.run(
            ["log", "--no-color", "-z", "--pretty=raw", "--show-notes", "--parents", "--boundary"]
                + resolved.logArgs + ["--stdin"], stdin: input)
        let ordering = VarcOrdering(store: CommitStore(), hashLength: hashLength)
        ordering.vdateMode = resolved.parsed.dateMode
        for record in output.stdout.split(separator: 0, omittingEmptySubsequences: true) {
            ordering.add(try RawLogParser.parse(record: Data(record), hashLength: hashLength))
        }
        ordering.closeVarcs()
        ordering.chewCommits()
        return ordering
    }

    static func compare(_ ordering: VarcOrdering, _ expected: OracleResult) {
        let actual = (0..<ordering.commitIdx).compactMap { ordering.commitOnRow($0) }
            .map { ordering.store.id(at: $0).hex }
        #expect(actual == expected.order)
        func hex(_ id: CommitIndex?) -> String { id.map { ordering.store.id(at: $0).hex } ?? "" }
        let arcs = expected.varcs
        #expect(ordering.varcStart.map(hex) == arcs.varcstart)
        #expect(ordering.varcCommits.map { $0.map { hex($0) } } == arcs.varccommits)
        #expect(ordering.varcTok == arcs.varctok)
        #expect(ordering.vupPtr == arcs.vupptr)
        #expect(ordering.vdownPtr == arcs.vdownptr)
        #expect(ordering.vleftPtr == arcs.vleftptr)
        #expect(ordering.vbackPtr == arcs.vbackptr)
        #expect(ordering.varcRow == arcs.varcrow)
        for row in 0..<ordering.commitIdx {
            guard let commit = ordering.commitOnRow(row) else { continue }
            #expect(ordering.rowOfCommit(commit) == row)
            for parent in ordering.parents[commit] ?? [] {
                #expect((ordering.rowOfCommit(parent) ?? -1) > row)
            }
        }
    }

    @Test(arguments: OracleGoldenTests.fixtures)
    func fixtureOrderingAndArcTables(_ fixture: String) async throws {
        let args = fixture == "random-dag" ? ["--all"] : []
        let ordering = try await Self.load(fixture, args: args)
        Self.compare(ordering, try OracleRunner.result(for: fixture))
    }

    @Test(.enabled(if: OracleRunner.liveAvailable), arguments: ["merge-simple", "criss-cross", "many-branches", "random-dag"])
    func allBranchesAndDateOrder(_ fixture: String) async throws {
        let repo = try FixtureRepo.make(fixture)
        let tclsh = try #require(OracleRunner.tclshURL)
        for args in [["--all"], ["--date-order", "--all"]] {
            let output = try await ProcessRunner().run(executable: tclsh, arguments:
                [OracleRunner.oracleScript.path, "--repo", repo.path] + args)
            #expect(output.status == 0, "\(output.stderrText)")
            let expected = try JSONDecoder().decode(OracleResult.self, from: output.stdout)
            Self.compare(try await Self.load(fixture, args: args), expected)
        }
    }

    @Test func duplicateAndBoundaryRecordsDoNotReplaceListedCommits() {
        let ordering = VarcOrdering(store: CommitStore())
        let commit = VarcTestSupport.commit(1, parents: [2], date: 500)
        ordering.add(commit)
        ordering.add(commit)
        var boundary = commit
        boundary.isBoundary = true
        ordering.add(boundary)
        #expect(ordering.commitIdx == 1)
        let id = ordering.store.index(of: commit.id)
        #expect(id.flatMap { ordering.parents[$0] }?.count == 1)
        ordering.closeVarcs()
        #expect(ordering.commitIdx == 2)
    }

    @Test func lateChildKeepsSelectedParent() {
        let ordering = VarcOrdering(store: CommitStore())
        let parent = VarcTestSupport.commit(1, date: 500)
        ordering.add(parent)
        ordering.currentID = ordering.store.index(of: parent.id)
        ordering.chewCommits()
        #expect(ordering.selectedLine == 0)
        ordering.add(VarcTestSupport.commit(2, parents: [1], date: 400))
        ordering.chewCommits()
        #expect(ordering.currentID == ordering.store.index(of: parent.id))
        #expect(ordering.selectedLine == 1)
    }
}
