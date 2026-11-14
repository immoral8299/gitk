// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
import Testing
@testable import GitkCore

@Suite struct NavigationHistoryTests {
    @Test func restoresPositionAndTruncatesForwardBranch() throws {
        let a = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let b = try #require(ObjectID(hex: String(repeating: "b", count: 40)))
        var history = NavigationHistory().adding(.init(target: .commit(a)))
        history = history.adding(.init(target: .link(b)), saving: 42)
        #expect(history.canGoBack)
        history = history.stepping(forward: false, saving: 17)
        #expect(history.current?.scrollPosition == 42)
        #expect(history.canGoForward)
        history = history.adding(.init(target: .line(a, child: b)), saving: 50)
        #expect(!history.canGoForward)
        #expect(history.entries.count == 2)
    }
}
