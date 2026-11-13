// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// What a finished child process produced.
public struct GitOutput: Sendable, Equatable {
    public var stdout: Data
    public var stderr: Data
    public var status: Int32

    public init(stdout: Data, stderr: Data, status: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }

    /// stderr decoded as UTF-8 (lossy).
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// A git command that failed: non-zero exit, or it could not be started
/// (then `status` is -1 and `stderr` describes why).
public struct GitError: Error, Sendable, Equatable, CustomStringConvertible {
    public var args: [String]
    public var status: Int32
    public var stderr: String

    public init(args: [String], status: Int32, stderr: String) {
        self.args = args
        self.status = status
        self.stderr = stderr
    }

    public var description: String {
        "git \(args.joined(separator: " ")) failed (status \(status)): \(stderr)"
    }
}

extension GitError: LocalizedError {
    public var errorDescription: String? { stderr.isEmpty ? description : stderr }
}

/// A spawned child process (posix_spawn, never a shell).
///
/// `@unchecked Sendable`: every mutable field is guarded by `lock`; the rest is
/// immutable after `init`. posix_spawn is used instead of `Foundation.Process`
/// because `Process` cannot put the child in its own process group, which
/// `GitProcess.cancel()` needs to signal the whole group.
final class ChildProcess: @unchecked Sendable {
    let pid: pid_t
    let stdoutFD: Int32
    let stderrFD: Int32
    /// Write end of the child's stdin, nil when it reads /dev/null.
    let stdinFD: Int32?
    private let ownProcessGroup: Bool
    private let lock = NSLock()
    private var exitStatus: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    struct SpawnError: Error { var message: String }

    /// - Parameters:
    ///   - executable: absolute path; `PATH` is not searched here.
    ///   - ownProcessGroup: make the child a process group leader.
    init(
        executable: String, arguments: [String], environment: [String: String],
        cwd: URL?, hasStdin: Bool, ownProcessGroup: Bool
    ) throws {
        var fds: [Int32] = []
        func makePipe() throws -> (read: Int32, write: Int32) {
            var p: [Int32] = [-1, -1]
            guard pipe(&p) == 0 else {
                throw SpawnError(message: String(cString: strerror(errno)))
            }
            fds += p
            return (p[0], p[1])
        }

        let inP: (read: Int32, write: Int32)?
        let outP: (read: Int32, write: Int32)
        let errP: (read: Int32, write: Int32)
        do {
            inP = hasStdin ? try makePipe() : nil
            outP = try makePipe()
            errP = try makePipe()
        } catch {
            fds.forEach { _ = close($0) }
            throw error
        }
        // Parent ends must not leak into other children.
        for fd in [inP?.write, outP.read, errP.read].compactMap({ $0 }) {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        }
        // A write to a closed stdin must fail with EPIPE, not raise SIGPIPE.
        if let w = inP?.write { _ = fcntl(w, F_SETNOSIGPIPE, 1) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let inP {
            posix_spawn_file_actions_adddup2(&actions, inP.read, 0)
        } else {
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, outP.write, 1)
        posix_spawn_file_actions_adddup2(&actions, errP.write, 2)
        if let cwd {
            posix_spawn_file_actions_addchdir_np(&actions, cwd.path)
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // The child starts with an empty signal mask and default dispositions,
        // whatever the parent (e.g. a test host) has blocked or ignored.
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attr, &noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attr, &allSignals)
        var flags = Int32(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
        if ownProcessGroup {
            flags |= Int32(POSIX_SPAWN_SETPGROUP)
            posix_spawnattr_setpgroup(&attr, 0)
        }
        posix_spawnattr_setflags(&attr, Int16(flags))

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var childPID: pid_t = 0
        let rc = posix_spawn(&childPID, executable, &actions, &attr, argv, envp)
        // The child's ends are closed in the parent whatever happened.
        if let inP { close(inP.read) }
        close(outP.write)
        close(errP.write)
        guard rc == 0 else {
            if let inP { close(inP.write) }
            close(outP.read)
            close(errP.read)
            throw SpawnError(message: "\(executable): \(String(cString: strerror(rc)))")
        }

        pid = childPID
        stdoutFD = outP.read
        stderrFD = errP.read
        stdinFD = inP?.write
        self.ownProcessGroup = ownProcessGroup

        let pid = childPID
        DispatchQueue.global().async { [self] in
            // Block until the child exits without reaping, so that `signal`
            // can never hit a recycled pid: it checks `exitStatus` under the
            // lock, and the reap below happens under the same lock.
            var info = siginfo_t()
            while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) != 0 && errno == EINTR {}
            lock.lock()
            var raw: Int32 = 0
            while waitpid(pid, &raw, 0) < 0 && errno == EINTR {}
            // Exit code, or 128 + signal number for a signalled child.
            let status: Int32 = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
            exitStatus = status
            let pending = waiters
            waiters = []
            lock.unlock()
            pending.forEach { $0.resume(returning: status) }
        }
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exitStatus == nil
    }

    /// Suspends until the child has exited and been reaped.
    func waitForExit() async -> Int32 {
        await withCheckedContinuation { cont in
            lock.lock()
            if let s = exitStatus {
                lock.unlock()
                cont.resume(returning: s)
            } else {
                waiters.append(cont)
                lock.unlock()
            }
        }
    }

    /// Sends `sig` to the process group (or just the process if it has no own
    /// group). Does nothing once the child has been reaped.
    func signal(_ sig: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard exitStatus == nil else { return }
        if ownProcessGroup { kill(-pid, sig) } else { kill(pid, sig) }
    }

    /// Reads `fd` to EOF on a background thread, then closes it.
    /// Chunks are buffered without limit (no back-pressure on the child).
    static func chunks(of fd: Int32) -> AsyncStream<Data> {
        AsyncStream(bufferingPolicy: .unbounded) { cont in
            DispatchQueue.global().async {
                var buf = [UInt8](repeating: 0, count: 65536)
                while true {
                    let n = read(fd, &buf, buf.count)
                    if n > 0 {
                        cont.yield(Data(buf[0..<n]))
                    } else if n < 0 && errno == EINTR {
                        continue
                    } else {
                        break
                    }
                }
                close(fd)
                cont.finish()
            }
        }
    }

    /// Writes `data` to stdin on a background thread, then closes it. A child
    /// that stops reading early is not an error (EPIPE ends the write).
    func feedStdin(_ data: Data) {
        guard let fd = stdinFD else { return }
        DispatchQueue.global().async {
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count, let base = raw.baseAddress {
                    let n = write(fd, base + offset, raw.count - offset)
                    if n > 0 {
                        offset += n
                    } else if n < 0 && errno == EINTR {
                        continue
                    } else {
                        break
                    }
                }
            }
            close(fd)
        }
    }
}

/// Runs any executable to completion and collects its output. Never uses a shell.
public struct ProcessRunner: Sendable {
    public init() {}

