// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A git version number such as `2.45.0`.
public struct GitVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// The oldest git gitk supports. Port of gitk's `MIN_GIT_VERSION` (gitk/gitk line 20).
    public static let minimumSupported = GitVersion(2, 20, 0)

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the output of `git version`, for example `git version 2.45.0.windows.1`.
    ///
    /// Takes the first `\d+(\.\d+)*` after `git version `. Components beyond the
    /// third are ignored and missing ones count as 0, so `2.20` is `2.20.0`.
    /// Returns nil when the prefix is missing or the number is malformed.
    ///
    /// Port of the version regexp in gitk/gitk line 21 (`^git version ([\d.]*\d)`).
    public init?(versionOutput: String) {
        let prefix = "git version "
        guard let prefixRange = versionOutput.range(of: prefix) else { return nil }
        let bytes = Array(versionOutput[prefixRange.upperBound...].utf8)

        var components: [Int] = []
        var index = 0
        while true {
            let start = index
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                index += 1
            }
            guard index > start, let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                break
            }
            components.append(value)
            // Continue only through a dot that is followed by another digit.
            guard index + 1 < bytes.count, bytes[index] == 0x2E,
                  bytes[index + 1] >= 0x30, bytes[index + 1] <= 0x39 else {
                break
            }
            index += 1
        }

        guard !components.isEmpty else { return nil }
        self.init(
            components[0],
            components.count > 1 ? components[1] : 0,
            components.count > 2 ? components[2] : 0
        )
    }

    /// True when this version is at least `minimumSupported`.
    public var isSupported: Bool {
        self >= GitVersion.minimumSupported
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
