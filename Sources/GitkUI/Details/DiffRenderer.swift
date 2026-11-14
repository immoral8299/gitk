// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Turns parsed diff lines into attributed text for the current Diff/Old/New
/// mode and word-diff style (design D7).
@MainActor
struct DiffRenderer {
    var settings: Settings
    var mode: DiffDisplayMode = .diff
    var wordMode: WordDiffMode = .line
    var encoding: String = "utf-8"
    private var words = WordDiffParser()

    init(settings: Settings, mode: DiffDisplayMode = .diff, wordMode: WordDiffMode = .line) {
        self.settings = settings
        self.mode = mode
        self.wordMode = wordMode
    }

    var base: [NSAttributedString.Key: Any] {
        [.font: MainLayoutMetrics.nsFont(settings.textFont), .foregroundColor: Palette.foreground(settings)]
    }

    private func styled(_ attrs: inout [NSAttributedString.Key: Any], side: Int) {
        attrs[.foregroundColor] = Palette.diff(settings, side)
        attrs[.backgroundColor] = Palette.diffBackground(settings, side)
    }

    /// A file separator line (gitk's `filesep` tag); `DiffTextView` draws its
    /// full-width bar.
    private func separatorAttributes() -> [NSAttributedString.Key: Any] {
        var attrs = base
        let font = MainLayoutMetrics.nsFont(settings.textFont)
        attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        attrs[.foregroundColor] = Palette.fileSeparatorForeground(settings)
        attrs[DiffTextView.separatorKey] = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 8
        attrs[.paragraphStyle] = paragraph
        return attrs
    }

    /// Port of gitk proc `parseblobdiffline` (gitk/gitk 8272–8542), the display part.
    mutating func render(_ line: DiffLine) -> NSAttributedString {
        if wordMode != .line {
            switch words.feed(line) {
            case .pending: return NSAttributedString(string: "")
            case .line(let runs):
                let result = NSMutableAttributedString(string: "")
                for run in runs {
                    var attrs = base
                    let data: Data
                    var pre = "", post = ""
                    switch run {
                    case .same(let value): data = value
                    case .added(let value):
                        if mode == .old { continue }
                        data = value
                        styled(&attrs, side: 1)
                        if wordMode == .markup { pre = "{+"; post = "+}" }
                    case .removed(let value):
                        if mode == .new { continue }
                        data = value
                        styled(&attrs, side: 0)
                        if wordMode == .markup { pre = "[-"; post = "-]" }
                    }
                    result.append(NSAttributedString(string: pre + decode(data) + post, attributes: attrs))
                }
                result.append(NSAttributedString(string: "\n", attributes: base))
                return result
            case .passthrough: break
            }
        }
        var attrs = base
        let text: String
        switch line {
        case .fileHeader(let old, let new, _):
            text = old != new ? "\(old ?? "/dev/null") → \(new ?? "/dev/null")" : (new ?? old ?? "")
            attrs = separatorAttributes()
        case .add(let data):
            if mode == .old { return NSAttributedString(string: "") }
            text = (mode == .diff ? "+" : "") + decode(data)
            styled(&attrs, side: 1)
        case .remove(let data):
            if mode == .new { return NSAttributedString(string: "") }
            text = (mode == .diff ? "-" : "") + decode(data)
            styled(&attrs, side: 0)
        case .context(let data): text = (mode == .diff ? " " : "") + decode(data)
        case .hunkHeader(let data, _):
            text = decode(data)
            attrs[.foregroundColor] = Palette.diff(settings, 2)
        case .combined(let markers, let data):
            let result = NSMutableAttributedString(string: "")
            for (index, marker) in markers.enumerated() {
                var markerAttrs = base
                markerAttrs[.foregroundColor] = Palette.merge(settings, index)
                result.append(NSAttributedString(string: String(marker), attributes: markerAttrs))
            }
            result.append(NSAttributedString(string: decode(data) + "\n", attributes: attrs))
            return result
        case .headerLine(let data), .binary(let data), .submodule(let data), .other(let data):
            text = decode(data)
            attrs[.foregroundColor] = NSColor.secondaryLabelColor
        }
        return NSAttributedString(string: text + "\n", attributes: attrs)
    }

    private func decode(_ data: Data) -> String { TextDecoder.decode(data, encodingName: encoding) }
}

/// The diff pane below the history list (design D16): streams `git diff-tree`
/// output for the selected commit into a TextKit 1 text view.
@MainActor
final class DiffPane: NSObject {
    let textView = DiffTextView(usingTextLayoutManager: false)
    let scrollView = NSScrollView()
    var settings: Settings
    var options: DiffOptions
    var mode: DiffDisplayMode = .diff
    private(set) var document = DiffDocument()
    /// Character offset of each file separator in the text.
    private(set) var sectionOffsets: [Int] = []
    var onSectionsChanged: (([DiffFileSection]) -> Void)?
    private var task: Task<Void, Never>?
    private var process: GitProcess?
    private var generation: UInt64 = 0
    private var renderer: DiffRenderer
    private weak var session: ViewSession?
    private(set) var ids: [ObjectID] = []
    private var renderedLines = 0

