// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Search speed on the `huge` fixture (task 14.7). Run with
/// `GITK_PERF=1 swift test -c release --filter FindPerfTests`.
@Suite struct FindPerfTests {
    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    /// Records the longest time the main actor was unavailable while running.
    @MainActor private final class StallMeter {
        private(set) var worst: Double = 0
        private var task: Task<Void, Never>?

        func start() {
            worst = 0
            task = Task { @MainActor in
                while !Task.isCancelled {
                    let t0 = ContinuousClock.now
                    try? await Task.sleep(for: .milliseconds(1))
                    worst = max(worst, FindPerfTests.seconds(t0.duration(to: .now)) - 0.001)
                }
            }
        }

        func stop() -> Double {
            task?.cancel()
            return worst
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITK_PERF"] == "1"))
    @MainActor func hugeSearchMeetsBudgets() async throws {
        let fixture = try FixtureRepo.make("huge")
        let repo = try await RepoContext.discover(cwd: fixture)
        let session = ViewSession(repo: repo, runner: GitRunner(cwd: fixture), view: ViewSpec(name: "All files", args: ["--all"]))
        session.showLocalChanges = false
        await session.load()
        #expect(session.rowCount == 200_000)

        let index = SearchIndex()
        let meter = StallMeter()
        meter.start()
        let t0 = ContinuousClock.now
        await index.sync(with: session.store)
        let buildTime = Self.seconds(t0.duration(to: .now))
        let buildStall = meter.stop()
        #expect(index.count == 200_000)
        #expect(buildStall <= 0.016, "index build stalled the main actor \(buildStall)s")

        let scanner = SearchScanner(index: index)
        let visible = (0..<100).compactMap { session.id(at: $0) }
        var report = "GITK_PERF search index=\(String(format: "%.3f", buildTime))s indexStall=\(String(format: "%.1f", buildStall * 1000))ms"

        for (name, query, expectedCount) in [
            ("common", FindQuery(matchMode: .ignoreCase, field: .headline, pattern: "commit"), 200_000),
            ("common-allfields", FindQuery(matchMode: .exact, field: .allFields, pattern: "Alice"), nil),
            ("nomatch", FindQuery(matchMode: .exact, field: .allFields, pattern: "zzqqxx-no-such-text"), 0),
        ] as [(String, FindQuery, Int?)] {
            meter.start()
            let start = ContinuousClock.now
            var first: Double?
            var total = 0
            var matches = Set<ObjectID>()
            for await update in scanner.search(query, priority: visible) {
                if first == nil { first = Self.seconds(start.duration(to: .now)) }
                total += update.matches.count
                matches.formUnion(update.matches)
            }
            let full = Self.seconds(start.duration(to: .now))
            let stall = meter.stop()
            let firstTime = try #require(first)
            if let expectedCount { #expect(matches.count == expectedCount, "\(name) matches") }
            #expect(firstTime <= 0.120, "\(name) first visible results: \(firstTime)s")
            #expect(full <= 1.0, "\(name) full result: \(full)s")
            #expect(stall <= 0.016, "\(name) stalled the main actor \(stall)s")
            report += " | \(name): first=\(String(format: "%.1f", firstTime * 1000))ms full=\(String(format: "%.0f", full * 1000))ms stall=\(String(format: "%.1f", stall * 1000))ms n=\(matches.count)"
        }

        // Prefix narrowing: "commit 1" extends "commit", but the previous
        // search was replaced by others, so rebuild the base first.
        var base = 0
        for await u in scanner.search(FindQuery(matchMode: .ignoreCase, field: .headline, pattern: "commit")) { base += u.matches.count }
        let narrowStart = ContinuousClock.now
        var narrowed = 0
        for await u in scanner.search(FindQuery(matchMode: .ignoreCase, field: .headline, pattern: "commit 1")) { narrowed += u.matches.count }
        let narrowTime = Self.seconds(narrowStart.duration(to: .now))
        #expect(base == 200_000)
        #expect(narrowed > 0)
        report += " | narrow: \(String(format: "%.0f", narrowTime * 1000))ms n=\(narrowed)"

        // A superseded search stops promptly.
        let heavy = FindQuery(matchMode: .regexp, field: .allFields, pattern: "zz(q|x)+-no-such-text")
        let old = scanner.search(heavy, priority: visible)
        try await Task.sleep(for: .milliseconds(10))
        let supersede = ContinuousClock.now
        let replacement = scanner.search(FindQuery(matchMode: .exact, field: .headline, pattern: "side"), priority: visible)
        var oldFinal = false
        for await u in old where u.isFinal { oldFinal = true }
        let stopTime = Self.seconds(supersede.duration(to: .now))
        for await _ in replacement {}
        #expect(!oldFinal, "superseded search must not complete")
        #expect(stopTime <= 0.050, "superseded search stopped after \(stopTime)s")
        report += " | superseded-stop=\(String(format: "%.1f", stopTime * 1000))ms"
        print(report)
    }
}
