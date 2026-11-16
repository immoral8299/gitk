// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing

@testable import GitkUI

@MainActor
@Suite struct StatusBarTests {
    /// Spec commit-list "Status during load": the status reads "Reading", the bar
    /// advances with the rows read, and both clear when loading is done.
    @Test func statusDuringLoad() {
        let bar = StatusBar()
        var busyStates: [Bool] = []
        bar.onBusyChange = { busyStates.append($0) }
        #expect(!bar.isBusy)
        #expect(bar.progress.isHidden)

        bar.setReading(true, count: 0, total: 200)
        #expect(bar.label.stringValue == L("Reading"))
        #expect(!bar.progress.isHidden)
        #expect(!bar.progress.isIndeterminate)
        #expect(bar.progress.doubleValue == 0)

        bar.setReading(true, count: 50, total: 200)
        #expect(bar.progress.doubleValue == 0.25)

        bar.setReading(true, count: 500, total: 200)
        #expect(bar.progress.doubleValue == 0.99)

        bar.setReading(false)
        #expect(bar.label.stringValue.isEmpty)
        #expect(bar.progress.isHidden)
        #expect(busyStates == [true, false])
    }

    @Test func runsIndeterminatelyWithoutTotal() {
        let bar = StatusBar()
        bar.setReading(true, count: 10)
        #expect(bar.progress.isIndeterminate)
    }

    @Test func searchOverridesAndReturnsToReading() {
        let bar = StatusBar()
        bar.setReading(true, count: 5, total: 10)
        bar.setSearching()
        #expect(bar.label.stringValue == L("Searching"))
        #expect(bar.progress.isIndeterminate)
        bar.setSearching(false)
        #expect(bar.label.stringValue == L("Reading"))
        #expect(!bar.progress.isIndeterminate)
        #expect(bar.isBusy)
    }

    @Test func rowCounterShowsSelectedRowAndCount() {
        let bar = StatusBar()
        bar.setRow(3, of: 7)
        #expect(bar.rowLabel.stringValue == "\(L("Row")) 3 / 7")
    }

    /// The busy state uses the system's spinning wait cursor (with the
    /// hourglass as the fallback), never an empty image.
    @Test func busyCursorHasAnImage() {
        #expect(StatusBar.busyCursor.image.size.width > 0)
        #expect(StatusBar.busyCursor.image.size.height > 0)
    }
}
