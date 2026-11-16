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

    /// The file name line above a blob shown in Tree mode (gitk's `filesep` in `showfile`).
    func blobSeparator(path: String) -> NSAttributedString {
        NSAttributedString(string: path + "\n", attributes: separatorAttributes())
    }

    /// A blob's text in the pane's plain style.
    func blobText(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: base)
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
final class DiffPane: NSObject, NSTextViewDelegate {
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
    /// Character offset in the text of each document line (empty renders share
    /// the next line's offset); maps a click back to `document.lines`.
    private var lineOffsets: [Int] = []
    /// Called when "Show origin of this line" finds the commit that introduced a
    /// line: the commit, the file path and the line number in that commit.
    var onShowOrigin: ((ObjectID, String, Int) -> Void)?
    /// Called as file sections stream in (and with an empty document on clear).
    var onSectionsChanged: ((DiffDocument) -> Void)?
    /// The file whose separator is at or above the top of the pane (13.2).
    var onTopSectionChanged: ((Int?) -> Void)?
    private var topSection: Int?
    private var task: Task<Void, Never>?
    /// True once the current diff has streamed completely.
    private var finished = false
    /// Reports when a diff starts and stops streaming (the main window then
    /// holds back the history load so the selected diff comes first).
    var onLoadingChanged: ((Bool) -> Void)?
    private(set) var isLoading = false {
        didSet { if isLoading != oldValue { onLoadingChanged?(isLoading) } }
    }
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
        textView.delegate = self
        textView.menuProvider = { [weak self] in self?.contextMenu(atCharacter: $0) }
        textView.drawsBackground = true
        textView.backgroundColor = Palette.background(settings)
        textView.separatorColor = Palette.fileSeparatorBackground(settings)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        // Diffs never wrap; long lines scroll sideways (gitk's ctext -wrap none).
        // Apple's recipe for unwrapped text: the view is at least as wide as
        // the clip view and grows with its longest line.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
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

    /// Called when a commit link in a report (`showReport`) is clicked.
    var onSelectCommit: ((ObjectID) -> Void)?

    /// Shows plain report text (the patch-ID comparison); `.link` runs get the link colour.
    func showReport(_ text: NSAttributedString) {
        cancel()
        ids = []
        document = DiffDocument()
        sectionOffsets = []
        lineOffsets = []
        finished = true
        let styled = NSMutableAttributedString(string: text.string, attributes: renderer.base)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            if let link = attrs[.link] {
                styled.addAttributes([.link: link, .foregroundColor: Palette.link(settings)], range: range)
            }
        }
        textView.textStorage?.setAttributedString(styled)
        onSectionsChanged?(document)
    }

    /// Tree mode before a file is chosen: an empty pane bound to commit `id`.
    func showEmpty(id: ObjectID, session: ViewSession) {
        cancel()
        self.session = session
        ids = [id]
        document = DiffDocument()
        finished = true
        sectionOffsets = []
        lineOffsets = []
        textView.textStorage?.setAttributedString(NSAttributedString())
    }

    /// Tree mode: shows `path`'s blob in place of the patch. Port of gitk procs
    /// `showfile` and `getblobline` (gitk/gitk 7900–7960); `id` keeps the pane
    /// bound to the selected commit.
    func showBlob(path: String, blob: ObjectID, id: ObjectID, session: ViewSession) {
        showEmpty(id: id, session: session)
        let token = generation
        truncationNotice = nil
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session.repo.guiEncoding
        sectionOffsets = [0]
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let runner = session.runner
        let encoding = session.repo.guiEncoding
        let perFile = settings.perFileAttrs
        task = Task { [weak self] in
            do {
                let text = try await TreeOutline.blobText(blob, path: path, runner: runner, attributes: GitAttributes(runner: runner),
                                                          guiEncoding: encoding, perFileAttrs: perFile)
                guard let self, generation == token, !Task.isCancelled, let storage = textView.textStorage else { return }
                storage.beginEditing()
                storage.append(renderer.blobSeparator(path: path))
                storage.append(renderer.blobText(text))
                storage.endEditing()
            } catch {
                guard let self, generation == token, !Task.isCancelled else { return }
                Alerts().showError(L("Error getting diffs: %s", error.localizedDescription), parent: scrollView.window)
            }
        }
    }

    func clear() {
        cancel()
        ids = []
        document = DiffDocument()
        sectionOffsets = []
        lineOffsets = []
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
        truncationNotice = nil
        finished = false
        sectionOffsets = []
        lineOffsets = []
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session.repo.guiEncoding
        textView.textStorage?.setAttributedString(NSAttributedString())
        // Keep the horizontal offset when moving between commits; start at the top.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        onSectionsChanged?(document)
        let child = session.runner.stream(DiffCommandBuilder.blobDiff(ids: ids, options: options))
        process = child
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { isLoading = false } }
            do {
                // Record splitting and line parsing run on a detached task in
                // `parsedBatches`; the main actor only appends and paints.
                let batches = DiffDocument.parsedBatches(child.records(separator: 10))
                for try await batch in batches {
                    guard generation == token, !Task.isCancelled else { return }
                    document.append(batch)
                    appendPending(final: false)
                    await Task.yield()
                }
                guard generation == token, !Task.isCancelled else { return }
                appendPending()
                finished = true
                appendTruncationNotice()
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
            if lineOffsets.count == renderedLines { lineOffsets.append(storage.length) }
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
        truncationNotice = nil
        renderedLines = 0
        sectionOffsets = []
        lineOffsets = []
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session?.repo.guiEncoding ?? "utf-8"
        appendPending()
        if finished { appendTruncationNotice() }
        scrollView.contentView.scroll(to: position)
    }

    /// The "load the rest" control after a capped diff (design D7 risk).
    private static let showAllLink = "gitk-showall:"
    private var truncationNotice: NSRange?

    private func appendTruncationNotice() {
        guard document.hiddenLineCount > 0, let storage = textView.textStorage else { return }
        let text = L("%d more lines not shown.", document.hiddenLineCount)
        let notice = NSMutableAttributedString(string: "\n" + text + " ", attributes: renderer.base)
        notice.append(NSAttributedString(string: L("Show all"), attributes: [
            .font: renderer.base[.font] as Any, .link: Self.showAllLink, .foregroundColor: Palette.link(settings),
        ]))
        notice.append(NSAttributedString(string: "\n", attributes: renderer.base))
        truncationNotice = NSRange(location: storage.length, length: notice.length)
        storage.append(notice)
    }

    func showAllLines() {
        if let notice = truncationNotice, let storage = textView.textStorage, NSMaxRange(notice) <= storage.length {
            storage.deleteCharacters(in: notice)
        }
        truncationNotice = nil
        document.lineLimit = Int.max
        appendPending()
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let id = LinkHandling.commit(in: link) { onSelectCommit?(id); return true }
        guard (link as? String) == Self.showAllLink else { return false }
        showAllLines()
        return true
    }

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

    func cancel() {
        generation &+= 1; task?.cancel(); task = nil; process?.cancel(); process = nil
        isLoading = false
    }
}

