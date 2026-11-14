// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// Shared native form layout and submission for repository action dialogs.
@MainActor
class RepositoryDialog: NSWindowController, NSWindowDelegate {
    let stack = NSStackView()
    let acceptButton: NSButton
    var onAccept: (() async -> Bool)?
    private var submitting = false
    private var submissionTask: Task<Void, Never>?

    init(title: String, accept: String) {
        acceptButton = NSButton(title: accept, target: nil, action: nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        window.contentView = content
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 650),
        ])
        acceptButton.target = self
        acceptButton.action = #selector(acceptAction)
        acceptButton.keyEquivalent = "\r"
    }
    required init?(coder: NSCoder) { nil }

    @discardableResult
    func field(label: String, value: String = "", editable: Bool = true) -> NSTextField {
        let field = editable ? NSTextField(string: value) : NSTextField(labelWithString: value)
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingTail
        row(label: label, control: field)
        return field
    }

    func row(label: String, control: NSView) {
        let caption = NSTextField(labelWithString: label)
        caption.alignment = .right
        caption.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let row = NSStackView(views: [caption, control])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }

    func finishForm() {
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, acceptButton])
        buttons.spacing = 8
        buttons.orientation = .horizontal
        stack.addArrangedSubview(buttons)
        window?.setContentSize(NSSize(width: 650, height: max(180, stack.fittingSize.height)))
        window?.center()
    }

    func present(relativeTo parent: NSWindow?) {
        if let parent, let window { parent.addChildWindow(window, ordered: .above) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func acceptAction() {
        guard !submitting, let onAccept else { return }
        submitting = true
        acceptButton.isEnabled = false
        submissionTask = Task { [weak self] in
            let accepted = await onAccept()
            guard let self else { return }
            self.submitting = false
            self.acceptButton.isEnabled = true
            if accepted { self.close() }
        }
    }
    @objc private func cancel() { if !submitting { close() } }
    func windowWillClose(_ notification: Notification) { submissionTask?.cancel() }
}
