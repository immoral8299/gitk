// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class DetailsTextController: NSObject, NSTextViewDelegate {
    let textView = NSTextView(usingTextLayoutManager: false)
    let scrollView = NSScrollView()
    var settings: Settings
    var options: DiffOptions
    var mode: DiffDisplayMode = .diff
    private(set) var document = DiffDocument()
    private(set) var sectionOffsets: [Int] = []
    var onSectionsChanged: (([DiffFileSection]) -> Void)?
    var onCommitLink: ((ObjectID) -> Void)?
    var onReady: (() -> Void)?
    private var task: Task<Void, Never>?
    private var process: GitProcess?
    private var generation: UInt64 = 0
    private var header = NSAttributedString(string: "")
    private var renderer: DiffRenderer
    private weak var session: ViewSession?
    private var ids: [ObjectID] = []
    private var renderedLines = 0

    init(settings: Settings, hashLength: Int) {
        self.settings = settings
        self.options = DiffOptions(context: settings.diffContext, hashLength: hashLength)
        self.renderer = DiffRenderer(settings: settings)
        super.init()
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = self
        textView.isRichText = true
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.textContainerInset = NSSize(width: 5, height: 4)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView
        applyWrapping(settings.wrapComment)
    }

    func applyWrapping(_ value: String) {
        let wraps = value != "none"
        textView.isHorizontallyResizable = !wraps
        textView.autoresizingMask = wraps ? [.width] : []
        textView.textContainer?.widthTracksTextView = wraps
        textView.textContainer?.containerSize = NSSize(width: wraps ? max(1, scrollView.contentSize.width) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = value == "char" ? .byCharWrapping : (wraps ? .byWordWrapping : .byClipping)
        textView.defaultParagraphStyle = paragraph
    }

    func show(commit: CommitIndex, session: ViewSession) {
        self.session = session
        let id = session.store.id(at: commit)
        let built = DetailsHeaderBuilder.build(commit: commit, session: session, dateFormat: settings.dateTimeFormat, translate: { L($0) })
        let attributed = NSMutableAttributedString(string: built.text, attributes: renderer.base)
        for run in built.runs {
            attributed.addAttribute(.foregroundColor, value: DiffRenderer.color(settings.mergeColors[run.mergeColor % settings.mergeColors.count]), range: run.range)
        }
        addLinks(to: attributed, session: session)
        header = attributed
        options.logShowRoot = session.repo.logShowRoot
        options.limitPaths = settings.limitDiffs ? session.view.files : nil
        fetch(ids: [id], session: session)
    }

    func showDiff(from: ObjectID, to: ObjectID, session: ViewSession) {
        self.session = session
        let attributed = NSMutableAttributedString(string: "\(from.hex) → \(to.hex)\n\n", attributes: renderer.base)
        addLinks(to: attributed, session: session)
        header = attributed
        fetch(ids: [from, to], session: session)
    }

    func refetch() {
        guard let session else { return }
        let position = scrollView.contentView.bounds.origin
        fetch(ids: ids, session: session, restore: position)
    }

    /// Port of gitk procs `getblobdiffs`, `parseblobdiffline` (8203–8542).
    private func fetch(ids: [ObjectID], session: ViewSession, restore: NSPoint? = nil) {
        cancel()
        let token = generation
        self.ids = ids
        document = DiffDocument()
        renderedLines = 0
        sectionOffsets = []
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session.repo.guiEncoding
        textView.textStorage?.setAttributedString(header)
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
                onReady?()
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                Alerts().showError(L("Error getting diffs: %s", error.localizedDescription), parent: scrollView.window)
                onReady?()
            }
        }
    }

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

    func renderAgain() {
        let position = scrollView.contentView.bounds.origin
        textView.textStorage?.setAttributedString(header)
        renderedLines = 0
        sectionOffsets = []
        renderer = DiffRenderer(settings: settings, mode: mode, wordMode: options.wordDiff)
        renderer.encoding = session?.repo.guiEncoding ?? "utf-8"
        appendPending()
        scrollView.contentView.scroll(to: position)
    }

    func showAllLines() { document.lineLimit = Int.max; appendPending() }
    func jumpToFile(_ index: Int) {
        if index == 0 { textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); return }
        guard sectionOffsets.indices.contains(index - 1) else { return }
        textView.scrollRangeToVisible(NSRange(location: sectionOffsets[index - 1], length: 0))
    }

    func cancel() { generation &+= 1; task?.cancel(); task = nil; process?.cancel(); process = nil }

    private func addLinks(to text: NSMutableAttributedString, session: ViewSession) {
        let links = LinkScanner.scan(text.string, hashLength: session.repo.hashLength) { prefix in
            let matches = (0..<session.rowCount).compactMap { session.id(at: $0) }.filter { $0.hex.hasPrefix(prefix) }
            return matches.count == 1 ? matches.first : nil
        }
        for link in links {
            let value: String
            switch link.target {
            case .commit(let id): value = "gitk-commit:" + id.hex
            case .web(let url): value = url.absoluteString
            }
            text.addAttributes([.link: value, .foregroundColor: DiffRenderer.color(settings.linkFgColor)], range: link.range)
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let value = (link as? String) ?? (link as? URL)?.absoluteString ?? ""
        if value.hasPrefix("gitk-commit:"), let id = ObjectID(hex: String(value.dropFirst(12))) {
            onCommitLink?(id)
        } else if let url = URL(string: value) {
            NSWorkspace.shared.open(url)
        }
        return true
    }
}
