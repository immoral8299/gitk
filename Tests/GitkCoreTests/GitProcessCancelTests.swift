// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct GitProcessCancelTests {
    private func spawnSh(_ script: String) -> GitProcess {
        // Test-only use of a shell, to get an endless producer.
        GitProcess(
            executable: URL(fileURLWithPath: "/bin/sh"), args: ["-c", script],
            environment: ProcessInfo.processInfo.environment, cwd: nil, stdin: nil)
    }

    @Test func cancelStopsEndlessChild() async throws {
        let p = spawnSh(#"while :; do printf "a\0"; done"#)
        #expect(p.isRunning)
        var seen = 0
        for try await record in p.records(separator: 0) {
            #expect(record == Data("a".utf8))
            seen += 1
            if seen == 5 { break }
        }
        p.cancel()
        let deadline = Date().addingTimeInterval(1)
        while p.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!p.isRunning)
    }

    @Test func cancelEndsStreamWithoutError() async throws {
        let p = spawnSh(#"while :; do printf "a\0"; done"#)
        var count = 0
        for try await _ in p.records(separator: 0) {
            count += 1
            if count == 3 { p.cancel() }
        }
        #expect(count >= 3)
        #expect(!p.isRunning)
    }

    @Test func cancelKillsGrandchildrenInProcessGroup() async throws {
        let p = spawnSh(#"sleep 30 & echo $!; wait"#)
        var iterator = p.records(separator: 0x0A).makeAsyncIterator()
        let line = try #require(try await iterator.next())
        let grandchild = try #require(
            pid_t(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces)))
        p.cancel()
        let deadline = Date().addingTimeInterval(2)
        while kill(grandchild, 0) == 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(kill(grandchild, 0) != 0)
        #expect(!p.isRunning)
    }

    @Test func abandoningTheStreamCancelsTheChild() async throws {
        let p = spawnSh(#"while :; do printf "a\0"; done"#)
        let task = Task {
            for try await _ in p.records(separator: 0) {}
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let deadline = Date().addingTimeInterval(1)
        while p.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!p.isRunning)
    }
}

@Suite struct GitProcessTests {
    @Test func streamsGitLogRecordsFromFixture() async throws {
        let repo = try FixtureRepo.make("linear")
        let runner = GitRunner(cwd: repo)
        var ids: [String] = []
        for try await rec in runner.stream(["rev-list", "HEAD"]).records(separator: 0x0A) {
            ids.append(String(decoding: rec, as: UTF8.self))
        }
        let all = try await runner.run(["rev-list", "HEAD"])
        let expected = String(decoding: all.stdout, as: UTF8.self)
            .split(separator: "\n").map(String.init)
        #expect(ids == expected)
        #expect(!ids.isEmpty)
    }

    @Test func nonZeroExitThrowsGitErrorWithStderr() async throws {
        let repo = try FixtureRepo.make("linear")
        let p = GitRunner(cwd: repo).stream(["rev-list", "nope"])
        do {
            for try await _ in p.records(separator: 0) {}
            Issue.record("expected GitError")
        } catch let e as GitError {
            #expect(e.stderr.contains("nope"))
            #expect(e.status != 0)
            #expect(e.args == ["rev-list", "nope"])
        }
        #expect(!p.isRunning)
    }

    @Test func finalUnterminatedRecordIsDelivered() async throws {
        let p = GitProcess(
            executable: URL(fileURLWithPath: "/usr/bin/printf"), args: ["a\\0b\\0c"],
            environment: ProcessInfo.processInfo.environment, cwd: nil, stdin: nil)
        var got: [String] = []
        for try await r in p.records(separator: 0) { got.append(String(decoding: r, as: UTF8.self)) }
        #expect(got == ["a", "b", "c"])
    }

    @Test func launchFailureThrowsOnRecords() async throws {
        let runner = GitRunner(gitURL: URL(fileURLWithPath: "/nonexistent/git"))
        await #expect(throws: GitError.self) {
            for try await _ in runner.stream(["status"]).records(separator: 0) {}
        }
    }

    @Test func largeStderrDoesNotBlockStdout() async throws {
        let p = GitProcess(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", "head -c 2000000 /dev/zero >&2; printf 'done\\n'"],
            environment: ProcessInfo.processInfo.environment, cwd: nil, stdin: nil)
        var got: [String] = []
        for try await r in p.records(separator: 0x0A) { got.append(String(decoding: r, as: UTF8.self)) }
        #expect(got == ["done"])
    }
}
