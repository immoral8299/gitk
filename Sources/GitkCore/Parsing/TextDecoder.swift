// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Decodes raw bytes from git or files into `String`s the way gitk's
/// `convertfrom -profile tcl8` does.
///
/// Port of gitk's encoding handling (gitk/gitk lines 36–55 and `tcl_encoding`
/// at 12420). Bytes that are invalid in the named encoding never cause the
/// whole text to be dropped: valid runs decode normally and each invalid byte
/// becomes the Unicode scalar with the same value (ISO-8859-1 style).
public enum TextDecoder {
    /// Result of a decode that also says whether the encoding name was known.
    public struct Result: Equatable, Sendable {
        public let text: String
        /// True when `encodingName` was given but is not a known encoding, so
        /// UTF-8 was used. Callers should warn the user.
        public let unknownEncoding: Bool
    }

    /// Decodes `data` using the IANA charset name `encodingName`.
    /// A nil or empty name means UTF-8.
    public static func decode(_ data: Data, encodingName: String?) -> String {
        decodeReporting(data, encodingName: encodingName).text
    }

    /// Like `decode(_:encodingName:)`, but also reports an unknown encoding name.
    public static func decodeReporting(_ data: Data, encodingName: String?) -> Result {
        guard let name = encodingName, !name.isEmpty else {
            return Result(text: decodeUTF8(data), unknownEncoding: false)
        }
        guard let encoding = resolve(name) else {
            return Result(text: decodeUTF8(data), unknownEncoding: true)
        }
        if encoding == .utf8 {
            return Result(text: decodeUTF8(data), unknownEncoding: false)
        }
        if let strict = String(data: data, encoding: encoding) {
            return Result(text: strict, unknownEncoding: false)
        }
        return Result(text: decodeLatin1(data), unknownEncoding: false)
    }

    /// Maps an IANA charset name to a Foundation encoding, or nil if unknown.
    static func resolve(_ name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != 0 else { return nil }
        return String.Encoding(rawValue: nsEncoding)
    }

    /// Decodes UTF-8 strictly per byte: a valid sequence becomes its scalar, and
    /// any byte that does not start a valid sequence becomes U+00XX.
    static func decodeUTF8(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var scalars = String.UnicodeScalarView()
        var index = 0
        while index < bytes.count {
            let lead = bytes[index]
            if lead < 0x80 {
                scalars.append(Unicode.Scalar(lead))
                index += 1
                continue
            }
            if let (scalar, length) = utf8Sequence(bytes, at: index) {
                scalars.append(scalar)
                index += length
            } else {
                scalars.append(Unicode.Scalar(lead))
                index += 1
            }
        }
        return String(scalars)
    }

    /// Decodes one multi-byte UTF-8 sequence starting at `index`, or nil if the
    /// bytes there are not a complete, well-formed sequence.
    private static func utf8Sequence(_ bytes: [UInt8], at index: Int) -> (Unicode.Scalar, Int)? {
        let lead = bytes[index]
        let length: Int
        var value: UInt32
        let minimum: UInt32
        switch lead {
        case 0xC2...0xDF:
            length = 2
            value = UInt32(lead & 0x1F)
            minimum = 0x80
        case 0xE0...0xEF:
            length = 3
            value = UInt32(lead & 0x0F)
            minimum = 0x800
        case 0xF0...0xF4:
            length = 4
            value = UInt32(lead & 0x07)
            minimum = 0x10000
        default:
            return nil
        }
        guard index + length <= bytes.count else { return nil }
        for offset in 1..<length {
            let continuation = bytes[index + offset]
            guard continuation & 0xC0 == 0x80 else { return nil }
            value = (value << 6) | UInt32(continuation & 0x3F)
        }
        guard value >= minimum, let scalar = Unicode.Scalar(value) else { return nil }
        return (scalar, length)
    }

    /// Maps every byte to the scalar with the same value.
    static func decodeLatin1(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in data {
            scalars.append(Unicode.Scalar(byte))
        }
        return String(scalars)
    }
}
