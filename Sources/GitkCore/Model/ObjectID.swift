// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// A git object name: SHA-1 (20 bytes, 40 hex digits) or SHA-256 (32 bytes,
/// 64 hex digits), stored inline without heap allocation (design D4).
///
/// Bytes are packed big-endian into four words, so comparing the words in
/// order is the same as comparing the bytes in order. Unused trailing bytes
/// are always zero.
public struct ObjectID: Sendable, Hashable, Comparable, CustomStringConvertible {
    private var w0: UInt64
    private var w1: UInt64
    private var w2: UInt64
    private var w3: UInt64
    /// Number of significant bytes: 20 or 32.
    private var byteCount: UInt8

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    private init(w0: UInt64, w1: UInt64, w2: UInt64, w3: UInt64, byteCount: UInt8) {
        self.w0 = w0
        self.w1 = w1
        self.w2 = w2
        self.w3 = w3
        self.byteCount = byteCount
    }

    /// Parses 40 or 64 lowercase hex characters. Any other length, any
    /// non-hex character and any uppercase letter yields nil (git prints
    /// lowercase only).
    public init?(hex: String) {
        var words: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
        var count = 0
        for unit in hex.utf8 {
            let nibble: UInt64
            switch unit {
            case 0x30...0x39: nibble = UInt64(unit - 0x30)
            case 0x61...0x66: nibble = UInt64(unit - 0x61 + 10)
            default: return nil
            }
            if count >= 64 { return nil }
            let shift = UInt64(60 - (count % 16) * 4)
            switch count / 16 {
            case 0: words.0 |= nibble << shift
            case 1: words.1 |= nibble << shift
            case 2: words.2 |= nibble << shift
            default: words.3 |= nibble << shift
            }
            count += 1
        }
        guard count == 40 || count == 64 else { return nil }
        self.init(w0: words.0, w1: words.1, w2: words.2, w3: words.3,
                  byteCount: UInt8(count / 2))
    }

    /// Number of hex digits: 40 (SHA-1) or 64 (SHA-256).
    public var hexLength: Int { Int(byteCount) * 2 }

    /// The full lowercase hex string.
    public var hex: String {
        let digits = ObjectID.hexDigits
        var out = [UInt8]()
        out.reserveCapacity(hexLength)
        for index in 0..<hexLength {
            let word: UInt64
            switch index / 16 {
            case 0: word = w0
            case 1: word = w1
            case 2: word = w2
            default: word = w3
            }
            let nibble = Int((word >> UInt64(60 - (index % 16) * 4)) & 0xF)
            out.append(digits[nibble])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The first `n` hex digits, clamped to 0...`hexLength`.
    public func abbreviated(_ n: Int) -> String {
        String(hex.prefix(max(0, n)))
    }

    public var description: String { hex }

    /// gitk `nullid`: the pseudo commit for unstaged local changes, all zeros.
    /// Its length depends on the repository's hash algorithm, so it is a
    /// function of the hash length in hex digits (40 or 64) rather than a
    /// constant. Returns nil for any other length.
    public static func localUnstaged(hashLength: Int) -> ObjectID? {
        guard hashLength == 40 || hashLength == 64 else { return nil }
        return ObjectID(w0: 0, w1: 0, w2: 0, w3: 0, byteCount: UInt8(hashLength / 2))
    }

    /// gitk `nullid2`: the pseudo commit for staged changes, zeros ending in
    /// `1`. Same sizing rule as ``localUnstaged(hashLength:)``.
    public static func localStaged(hashLength: Int) -> ObjectID? {
        guard var id = localUnstaged(hashLength: hashLength) else { return nil }
        // The last hex digit is the low nibble of the last significant byte:
        // word 2 for 20 bytes (its low 32 bits are unused), word 3 for 32.
        if hashLength == 40 {
            id.w2 = 1 << 32
        } else {
            id.w3 = 1
        }
        return id
    }

    public static func < (lhs: ObjectID, rhs: ObjectID) -> Bool {
        if lhs.w0 != rhs.w0 { return lhs.w0 < rhs.w0 }
        if lhs.w1 != rhs.w1 { return lhs.w1 < rhs.w1 }
        if lhs.w2 != rhs.w2 { return lhs.w2 < rhs.w2 }
        if lhs.w3 != rhs.w3 { return lhs.w3 < rhs.w3 }
        return lhs.byteCount < rhs.byteCount
    }
}
