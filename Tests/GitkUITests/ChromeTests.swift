// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkUI

@MainActor
@Suite struct ChromeTests {
    @Test func liquidGlassFlagMatchesTheRunningSystem() {
        let expected = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        #expect(Chrome.hasLiquidGlass == expected)
    }

    @Test func barIsWrappedOnceAndFillsItsRow() {
        let bar = NSStackView()
        let wrapped = Chrome.bar(bar)
        #expect(wrapped is BarChrome)
        #expect(Chrome.bar(wrapped) === wrapped)

        wrapped.frame = NSRect(x: 0, y: 0, width: 200, height: 28)
        wrapped.layoutSubtreeIfNeeded()
        #expect(bar.frame.width > 0 && bar.frame.height > 0)
        #expect(wrapped.bounds.contains(bar.frame))
    }
}
