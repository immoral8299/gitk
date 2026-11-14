// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class PatchDialog: RepositoryDialog {
    let outputField = NSTextField(string: "")
    let reverseButton = NSButton(checkboxWithTitle: L("Reverse"), target: nil, action: nil)

    /// Port of gitk proc `mkpatch` (gitk/gitk 9424–9491).
    init(from: ObjectID, to: ObjectID, number: Int, coordinator: RepositoryActionCoordinator) {
        super.init(title: L("Generate patch"), accept: L("Generate"))
        field(label: L("From:"), value: from.hex, editable: false)
        field(label: L("To:"), value: to.hex, editable: false)
        stack.addArrangedSubview(reverseButton)
        let repo = coordinator.session.repo
        let base = URL(fileURLWithPath: repo.worktree.isEmpty ? repo.gitDir : repo.worktree)
        outputField.stringValue = base.appendingPathComponent("patch\(number).patch").path
        row(label: L("Output file:"), control: outputField)
        finishForm()
        onAccept = { [weak self] in
            guard let self else { return false }
            return await coordinator.makePatch(from: from, to: to, reverse: self.reverseButton.state == .on,
                                                output: URL(fileURLWithPath: self.outputField.stringValue))
        }
        window?.initialFirstResponder = outputField
    }
    required init?(coder: NSCoder) { nil }
}
