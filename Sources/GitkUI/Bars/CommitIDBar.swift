// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class CommitIDBar: NSStackView {
    let field = NSTextField()
    let back = NSButton(title: "←", target: nil, action: nil)
    let forward = NSButton(title: "→", target: nil, action: nil)
    let counter = NSTextField(labelWithString: "0 / 0")
    let status = StatusBar()
    var onGo: ((String) -> Void)?
    var onCommand: ((AppCommand) -> Void)?

    init(font: NSFont) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        field.font = font
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.target = self
        field.action = #selector(go)
        back.target = self
        back.action = #selector(goBack)
        forward.target = self
        forward.action = #selector(goForward)
        back.isEnabled = false
        forward.isEnabled = false
        for view in [NSTextField(labelWithString: L("Commit ID:")), field, back, forward,
                     NSTextField(labelWithString: L("Row")), counter, status] {
            addArrangedSubview(view)
        }
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        status.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh(session: ViewSession) {
        field.stringValue = session.selection.selectedID?.hex ?? ""
        let row = session.selection.selectedID.flatMap { session.row(of: $0) }.map { $0 + 1 } ?? 0
        counter.stringValue = "\(row) / \(session.rowCount)"
        back.isEnabled = session.selection.history.canGoBack
        forward.isEnabled = session.selection.history.canGoForward
    }

    @objc private func go() { onGo?(field.stringValue) }
    @objc private func goBack() { onCommand?(.goBack) }
    @objc private func goForward() { onCommand?(.goForward) }
}
