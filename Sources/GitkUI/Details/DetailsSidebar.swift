// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The right-hand details sidebar (design D16), gitk's commit header, comment
/// and file list relocated into three collapsible, full-width sections:
/// Commit (identity, ID, refs and gitk's header rows), Message (the subject,
/// with Show More for the rest and the notes) and Changed Files (13.1).
/// Section headers and dividers span the sidebar; their contents are padded.
@MainActor
final class DetailsSidebar: NSView, NSTextViewDelegate {
    private static let padding: CGFloat = 14

    private let panel: SidebarPanel
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let monogram = Monogram()
    private let nameLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let emailLabel = NSTextField(labelWithString: "")
    let idButton = CopyIDButton()
    /// Branch and tag names as rounded labels (match boxes in `AutoHeightTextView`).
    private let refsView = AutoHeightTextView()
    /// The monogram and name block, hidden while a tag is shown.
    private var identityView: NSView!
    private let rowsView = AutoHeightTextView()
    let messageView = AutoHeightTextView()
    /// Show More / Show Less for the message beyond its first line.
    let moreButton = NSButton(title: "", target: nil, action: nil)
    private(set) var messageExpanded = false
    private var findQuery = FindQuery()
    private var findMatches = Set<ObjectID>()
    private var fullMessage = NSAttributedString()
    /// The Changed Files list (13.1).
    let fileList = FileListController()
    private(set) var commitSection: SidebarSection!
    private(set) var messageSection: SidebarSection!
    private(set) var filesSection: SidebarSection!
    private var sections: [SidebarSection] { [commitSection, messageSection, filesSection] }

    var settings = Settings() { didSet { applySettings() } }
    var onCommitLink: ((ObjectID) -> Void)?

    /// gitk's Branch/Follows/Precedes rows (12.5), filled in once the ancestry
    /// index is ready.
    enum Nearby: Equatable { case hidden, pending, ready(NearbyRefs) }
    var nearby: Nearby = .hidden {
        didSet { if nearby != oldValue, let shownHeader { setText(rowsView, rowsText(shownHeader)) } }
    }
    private var shownHeader: DetailsHeader?
    private(set) var shownID: ObjectID?
    private weak var session: ViewSession?

    init() {
        panel = Chrome.sidebarBackground()
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        buildContent()
        addSubview(panel.view)
        panel.content.addSubview(scrollView)
        applySettings()
        clear()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // MARK: Building

    private func buildContent() {
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        for label in [nameLabel, dateLabel, emailLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.cell?.truncatesLastVisibleLine = true
        }
        for label in [dateLabel, emailLabel] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.isSelectable = true
        }
        let names = NSStackView(views: [nameLabel, dateLabel, emailLabel])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 1
        let identity = NSStackView(views: [monogram, names])
        identityView = identity
        for stack in [names, identity] { stack.setClippingResistancePriority(.defaultLow, for: .horizontal) }
        identity.alignment = .top
        identity.spacing = 10
        monogram.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([monogram.widthAnchor.constraint(equalToConstant: 36),
                                     monogram.heightAnchor.constraint(equalToConstant: 36)])

        idButton.target = self
        idButton.action = #selector(copyID)
        idButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refsView.isEditable = false
        refsView.isSelectable = false
        refsView.drawsBackground = false
        refsView.textContainerInset = .zero
        // Room for the label boxes, which extend past the text.
        refsView.textContainer?.lineFragmentPadding = Palette.matchBoxOutset

        for view in [rowsView, messageView] {
            view.delegate = self
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = .zero
            view.textContainer?.lineFragmentPadding = 0
        }
        moreButton.isBordered = false
        moreButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        moreButton.contentTintColor = .linkColor
        moreButton.target = self
        moreButton.action = #selector(toggleMore)

        let commitBody = Self.column([identity, idButton, refsView, rowsView], spacing: 8)
        commitSection = SidebarSection(title: L("Commit"), body: commitBody, showsDivider: false)
        messageSection = SidebarSection(title: L("Message"), body: Self.column([messageView, moreButton], spacing: 4))
        filesSection = SidebarSection(title: "", body: fileList.view, padded: false)
        filesSection.titleLabel.attributedStringValue = NSAttributedString()
        filesSection.accessory = [fileList.totalsLabel, fileList.layoutSwitch]
        fileList.onTitleChange = { [weak self] in self?.filesSection.title = $0 }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        for section in sections {
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let document = FlippedView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
        document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor).isActive = true
    }

