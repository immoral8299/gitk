// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class WriteCommitDialog: RepositoryDialog {
    let commandField = NSTextField(string: "git diff-tree --stdin -p --pretty=email")
    let outputField = NSTextField(string: "")

    /// Port of gitk proc `writecommit` (gitk/gitk 9647–9677).
    init(id: ObjectID, coordinator: RepositoryActionCoordinator) {
        super.init(title: L("Write commit to file"), accept: L("Write"))
        field(label: L("ID:"), value: id.hex, editable: false)
        let headline = field(label: "", value: "", editable: false)
        let runner = coordinator.session.runner
        Task { [weak headline] in
            let out = try? await runner.run(["show", "-s", "--format=%s", id.hex])
            let text = out.map { String(decoding: $0.stdout, as: UTF8.self).trimmingCharacters(in: .newlines) } ?? ""
            headline?.stringValue = text
        }
        row(label: L("Command:"), control: commandField)
        let base = URL(fileURLWithPath: coordinator.session.repo.worktree, isDirectory: true)
        outputField.stringValue = base.appendingPathComponent("commit-" + id.abbreviated(7)).path
        row(label: L("Output file:"), control: outputField)
        finishForm()
        onAccept = { [weak self] in
            guard let self else { return false }
            return await coordinator.writeCommit(id, command: self.commandField.stringValue,
                output: URL(fileURLWithPath: self.outputField.stringValue))
        }
        window?.initialFirstResponder = outputField
    }
    required init?(coder: NSCoder) { nil }
}
