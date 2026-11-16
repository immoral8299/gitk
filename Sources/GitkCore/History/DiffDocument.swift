// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum DiffDisplayMode: Sendable { case diff, old, new }

/// A chunk of diff lines parsed off the main actor by
/// `DiffDocument.parsedBatches`, ready for `DiffDocument.append(_:)`.
/// `sections` is the producer's complete section list at the time of the
/// batch; `startLine`s are indexes into the whole stream.
public struct ParsedBatch: Sendable {
    public var lines: [DiffLine]
    public var rawLines: [Data]
    public var sections: [DiffFileSection]
    /// Lines parsed by the producer so far, stream-wide.
    public var lineCount: Int

    public init(lines: [DiffLine], rawLines: [Data], sections: [DiffFileSection], lineCount: Int) {
        self.lines = lines
        self.rawLines = rawLines
        self.sections = sections
        self.lineCount = lineCount
    }
}

public struct DiffDocument: Sendable {
    public private(set) var lines: [DiffLine] = []
    public private(set) var rawLines: [Data] = []
    public private(set) var sections: [DiffFileSection] = []
    /// The streaming parser behind `append(_:)`. Only meaningful for callers
    /// that feed one line at a time; the batch path (`append(_:)` with a
    /// `ParsedBatch`, produced by `parsedBatches`) parses off the main actor
    /// and records the same state directly.
    public private(set) var parser = DiffParser()
    public var lineLimit: Int = 200_000
    public init() {}
    public var hiddenLineCount: Int { max(0, lines.count - lineLimit) }
    /// Lines added and removed in each file section, aligned with `sections`.
    /// For a combined diff a line counts as added if any parent marker is `+`,
    /// else as removed if any is `-`.
    public private(set) var addedPerFile: [Int] = []
    public private(set) var removedPerFile: [Int] = []
    public var totalAdded: Int { addedPerFile.reduce(0, +) }
    public var totalRemoved: Int { removedPerFile.reduce(0, +) }

    /// Port of gitk proc `parseblobdiffline` (gitk/gitk 8231–8542): classify one
    /// streamed line and record file sections.
    public mutating func append(_ raw: Data) {
        let line = parser.parse(line: raw)
        mirrorSections()
        lines.append(line)
        rawLines.append(raw)
        while addedPerFile.count < parser.sections.count {
            addedPerFile.append(0)
            removedPerFile.append(0)
        }
        guard !addedPerFile.isEmpty else { return }
        switch line {
        case .add: addedPerFile[addedPerFile.count - 1] += 1
        case .remove: removedPerFile[removedPerFile.count - 1] += 1
        case .combined(let markers, _):
            if markers.contains("+") { addedPerFile[addedPerFile.count - 1] += 1 }
            else if markers.contains("-") { removedPerFile[removedPerFile.count - 1] += 1 }
        default: break
        }
    }

    /// Adds a chunk parsed by `parsedBatches`, extending the file sections and
    /// the per-file add/remove counts exactly as one-line `append(_:)` does: a
    /// section born on a line is padded before that line is counted.
    public mutating func append(_ batch: ParsedBatch) {
        let base = lines.count
        lines.append(contentsOf: batch.lines)
        rawLines.append(contentsOf: batch.rawLines)
        // `batch.sections` mirrors the producer's whole section list, so the
        // shared head is refreshed (a rename can fill in paths after the
        // section was created) and the tail is appended.
        let shared = min(sections.count, batch.sections.count)
        for i in 0..<shared where sections[i] != batch.sections[i] { sections[i] = batch.sections[i] }
        if batch.sections.count > shared { sections.append(contentsOf: batch.sections[shared...]) }
        var cursor = addedPerFile.count
        for (local, line) in batch.lines.enumerated() {
            let at = base + local
            while cursor < batch.sections.count, batch.sections[cursor].startLine <= at {
                addedPerFile.append(0)
                removedPerFile.append(0)
                cursor += 1
            }
            guard !addedPerFile.isEmpty else { continue }
            switch line {
            case .add: addedPerFile[addedPerFile.count - 1] += 1
            case .remove: removedPerFile[removedPerFile.count - 1] += 1
            case .combined(let markers, _):
                if markers.contains("+") { addedPerFile[addedPerFile.count - 1] += 1 }
                else if markers.contains("-") { removedPerFile[removedPerFile.count - 1] += 1 }
            default: break
            }
        }
    }

