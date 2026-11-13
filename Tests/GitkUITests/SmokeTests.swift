// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkUI

@Suite struct SmokeTests {
    @Test func uiModuleLoads() {
        #expect(GitkUI.coreVersion == "0.0.0")
    }
}
