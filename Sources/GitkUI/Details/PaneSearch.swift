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
    /// selection start (or the anchor). Without a hit the selection is cleared (bell).
    mutating func next(anchor: Int) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let start = current.map { $0.location + 1 } ?? anchor
        current = firstMatch(from: start)
        return current
    }

    /// Port of gitk proc `dosearchback` (gitk/gitk 8691–8715): the last hit
    /// before the selection start (or the anchor).
    mutating func previous(anchor: Int) -> NSRange? {
        guard !query.isEmpty else { return nil }
        current = lastMatch(before: current?.location ?? anchor)
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
@MainActor
final class PaneSearch: NSObject, NSSearchFieldDelegate {
    let field = NSSearchField()
    private weak var textView: NSTextView?
    private var settings: Settings
    private var model = PaneSearchModel(text: "")
    private var forwardDirection = true
    private var anchor: Int?
    private var marked: [NSRange] = []

    init(textView: NSTextView, settings: Settings) {
        self.textView = textView
        self.settings = settings
        super.init()
        field.placeholderString = L("Search")
        field.controlSize = .small
        field.delegate = self
    }

    /// Re-read the pane text (after the diff changes) and redo the highlighting.
    func refresh() {
        model = PaneSearchModel(text: textView?.string ?? "", query: field.stringValue)
        anchor = nil
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
        textView?.window?.makeFirstResponder(field)
        guard !field.stringValue.isEmpty, let textView else { return }
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

    private func show(_ range: NSRange) {
        textView?.setSelectedRange(range)
        textView?.scrollRangeToVisible(range)
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
        let whole = NSRange(location: 0, length: (textView?.string as NSString?)?.length ?? 0)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        let found = Palette.found(settings)
        let currentColour = Palette.tk(settings.currentSearchHitBgColor)
        for r in model.foundRanges { lm.addTemporaryAttribute(.backgroundColor, value: found, forCharacterRange: r) }
        if let c = model.currentHitRange { lm.addTemporaryAttribute(.backgroundColor, value: currentColour, forCharacterRange: c) }
    }
}
