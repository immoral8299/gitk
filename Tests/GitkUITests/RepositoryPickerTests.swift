// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkUI

/// Launched outside a repository, the app asks for one only when no revisions
/// or paths were given and errors are not headless.
@MainActor
@Suite struct RepositoryPickerTests {
    @Test func offeredWithNoArgumentsOrOnlyOptions() {
        #expect(AppDelegate.offersRepositoryPicker(arguments: [], environment: [:]))
        #expect(AppDelegate.offersRepositoryPicker(arguments: ["--all", "--date-order"], environment: [:]))
    }

    @Test func notOfferedWithRevisionsOrPaths() {
        #expect(!AppDelegate.offersRepositoryPicker(arguments: ["main..feature"], environment: [:]))
        #expect(!AppDelegate.offersRepositoryPicker(arguments: ["--all", "--", "src"], environment: [:]))
        #expect(!AppDelegate.offersRepositoryPicker(arguments: ["--"], environment: [:]))
    }

    @Test func notOfferedWithHeadlessErrors() {
        #expect(!AppDelegate.offersRepositoryPicker(arguments: [], environment: ["GITK_SWIFT_HEADLESS_ERRORS": "1"]))
    }
}

@MainActor
@Suite struct DefaultSettingsFlagTests {
    @Test func flagIsRemovedFromTheOptions() {
        let (on, rest) = AppDelegate.extractDefaultSettingsFlag(["--all", "--default-settings", "main"])
        #expect(on)
        #expect(rest == ["--all", "main"])
    }

    @Test func flagAfterDoubleDashIsAPath() {
        let (on, rest) = AppDelegate.extractDefaultSettingsFlag(["--all", "--", "--default-settings"])
        #expect(!on)
        #expect(rest == ["--all", "--", "--default-settings"])
    }

    @Test func delegateUsesDefaultsOnlyWithTheFlag() {
        #expect(AppDelegate(arguments: ["--default-settings"], environment: [:]).usesDefaultSettings)
        #expect(AppDelegate(arguments: ["--default-settings"], environment: [:]).arguments.isEmpty)
        #expect(!AppDelegate(arguments: ["--all"], environment: [:]).usesDefaultSettings)
    }
}
