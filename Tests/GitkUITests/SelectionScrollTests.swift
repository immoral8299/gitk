// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkUI

/// Keyboard navigation: the list scrolls the least distance below the header
/// inset, and details load only after the keys go quiet.
@Suite struct SelectionScrollTests {
    // A 400 pt clip with a 52 pt top inset (header and titlebar), rows 20 pt.
    private func offset(row: Int, boundsMinY: CGFloat) -> CGFloat? {
        CommitListController.revealOffset(rowMinY: CGFloat(row) * 20, rowMaxY: CGFloat(row + 1) * 20,
                                          boundsMinY: boundsMinY, boundsHeight: 400,
                                          insetTop: 52, insetBottom: 0)
    }

    @Test func visibleRowDoesNotScroll() {
        #expect(offset(row: 0, boundsMinY: -52) == nil)
        #expect(offset(row: 16, boundsMinY: -52) == nil)  // 320...340 inside 0...348
    }

    @Test func rowBelowLandsAtBottomEdge() {
        // Row 17 (340...360) ends 12 pt below the visible bottom (348).
        #expect(offset(row: 17, boundsMinY: -52) == -40)
        // Moving one row further scrolls exactly one row.
        #expect(offset(row: 18, boundsMinY: -40) == -20)
    }

    @Test func rowAboveLandsBelowTheHeaderNotUnderIt() {
        // Scrolled to y = 200: the visible area starts at 252, so row 12
        // (240...260) is half under the header.
        #expect(offset(row: 12, boundsMinY: 200) == 188)
        #expect(offset(row: 0, boundsMinY: 200) == -52)
    }

    @Test func detailsDelayCoversKeyRepeat() {
        // Default repeat (~83 ms): wait two repeats.
        #expect(MainWindowController.detailsDelay(keyRepeatInterval: 0.083) == .milliseconds(166))
        // Fastest repeat: never below 150 ms.
        #expect(MainWindowController.detailsDelay(keyRepeatInterval: 0.015) == .milliseconds(150))
        // Slow repeat: capped so a single press still feels immediate.
        #expect(MainWindowController.detailsDelay(keyRepeatInterval: 0.5) == .milliseconds(350))
    }
}
