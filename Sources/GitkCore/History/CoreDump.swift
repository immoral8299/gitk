// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The oracle-schema export used by the gitk-core-dump developer executable.
public enum CoreDump {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    @MainActor
    public static func run(repoURL: URL, args: [String]) async throws -> Data {
        let repo = try await RepoContext.discover(cwd: repoURL)
        let launch = try await LaunchArguments.parse(argv: args, repo: repoURL, runner: GitRunner(cwd: repoURL))
        let session = ViewSession(repo: repo, runner: GitRunner(cwd: repoURL),
            view: ViewSpec(name: "Command line", args: launch.revisionArgs, files: launch.paths, argsCmd: launch.argsCmd))
        session.showLocalChanges = false
        await session.load()
        if let error = session.errorMessage { throw Failure(description: error) }
        let colors = GraphColors(layout: session.layout)
        for row in stride(from: 0, to: session.rowCount, by: 50) {
            session.layout.ensureLaid(visibleRows: row..<(row + 50))
        }
        return try json(layout: session.layout, colors: colors)
    }

    /// Every field is intentionally named as in Tests/Oracle/oracle.tcl.
    public static func json(layout: GraphLayout, colors: GraphColors) throws -> Data {
        let ordering = layout.ordering
        func hex(_ id: CommitIndex?) -> String { id.map { ordering.store.id(at: $0).hex } ?? "" }
        let order = (0..<ordering.commitIdx).compactMap { ordering.commitOnRow($0) }
        let rows: [[String: Any]] = order.enumerated().map { row, id in
            let list = layout.ids(on: row)
            return ["id": hex(id), "col": list.firstIndex(of: id) ?? -1, "idlist": list.map(hex)]
        }
        let varcs: [String: Any] = [
            "varcstart": ordering.varcStart.map(hex),
            "varccommits": ordering.varcCommits.map { $0.map { hex($0) } },
            "varctok": ordering.varcTok, "vupptr": ordering.vupPtr,
            "vdownptr": ordering.vdownPtr, "vleftptr": ordering.vleftPtr,
            "vbackptr": ordering.vbackPtr,
            "varcrow": ordering.varcRow.map { $0.map { $0 as Any } ?? NSNull() },
        ]
        let ranges = Dictionary(uniqueKeysWithValues: order.map { (hex($0), layout.rowRanges($0)) })
        let colorMap = Dictionary(uniqueKeysWithValues: colors.colorMap.map { (hex($0.key), $0.value) })
        return try JSONSerialization.data(withJSONObject: [
            "order": order.map { hex($0) }, "varcs": varcs, "rows": rows,
            "ranges": ranges, "colors": colorMap,
        ], options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
