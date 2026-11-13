// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Runs the asynchronous find types ("touching paths:", "adding/removing
/// string:", "changing lines matching:") through `git diff-tree`.
///
/// Deviation: gitk keeps `diff-tree --stdin` open and writes ids as rows are
/// drawn. `GitRunner.stream` takes stdin as `Data` up front, so the caller
/// passes every commit to check at once; git still reports matches
/// incrementally. The empty-line flush marker gitk uses to find the end of a
/// batch is not needed.
public final class FindEngine: @unchecked Sendable {
    // @unchecked Sendable: `process` is only touched under `lock`.
    private let runner: GitRunner
    private let lock = NSLock()
    private var process: GitProcess?

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    /// The `git` arguments for `query`, or nil when nothing should run: the
    /// type is "containing:", the pattern is empty, or the paths have an
    /// unbalanced quote (gitk just returns in that case).
    ///
    /// Port of gitk proc `do_file_hl` (gitk/gitk 4989–5024).
    static func arguments(for query: FindQuery, cdup: String) -> [String]? {
        guard !query.pattern.isEmpty else { return nil }
        let base = ["diff-tree", "-r", "-s", "--stdin"]
        switch query.type {
        case .containing:
            return nil
        case .touchingPaths:
            guard let patterns = try? PathPatterns(
                findString: query.pattern, exact: query.matchMode == .exact)
            else { return nil }
            return base + ["--"] + patterns.paths.map { joinPath(cdup, $0) }
        case .addingRemovingString:
            return base + ["-S" + query.pattern]
        case .changingLinesMatching:
            return base + ["-G" + query.pattern]
        }
    }

    /// Tcl `file join $cdup $path`: an empty prefix leaves the path alone; an
    /// absolute path wins over the prefix.
    private static func joinPath(_ cdup: String, _ path: String) -> String {
        if cdup.isEmpty || path.hasPrefix("/") { return path }
        if path.isEmpty { return cdup }
        return cdup.hasSuffix("/") ? cdup + path : cdup + "/" + path
    }

    /// Starts a search and streams the ids (from `commitIDs`) that match.
    /// Port of gitk procs `do_file_hl`, `askfilehighlight` and
    /// `readfhighlight` (gitk/gitk 4989–5079). Replaces any earlier search
    /// (it is cancelled). The stream finishes when git does and throws
    /// `GitError` if git fails; `cancel()` ends it without an error.
    public func start(
        query: FindQuery, cdup: String = "", commitIDs: [ObjectID]
    ) -> AsyncThrowingStream<ObjectID, Error> {
        cancel()
        guard let args = Self.arguments(for: query, cdup: cdup) else {
            return AsyncThrowingStream { $0.finish() }
        }
        let wanted = Set(commitIDs)
        var input = Data()
        for id in commitIDs { input.append(contentsOf: (id.hex + "\n").utf8) }
        let p = runner.stream(args, stdin: input)
        lock.lock()
        process = p
        lock.unlock()
        let records = p.records(separator: 0x0A)
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    for try await line in records {
                        // readfhighlight ignores lines that are not a requested id.
                        let text = String(decoding: line, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let id = ObjectID(hex: text), wanted.contains(id) else {
                            continue
                        }
                        cont.yield(id)
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { @Sendable _ in
                task.cancel()
                p.cancel()
            }
        }
    }

    /// Stops the running search, if any. Its stream ends without an error.
    public func cancel() {
        lock.lock()
        let p = process
        process = nil
        lock.unlock()
        p?.cancel()
    }

    /// True while the git child is alive.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }
}
