// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Splits a byte stream, delivered in arbitrary chunks, into records ended by
/// a separator byte (0x00 for `-z` output, 0x0A for line output).
///
/// The separator is not part of a record. Empty records between two
/// separators are kept. A trailing separator does not start another record.
public struct RecordSplitter: Sendable {
    public let separator: UInt8
    private var pending = Data()

    public init(separator: UInt8) {
        self.separator = separator
    }

    /// Adds `chunk` and returns every record it completed, in order.
    public mutating func feed(_ chunk: Data) -> [Data] {
        var records: [Data] = []
        var start = chunk.startIndex
        while let hit = chunk[start...].firstIndex(of: separator) {
            if pending.isEmpty {
                records.append(Data(chunk[start..<hit]))
            } else {
                pending.append(chunk[start..<hit])
                records.append(pending)
                pending = Data()
            }
            start = chunk.index(after: hit)
        }
        pending.append(chunk[start...])
        return records
    }

    /// Call at EOF: the final record when the stream did not end with the
    /// separator, nil when there is none.
    public mutating func finish() -> Data? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return pending
    }
}
