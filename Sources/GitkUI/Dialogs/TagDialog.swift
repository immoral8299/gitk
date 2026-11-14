// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class TagDialog: RepositoryDialog {
    let nameField = NSTextField(string: "")
    let messageField = NSTextField(string: "")

    /// Port of gitk proc `mktag` (gitk/gitk 9514–9552).
    init(id: ObjectID, coordinator: RepositoryActionCoordinator) {
        super.init(title: L("Create tag"), accept: L("Create"))
        field(label: L("ID:"), value: id.hex, editable: false)
        row(label: L("Tag name:"), control: nameField)
        stack.addArrangedSubview(NSTextField(labelWithString: L("Tag message is optional")))
        row(label: L("Tag message:"), control: messageField)
        finishForm()
        onAccept = { [weak self] in
            guard let self else { return false }
            return await coordinator.tag(name: self.nameField.stringValue, at: id, message: self.messageField.stringValue)
        }
        window?.initialFirstResponder = nameField
    }
    required init?(coder: NSCoder) { nil }
}