    init(settings: Settings, hashLength: Int) {
        self.settings = settings
        options = DiffOptions(context: settings.diffContext, hashLength: hashLength)
        renderer = DiffRenderer(settings: settings)
        super.init()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = Palette.background(settings)
        textView.separatorColor = Palette.fileSeparatorBackground(settings)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        // Diffs never wrap; long lines scroll sideways (gitk's ctext -wrap none).
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.background(settings)
        scrollView.documentView = textView
    }

    /// Shows the patch of `id` (gitk's `startdiff`/`mergediff`).
    func show(_ id: ObjectID, session: ViewSession) {
        self.session = session
        options.logShowRoot = session.repo.logShowRoot
        options.limitPaths = settings.limitDiffs ? session.view.files : nil
        fetch(ids: [id], session: session)
    }

    /// Diff between two commits (task 16.2).
    func showDiff(from: ObjectID, to: ObjectID, session: ViewSession) {
        self.session = session
        fetch(ids: [from, to], session: session)
    }

    func clear() {
        cancel()
        ids = []
        document = DiffDocument()
        sectionOffsets = []
        textView.textStorage?.setAttributedString(NSAttributedString())
        onSectionsChanged?([])
    }

    func refetch() {
        guard let session, !ids.isEmpty else { return }
        let position = scrollView.contentView.bounds.origin
        fetch(ids: ids, session: session, restore: position)
    }

    /// Port of gitk procs `getblobdiffs` and `getblobdiffline` (gitk/gitk 8203–8272):
    /// stream the diff, parse each line, and paint in batches.
    private func fetch(ids: [ObjectID], session: ViewSession, restore: NSPoint? = nil) {
        cancel()
        let token = generation
        self.ids = ids
        document = DiffDocument()
        renderedLines = 0
        sectionOffsets = []
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session.repo.guiEncoding
        textView.textStorage?.setAttributedString(NSAttributedString())
        scrollView.contentView.scroll(to: .zero)
        onSectionsChanged?([])
        let child = session.runner.stream(DiffCommandBuilder.blobDiff(ids: ids, options: options))
        process = child
        task = Task { [weak self] in
            guard let self else { return }
            var lastPaint = ContinuousClock.now
            do {
                for try await line in child.records(separator: 10) {
                    guard generation == token, !Task.isCancelled else { return }
                    document.append(line)
                    if document.lines.count % 500 == 0 || lastPaint.duration(to: .now) > .milliseconds(50) {
                        appendPending()
                        lastPaint = .now
                        await Task.yield()
                    }
                }
                guard generation == token, !Task.isCancelled else { return }
                appendPending()
                if let restore { scrollView.contentView.scroll(to: restore) }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                Alerts().showError(L("Error getting diffs: %s", error.localizedDescription), parent: scrollView.window)
            }
        }
    }

    /// Waits for the current diff to finish streaming (snapshots).
    func waitUntilLoaded() async { await task?.value }

    private func appendPending() {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        let end = min(document.lines.count, document.lineLimit)
        while renderedLines < end {
            let line = document.lines[renderedLines]
            if case .fileHeader = line { sectionOffsets.append(storage.length) }
            storage.append(renderer.render(line))
            renderedLines += 1
        }
        storage.endEditing()
        onSectionsChanged?(document.sections)
    }

    /// Re-renders from the model, e.g. after a Diff/Old/New change.
    func renderAgain() {
        let position = scrollView.contentView.bounds.origin
        textView.textStorage?.setAttributedString(NSAttributedString())
        renderedLines = 0
        sectionOffsets = []
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session?.repo.guiEncoding ?? "utf-8"
        appendPending()
        scrollView.contentView.scroll(to: position)
    }

    func showAllLines() { document.lineLimit = Int.max; appendPending() }

    /// Scrolls file section `index` (0-based) to the top of the pane.
    func jumpToFile(_ index: Int) {
        guard sectionOffsets.indices.contains(index), let manager = textView.layoutManager,
              let container = textView.textContainer else { return }
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: sectionOffsets[index], length: 1), actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let y = rect.minY + textView.textContainerOrigin.y - textView.textContainerInset.height
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func cancel() { generation &+= 1; task?.cancel(); task = nil; process?.cancel(); process = nil }
}

/// The diff text view. Draws gitk's full-width file separator bars behind the
/// lines marked with `separatorKey`, across the whole visible width.
final class DiffTextView: NSTextView {
    static let separatorKey = NSAttributedString.Key("gitk.fileSeparator")
    var separatorColor: NSColor = .tertiarySystemFill

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let manager = layoutManager, let container = textContainer, let storage = textStorage else { return }
        let origin = textContainerOrigin
        let glyphs = manager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        separatorColor.setFill()
        storage.enumerateAttribute(Self.separatorKey, in: characters) { value, range, _ in
            guard value != nil else { return }
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)) { line, used, _, _, _ in
                // The fragment includes the spacing above the line; the bar covers only the text.
                let top = line.maxY - used.height
                NSRect(x: rect.minX, y: top + origin.y, width: rect.width, height: used.height).fill()
            }
        }
    }
}