/// The diff text view. Draws gitk's full-width file separator bars behind the
/// lines marked with `separatorKey`, across the whole visible width.
final class DiffTextView: NSTextView {
    /// The context menu for the character under the pointer (nil: no menu).
    var menuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menuProvider else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)
        return menuProvider(characterIndexForInsertion(at: point))
    }

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
        // Resizing must not move the text: keep the scroll origin (clamped).
        let scroll = scrollView as? NSScrollView
        let origin = scroll?.contentView.bounds.origin
        scrollView?.frame = NSRect(x: 0, y: bar, width: bounds.width, height: max(0, bounds.height - bar))
        if let scroll, let origin, let document = scroll.documentView {
            let clip = scroll.contentView
            let x = min(origin.x, max(0, document.frame.width - clip.bounds.width))
            let y = min(origin.y, max(0, document.frame.height - clip.bounds.height))
            if clip.bounds.origin != NSPoint(x: x, y: y) {
                clip.scroll(to: NSPoint(x: x, y: y))
                scroll.reflectScrolledClipView(clip)
            }
        }
    }
}

// MARK: - Line origin (task 13.6)

@MainActor
private final class LineMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { handler() }
}

extension DiffPane {
    /// The document line holding text offset `offset`.
    private func documentLine(atCharacter offset: Int) -> Int? {
        guard let last = lineOffsets.lastIndex(where: { $0 <= offset }) else { return nil }
        return last < renderedLines ? last : nil
    }

