// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A running git command whose stdout is consumed as a stream of records.
///
/// Replaces gitk's `filerun`/`dorunq` machinery (gitk/gitk 283–354): instead of
/// a file-event queue, the caller iterates an `AsyncThrowingStream`.
/// The child is started by `GitRunner.stream`, in its own process group.
public final class GitProcess: Sendable {
    private let args: [String]
    private let child: ChildProcess?
    private let launchError: GitError?
    /// stderr, drained from the start so a chatty child cannot block on a full pipe.
    private let stderrTask: Task<Data, Never>?
    private let state = State()

    /// `@unchecked Sendable`: `flags` is only touched while holding `lock`.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var recordsCalled = false

        func markCancelled() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }
        /// True the first time only.
        func claimRecords() -> Bool {
            lock.withLock {
                defer { recordsCalled = true }
                return !recordsCalled
            }
        }
    }

    init(
        executable: URL, args: [String], environment: [String: String], cwd: URL?, stdin: Data?
    ) {
        self.args = args
        do {
            let child = try ChildProcess(
                executable: executable.path, arguments: args, environment: environment,
                cwd: cwd, hasStdin: stdin != nil, ownProcessGroup: true)
            if let stdin { child.feedStdin(stdin) }
            self.child = child
            self.launchError = nil
            let errFD = child.stderrFD
            self.stderrTask = Task {
                var all = Data()
                for await chunk in ChildProcess.chunks(of: errFD) { all.append(chunk) }
                return all
            }
        } catch {
            let message = (error as? ChildProcess.SpawnError)?.message ?? "\(error)"
            self.child = nil
            self.launchError = GitError(args: args, status: -1, stderr: message)
            self.stderrTask = nil
        }
    }

    /// True from launch until the child has exited and been reaped.
    public var isRunning: Bool { child?.isRunning ?? false }

    /// Sends SIGTERM to the child's process group. The record stream then ends
    /// without an error. Safe to call at any time, any number of times.
    public func cancel() {
        state.markCancelled()
        child?.signal(SIGTERM)
    }

    /// Stdout split on `separator` (0x00 for `-z` output, 0x0A for lines).
    ///
    /// Records arrive as they are produced. The stream finishes after the child
    /// has exited; a non-zero exit then throws `GitError` with the stderr text,
    /// unless `cancel()` was called. Dropping the consumer cancels the child.
    /// The output can be consumed only once; a second call's stream throws.
    public func records(separator: UInt8) -> AsyncThrowingStream<Data, Error> {
        guard state.claimRecords() else {
            return AsyncThrowingStream {
                $0.finish(throwing: GitError(
                    args: args, status: -1, stderr: "records(separator:) was already called"))
            }
        }
        guard let child, let stderrTask else {
            let err = launchError
            return AsyncThrowingStream { $0.finish(throwing: err) }
        }
        let args = self.args
        let state = self.state
        return AsyncThrowingStream(bufferingPolicy: .unbounded) { cont in
            let reader = Task {
                var splitter = RecordSplitter(separator: separator)
                for await chunk in ChildProcess.chunks(of: child.stdoutFD) {
                    for record in splitter.feed(chunk) { cont.yield(record) }
                }
                if let last = splitter.finish() { cont.yield(last) }
                let status = await child.waitForExit()
                let stderr = await stderrTask.value
                if status != 0 && !state.isCancelled {
                    cont.finish(throwing: GitError(
                        args: args, status: status,
                        stderr: String(decoding: stderr, as: UTF8.self)))
                } else {
                    cont.finish()
                }
            }
            cont.onTermination = { @Sendable _ in
                state.markCancelled()
                child.signal(SIGTERM)
                reader.cancel()
            }
        }
    }
}

extension GitRunner {
    /// Starts `git <args>` and returns immediately. Launch failures surface as a
    /// `GitError` thrown by `records(separator:)`.
    public func stream(_ args: [String], stdin: Data? = nil, cwd: URL? = nil) -> GitProcess {
        GitProcess(
            executable: gitURL, args: args, environment: environment,
            cwd: cwd ?? self.cwd, stdin: stdin)
    }
}
