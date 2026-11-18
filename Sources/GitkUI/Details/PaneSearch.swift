// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Match ranges and the next/previous cursor, without any view (testable).
/// Matching is case-sensitive, like Tk's `text search` without `-nocase`, and
/// forward matches do not overlap (gitk `searchmark` restarts at the match end).
struct PaneSearchModel {
    var text: NSString
    var query: String
    /// The current hit (gitk's `sel` tag range), if any.
    var current: NSRange?

    init(text: String, query: String = "") {
        self.text = text as NSString
        self.query = query
    }

    /// All hits, in order (gitk `searchmark`).
    var matches: [NSRange] {
        guard !query.isEmpty else { return [] }
        var result: [NSRange] = []
        var from = 0
        while from < text.length {
            let r = text.range(of: query, options: .literal, range: NSRange(location: from, length: text.length - from))
            if r.location == NSNotFound { break }
            result.append(r)
            from = r.location + max(r.length, 1)
        }
        return result
    }

    /// Hits other than the current one (the `found` tag) and the current hit
    /// (`currentsearchhit`): gitk marks the match starting at the selection.
    var foundRanges: [NSRange] { matches.filter { $0.location != current?.location } }
    var currentHitRange: NSRange? { current.flatMap { c in matches.first { $0.location == c.location } } }

    /// Port of gitk proc `incrsearch` (gitk/gitk 8638–8663): search from the
    /// anchor in the given direction and select the hit; no hit leaves the selection.
    mutating func incremental(anchor: Int, forward: Bool) -> NSRange? {
        guard !query.isEmpty else { return nil }
        guard let hit = forward ? firstMatch(from: anchor) : lastMatch(before: anchor) else { return nil }
        current = hit
        return hit
    }

    /// Port of gitk proc `dosearch` (gitk/gitk 8665–8689): the next hit after the
    /// selection start (or the anchor). Unlike gitk, which stops at the last hit,
    /// it wraps to the first, like macOS find; only a text without hits gives nil.
    mutating func next(anchor: Int) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let start = current.map { $0.location + 1 } ?? anchor
        current = firstMatch(from: start) ?? firstMatch(from: 0)
        return current
    }

    /// Port of gitk proc `dosearchback` (gitk/gitk 8691–8715): the last hit
    /// before the selection start (or the anchor), wrapping to the last hit.
    mutating func previous(anchor: Int) -> NSRange? {
        guard !query.isEmpty else { return nil }
        current = lastMatch(before: current?.location ?? anchor) ?? lastMatch(before: text.length)
        return current
    }

    private func firstMatch(from start: Int) -> NSRange? {
        guard start >= 0, start < text.length else { return nil }
        let r = text.range(of: query, options: .literal, range: NSRange(location: start, length: text.length - start))
        return r.location == NSNotFound ? nil : r
    }

    private func lastMatch(before end: Int) -> NSRange? {
        let e = min(max(end, 0), text.length)
        guard e > 0 else { return nil }
        let r = text.range(of: query, options: [.literal, .backwards], range: NSRange(location: 0, length: e))
        return r.location == NSNotFound ? nil : r
    }
}

/// Drives a diff pane's text view from a search field: highlights every hit with
/// the found colour and the current hit with the current-search-hit colour.
/// gitk's `.bleft.top.search` button and `$sstring` entry (gitk/gitk 2606–2612).
@MainActor
final class PaneSearch: NSObject, NSSearchFieldDelegate {
    let field = NSSearchField()
    /// "N / M": the current hit and the number of hits, shown while there is a query.
    let counter = NSTextField(labelWithString: "")
    private weak var textView: NSTextView?
    var settings: Settings { didSet { rehighlight() } }
    private var model = PaneSearchModel(text: "")
    private var forwardDirection = true
    private var anchor: Int?
    /// The ranges this search coloured, so clearing leaves other highlights alone.
    private var marked: [NSRange] = []
    private var refreshPending = false

