// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct FindSteppingTests {
    @Test func wrapAndNoWrap() {
        #expect(FindStepper.nextRow(current: 4, rowCount: 5, matchingRows: [1, 3], forward: true, wrap: true) == 1)
        #expect(FindStepper.nextRow(current: 4, rowCount: 5, matchingRows: [1, 3], forward: true, wrap: false) == nil)
        #expect(FindStepper.nextRow(current: 0, rowCount: 5, matchingRows: [1, 3], forward: false, wrap: true) == 3)
        #expect(FindStepper.nextRow(current: 0, rowCount: 5, matchingRows: [1, 3], forward: false, wrap: false) == nil)
        #expect(FindStepper.nextRow(current: 1, rowCount: 5, matchingRows: [1], forward: true, wrap: true) == 1)
        #expect(FindStepper.nextRow(current: nil, rowCount: 0, matchingRows: [], forward: true, wrap: true) == nil)
    }
}
