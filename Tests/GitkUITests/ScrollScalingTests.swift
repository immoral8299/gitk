// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkUI

@Suite struct ScrollScalingTests {
    /// Spec commit-list "Wheel multiplier": multiplier 3 moves three times as
    /// far as multiplier 1 for one wheel notch.
    @Test func wheelMultiplierThreeMovesThreeTimesAsFarAsOne() {
        let one = CommitListController.wheelPointDelta(1, precise: false, lineHeight: 16, multiplier: 1)
        let three = CommitListController.wheelPointDelta(1, precise: false, lineHeight: 16, multiplier: 3)
        #expect(one == 16)
        #expect(three == 48)
        #expect(three == 3 * one)
    }

    @Test func multiplierBelowOneCountsAsOne() {
        #expect(CommitListController.wheelPointDelta(2, precise: false, lineHeight: 10, multiplier: 0) == 20)
        #expect(CommitListController.wheelPointDelta(2, precise: false, lineHeight: 10, multiplier: -4) == 20)
    }

    /// Trackpad deltas are already in points and are not multiplied.
    @Test func preciseDeltasArePointsAndNotMultiplied() {
        #expect(CommitListController.wheelPointDelta(7.5, precise: true, lineHeight: 16, multiplier: 1) == 7.5)
        #expect(CommitListController.wheelPointDelta(7.5, precise: true, lineHeight: 16, multiplier: 3) == 7.5)
    }

    @Test func negativeDeltasKeepTheirSign() {
        #expect(CommitListController.wheelPointDelta(-1, precise: false, lineHeight: 16, multiplier: 3) == -48)
    }

    @Test func shiftOrHorizontalGestureOverFirstColumnScrollsItSideways() {
        #expect(CommitListController.scrollsFirstColumn(deltaX: 0, deltaY: 1, shift: true))
        #expect(CommitListController.scrollsFirstColumn(deltaX: 4, deltaY: 1, shift: false))
        #expect(!CommitListController.scrollsFirstColumn(deltaX: 0, deltaY: 1, shift: false))
        #expect(!CommitListController.scrollsFirstColumn(deltaX: 1, deltaY: 4, shift: false))
    }

    /// Dragging the pointer down by 10 moves the content down, so the clip
    /// origin goes up by 10.
    @Test func panMovesContentWithThePointer() {
        #expect(CommitListController.panOrigin(start: 100, mark: 50, now: 60) == 90)
        #expect(CommitListController.panOrigin(start: 100, mark: 50, now: 50) == 100)
    }

    @Test func clampedOffsetStaysInRange() {
        #expect(CommitListController.clampedOffset(-5, lower: 0, upper: 10) == 0)
        #expect(CommitListController.clampedOffset(4, lower: 0, upper: 10) == 4)
        #expect(CommitListController.clampedOffset(50, lower: 0, upper: 10) == 10)
        #expect(CommitListController.clampedOffset(3, lower: 8, upper: 2) == 8)
    }
}
