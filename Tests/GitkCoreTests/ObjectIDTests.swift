// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct ObjectIDTests {
    static let sha1 = "0123456789abcdef0123456789abcdef01234567"
    static let sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    @Test func validLengthsRoundTrip() throws {
        let a = try #require(ObjectID(hex: Self.sha1))
        #expect(a.hex == Self.sha1)
        #expect(a.description == Self.sha1)
        #expect(a.hexLength == 40)
        let b = try #require(ObjectID(hex: Self.sha256))
        #expect(b.hex == Self.sha256)
        #expect(b.hexLength == 64)
    }

    @Test func invalidInputRejected() {
        #expect(ObjectID(hex: "") == nil)
        #expect(ObjectID(hex: String(Self.sha1.dropLast())) == nil)
        #expect(ObjectID(hex: Self.sha1 + "0") == nil)
        #expect(ObjectID(hex: String(repeating: "a", count: 63)) == nil)
        #expect(ObjectID(hex: String(repeating: "a", count: 65)) == nil)
        #expect(ObjectID(hex: String(repeating: "g", count: 40)) == nil)
        #expect(ObjectID(hex: " " + String(Self.sha1.dropLast())) == nil)
    }

    @Test func uppercaseRejected() {
        #expect(ObjectID(hex: Self.sha1.uppercased()) == nil)
        #expect(ObjectID(hex: Self.sha256.uppercased()) == nil)
        let mixed = "A" + Self.sha1.dropFirst()
        #expect(ObjectID(hex: mixed) == nil)
    }

    @Test func abbreviationLengths() throws {
        let id = try #require(ObjectID(hex: Self.sha1))
        #expect(id.abbreviated(0) == "")
        #expect(id.abbreviated(7) == "0123456")
        #expect(id.abbreviated(40) == Self.sha1)
        #expect(id.abbreviated(100) == Self.sha1)
        #expect(id.abbreviated(-3) == "")
        let long = try #require(ObjectID(hex: Self.sha256))
        #expect(long.abbreviated(64) == Self.sha256)
        #expect(long.abbreviated(12) == "0123456789ab")
    }

    @Test func localPseudoIDs() throws {
        let u40 = try #require(ObjectID.localUnstaged(hashLength: 40))
        #expect(u40.hex == String(repeating: "0", count: 40))
        let s40 = try #require(ObjectID.localStaged(hashLength: 40))
        #expect(s40.hex == String(repeating: "0", count: 39) + "1")
        let u64 = try #require(ObjectID.localUnstaged(hashLength: 64))
        #expect(u64.hex == String(repeating: "0", count: 64))
        let s64 = try #require(ObjectID.localStaged(hashLength: 64))
        #expect(s64.hex == String(repeating: "0", count: 63) + "1")
        #expect(ObjectID(hex: s40.hex) == s40)
        #expect(ObjectID(hex: s64.hex) == s64)
        #expect(ObjectID.localUnstaged(hashLength: 41) == nil)
        #expect(ObjectID.localStaged(hashLength: 0) == nil)
        #expect(u40 != u64)
    }

    @Test func hashableAndEquatable() throws {
        let a = try #require(ObjectID(hex: Self.sha1))
        let b = try #require(ObjectID(hex: Self.sha1))
        let c = try #require(ObjectID(hex: Self.sha256))
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test func byteWiseOrdering() throws {
        let lo = try #require(ObjectID(hex: "00" + String(repeating: "f", count: 38)))
        let hi = try #require(ObjectID(hex: "01" + String(repeating: "0", count: 38)))
        #expect(lo < hi)
        let tail1 = try #require(ObjectID(hex: String(repeating: "a", count: 39) + "1"))
        let tail2 = try #require(ObjectID(hex: String(repeating: "a", count: 39) + "2"))
        #expect(tail1 < tail2)
        let hexSorted = ["f" + String(repeating: "0", count: 39),
                         "9" + String(repeating: "0", count: 39),
                         "a" + String(repeating: "0", count: 39)]
        let sorted = hexSorted.compactMap { ObjectID(hex: $0) }.sorted().map(\.hex)
        #expect(sorted == hexSorted.sorted())
        let short = try #require(ObjectID.localUnstaged(hashLength: 40))
        let long = try #require(ObjectID.localUnstaged(hashLength: 64))
        #expect(short < long)
    }
}