    /// A vertical stack whose rows all span its width.
    private static func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = spacing
        for view in views where !(view is NSButton) {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        column.setClippingResistancePriority(.defaultLow, for: .horizontal)
        return column
    }

    private func applySettings() {
        let font = MainLayoutMetrics.nsFont(settings.textFont)
        messageView.font = font
        CommentWrap(setting: settings.wrapComment).apply(to: messageView)
    }

    override func layout() {
        super.layout()
        let inset = panel.inset
        panel.view.frame = NSRect(x: inset, y: inset, width: max(0, bounds.width - 2 * inset),
                                  height: max(0, bounds.height - 2 * inset))
        panel.content.frame = panel.view.bounds
        // Inset the content, not the viewport, so scrolling runs under the titlebar.
        let top = max(0, safeAreaInsets.top - inset)
        let content = panel.content.bounds
        scrollView.frame = content
        if scrollView.contentInsets.top != top {
            scrollView.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        }
    }

    // MARK: Content

    /// Empties the sidebar (no selection).
    func clear() {
        shownID = nil
        for section in sections { section.isHidden = true }
    }

    /// Shows `header` (commit-details "Sidebar follows selection").
    func show(_ header: DetailsHeader, session: ViewSession) {
        self.session = session
        shownID = header.id
        for section in sections { section.isHidden = false }
        monogram.initials = header.initials
        monogram.seed = header.authorEmail.isEmpty ? header.authorName : header.authorEmail
        nameLabel.stringValue = header.authorName
        dateLabel.stringValue = header.authorDate
        emailLabel.stringValue = header.authorEmail
        emailLabel.isHidden = header.authorEmail.isEmpty
        idButton.title = header.id.hex
        setText(refsView, refsText(header.refs, id: header.id, session: session))
        refsView.isHidden = header.refs.isEmpty
        shownHeader = header
        identityView.isHidden = false
        idButton.isHidden = false
        commitSection.title = L("Commit")
        setText(rowsView, rowsText(header))
        var message = header.message.trimmingCharacters(in: .newlines)
        if let notes = header.notes, !notes.isEmpty {
            // git's notes text already starts with its "Notes:" heading.
            message += "\n\n" + notes.trimmingCharacters(in: .newlines)
        }
        setMessage(message, session: session)
    }

    /// Shows one or more tags (commit-details "Click a tag"). Port of gitk procs
    /// `showtag` and `showtags` (gitk/gitk 11573–11603): one block per tag with
    /// a blank line between blocks. Each block gives the tag name, the tagged
    /// commit as a link and, for an annotated tag, the tagger and message. The
    /// commit identity and the Changed Files section are cleared.
    func show(tags: [TagInfo], session: ViewSession) {
        guard !tags.isEmpty else { clear(); return }
        self.session = session
        shownID = nil
        shownHeader = nil
        for section in sections { section.isHidden = false }
        commitSection.title = L("Tag")
        identityView.isHidden = true
        idButton.isHidden = true
        refsView.isHidden = true
        setText(rowsView, tagRowsText(tags, session: session))
        let messages = tags.map(\.message).filter { !$0.isEmpty }
        messageSection.isHidden = messages.isEmpty
        filesSection.isHidden = true
        fileList.update(nil)
        setMessage(messages.joined(separator: "\n\n"), session: session)
    }

