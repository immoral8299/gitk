// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct TextDecoderTests {
    @Test func decodesUTF8() {
        let data = Data("héllo, 世界".utf8)
        #expect(TextDecoder.decode(data, encodingName: "UTF-8") == "héllo, 世界")
        #expect(TextDecoder.decode(data, encodingName: nil) == "héllo, 世界")
    }

    @Test func decodesLatin1() {
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in ISO-8859-1
        let result = TextDecoder.decodeReporting(data, encodingName: "ISO-8859-1")
        #expect(result.text == "café")
        #expect(!result.unknownEncoding)
    }

    @Test func decodesShiftJIS() throws {
        let data = try #require("日本語".data(using: .shiftJIS))
        let result = TextDecoder.decodeReporting(data, encodingName: "Shift_JIS")
        #expect(result.text == "日本語")
        #expect(!result.unknownEncoding)
    }

    @Test func keepsInvalidUTF8BytesAsLatin1Scalars() {
        // "a", an invalid 0xFF, "b", then a truncated three-byte sequence.
        let data = Data([0x61, 0xFF, 0x62, 0xE6, 0x97])
        let result = TextDecoder.decodeReporting(data, encodingName: "utf-8")
        #expect(result.text == "a\u{FF}b\u{E6}\u{97}")
        #expect(!result.unknownEncoding)
    }

    @Test func rejectsOverlongAndSurrogateUTF8() {
        // Overlong encoding of "/" (C0 AF) and an encoded surrogate (ED A0 80).
        let data = Data([0xC0, 0xAF, 0xED, 0xA0, 0x80])
        #expect(TextDecoder.decode(data, encodingName: "utf-8") == "\u{C0}\u{AF}\u{ED}\u{A0}\u{80}")
    }

    @Test func unknownNameFallsBackToUTF8AndReports() {
        let data = Data("abc".utf8)
        let result = TextDecoder.decodeReporting(data, encodingName: "x-no-such-charset")
        #expect(result.text == "abc")
        #expect(result.unknownEncoding)
        #expect(TextDecoder.decode(data, encodingName: "x-no-such-charset") == "abc")
    }
}