    private func textLines() -> [String] {
        document.rawLines.prefix(renderedLines).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Port of gitk proc `pop_diff_menu` (gitk/gitk 3698–3716): no menu on file
    /// or hunk separator lines.
    func contextMenu(atCharacter offset: Int) -> NSMenu? {
        guard let line = documentLine(atCharacter: offset), session != nil else { return nil }
        switch document.lines[line] {
        case .fileHeader, .hunkHeader, .headerLine, .binary, .submodule, .other: return nil
        default: break
        }
        guard let section = document.fileSection(at: line), document.sections.indices.contains(section),
              let path = document.sections[section].newPath ?? document.sections[section].oldPath else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(LineMenuItem(title: L("Show origin of this line")) { [weak self] in
            self?.showLineSource(line: line, path: path)
        })
        menu.addItem(LineMenuItem(title: L("Run git gui blame on this line")) { [weak self] in
            self?.externalBlameDiff(line: line, path: path)
        })
        return menu
    }

    private func blamePath(_ path: String) -> String {
        guard let session, !session.repo.cdup.isEmpty else { return path }
        return session.repo.cdup.hasSuffix("/") ? session.repo.cdup + path : session.repo.cdup + "/" + path
    }

    private func parentIDs() -> [ObjectID] {
        guard let session, let id = ids.first else { return [] }
        return LineOrigin.parents(of: id, in: session)
    }

    /// Port of gitk procs `external_blame_diff` and `external_blame` (gitk/gitk 3942–4031).
    private func externalBlameDiff(line: Int, path: String) {
        guard let session, let current = ids.first else { return }
        let spec = LineOrigin.blameSpec(diffLines: textLines(), at: line)
        let parentIndex = spec?.parentIndex ?? 0
        let lineNumber = spec?.line ?? 0
        let hashLength = session.repo.hashLength
        var base: ObjectID? = current
        if parentIndex > 0 {
            let parents = parentIDs()
            base = parents.indices.contains(parentIndex - 1) ? parents[parentIndex - 1] : nil
        }
        guard let base, base != ObjectID.localUnstaged(hashLength: hashLength),
              base != ObjectID.localStaged(hashLength: hashLength) else {
            Alerts().errorPopup(L("No such commit"), parent: scrollView.window)
            return
        }
        let process = Process()
        process.executableURL = session.runner.gitURL
        process.arguments = LineOrigin.guiArguments(revision: base.hex, path: blamePath(path), line: lineNumber)
        process.currentDirectoryURL = session.runner.cwd
        do { try process.run() } catch {
            Alerts().errorPopup("\(L("git gui blame: command failed:")) \(error.localizedDescription)", parent: scrollView.window)
        }
    }

    /// Port of gitk proc `show_line_source` (gitk/gitk 4033–4105).
    private func showLineSource(line: Int, path: String) {
        guard let session, let current = ids.first,
              let spec = LineOrigin.blameSpec(diffLines: textLines(), at: line) else { return }
        let window = scrollView.window
        if spec.parentIndex == 0 {
            markLine(line)
            return
        }
        let pi = spec.parentIndex - 1
        let hashLength = session.repo.hashLength
        let parents = parentIDs()
        let revision: FileRevision
        if current == ObjectID.localUnstaged(hashLength: hashLength) {
            if pi > 0 {
                let url = URL(fileURLWithPath: session.repo.gitDir, relativeTo: session.runner.cwd)
                    .appendingPathComponent("MERGE_HEAD")
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                guard let id = text.split(separator: "\n").last.flatMap({ ObjectID(hex: String($0)) }) else {
                    Alerts().errorPopup(L("Couldn't read merge head: %s", "MERGE_HEAD"), parent: window)
                    return
                }
                revision = .commit(id)
            } else if parents.count == 1, parents[0] == ObjectID.localStaged(hashLength: hashLength) {
                revision = .index
            } else if let first = parents.first {
                revision = .commit(first)
            } else { return }
        } else {
            guard parents.indices.contains(pi) else { return }
            revision = .commit(parents[pi])
        }
        let runner = session.runner
        let file = blamePath(path)
        Task { [weak self] in
            do {
                guard let result = try await LineOrigin.blame(revision: revision, path: file, line: spec.line,
                                                              runner: runner, hashLength: hashLength) else { return }
                guard let self, let session = self.session else { return }
                if session.row(of: result.commitID) != nil {
                    self.onShowOrigin?(result.commitID, result.path, result.line)
                } else {
                    Alerts().errorPopup(L("That line comes from commit %s,  which is not in this view",
                                          result.commitID.abbreviated(8)), parent: window)
                }
            } catch {
                Alerts().errorPopup(L("Error running git blame: %s", "\(error)"), parent: window)
            }
        }
    }

    /// After the commit is selected: scroll to line `lineNumber` of `path` in its
    /// diff and mark it (the `selectline` tail with a `{fname lnum}` target).
    func revealLine(path: String, lineNumber: Int) {
        Task { [weak self] in
            await self?.waitUntilLoaded()
            guard let self else { return }
            let lines = self.textLines()
            for (index, section) in self.document.sections.enumerated()
            where section.newPath == path || (section.newPath == nil && section.oldPath == path) {
                let end = self.document.sections.indices.contains(index + 1)
                    ? self.document.sections[index + 1].startLine : lines.count
                if section.startLine < end,
                   let found = LineOrigin.diffLineIndex(ofNewLine: lineNumber, in: lines, range: section.startLine..<end),
                   self.lineOffsets.indices.contains(found) {
                    self.markLine(found)
                    self.scroll(toCharacter: self.lineOffsets[found])
                    return
                }
            }
        }
    }

    /// Port of gitk proc `mark_ctext_line`: a highlight on the line.
    private func markLine(_ line: Int) {
        guard let manager = textView.layoutManager, let storage = textView.textStorage,
              lineOffsets.indices.contains(line) else { return }
        manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
        let start = lineOffsets[line]
        let end = lineOffsets.indices.contains(line + 1) ? lineOffsets[line + 1] : storage.length
        guard end > start, end <= storage.length else { return }
        manager.addTemporaryAttribute(.backgroundColor, value: NSColor.findHighlightColor,
                                      forCharacterRange: NSRange(location: start, length: end - start))
    }
}