    /// Shows the parent and children of a clicked graph line. Port of the text
    /// of gitk proc `lineclick` (gitk/gitk 9082–9118): "Parent" then "Children",
    /// each commit ID a link, then its subject, author and date. The commit
    /// identity and the Changed Files section are cleared.
    func show(line: LineDetails, session: ViewSession) {
        self.session = session
        shownID = nil
        shownHeader = nil
        for section in sections { section.isHidden = false }
        commitSection.title = L("Parent")
        identityView.isHidden = true
        idButton.isHidden = true
        refsView.isHidden = true
        messageSection.isHidden = true
        filesSection.isHidden = true
        fileList.update(nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 74)]
        paragraph.headIndent = 74
        paragraph.paragraphSpacing = 3
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ]
        let value: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let result = NSMutableAttributedString()
        func append(_ entry: LineDetails.Entry, heading: String) {
            result.append(NSAttributedString(string: heading + "\t", attributes: label))
            result.append(NSAttributedString(string: entry.id.abbreviated(8), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .link: LinkHandling.commitScheme + entry.id.hex, .foregroundColor: Palette.link(settings),
                .paragraphStyle: paragraph,
            ]))
            result.append(NSAttributedString(string: " " + entry.headline + "\n", attributes: value))
            result.append(NSAttributedString(string: L("Author") + "\t", attributes: label))
            result.append(NSAttributedString(string: entry.author + "\n", attributes: value))
            result.append(NSAttributedString(string: L("Date") + "\t", attributes: label))
            result.append(NSAttributedString(string: entry.date + "\n", attributes: value))
        }
        append(line.parent, heading: L("Parent"))
        for (n, child) in line.children.enumerated() {
            if n == 0 { result.append(NSAttributedString(string: "\n" + L("Children") + ":\n", attributes: label)) }
            else { result.append(NSAttributedString(string: "\n", attributes: value)) }
            append(child, heading: " ")
        }
        if result.length > 0 { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        setText(rowsView, result)
        setMessage("", session: session)
    }

    /// Shows the two commits of a row-menu diff. Port of the text of gitk proc
    /// `doseldiff` (gitk/gitk 9407–9420): "From" and "To" lines with each ID as
    /// a commit link and its headline. The Changed Files section stays and is
    /// filled from the diff pane.
    func show(diff: TwoCommitDiff, session: ViewSession) {
        self.session = session
        shownID = nil
        shownHeader = nil
        for section in sections { section.isHidden = false }
        commitSection.title = L("Commit")
        identityView.isHidden = true
        idButton.isHidden = true
        refsView.isHidden = true
        messageSection.isHidden = true
        func headline(_ id: ObjectID) -> String {
            guard let commit = session.store.index(of: id), session.store.isLoaded(commit) else { return "" }
            return session.store.headline(at: commit)
        }
        let header = diff.header(oldHeadline: headline(diff.old), newHeadline: headline(diff.new))
        let text = NSMutableAttributedString(string: header.text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor,
        ])
        for (range, id) in [(header.oldRange, diff.old), (header.newRange, diff.new)] {
            text.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .link: LinkHandling.commitScheme + id.hex, .foregroundColor: Palette.link(settings),
            ], range: range)
        }
        setText(rowsView, text)
        setMessage("", session: session)
    }

    /// Sets the message (the subject only until Show More), with commit and web
    /// links, and scrolls the sidebar to the top.
    private func setMessage(_ text: String, session: ViewSession) {
        let body = NSMutableAttributedString(string: text, attributes: [
            .font: MainLayoutMetrics.nsFont(settings.textFont), .foregroundColor: NSColor.textColor,
        ])
        LinkHandling.addLinks(to: body, session: session, settings: settings)
        fullMessage = body
        messageExpanded = false
        showMessage()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
    }

    /// The tag name, tagged commit and tagger lines for `show(tags:)`. Labels use
    /// gitk's "Tag" and "Id" msgids; the tagger line has no label because gitk
    /// has no msgid for one, so it lines up with the values like the Author row.
    private func tagRowsText(_ tags: [TagInfo], session: ViewSession) -> NSAttributedString {
        let labelFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let valueFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let refFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 74)]
        paragraph.headIndent = 74
        paragraph.paragraphSpacing = 3
        let label: [NSAttributedString.Key: Any] = [
            .font: labelFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ]
        let value: [NSAttributedString.Key: Any] = [
            .font: valueFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let result = NSMutableAttributedString()
        for (n, tag) in tags.enumerated() {
            if n > 0 { result.append(NSAttributedString(string: "\n", attributes: value)) }
            result.append(NSAttributedString(string: L("Tag") + "\t", attributes: label))
            result.append(NSAttributedString(string: tag.name + "\n", attributes: value))
            if let object = tag.object {
                result.append(NSAttributedString(string: L("Id") + "\t", attributes: label))
                result.append(NSAttributedString(string: object.abbreviated(8), attributes: [
                    .font: refFont, .link: LinkHandling.commitScheme + object.hex,
                    .foregroundColor: Palette.link(settings), .paragraphStyle: paragraph,
                ]))
                if let commit = session.store.index(of: object), session.store.isLoaded(commit) {
                    result.append(NSAttributedString(string: " " + session.store.headline(at: commit), attributes: value))
                }
                result.append(NSAttributedString(string: "\n", attributes: value))
            }
            if let name = tag.taggerName {
                let email = tag.taggerEmail.map { $0.isEmpty ? "" : " <\($0)>" } ?? ""
                let date = tag.taggerDate.map { "  " + $0 } ?? ""
                result.append(NSAttributedString(string: "\t" + name + email + date + "\n", attributes: value))
            }
        }
        if result.length > 0 { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    private func setText(_ view: AutoHeightTextView, _ text: NSAttributedString) {
        view.textStorage?.setAttributedString(text)
        view.invalidateIntrinsicContentSize()
    }

    private func refsText(_ refs: [String], id: ObjectID, session: ViewSession) -> NSAttributedString {
        let tags = Set(session.refs.tags(of: id))
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3  // keeps wrapped rows of labels apart
        for (n, ref) in refs.enumerated() {
            if n > 0 { result.append(NSAttributedString(string: " ", attributes: [.font: font, .paragraphStyle: paragraph])) }
            let isTag = tags.contains(ref)
            // No-break spaces pad the name inside its box and keep the box on one line.
            result.append(NSAttributedString(string: "\u{00A0}\(ref)\u{00A0}", attributes: [
                .font: font, .paragraphStyle: paragraph,
                .foregroundColor: Palette.refForeground(settings, isTag ? .tag : .head),
                MatchBoxes.key: Palette.refBackground(settings, isTag ? .tag : .head),
            ]))
        }
        return result
    }

    /// gitk's header lines as label/value rows; Parent and Child link to the commit.
    private func rowsText(_ header: DetailsHeader) -> NSAttributedString {
        let labelFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let valueFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 74)]
        paragraph.headIndent = 74
        paragraph.paragraphSpacing = 3
        let result = NSMutableAttributedString()
        for row in header.rows {
            var label = L(row.label)
            if label.hasSuffix(":") { label.removeLast() }
            let labelColor = row.mergeColor.map { Palette.merge(settings, $0) } ?? NSColor.secondaryLabelColor
            result.append(NSAttributedString(string: label + "\t", attributes: [
                .font: labelFont, .foregroundColor: labelColor, .paragraphStyle: paragraph,
            ]))
            var attrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            if let commit = row.commit {
                let short = NSMutableAttributedString(string: commit.abbreviated(8), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                    .link: LinkHandling.commitScheme + commit.hex, .foregroundColor: Palette.link(settings), .paragraphStyle: paragraph,
                ])
                result.append(short)
                result.append(NSAttributedString(string: " ", attributes: attrs))
                if let color = row.mergeColor { attrs[.foregroundColor] = Palette.merge(settings, color) }
            }
            result.append(NSAttributedString(string: row.value + "\n", attributes: attrs))
        }
        appendNearby(to: result, labelFont: labelFont, valueFont: valueFont, paragraph: paragraph)
        if result.length > 0 { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    /// Port of gitk procs `dispneartags` and `appendrefs` (gitk/gitk 7358–7472):
    /// ref names link to their commits; too many refs read "many" or
    /// "and many more".
    private func appendNearby(to result: NSMutableAttributedString, labelFont: NSFont, valueFont: NSFont,
                              paragraph: NSParagraphStyle) {
        let lines: [(String, NearbyRefLine?)]
        switch nearby {
        case .hidden: return
        case .pending: lines = [("Branch", nil), ("Follows", nil), ("Precedes", nil)]
        case .ready(let refs): lines = [("Branch", refs.branches), ("Follows", refs.follows), ("Precedes", refs.precedes)]
        }
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let refFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        for (label, line) in lines {
            result.append(NSAttributedString(string: L(label) + "\t", attributes: [
                .font: labelFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
            ]))
            guard let line else {
                result.append(NSAttributedString(string: "…\n", attributes: valueAttrs))
                continue
            }
            for (n, entry) in line.entries.enumerated() {
                if n > 0 { result.append(NSAttributedString(string: ", ", attributes: valueAttrs)) }
                result.append(NSAttributedString(string: entry.name, attributes: [
                    .font: refFont, .link: LinkHandling.commitScheme + entry.id.hex,
                    .foregroundColor: Palette.link(settings), .paragraphStyle: paragraph,
                ]))
            }
            if let key = line.overflowKey {
                result.append(NSAttributedString(string: (line.entries.isEmpty ? "" : " ") + L(key), attributes: valueAttrs))
            }
            result.append(NSAttributedString(string: "\n", attributes: valueAttrs))
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let id = LinkHandling.commit(in: link) {
            onCommitLink?(id)
        } else {
            LinkHandling.openWeb(link, settings: settings, parent: window)
        }
        return true
    }

    // MARK: Actions

    /// Clicking the full commit ID copies it (D16).
    @objc private func copyID() {
        guard let shownID else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shownID.hex, forType: .string)
        idButton.showCopied()
    }

    /// The subject only, or the whole message and notes when expanded.
    private func showMessage() {
        let text = fullMessage.string as NSString
        let fullMessage = markedMessage()
        let firstLineEnd = text.range(of: "\n").location
        let hasMore = firstLineEnd != NSNotFound
            && !text.substring(from: firstLineEnd).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if messageExpanded || !hasMore {
            setText(messageView, fullMessage)
        } else {
            setText(messageView, fullMessage.attributedSubstring(from: NSRange(location: 0, length: firstLineEnd)))
        }
        moreButton.isHidden = !hasMore
        moreButton.title = messageExpanded ? L("Show Less") : L("Show More")
    }

    /// The find query and the ids it matches; the message of a matching commit
    /// shows the same match boxes as the list (commit-find "Matches in visible
    /// text"). Port of gitk proc `findselectline` (gitk/gitk 7130–7152).
    func setFind(_ query: FindQuery, matches: Set<ObjectID>) {
        findQuery = query
        findMatches = matches
        if shownID != nil, messageSection?.isHidden == false { showMessage() }
    }

    /// `fullMessage` with `MatchBoxes.key` on each match: the first occurrence
    /// in the current-match colour, the rest in the found colour.
    private func markedMessage() -> NSAttributedString {
        guard let id = shownID, findMatches.contains(id), findQuery.field == .allFields || findQuery.field == .comments
        else { return fullMessage }
        let marked = NSMutableAttributedString(attributedString: fullMessage)
        let string = fullMessage.string
        let ranges = findQuery.matches(in: string)
        let first = FindStepper.currentOccurrence(counts: [ranges.count]) != nil
        for (n, range) in ranges.enumerated() {
            let colour = first && n == 0 ? Palette.tk(settings.currentSearchHitBgColor) : Palette.found(settings)
            marked.addAttribute(MatchBoxes.key, value: colour, range: NSRange(range, in: string))
        }
        return marked
    }

    @objc private func toggleMore() {
        messageExpanded.toggle()
        showMessage()
    }
}

