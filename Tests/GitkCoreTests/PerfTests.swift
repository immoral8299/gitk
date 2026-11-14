// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Darwin
import Foundation
import Testing
@testable import GitkCore

@Suite struct PerfTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITK_PERF"] == "1"))
    @MainActor func hugeHistoryMeetsLoadAndMemoryBudgets() async throws {
        let fixture = try FixtureRepo.make("huge")
        let repo = try await RepoContext.discover(cwd: fixture)
        let session = ViewSession(repo: repo, runner: GitRunner(cwd: fixture), view: ViewSpec(name: "All files", args: ["--all"]))
        session.showLocalChanges = false
        var colors: GraphColors?
        let start = ContinuousClock.now
        var firstPaint: Double?
        session.onEvent = { event in
            if case .rowsChanged = event, session.rowCount >= 100, firstPaint == nil {
                colors = GraphColors(layout: session.layout)
                session.layout.ensureLaid(visibleRows: 0..<100)
                let elapsed = start.duration(to: .now).components
                firstPaint = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            }
        }
        await session.load()
        let elapsed = start.duration(to: .now).components
        let fullLoad = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let first = try #require(firstPaint)
        let rss = try residentMemory()
        #expect(session.errorMessage == nil)
        #expect(session.rowCount == 200_000)
        #expect(first < 1.5, "first 100 rows: \(first)s")
        #expect(fullLoad < 10, "full load: \(fullLoad)s")
        #expect(rss < 1_500_000_000, "resident memory: \(rss) bytes")
        print("GITK_PERF first100=\(first)s full200k=\(fullLoad)s rss=\(rss) bytes")
        withExtendedLifetime(colors) {}
    }

    private func residentMemory() throws -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        #expect(result == KERN_SUCCESS)
        return UInt64(info.resident_size)
    }
}
