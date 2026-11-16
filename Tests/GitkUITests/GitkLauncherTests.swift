// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkUI

/// A shell that exports `DYLD_LIBRARY_PATH=/opt/homebrew/lib` makes ImageIO
/// load Homebrew's libpng and crash while drawing emoji. The launcher strips
/// those paths and re-executes; ordinary launches must not be disturbed.
@Suite struct GitkLauncherTests {
    @Test func ordinaryLaunchIsLeftAlone() {
        #expect(GitkLauncher.environmentWithoutLoaderPaths(["PATH": "/usr/bin"]) == nil)
        #expect(GitkLauncher.environmentWithoutLoaderPaths(["DYLD_LIBRARY_PATH": ""]) == nil)
    }

    @Test func bothLoaderPathsAreRemoved() throws {
        let clean = try #require(GitkLauncher.environmentWithoutLoaderPaths([
            "DYLD_LIBRARY_PATH": "/opt/homebrew/lib",
            "DYLD_FALLBACK_LIBRARY_PATH": "/opt/homebrew/lib",
            "PATH": "/usr/bin",
        ]))
        #expect(clean["DYLD_LIBRARY_PATH"] == nil)
        #expect(clean["DYLD_FALLBACK_LIBRARY_PATH"] == nil)
        #expect(clean["PATH"] == "/usr/bin")
    }

    @Test func oneLoaderPathIsEnoughToRelaunch() throws {
        let clean = try #require(GitkLauncher.environmentWithoutLoaderPaths([
            "DYLD_LIBRARY_PATH": "/opt/homebrew/lib",
        ]))
        #expect(clean["DYLD_LIBRARY_PATH"] == nil)
    }
}