/// A flipped container so scrolled content starts at the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// gitk's `wrapcomment` setting (gitk/gitk 2660 and 11760–11762, the ctext `-wrap`
/// option) applied to the sidebar message. Fall back to word wrapping so
/// messages remain readable without a horizontal scroller.
struct CommentWrap: Equatable {
    enum Mode: Equatable { case char, word }
    var mode: Mode

    init(setting: String) {
        switch setting {
        case "char": mode = .char
        default: mode = .word
        }
    }

    var lineBreakMode: NSLineBreakMode {
        switch mode {
        case .char: .byCharWrapping
        case .word: .byWordWrapping
        }
    }

    @MainActor func apply(to textView: NSTextView) {
        guard let container = textView.textContainer else { return }
        container.widthTracksTextView = true
        container.lineBreakMode = lineBreakMode
        container.containerSize = NSSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)
        textView.invalidateIntrinsicContentSize()
    }
}

/// A non-scrolling text view whose height follows its text, for use in stacks.
final class AutoHeightTextView: NSTextView {
    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        translatesAutoresizingMaskIntoConstraints = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
    }

    /// Match boxes (`MatchBoxes.key`) behind the text, as in the list.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let manager = layoutManager, storage.length > 0 else { return }
        storage.enumerateAttribute(MatchBoxes.key, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let colour = value as? NSColor else { return }
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? self.font
            // One box per line, as tall as the font rather than the line, so
            // line spacing stays visible between wrapped rows of boxes.
            manager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, container, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                var box = manager.boundingRect(forGlyphRange: part, in: container)
                if let font {
                    let baseline = line.minY + manager.location(forGlyphAt: part.location).y
                    box.origin.y = baseline - font.ascender
                    box.size.height = font.ascender - font.descender
                }
                let r = box.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                    .insetBy(dx: -Palette.matchBoxOutset, dy: 0)
                colour.setFill()
                NSBezierPath(roundedRect: r, xRadius: Palette.cornerRadius, yRadius: Palette.cornerRadius).fill()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else { return super.intrinsicContentSize }
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height + 2 * textContainerInset.height
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }
}