    /// stdout and stderr are drained concurrently with the stdin write, so large
    /// outputs cannot deadlock on a full pipe. A non-zero exit is returned in
    /// `GitOutput.status`, not thrown. Task cancellation sends SIGTERM to the child.
    /// - Parameter environment: the complete child environment; nil inherits the
    ///   parent's as is (use `GitEnvironment.childEnvironment` to strip `GIT_TRACE`).
    public func run(
        executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
        cwd: URL? = nil, stdin: Data? = nil
    ) async throws -> GitOutput {
        let child = try ChildProcess(
            executable: executable.path, arguments: arguments,
            environment: environment ?? ProcessInfo.processInfo.environment,
            cwd: cwd, hasStdin: stdin != nil, ownProcessGroup: true)
        return await withTaskCancellationHandler {
            if let stdin { child.feedStdin(stdin) }
            async let out = Self.collect(ChildProcess.chunks(of: child.stdoutFD))
            async let err = Self.collect(ChildProcess.chunks(of: child.stderrFD))
            let (o, e) = await (out, err)
            let status = await child.waitForExit()
            return GitOutput(stdout: o, stderr: e, status: status)
        } onCancel: {
            child.signal(SIGTERM)
        }
    }

    private static func collect(_ stream: AsyncStream<Data>) async -> Data {
        var all = Data()
        for await chunk in stream { all.append(chunk) }
        return all
    }
}

/// Runs git (design D2). Arguments are always an array, never a shell string.
public struct GitRunner: Sendable {
    public var gitURL: URL
    /// Default working directory; nil is the launch cwd.
    public var cwd: URL?
    /// Child environment, already stripped of `GIT_TRACE`.
    let environment: [String: String]

    /// - Parameter baseEnvironment: the "parent" environment; `GIT_TRACE` is removed from it.
    public init(
        gitURL: URL? = nil, cwd: URL? = nil, baseEnvironment: [String: String]? = nil
    ) {
        self.gitURL = gitURL ?? GitEnvironment.gitURL
        self.cwd = cwd
        self.environment = baseEnvironment.map { GitEnvironment.childEnvironment(from: $0) }
            ?? GitEnvironment.childEnvironment()
    }

    /// Runs `git <args>`. Throws `GitError` on a non-zero exit or if git cannot start.
    public func run(_ args: [String], stdin: Data? = nil, cwd: URL? = nil) async throws -> GitOutput {
        let output: GitOutput
        do {
            output = try await ProcessRunner().run(
                executable: gitURL, arguments: args, environment: environment,
                cwd: cwd ?? self.cwd, stdin: stdin)
        } catch let e as ChildProcess.SpawnError {
            throw GitError(args: args, status: -1, stderr: e.message)
        }
        guard output.status == 0 else {
            throw GitError(args: args, status: output.status, stderr: output.stderrText)
        }
        return output
    }
}
