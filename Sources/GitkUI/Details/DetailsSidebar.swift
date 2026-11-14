// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The right-hand details sidebar (design D16), gitk's commit header and
/// comment relocated. Top to bottom: the identity header, gitk's header rows,
/// a collapsible Message section and the Changed Files mount point (13.1).
///
/// The content sits on a floating Liquid Glass panel inset from the window
/// edges, like Finder's sidebar (macOS 26+); earlier systems use the sidebar
/// material edge to edge (`Chrome.sidebarBackground`).
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
    let idButton = NSButton(title: "", target: nil, action: nil)
    private let refsLabel = NSTextField(labelWithString: "")
    private let rowsView = AutoHeightTextView()
    let messageToggle = NSButton(title: "", target: nil, action: nil)
    let messageView = AutoHeightTextView()
    /// Where task 13.1 mounts the Changed Files section.
    let changedFilesSlot = NSStackView()
    private var content: [NSView] = []

    var settings = Settings() { didSet { applySettings() } }
    var onCommitLink: ((ObjectID) -> Void)?
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
        for stack in [names, identity] { stack.setClippingResistancePriority(.defaultLow, for: .horizontal) }
        identity.alignment = .top
        identity.spacing = 10
        monogram.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([monogram.widthAnchor.constraint(equalToConstant: 36),
                                     monogram.heightAnchor.constraint(equalToConstant: 36)])

        idButton.isBordered = false
        idButton.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        idButton.contentTintColor = .secondaryLabelColor
        idButton.lineBreakMode = .byTruncatingMiddle
        idButton.alignment = .left
        idButton.target = self
        idButton.action = #selector(copyID)
        idButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refsLabel.lineBreakMode = .byWordWrapping
        refsLabel.maximumNumberOfLines = 0

        for view in [rowsView, messageView] {
            view.delegate = self
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = .zero
            view.textContainer?.lineFragmentPadding = 0
        }

        messageToggle.bezelStyle = .disclosure
        messageToggle.setButtonType(.onOff)
        messageToggle.state = .on
        messageToggle.target = self
        messageToggle.action = #selector(toggleMessage)
        let messageTitle = NSButton(title: L("Message"), target: self, action: #selector(toggleMessageFromTitle))
        messageTitle.isBordered = false
        messageTitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        messageTitle.contentTintColor = .secondaryLabelColor
        let messageHeader = NSStackView(views: [messageToggle, messageTitle])
        messageHeader.spacing = 2

        changedFilesSlot.orientation = .vertical
        changedFilesSlot.alignment = .leading

        let lines = [separator(), separator()]
        content = [identity, idButton, refsLabel, lines[0], rowsView, lines[1], messageHeader, messageView, changedFilesSlot]
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: Self.padding, bottom: Self.padding, right: Self.padding)
        for view in content { stack.addArrangedSubview(view) }
        // Every block spans the content width, so a long name or email truncates
        // instead of widening the sidebar and eating its padding.
        for view in [identity, idButton, refsLabel, rowsView, messageView, changedFilesSlot] + lines {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.padding).isActive = true
        }
        stack.setCustomSpacing(4, after: messageHeader)
        stack.setCustomSpacing(2, after: idButton)

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

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    private func applySettings() {
        let font = MainLayoutMetrics.nsFont(settings.textFont)
        messageView.font = font
        // gitk `wrapcomment`: the sidebar always wraps; task 11.3 maps the modes.
        messageView.textContainer?.lineBreakMode = settings.wrapComment == "char" ? .byCharWrapping : .byWordWrapping
    }

    override func layout() {
        super.layout()
        let inset = panel.inset
        panel.view.frame = NSRect(x: inset, y: inset, width: max(0, bounds.width - 2 * inset),
                                  height: max(0, bounds.height - 2 * inset))
        panel.content.frame = panel.view.bounds
        // Keep the content clear of the titlebar when the panel runs under it.
        let top = max(0, safeAreaInsets.top - inset) + 6
        let content = panel.content.bounds
        scrollView.frame = NSRect(x: 0, y: top, width: content.width, height: max(0, content.height - top))
    }

    // MARK: Content

    /// Empties the sidebar (no selection).
    func clear() {
        shownID = nil
        for view in content { view.isHidden = true }
    }

    /// Shows `header` (commit-details "Sidebar follows selection").
    func show(_ header: DetailsHeader, session: ViewSession) {
        self.session = session
        shownID = header.id
        for view in content { view.isHidden = false }
        monogram.initials = header.initials
        monogram.seed = header.authorEmail.isEmpty ? header.authorName : header.authorEmail
        nameLabel.stringValue = header.authorName
        dateLabel.stringValue = header.authorDate
        emailLabel.stringValue = header.authorEmail
        emailLabel.isHidden = header.authorEmail.isEmpty
        idButton.title = header.id.hex
        idButton.toolTip = header.id.hex
        refsLabel.attributedStringValue = refsText(header.refs, id: header.id, session: session)
        refsLabel.isHidden = header.refs.isEmpty
        setText(rowsView, rowsText(header))
        var message = header.message.trimmingCharacters(in: .newlines)
        if let notes = header.notes, !notes.isEmpty {
            // git's notes text already starts with its "Notes:" heading.
            message += "\n\n" + notes.trimmingCharacters(in: .newlines)
        }
        let body = NSMutableAttributedString(string: message, attributes: [
            .font: MainLayoutMetrics.nsFont(settings.textFont), .foregroundColor: NSColor.textColor,
        ])
        addLinks(to: body, session: session)
        setText(messageView, body)
        messageView.isHidden = messageToggle.state == .off
        scrollView.contentView.scroll(to: .zero)
    }

    private func setText(_ view: AutoHeightTextView, _ text: NSAttributedString) {
        view.textStorage?.setAttributedString(text)
        view.invalidateIntrinsicContentSize()
    }

    private func refsText(_ refs: [String], id: ObjectID, session: ViewSession) -> NSAttributedString {
        let tags = Set(session.refs.tags(of: id))
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        for (n, ref) in refs.enumerated() {
            if n > 0 { result.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            let isTag = tags.contains(ref)
            result.append(NSAttributedString(string: " \(ref) ", attributes: [
                .font: font,
                .foregroundColor: Palette.refForeground(settings, isTag ? .tag : .head),
                .backgroundColor: Palette.refBackground(settings, isTag ? .tag : .head),
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
                    .link: "gitk-commit:" + commit.hex, .foregroundColor: Palette.link(settings), .paragraphStyle: paragraph,
                ])
                result.append(short)
                result.append(NSAttributedString(string: " ", attributes: attrs))
                if let color = row.mergeColor { attrs[.foregroundColor] = Palette.merge(settings, color) }
            }
            result.append(NSAttributedString(string: row.value + "\n", attributes: attrs))
        }
        if result.length > 0 { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    /// Port of gitk proc `appendwithlinks` (gitk/gitk 7222–7262): commit IDs and URLs become links.
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
            text.addAttributes([.link: value, .foregroundColor: Palette.link(settings)], range: link.range)
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

    // MARK: Actions

    /// Clicking the full commit ID copies it (D16).
    @objc private func copyID() {
        guard let shownID else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shownID.hex, forType: .string)
    }

    @objc private func toggleMessage() { messageView.isHidden = messageToggle.state == .off }
    @objc private func toggleMessageFromTitle() {
        messageToggle.state = messageToggle.state == .on ? .off : .on
        toggleMessage()
    }
}

/// A flipped container so scrolled content starts at the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