/// The author's initials in a coloured circle (no network fetch, D16).
@MainActor
final class Monogram: NSView {
    var initials = "" { didSet { needsDisplay = true } }
    var seed = "" { didSet { needsDisplay = true } }

    private static let colors: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemOrange,
                                            .systemTeal, .systemIndigo, .systemGreen, .systemBrown]

    /// A stable colour per author (FNV-1a of the seed).
    var fill: NSColor {
        var hash: UInt32 = 2_166_136_261
        for byte in seed.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Self.colors[Int(hash % UInt32(Self.colors.count))]
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        let font = NSFont.systemFont(ofSize: bounds.height * 0.4, weight: .semibold)
        let text = initials as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}

/// One collapsible sidebar section: a full-width header (title, optional
/// accessory controls and a disclosure chevron) with a divider above it, and a
/// padded body.
@MainActor
final class SidebarSection: NSView {
    static let padding: CGFloat = 14
    let titleLabel = NSTextField(labelWithString: "")
    private let titleButton = NSButton(title: "", target: nil, action: nil)
    private let chevron = NSButton(title: "", target: nil, action: nil)
    private let accessoryStack = NSStackView()
    private let header = NSStackView()
    private let bodyContainer = NSView()
    let body: NSView
    private var bodyHeight: NSLayoutConstraint?

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }
    var accessory: [NSView] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            accessory.forEach { accessoryStack.addArrangedSubview($0) }
        }
    }
    var isExpanded = true { didSet { update() } }

    init(title: String, body: NSView, padded: Bool = true, showsDivider: Bool = true) {
        self.body = body
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize - 1, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.init(740), for: .horizontal)
        // The title area is a borderless button so the whole label toggles.
        titleButton.isBordered = false
        titleButton.title = ""
        titleButton.target = self
        titleButton.action = #selector(toggle)
        chevron.isBordered = false
        chevron.target = self
        chevron.action = #selector(toggle)
        chevron.contentTintColor = .tertiaryLabelColor
        accessoryStack.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        for view in [titleLabel, spacer, accessoryStack, chevron] { header.addArrangedSubview(view) }
        header.spacing = 8
        // The title gives way only after the spacer, and truncates rather than
        // being detached when the sidebar is narrow.
        header.setVisibilityPriority(.mustHold, for: titleLabel)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        header.edgeInsets = NSEdgeInsets(top: 0, left: Self.padding, bottom: 0, right: Self.padding - 4)
        header.translatesAutoresizingMaskIntoConstraints = false
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox()
        divider.boxType = .separator
        divider.isHidden = !showsDivider
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        addSubview(header)
        addSubview(titleButton)
        addSubview(bodyContainer)
        bodyContainer.addSubview(body)
        let inset: CGFloat = padded ? Self.padding : 0
        let hidden = bodyContainer.heightAnchor.constraint(equalToConstant: 0)
        hidden.priority = .required
        bodyHeight = hidden
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 27), // Important: exactly at 27 for it to aligned with commit table
            titleButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            titleButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            titleButton.topAnchor.constraint(equalTo: header.topAnchor),
            titleButton.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            bodyContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            body.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: inset),
            body.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -inset),
            body.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -12),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func update() {
        body.isHidden = !isExpanded
        bodyHeight?.isActive = !isExpanded
        let symbol = isExpanded ? "chevron.down" : "chevron.right"
        chevron.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        chevron.setAccessibilityLabel(title)
    }

    @objc private func toggle() { isExpanded.toggle() }
}
