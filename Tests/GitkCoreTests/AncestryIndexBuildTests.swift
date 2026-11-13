// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct AncestryIndexBuildTests {
    static let fixtures = [
        "linear", "merge-simple", "octopus", "criss-cross", "many-branches",
        "long-lines", "renames", "encodings", "tags-notes", "sha256",
        "local-changes", "conflict",
    ]

    // MARK: helpers

    /// A 40-digit id made from a small number, for hand-built graphs.
    static func oid(_ n: Int) -> ObjectID {
        ObjectID(hex: String(repeating: "0", count: 30) + String(format: "%010x", n))!
    }

    static func line(_ n: Int, _ parents: Int...) -> AncestryLine {
        AncestryLine(id: oid(n), parents: parents.map(oid))
    }

    /// Everything the oracle dumps, read from an index.
    static func snapshot(_ index: AncestryIndex) -> OracleAllCommits {
        var arcs: [OracleAllCommits.Arc] = []
        if index.nextArc >= 1 {
            for a in 1...index.nextArc {
                arcs.append(.init(
                    a: a,
                    start: index.arcStart(a)?.hex ?? "",
                    end: index.arcEnd(a)?.hex,
                    ids: index.arcIDs(a).map(\.hex),
                    growing: index.isGrowing(a),
                    tags: index.arcTags(a).map(\.hex),
                    heads: index.arcHeads(a).map(\.hex)))
            }
        }
        var allParents: [String: [String]] = [:]
        var allChildren: [String: [String]] = [:]
        var arcNos: [String: [Int]] = [:]
        var arcOut: [String: [Int]] = [:]
        for id in index.ids {
            if let v = index.allParents(of: id) { allParents[id.hex] = v.map(\.hex) }
            if let v = index.allChildren(of: id) { allChildren[id.hex] = v.map(\.hex) }
            if let v = index.arcNos(of: id) { arcNos[id.hex] = v }
            if let v = index.arcOut(of: id) { arcOut[id.hex] = v }
        }
        return OracleAllCommits(
            allchildren: allChildren, allcommits: index.allCommits ?? -1,
            allparents: allParents, arcnos: arcNos, arcout: arcOut, arcs: arcs,
            nextarc: index.nextArc, seeds: index.seedIDs.map(\.hex))
    }

    static func git(_ repo: URL, _ args: [String]) async throws -> Data {
        try await GitRunner(cwd: repo).run(args).stdout
    }

    /// Builds an index the way the app does: refs from `show-ref`, then
    /// `load(runner:)`.
    @MainActor
    static func loaded(_ fixture: String) async throws -> AncestryIndex {
        let repo = try FixtureRepo.make(fixture)
        let runner = GitRunner(cwd: repo)
        let index = AncestryIndex(refs: await RefParser.load(runner: runner))
        let result = try await index.load(runner: runner)
        #expect(result == AncestryFinish(saveCache: true))
        return index
    }

    // MARK: oracle parity

    @Test(.enabled(if: OracleRunner.liveAvailable), arguments: fixtures)
    @MainActor
    func arcTablesEqualOracle(_ fixture: String) async throws {
        let expected = try OracleRunner.liveAllCommits(fixture)
        let actual = Self.snapshot(try await Self.loaded(fixture))
        #expect(actual.nextarc == expected.nextarc, "nextarc of \(fixture)")
        #expect(actual.seeds == expected.seeds, "seeds of \(fixture)")
        #expect(actual.allcommits == expected.allcommits)
        #expect(actual.arcs == expected.arcs, "arcs of \(fixture)")
        #expect(actual.arcout == expected.arcout, "arcout of \(fixture)")
        #expect(actual.arcnos == expected.arcnos, "arcnos of \(fixture)")
        #expect(actual.allparents == expected.allparents)
        #expect(actual.allchildren == expected.allchildren)
    }

    @Test(.enabled(if: OracleRunner.liveAvailable))
    @MainActor
    func mergeSimpleHasThreeArcs() async throws {
        // f27 -> 8c4 (merge) -> {f93.., 7b6..} -> 031: arc 1 ends at the merge,
        // arcs 2 and 3 run to the root.
        let oracle = try OracleRunner.liveAllCommits("merge-simple")
        let index = try await Self.loaded("merge-simple")
        #expect(index.nextArc == 3)
        #expect(oracle.nextarc == 3)
        #expect(index.arcStart(1)?.hex == oracle.arcs[0].start)
        #expect(index.arcEnd(1)?.hex == oracle.arcs[0].end)
        #expect(index.arcOut(of: try #require(index.arcEnd(1))) == [2, 3])
    }

    @Test(.enabled(if: OracleRunner.liveAvailable))
    @MainActor
    func crissCrossEndpointsEqualOracle() async throws {
        let oracle = try OracleRunner.liveAllCommits("criss-cross")
        let index = try await Self.loaded("criss-cross")
        #expect(index.nextArc == oracle.nextarc)
        for arc in oracle.arcs {
            #expect(index.arcStart(arc.a)?.hex == arc.start)
            #expect(index.arcEnd(arc.a)?.hex == arc.end)
        }
    }

    // MARK: invariants that hold on every fixture (no tclsh needed)

    @Test(arguments: fixtures)
    @MainActor
    func arcsAreConsistentWithRevList(_ fixture: String) async throws {
        let repo = try FixtureRepo.make(fixture)
        let listing = try await Self.git(repo, ["rev-list", "--parents", "--all"])
        let lines = listing.split(separator: 0x0A).compactMap { AncestryLine.parse(Data($0)) }
        let index = try await Self.loaded(fixture)
        try Self.checkConsistent(index, lines)
    }

    /// Structural invariants of a finished index for the given rev-list lines.
    static func checkConsistent(_ index: AncestryIndex, _ lines: [AncestryLine]) throws {
        #expect(index.commitCount == lines.count)
        #expect(index.isComplete)
        for line in lines {
            #expect(index.allParents(of: line.id) == line.parents)
        }
        for a in stride(from: 1, through: index.nextArc, by: 1) {
            let start = try #require(index.arcStart(a))
            let end = try #require(index.arcEnd(a))
            #expect(!index.isGrowing(a))
            // The ids walk down the parent chain from the start to the end,
            // and every id but the end has one parent and one child.
            let ids = index.arcIDs(a)
            #expect(ids.last == end)
            var previous = start
            for id in ids {
                #expect(index.allParents(of: previous)?.contains(id) == true)
                previous = id
            }
            for id in ids.dropLast() {
                #expect(index.allParents(of: id)?.count == 1)
                #expect(index.allChildren(of: id)?.count == 1)
                #expect(index.arcNos(of: id) == [a])
            }
            #expect(index.arcOut(of: start)?.contains(a) == true)
        }
    }

    @Test @MainActor func tagsNotesArcsRecordTags() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let index = try await Self.loaded("tags-notes")
        let refs = await RefParser.load(runner: GitRunner(cwd: repo))
        var tagged: [ObjectID] = []
        if index.nextArc >= 1 {
            for a in 1...index.nextArc { tagged += index.arcTags(a) }
        }
        #expect(!tagged.isEmpty)
        for id in tagged {
            #expect(refs.idTags[id] != nil)
        }
    }

    // MARK: hand-built graphs

    /// Linear chain 4 -> 3 -> 2 -> 1 (4 is the tip), given tip first.
    @Test func linearChainIsOneArc() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        index.add(Self.line(4, 3))
        index.add(Self.line(3, 2))
        index.add(Self.line(2, 1))
        index.add(Self.line(1))
        _ = index.finish(error: nil)
        #expect(index.nextArc == 1)
        #expect(index.arcStart(1) == Self.oid(4))
        #expect(index.arcEnd(1) == Self.oid(1))
        #expect(index.arcIDs(1) == [Self.oid(3), Self.oid(2), Self.oid(1)])
        #expect(index.seedIDs == [Self.oid(4)])
        #expect(index.arcOut(of: Self.oid(1)) == [])
        #expect(index.arcOut(of: Self.oid(4)) == [1])
    }

    @Test func duplicateLinesAreIgnored() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        index.add(Self.line(2, 1))
        index.add(Self.line(2, 1))
        index.add(Self.line(1))
        #expect(index.nextArc == 1)
        #expect(index.commitCount == 2)
    }

    /// 5 and 4 both have parent 3; 3 -> 2 -> 1. The second child of 3 forces
    /// `splitarc` at 3, which also moves the tail's ownership and recomputes
    /// tags and heads.
    @Test func splitArcDividesTagsAndHeads() {
        var refs = RefSet()
        refs.addTag("t2", Self.oid(2), peeled: false)
        refs.addHead("h3", Self.oid(3))
        let index = AncestryIndex(refs: refs)
        _ = index.beginLoad()
        index.add(Self.line(5, 3))
        index.add(Self.line(3, 2))
        index.add(Self.line(2, 1))
        // Arc 1 is 5 -> [3, 2, 1...] still growing.
        #expect(index.arcIDs(1) == [Self.oid(3), Self.oid(2)])
        #expect(index.arcTags(1) == [Self.oid(2)])
        #expect(index.arcHeads(1) == [Self.oid(3)])
        #expect(index.isGrowing(1))
        index.add(Self.line(1))
        #expect(index.arcEnd(1) == Self.oid(1))
        #expect(!index.isGrowing(1))

        index.add(Self.line(4, 3))
        // 4 -> 3 is arc 2; splitting arc 1 at 3 then creates arc 3 (3 -> 2 -> 1).
        #expect(index.nextArc == 3)
        #expect(index.arcIDs(1) == [Self.oid(3)])
        #expect(index.arcEnd(1) == Self.oid(3))
        #expect(index.arcTags(1) == [])
        #expect(index.arcHeads(1) == [])
        #expect(index.arcStart(2) == Self.oid(4))
        #expect(index.arcIDs(2) == [Self.oid(3)])
        #expect(index.arcStart(3) == Self.oid(3))
        #expect(index.arcIDs(3) == [Self.oid(2), Self.oid(1)])
        #expect(index.arcEnd(3) == Self.oid(1))
        #expect(index.arcTags(3) == [Self.oid(2)])
        #expect(index.arcOut(of: Self.oid(3)) == [3])
        #expect(index.arcNos(of: Self.oid(3)) == [1, 2])
        #expect(index.arcNos(of: Self.oid(2)) == [3])
        #expect(index.arcNos(of: Self.oid(1)) == [3])
        #expect(index.seedIDs == [Self.oid(5), Self.oid(4)])
        #expect(index.diagnostics.isEmpty)
    }

    /// Splitting an arc that is still growing hands `growing` to the new tail
    /// and rewrites the unseen parent's `arcnos`.
    @Test func splitOfGrowingArcMovesGrowingFlag() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        index.add(Self.line(6, 5))
        index.add(Self.line(5, 4))
        index.add(Self.line(4, 3))
        #expect(index.isGrowing(1))
        index.add(Self.line(7, 5))
        // 7 -> 5 is arc 2; splitting arc 1 at 5 creates arc 3 (5 -> 4 -> ...).
        #expect(index.nextArc == 3)
        #expect(index.arcIDs(1) == [Self.oid(5)])
        #expect(index.arcEnd(1) == Self.oid(5))
        #expect(!index.isGrowing(1))
        #expect(index.arcIDs(2) == [Self.oid(5)])
        #expect(index.isGrowing(3))
        #expect(index.arcStart(3) == Self.oid(5))
        #expect(index.arcIDs(3) == [Self.oid(4)])
        #expect(index.arcEnd(3) == nil)
        // The still-unseen parent 3 now hangs off the new arc.
        #expect(index.arcNos(of: Self.oid(3)) == [3])
        #expect(index.arcNos(of: Self.oid(4)) == [3])
    }

    @Test func mergeCreatesOneArcPerParent() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        index.add(Self.line(9, 8, 7))
        #expect(index.nextArc == 2)
        #expect(index.arcOut(of: Self.oid(9)) == [1, 2])
        #expect(index.isGrowing(1))
        #expect(index.isGrowing(2))
        index.add(Self.line(8, 6))
        index.add(Self.line(7, 6))
        index.add(Self.line(6))
        #expect(index.nextArc == 2)
        #expect(index.arcEnd(1) == Self.oid(6))
        #expect(index.arcEnd(2) == Self.oid(6))
        #expect(index.arcNos(of: Self.oid(6)) == [1, 2])
        #expect(index.arcIDs(1) == [Self.oid(8), Self.oid(6)])
    }

    @Test func addNewChildBranchesOffAnExistingCommit() {
        let index = AncestryIndex()
        // Before getallcommits ran, addnewchild is a no-op.
        index.addNewChild(Self.oid(10), parent: Self.oid(2))
        #expect(index.commitCount == 0)

        _ = index.beginLoad()
        index.add(Self.line(3, 2))
        index.add(Self.line(2, 1))
        index.add(Self.line(1))
        // Unknown parent: no-op.
        index.addNewChild(Self.oid(10), parent: Self.oid(99))
        #expect(index.allParents(of: Self.oid(10)) == nil)

        index.addNewChild(Self.oid(10), parent: Self.oid(2))
        #expect(index.allParents(of: Self.oid(10)) == [Self.oid(2)])
        #expect(index.seedIDs == [Self.oid(3), Self.oid(10)])
        #expect(index.allChildren(of: Self.oid(2)) == [Self.oid(3), Self.oid(10)])
        // 2 became a branch point: arc 1 (3 -> 2 -> 1) split at 2.
        #expect(index.arcIDs(1) == [Self.oid(2)])
        #expect(index.arcStart(3) == Self.oid(2))
        #expect(index.arcIDs(3) == [Self.oid(1)])
        #expect(index.arcStart(2) == Self.oid(10))
        #expect(index.arcIDs(2) == [Self.oid(2)])
        #expect(index.arcOut(of: Self.oid(10)) == [2])
        #expect(index.arcNos(of: Self.oid(2)) == [1, 2])
    }

    // MARK: getallcommits command selection

    @Test func firstLoadUsesAll() throws {
        let index = AncestryIndex()
        #expect(index.allCommits == nil)
        let command = try #require(index.beginLoad())
        #expect(command.arguments == ["rev-list", "--parents", "--all"])
        #expect(command.stdin == nil)
        #expect(index.allCommits == 1)
        #expect(!index.allCUpdate)
    }

    @Test func updateReadsNewRefsAndExcludesSeeds() throws {
        var refs = RefSet()
        refs.addHead("main", Self.oid(3))
        let index = AncestryIndex(refs: refs)
        _ = index.beginLoad()
        index.add(Self.line(3, 2))
        index.add(Self.line(2))
        _ = index.finish(error: nil)
        #expect(index.isComplete)

        // Nothing new: gitk only calls dispneartags.
        #expect(index.beginLoad() == nil)
        #expect(index.allCommits == 0)

        // A new head, a tag object that is not a commit, and a seen ref.
        refs.addHead("topic", Self.oid(8))
        refs.addTag("ann", Self.oid(7), peeled: false)
        refs.addTag("ann", Self.oid(6), peeled: true)
        index.refs = refs
        let command = try #require(index.beginLoad())
        #expect(command.arguments == ["rev-list", "--parents", "--stdin"])
        #expect(index.allCUpdate)
        #expect(index.allCommits == 1)
        let text = String(decoding: try #require(command.stdin), as: UTF8.self)
        // 3 is already known; 7 is the tag object (excluded); 6 is the peeled
        // commit and 8 the new head. The seed 3 is excluded with ^, then `--`.
        #expect(text == [Self.oid(6).hex, Self.oid(8).hex, "^" + Self.oid(3).hex, "--"]
            .joined(separator: "\n") + "\n")
    }

    @Test func allCWaitBlocksTheCommand() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        index.allCWait = true
        #expect(index.beginLoad() == nil)
    }

    // MARK: finish

    @Test func finishOnErrorReportsTheTopologyMessage() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        let result = index.finish(error: "fatal: bad")
        #expect(result.errorMessage == AncestryIndex.topologyErrorMessage)
        #expect(result.errorDetail == "fatal: bad")
        #expect(!result.saveCache)
        #expect(!result.restart)
        #expect(index.isComplete)
    }

    @Test func finishOnErrorWhileUpdatingDropsEverythingAndRestarts() throws {
        var refs = RefSet()
        refs.addHead("main", Self.oid(2))
        let index = AncestryIndex(refs: refs)
        _ = index.beginLoad()
        index.add(Self.line(2, 1))
        index.add(Self.line(1))
        _ = index.finish(error: nil)
        refs.addHead("topic", Self.oid(5))
        index.refs = refs
        _ = try #require(index.beginLoad())
        #expect(index.allCUpdate)

        let result = index.finish(error: "fatal")
        #expect(result.restart)
        #expect(result.errorMessage == nil)
        #expect(index.nextArc == 0)
        #expect(index.seedIDs.isEmpty)
        #expect(index.allParents(of: Self.oid(2)) == nil)
        // The next beginLoad is a full load again.
        let again = try #require(index.beginLoad())
        #expect(again.arguments == ["rev-list", "--parents", "--all"])
    }

    @Test func generationCountsEveryAddedLine() {
        let index = AncestryIndex()
        _ = index.beginLoad()
        let before = index.generation
        index.add(Self.line(2, 1))
        index.add(Self.line(1))
        #expect(index.generation == before + 2)
    }

    // MARK: parsing

    @Test func parsesIdAndParents() throws {
        let a = Self.oid(1), b = Self.oid(2), c = Self.oid(3)
        let line = try #require(AncestryLine.parse(Data("\(a.hex) \(b.hex) \(c.hex)".utf8)))
        #expect(line.id == a)
        #expect(line.parents == [b, c])
        #expect(AncestryLine.parse(Data(a.hex.utf8))?.parents == [])
        #expect(AncestryLine.parse(Data()) == nil)
        #expect(AncestryLine.parse(Data("zzz".utf8)) == nil)
    }

    // MARK: incremental update equals a fresh build

    /// Loads the history of `criss-cross` in two steps (the part reachable
    /// from `HEAD~2`, then the rest through gitk's update command). The result
    /// is a valid index of the same graph. It need not equal a one-shot load:
    /// a tip seen in the first step keeps the arc that starts at it, so gitk's
    /// update leaves arcs split at former tips.
    @Test @MainActor func updateAfterPartialLoadGivesAValidIndex() async throws {
        let repo = try FixtureRepo.make("criss-cross")
        let runner = GitRunner(cwd: repo)
        let refs = await RefParser.load(runner: runner)

        let partial = AncestryIndex(refs: RefSet())
        _ = partial.beginLoad()
        let old = String(decoding: try await Self.git(repo, ["rev-parse", "HEAD~2"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let listing = try await Self.git(repo, ["rev-list", "--parents", old])
        for record in listing.split(separator: 0x0A) { partial.add(line: Data(record)) }
        _ = partial.finish(error: nil)
        let seedsBefore = partial.seedIDs
        partial.refs = refs
        let result = try await partial.load(runner: runner)
        #expect(result.errorMessage == nil)
        #expect(partial.allCUpdate)
        #expect(partial.seedIDs.starts(with: seedsBefore))

        let all = try await Self.git(repo, ["rev-list", "--parents", "--all"])
        let lines = all.split(separator: 0x0A).compactMap { AncestryLine.parse(Data($0)) }
        try Self.checkConsistent(partial, lines)

        let full = try await Self.loaded("criss-cross")
        #expect(partial.nextArc >= full.nextArc)
        for line in lines {
            #expect(Set(partial.allChildren(of: line.id) ?? []) == Set(full.allChildren(of: line.id) ?? []))
        }
    }
}
