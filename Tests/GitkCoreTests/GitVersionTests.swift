// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct GitVersionTests {
    @Test func parsesAppleGitOutput() throws {
        let version = try #require(GitVersion(versionOutput: "git version 2.54.0 (Apple Git-157)"))
        #expect(version == GitVersion(2, 54, 0))
        #expect(version.isSupported)
    }

    @Test func rejectsVersionBelowMinimum() throws {
        let version = try #require(GitVersion(versionOutput: "git version 2.19.1"))
        #expect(version == GitVersion(2, 19, 1))
        #expect(!version.isSupported)
    }

    @Test func ignoresWindowsSuffix() throws {
        let version = try #require(GitVersion(versionOutput: "git version 2.45.0.windows.1"))
        #expect(version == GitVersion(2, 45, 0))
        #expect(version.isSupported)
    }

    @Test func missingPatchComponentIsZero() throws {
        let version = try #require(GitVersion(versionOutput: "git version 2.20"))
        #expect(version == GitVersion(2, 20, 0))
        #expect(version == GitVersion.minimumSupported)
        #expect(version.isSupported)
    }

    @Test func rejectsMissingPrefixOrNumber() {
        #expect(GitVersion(versionOutput: "") == nil)
        #expect(GitVersion(versionOutput: "hg version 6.0") == nil)
        #expect(GitVersion(versionOutput: "git version ") == nil)
        #expect(GitVersion(versionOutput: "git version abc") == nil)
    }

    @Test func comparesComponentwise() {
        #expect(GitVersion(2, 9, 0) < GitVersion(2, 10, 0))
        #expect(GitVersion(2, 20, 0) < GitVersion(2, 20, 1))
        #expect(GitVersion(3, 0, 0) > GitVersion(2, 99, 99))
        #expect(GitVersion(2, 20, 0) <= GitVersion(2, 20, 0))
    }
}
