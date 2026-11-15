// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class BranchDialog: RepositoryDialog {
    let nameField = NSTextField(string: "")

    /// Port of gitk procs `mkbranch`, `mvbranch` and `branchdia` (gitk/gitk 9706–9770).
    init(id: ObjectID, renameFrom oldName: String? = nil, coordinator: RepositoryActionCoordinator) {
        super.init(title: oldName.map { L("Rename branch %s", $0) } ?? L("Create branch"),
                   accept: oldName == nil ? L("Create") : L("Rename"))
        field(label: L("ID:"), value: id.hex, editable: false)
        let headline = field(label: "", value: "", editable: false)
        let runner = coordinator.session.runner
        Task { [weak headline] in
            let out = try? await runner.run(["show", "-s", "--format=%s", id.hex])
            headline?.stringValue = out.map { String(decoding: $0.stdout, as: UTF8.self).trimmingCharacters(in: .newlines) } ?? ""
        }
        nameField.stringValue = oldName ?? ""
        row(label: L("Name:"), control: nameField)
        finishForm()
        onAccept = { [weak self] in
            guard let self else { return false }
            return await coordinator.branch(name: self.nameField.stringValue, at: id, renameFrom: oldName)
        }
        window?.initialFirstResponder = nameField
    }
    required init?(coder: NSCoder) { nil }
}