    init(textView: NSTextView, settings: Settings) {
        self.textView = textView
        self.settings = settings
        super.init()
        field.placeholderString = L("Search")
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.sendsSearchStringImmediately = true
        field.delegate = self
        counter.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .right
        counter.isHidden = true
        counter.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        if let storage = textView.textStorage {
            NotificationCenter.default.addObserver(self, selector: #selector(textDidEdit(_:)),
                                                   name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
    }

    /// The pane text changed (a new diff, or a streamed batch): redo the
    /// highlighting once per run-loop turn. A shrinking text is a new document,
    /// so the current hit goes; appended text keeps it.
    @objc private func textDidEdit(_ notification: Notification) {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshPending = false
            refresh()
        }
    }

    /// Re-read the pane text (after the diff changes) and redo the highlighting.
    func refresh() {
        let text = textView?.string ?? ""
        let current = model.current
        let grew = (text as NSString).length >= model.text.length && model.text.length > 0
        model = PaneSearchModel(text: text, query: field.stringValue)
        if grew, let current, NSMaxRange(current) <= model.text.length { model.current = current }
        if !grew { anchor = nil; marked = [] }
        rehighlight()
    }

    /// Typing in the field (gitk `incrsearch`, a trace on `searchstring`).
    func controlTextDidChange(_ obj: Notification) {
        model = PaneSearchModel(text: textView?.string ?? "", query: field.stringValue)
        if anchor == nil {
            let sel = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            anchor = sel.length > 0 ? sel.location : (forwardDirection ? visibleTop : visibleBottom)
        }
        if let hit = model.incremental(anchor: anchor ?? 0, forward: forwardDirection) { show(hit) }
        rehighlight()
    }

    /// Return steps forward, Shift-Return back; Escape clears the field and
    /// returns focus to the pane.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { searchPrevious() } else { searchNext() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            field.stringValue = ""
            model = PaneSearchModel(text: self.textView?.string ?? "")
            anchor = nil
            rehighlight()
            if let pane = self.textView { pane.window?.makeFirstResponder(pane) }
            return true
        default:
            return false
        }
    }

    /// Types `text` into the field as if the user had (`GITK_SWIFT_DIFF_SEARCH`).
    func applySnapshotQuery(_ text: String) {
        field.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// ⌘-S (gitk `dosearch`).
    func searchNext() {
        forwardDirection = true
        step { model.next(anchor: $0) }
    }

    /// ⌘-R (gitk `dosearchback`).
    func searchPrevious() {
        forwardDirection = false
        step { model.previous(anchor: $0) }
    }

    private func step(_ move: (Int) -> NSRange?) {
        if let window = textView?.window, field.currentEditor() == nil { window.makeFirstResponder(field) }
        guard !field.stringValue.isEmpty, let textView else { return }
        model.text = textView.string as NSString
        model.query = field.stringValue
        let sel = textView.selectedRange()
        if model.current == nil, sel.length > 0 { model.current = sel }
        let from = forwardDirection ? (anchor ?? visibleTop) : (anchor ?? visibleBottom)
        if let hit = move(from) {
            show(hit)
        } else {
            NSSound.beep()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        anchor = nil
        rehighlight()
    }

    /// Moves the insertion point to the hit and scrolls it into view, centred
    /// vertically when it was off screen (gitk's `$ctext see`). The hit is not
    /// selected: the text view's selection would paint over the current-hit colour.
    private func show(_ range: NSRange) {
        guard let textView else { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        guard let lm = textView.layoutManager, let tc = textView.textContainer,
              let clip = textView.enclosingScrollView?.contentView else {
            textView.scrollRangeToVisible(range)
            return
        }
        lm.ensureLayout(forCharacterRange: range)
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        let visible = clip.documentVisibleRect
        guard !visible.contains(rect) else { return }
        var origin = visible.origin
        if rect.minY < visible.minY || rect.maxY > visible.maxY {
            origin.y = rect.midY - visible.height / 2
        }
        if rect.minX < visible.minX || rect.maxX > visible.maxX {
            origin.x = max(0, rect.maxX - visible.width + 20)
            if rect.minX < origin.x { origin.x = max(0, rect.minX - 20) }
        }
        origin.y = min(max(0, origin.y), max(0, textView.frame.height - visible.height))
        clip.scroll(to: origin)
        textView.enclosingScrollView?.reflectScrolledClipView(clip)
    }

    private var visibleTop: Int { visibleCharacter(atTop: true) }
    private var visibleBottom: Int { visibleCharacter(atTop: false) }

    private func visibleCharacter(atTop: Bool) -> Int {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return 0 }
        let glyphs = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return atTop ? chars.location : NSMaxRange(chars)
    }

    /// Port of gitk proc `rehighlight_search_results` (gitk/gitk 8717–8725).
    private func rehighlight() {
        guard let lm = textView?.layoutManager else { return }
        let length = (textView?.string as NSString?)?.length ?? 0
        for r in marked where NSMaxRange(r) <= length {
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: r)
        }
        let matches = model.matches
        let currentLocation = model.current?.location
        let found: [NSAttributedString.Key: Any] = [.backgroundColor: Palette.paneFound(settings),
                                                    .foregroundColor: Palette.paneSearchText]
        let current: [NSAttributedString.Key: Any] = [.backgroundColor: Palette.paneCurrentHit(settings),
                                                      .foregroundColor: Palette.paneSearchText]
        for r in matches {
            lm.addTemporaryAttributes(r.location == currentLocation ? current : found, forCharacterRange: r)
        }
        marked = matches
        updateCounter(matches)
    }

    private func updateCounter(_ matches: [NSRange]) {
        counter.isHidden = model.query.isEmpty
        guard !model.query.isEmpty else { counter.stringValue = ""; return }
        let index = model.current.flatMap { c in matches.firstIndex { $0.location == c.location } }.map { $0 + 1 }
        counter.stringValue = "\(index ?? 0) / \(matches.count)"
    }

    /// The current hit, if any.
    var currentHit: NSRange? { model.current }

    /// Test hook: the counter text.
    var counterText: String { counter.isHidden ? "" : counter.stringValue }
}
