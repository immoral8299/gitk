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

    /// The separator line for a file section, from the section's final paths
    /// (gitk shows `old -> new` for renames and copies).
    func separator(for section: DiffFileSection) -> NSAttributedString {
        let old = section.oldPath, new = section.newPath
        let text = old != nil && new != nil && old != new ? "\(old!) → \(new!)" : (new ?? old ?? "")
        return NSAttributedString(string: text + "\n", attributes: separatorAttributes())
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
    /// The pane as installed in the window: the controls bar over the text.
    let view = DiffPaneView()
    let controls: DiffControlsBar
    var settings: Settings
    var options: DiffOptions
    var mode: DiffDisplayMode = .diff
    private(set) var document = DiffDocument()
    /// Character offset of each file separator in the text.
    private(set) var sectionOffsets: [Int] = []
    /// Called as file sections stream in (and with an empty document on clear).
    var onSectionsChanged: ((DiffDocument) -> Void)?
    /// The file whose separator is at or above the top of the pane (13.2).
    var onTopSectionChanged: ((Int?) -> Void)?
    private var topSection: Int?
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
        controls = DiffControlsBar(context: settings.diffContext)
        super.init()
        view.controls = controls
        view.scrollView = scrollView
        controls.onModeChange = { [weak self] mode in
            self?.mode = mode
            self?.renderAgain()
        }
        controls.onOptionsChange = { [weak self] context, ignoreSpace, wordDiff in
            guard let self else { return }
            options.context = context
            options.ignoreSpace = ignoreSpace
            options.wordDiff = wordDiff
            refetch()
        }
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    /// Port of gitk proc `highlightfile_for_scrollpos`: report the file at the top.
    @objc private func scrolled() { updateTopSection() }

    /// The character at the top of the visible text.
    private func topCharacterIndex() -> Int? {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              (textView.textStorage?.length ?? 0) > 0 else { return nil }
        let top = NSPoint(x: 0, y: scrollView.contentView.bounds.minY - textView.textContainerOrigin.y + 1)
        return manager.characterIndexForGlyph(at: manager.glyphIndex(for: top, in: container))
    }

    private func updateTopSection() {
        var section: Int?
        if !sectionOffsets.isEmpty, let top = topCharacterIndex() {
            section = DiffDocument.section(at: top, sectionStarts: sectionOffsets) ?? 0
        }
        guard section != topSection else { return }
        topSection = section
        onTopSectionChanged?(section)
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
        onSectionsChanged?(document)
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
        onSectionsChanged?(document)
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
                        appendPending(final: false)
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

    /// Applies `GITK_SWIFT_DIFF_OPTIONS` for snapshots: comma-separated
    /// `context=N`, `words=line|markup|color`, `mode=diff|old|new`, `ignorespace`.
    func applySnapshotOptions(_ text: String) {
        for item in text.split(separator: ",") {
            let parts = item.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            switch (parts.first, parts.count > 1 ? parts[1] : nil) {
            case ("context", let value?): controls.context.stringValue = value; controls.contextStepper.integerValue = Int(value) ?? 3
            case ("words", let value?): controls.wordDiff.selectItem(at: ["line", "markup", "color"].firstIndex(of: value) ?? 0)
            case ("mode", let value?): controls.mode.selectedSegment = ["diff", "old", "new"].firstIndex(of: value) ?? 0
            case ("ignorespace", _): controls.ignoreSpace.state = .on
            default: break
            }
        }
        options.context = max(0, controls.context.integerValue)
        options.ignoreSpace = controls.ignoreSpace.state == .on
        options.wordDiff = controls.wordDiffMode
        mode = controls.displayMode
    }

    /// Waits for the current diff to finish streaming (snapshots).
    func waitUntilLoaded() async { await task?.value }

    /// Renders the lines parsed since the last call. A file separator waits
    /// until its header lines have arrived (unless `final`), because a rename's
    /// paths are only known from the `rename from`/`rename to` lines after it.
    private func appendPending(final: Bool = true) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        let end = min(document.lines.count, document.lineLimit)
        while renderedLines < end {
            let line = document.lines[renderedLines]
            if case .fileHeader = line {
                let index = sectionOffsets.count
                if !final, document.lines.count - renderedLines < 12, document.sections.count <= index + 1,
                   !document.lines[(renderedLines + 1)...].contains(where: { if case .hunkHeader = $0 { true } else { false } }) {
                    break
                }
                sectionOffsets.append(storage.length)
                if document.sections.indices.contains(index) {
                    storage.append(renderer.separator(for: document.sections[index]))
                    renderedLines += 1
                    continue
                }
            }
            storage.append(renderer.render(line))
            renderedLines += 1
        }
        storage.endEditing()
        onSectionsChanged?(document)
        updateTopSection()
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
        guard sectionOffsets.indices.contains(index) else { return }
        scroll(toCharacter: sectionOffsets[index])
    }

    /// Scrolls so the line holding `offset` is at the top (offset 0: the very top).
    private func scroll(toCharacter offset: Int) {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        var y: CGFloat = 0
        if offset > 0, let length = textView.textStorage?.length, offset < length {
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: offset, length: 1), actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            y = rect.minY + textView.textContainerOrigin.y - textView.textContainerInset.height
        }
        scroll(toY: y)
    }

    private func scroll(toY y: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// `f` and `b` (gitk `nextfile`/`prevfile`).
    func jumpFile(forward: Bool) {
        let top = topCharacterIndex() ?? 0
        guard let target = DiffDocument.fileJump(from: top, sectionStarts: sectionOffsets, forward: forward) else { return }
        scroll(toCharacter: target)
    }

    /// Space, Delete/Backspace, `d` and `u` (gitk binds these on `$ctext`).
    func scroll(_ step: AppCommand.ScrollStep) {
        let clip = scrollView.contentView
        let line = textView.layoutManager?.defaultLineHeight(for: textView.font ?? MainLayoutMetrics.nsFont(settings.textFont)) ?? 14
        switch step {
        case .lines(let n): scroll(toY: clip.bounds.minY + CGFloat(n) * line)
        case .pages(let n): scroll(toY: clip.bounds.minY + CGFloat(n) * max(line, clip.bounds.height - line))
        case .toStart: scroll(toY: 0)
        case .toEnd: scroll(toY: .greatestFiniteMagnitude)
        }
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

/// The diff pane's container: `DiffControlsBar` on top, the text below.
final class DiffPaneView: NSView {
    var controls: NSView? { didSet { oldValue?.removeFromSuperview(); controls.map(addSubview) } }
    var scrollView: NSView? { didSet { oldValue?.removeFromSuperview(); scrollView.map(addSubview) } }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let bar = DiffControlsBar.height
        controls?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bar)
        scrollView?.frame = NSRect(x: 0, y: bar, width: bounds.width, height: max(0, bounds.height - bar))
    }
}