    /// Makes `sections` match `parser.sections`: new sections are appended, and
    /// the last one is re-copied because header lines that follow a section
    /// (`rename from`, `deleted file`, `Binary files …`) fill in its paths and
    /// status afterwards.
    private mutating func mirrorSections() {
        while sections.count < parser.sections.count { sections.append(parser.sections[sections.count]) }
        if !sections.isEmpty { sections[sections.count - 1] = parser.sections[parser.sections.count - 1] }
    }

    /// Parses `records` (diff lines without their trailing newline) into
    /// batches on a detached task, so the main actor neither splits records nor
    /// classifies lines while a diff streams. Batches hold at most 2,000 lines
    /// and flush early once 50 ms have passed, mirroring
    /// `AncestryIndex.parsedBatches`.
    public static func parsedBatches(
        _ records: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<ParsedBatch, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                var parser = DiffParser()
                var lastFlush = ContinuousClock.now
                var batch = ParsedBatch(lines: [], rawLines: [], sections: [], lineCount: 0)
                do {
                    for try await record in records {
                        batch.lines.append(parser.parse(line: record))
                        batch.rawLines.append(record)
                        // Mirror the parser's section list: new sections are
                        // appended, the last one is re-copied because header
                        // lines after it fill in its paths and status.
                        while batch.sections.count < parser.sections.count {
                            batch.sections.append(parser.sections[batch.sections.count])
                        }
                        if !batch.sections.isEmpty {
                            batch.sections[batch.sections.count - 1] = parser.sections[parser.sections.count - 1]
                        }
                        batch.lineCount = parser.lineCount
                        let now = ContinuousClock.now
                        if batch.lines.count >= 2000 || (!batch.lines.isEmpty && now - lastFlush >= .milliseconds(50)) {
                            continuation.yield(batch)
                            batch = ParsedBatch(lines: [], rawLines: [], sections: batch.sections, lineCount: parser.lineCount)
                            lastFlush = now
                        }
                    }
                    if !batch.lines.isEmpty { continuation.yield(batch) }
                    continuation.finish()
                } catch {
                    if !batch.lines.isEmpty { continuation.yield(batch) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Ports of gitk procs `nextfile` and `prevfile` (gitk/gitk 8574–8603): the
    /// file start to scroll to from `offset` (the top of the pane). Forward is
    /// the first start after `offset` (nil at the last file); backward is the
    /// last start before it, or the top of the text.
    public static func fileJump(from offset: Int, sectionStarts: [Int], forward: Bool) -> Int? {
        if forward { return sectionStarts.first { $0 > offset } }
        return sectionStarts.last { $0 < offset } ?? 0
    }

    /// Port of gitk proc `highlightfile_for_scrollpos` (gitk/gitk 8560–8572): the
    /// file whose section starts at or above `offset` (a character offset or a
    /// line number, matching `sectionStarts`); nil above the first file.
    public static func section(at offset: Int, sectionStarts: [Int]) -> Int? {
        var low = 0, high = sectionStarts.count
        while low < high {
            let mid = (low + high) / 2
            if sectionStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    public func visibleIndices(mode: DiffDisplayMode) -> [Int] {
        lines.prefix(lineLimit).enumerated().compactMap { index, line in
            switch (mode, line) {
            case (.old, .add), (.new, .remove): nil
            default: index
            }
        }
    }

    /// Port of gitk procs `nextfile`, `prevfile` (gitk/gitk 8574–8603).
    public func fileSection(at line: Int) -> Int? { sections.lastIndex { $0.startLine <= line } }
    public func fileJump(from line: Int, forward: Bool) -> Int? {
        forward ? sections.first(where: { $0.startLine > line })?.startLine
            : sections.last(where: { $0.startLine < line })?.startLine
    }

    /// The path whose attributes decide the encoding of line `index`: the new
    /// path of its file section, else the old one.
    public func path(ofLine index: Int) -> String? {
        guard let section = fileSection(at: index).map({ sections[$0] }) else { return nil }
        return section.newPath ?? section.oldPath
    }

    /// Text of line `index` (without its marker) decoded with the per-file
    /// encoding, as gitk does through `get_path_encoding` (gitk/gitk 12504–12514).
    public func text(ofLine index: Int, attributes: GitAttributes, guiEncoding: String,
                     perFileAttrs: Bool) async -> String {
        guard lines.indices.contains(index) else { return "" }
        let data: Data
        switch lines[index] {
        case .add(let d), .remove(let d), .context(let d), .headerLine(let d), .hunkHeader(let d, _),
             .binary(let d), .submodule(let d), .other(let d): data = d
        case .combined(_, let d): data = d
        case .fileHeader: data = rawLines[index]
        }
        return await attributes.decode(data, path: path(ofLine: index), guiEncoding: guiEncoding,
                                       perFileAttrs: perFileAttrs)
    }
}
