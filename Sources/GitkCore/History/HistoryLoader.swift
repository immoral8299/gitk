// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct HistoryBatch: Sendable {
    public let generation: UInt64
    public let commits: [ParsedCommit]
}

/// Owns one cancellable git log. Parsing runs outside the main actor.
public actor HistoryLoader {
    private let runner: GitRunner
    private var process: GitProcess?
    private var reader: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(runner: GitRunner) { self.runner = runner }
    public var isRunning: Bool { process?.isRunning ?? false }

    /// Port of gitk proc `start_rev_list` (gitk/gitk 587–672).
    public func start(view: ViewSpec, hashLength: Int) async throws
        -> AsyncThrowingStream<HistoryBatch, Error> {
        cancel()
        let token = generation
        let resolved = try await view.resolve(hashLength: hashLength, runner: runner)
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        return startResolved(resolved, hashLength: hashLength, token: token)
    }

    public func start(resolved: ResolvedView, hashLength: Int) -> AsyncThrowingStream<HistoryBatch, Error> {
        cancel()
        return startResolved(resolved, hashLength: hashLength, token: generation)
    }

    private func startResolved(_ resolved: ResolvedView, hashLength: Int, token: UInt64)
        -> AsyncThrowingStream<HistoryBatch, Error> {
        var environment = runner.environment
        if resolved.parsed.noReplaceObjects { environment["GIT_NO_REPLACE_OBJECTS"] = "1" }
        let git = GitRunner(gitURL: runner.gitURL, cwd: runner.cwd, baseEnvironment: environment)
        let command = Self.command(for: resolved)
        let child = git.stream(command.args, stdin: command.stdin)
        process = child
        let pair = AsyncThrowingStream<HistoryBatch, Error>.makeStream()
        reader = Task.detached {
            let buffer = HistoryBatchBuffer(generation: token, continuation: pair.continuation)
            let timer = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
                    await buffer.flush()
                }
            }
            defer { timer.cancel() }
            await withTaskCancellationHandler {
                do {
                    for try await record in child.records(separator: 0) {
                        try Task.checkCancellation()
                        if record.isEmpty { continue }
                        let commit = try RawLogParser.parse(record: record, hashLength: hashLength)
                        await buffer.append(commit)
                    }
                    try Task.checkCancellation()
                    await buffer.finish()
                } catch {
                    if Task.isCancelled {
                        await buffer.finish(error: CancellationError(), discard: true)
                    } else {
                        await buffer.finish(error: error)
                    }
                }
            } onCancel: { child.cancel() }
        }
        pair.continuation.onTermination = { @Sendable _ in child.cancel() }
        return pair.stream
    }

    /// Port of gitk proc `stop_rev_list` (gitk/gitk 701–709).
    public func cancel() {
        generation &+= 1
        reader?.cancel()
        reader = nil
        process?.cancel()
        process = nil
    }

    public static func command(for view: ResolvedView) -> (args: [String], stdin: Data) {
        let args = ["log", "--no-color", "-z", "--pretty=raw", "--show-notes",
                    "--parents", "--boundary"] + view.logArgs + ["--stdin"]
        return (args, Data((view.revs + ["--"] + view.fileLimit).joined(separator: "\n").appending("\n").utf8))
    }
}

private actor HistoryBatchBuffer {
    private var commits: [ParsedCommit] = []
    private var finished = false
    private let generation: UInt64
    private let continuation: AsyncThrowingStream<HistoryBatch, Error>.Continuation

    init(generation: UInt64, continuation: AsyncThrowingStream<HistoryBatch, Error>.Continuation) {
        self.generation = generation
        self.continuation = continuation
    }

    func append(_ commit: ParsedCommit) {
        guard !finished else { return }
        commits.append(commit)
        if commits.count >= 2_000 { flush() }
    }

    func flush() {
        guard !finished, !commits.isEmpty else { return }
        continuation.yield(HistoryBatch(generation: generation, commits: commits))
        commits.removeAll(keepingCapacity: true)
    }

    func finish(error: (any Error)? = nil, discard: Bool = false) {
        guard !finished else { return }
        if !discard { flush() }
        commits.removeAll()
        finished = true
        continuation.finish(throwing: error)
    }
}
