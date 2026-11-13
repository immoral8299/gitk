// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct SmokeTests {
    @Test func coreModuleLoads() {
        #expect(GitkCore.version == "0.0.0")
    }
}
