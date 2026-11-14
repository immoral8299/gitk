// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct PatchIDComparison: Sendable, Equatable {
    public struct Equivalent: Sendable, Equatable {
        public let left: ObjectID
        public let right: ObjectID
    }
    public let equivalent: [Equivalent]
    public let unmatchedLeft: [ObjectID]
    public let unmatchedRight: [ObjectID]
    public let skippedMerges: [ObjectID]
}

public enum PatchIDCompare {
    /// Port of gitk proc `getpatchid` and the comparison in `do_cmp_commits`
    /// (gitk/gitk 9250–9343). Each side's nonshared history is compared by patch ID.
    public static func compare(_ left: ObjectID, with right: ObjectID,
                               runner: GitRunner) async throws -> PatchIDComparison {
        let leftOutput = try await runner.run(["rev-list", "--parents", left.hex, "^" + right.hex, "--"])
        let rightOutput = try await runner.run(["rev-list", "--parents", right.hex, "^" + left.hex, "--"])
        let leftLines = leftOutput.stdout.split(separator: 0x0a).compactMap { AncestryLine.parse(Data($0)) }
        let rightLines = rightOutput.stdout.split(separator: 0x0a).compactMap { AncestryLine.parse(Data($0)) }
        let actions = RepoActions(runner: runner)
        var rightByPatch: [String: [ObjectID]] = [:]
        let skipped = (leftLines + rightLines).filter { $0.parents.count > 1 }.map(\.id)
        for line in rightLines where line.parents.count <= 1 {
            try Task.checkCancellation()
            let patch = try await actions.patchID(of: line.id.hex)
            rightByPatch[patch, default: []].append(line.id)
        }
        var matches: [PatchIDComparison.Equivalent] = []
        var unmatchedLeft: [ObjectID] = []
        var matchedRight = Set<ObjectID>()
        for line in leftLines where line.parents.count <= 1 {
            try Task.checkCancellation()
            let patch = try await actions.patchID(of: line.id.hex)
            if let candidate = rightByPatch[patch]?.first {
                matches.append(.init(left: line.id, right: candidate))
                matchedRight.insert(candidate)
                rightByPatch[patch]?.removeFirst()
            } else { unmatchedLeft.append(line.id) }
        }
        let unmatchedRight = rightLines.filter { $0.parents.count <= 1 && !matchedRight.contains($0.id) }.map(\.id)
        return PatchIDComparison(equivalent: matches, unmatchedLeft: unmatchedLeft,
                                 unmatchedRight: unmatchedRight, skippedMerges: skipped)
    }
}
