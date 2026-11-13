// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

// Expected strings come from Tcl 9 `clock format <epoch> -timezone <tz> -format <fmt>`
// run with /opt/homebrew/bin/tclsh. Epochs: 1577836800 = 2020-01-01T00:00:00Z,
// 1583020805 = 2020-03-01T00:00:05Z, 1593620405 = 2020-07-01T16:20:05Z.
@Suite struct TclDateFormatTests {
    let ny = TimeZone(identifier: "America/New_York")!

    @Test func isoWithZoneUsesCommitOffset() {
        // clock format 1577836800 -timezone +0530 -format "%Y-%m-%d %H:%M:%S %z %Z"
        #expect(TclDateFormat.format(epoch: 1577836800, tzOffsetSeconds: 19800,
            format: "%Y-%m-%d %H:%M:%S %z %Z", localZone: ny) == "2020-01-01 05:30:00 +0530 +0530")
        // clock format 1577836800 -timezone -0430 -format "%Y-%m-%d %H:%M:%S %z %Z"
        #expect(TclDateFormat.format(epoch: 1577836800, tzOffsetSeconds: -16200,
            format: "%Y-%m-%d %H:%M:%S %z %Z", localZone: ny) == "2019-12-31 19:30:00 -0430 -0430")
    }

    @Test func noZoneUsesLocalZone() {
        // clock format 1583020805 -timezone :America/New_York -format "%Y-%m-%d %H:%M:%S"
        #expect(TclDateFormat.format(epoch: 1583020805, tzOffsetSeconds: 19800,
            format: "%Y-%m-%d %H:%M:%S", localZone: ny) == "2020-02-29 19:00:05")
        // clock format 1593620405 -timezone :America/New_York -format "%Y-%m-%d %H:%M:%S %z %Z"
        #expect(TclDateFormat.format(epoch: 1593620405, tzOffsetSeconds: 0,
            format: "%Y-%m-%d %H:%M:%S %z %Z", useCommitZone: false, localZone: ny)
            == "2020-07-01 12:20:05 -0400 EDT")
    }

    @Test func dayAndMonthNames() {
        // clock format 1577836800 -timezone +0530 -format "%a %b %e %A %B %j %p %I %y %%"
        #expect(TclDateFormat.format(epoch: 1577836800, tzOffsetSeconds: 19800,
            format: "%a %b %e %A %B %j %p %I %y %%", useCommitZone: true)
            == "Wed Jan  1 Wednesday January 001 AM 05 20 %")
        // clock format 1583020805 -timezone -0430 -format "%a %b %e %A %B %j %p %I %y %%"
        #expect(TclDateFormat.format(epoch: 1583020805, tzOffsetSeconds: -16200,
            format: "%a %b %e %A %B %j %p %I %y %%", useCommitZone: true)
            == "Sat Feb 29 Saturday February 060 PM 07 20 %")
        // clock format 1583020805 -timezone +0000 -format "%a %b %e %A %B %j %p %I %y %%"
        #expect(TclDateFormat.format(epoch: 1583020805, tzOffsetSeconds: 0,
            format: "%a %b %e %A %B %j %p %I %y %%", useCommitZone: true)
            == "Sun Mar  1 Sunday March 061 AM 12 20 %")
    }

    @Test func compositeSpecifiers() {
        // clock format 1577836800 -timezone -0430 -format "%c|%x|%X"
        #expect(TclDateFormat.format(epoch: 1577836800, tzOffsetSeconds: -16200,
            format: "%c|%x|%X", useCommitZone: true) == "Tue Dec 31 19:30:00 2019|12/31/2019|19:30:00")
    }

    @Test func percentEscape() {
        #expect(TclDateFormat.format(epoch: 0, tzOffsetSeconds: 0, format: "100%%", localZone: ny) == "100%")
    }

    @Test func parsesGitTimezone() {
        #expect(TclDateFormat.offsetSeconds(fromGitTZ: "+0530") == 19800)
        #expect(TclDateFormat.offsetSeconds(fromGitTZ: "-0430") == -16200)
        #expect(TclDateFormat.offsetSeconds(fromGitTZ: "+0000") == 0)
        #expect(TclDateFormat.offsetSeconds(fromGitTZ: "0530") == nil)
        #expect(TclDateFormat.offsetSeconds(fromGitTZ: "+05x0") == nil)
    }
}
