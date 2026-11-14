// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum CommitResolutionError: Error, Sendable, Equatable {
    case ambiguous(String)
    case unknownRevision(String)
    case unknownCommit(String)
    case notInView(String)

    public var msgid: String {
        switch self {
        case .ambiguous: return "Short commit ID %s is ambiguous"
        case .unknownRevision: return "Revision %s is not known"
        case .unknownCommit: return "Commit ID %s is not known"
        case .notInView: return "Revision %s is not in the current view"
        }
    }
    public var value: String {
        switch self {
        case .ambiguous(let value), .unknownRevision(let value), .unknownCommit(let value), .notInView(let value): return value
        }
    }
}

public enum CommitResolver {
    /// Port of gitk procs `gotocommit`, `longid` (gitk/gitk 8901–8967, 1989–2014).
    public static func resolve(_ revision: String, inView ids: [ObjectID], runner: any GitRunning) async throws -> ObjectID {
        let value = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = value.count >= 4 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
        if hex {
            let matches = ids.filter { $0.hex.hasPrefix(value.lowercased()) }
            if matches.count > 1 { throw CommitResolutionError.ambiguous(value) }
            if let id = matches.first { return id }
        }
        let output: GitOutput
        do { output = try await runner.run(["rev-parse", "--verify", value + "^{commit}"], stdin: nil, cwd: nil) }
        catch {
            if (error as? GitError)?.stderr.contains("ambiguous") == true {
                throw CommitResolutionError.ambiguous(value)
            }
            throw hex ? CommitResolutionError.unknownCommit(value) : CommitResolutionError.unknownRevision(value)
        }
        guard let id = ObjectID(hex: String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw hex ? CommitResolutionError.unknownCommit(value) : CommitResolutionError.unknownRevision(value)
        }
        guard ids.contains(id) else { throw CommitResolutionError.notInView(value) }
        return id
    }
}
