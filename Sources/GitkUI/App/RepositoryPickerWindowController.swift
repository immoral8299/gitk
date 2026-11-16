// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// The window shown when the app starts outside a repository: it says so, opens
/// the folder chooser as a sheet straight away, and keeps an Open Repository
/// button for after a cancel. Closing it quits, as the last window.
@MainActor
final class RepositoryPickerWindowController: NSWindowController {
    var onChoose: ((URL) -> Void)?
    private var directory: URL?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "gitk"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let message = NSTextField(labelWithString: L("Cannot find a git repository here."))
        message.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        let detail = NSTextField(labelWithString: L("Choose a repository to open."))
        detail.textColor = .secondaryLabelColor
        let button = NSButton(title: L("Open Repository…"), target: self, action: #selector(openRepository))
        button.keyEquivalent = "\r"
        button.controlSize = .large
        let stack = NSStackView(views: [message, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(20, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the window, then the chooser on it, starting in `directory`.
    func present(startingAt directory: URL) {
        self.directory = directory
        if NSApp.mainMenu == nil { NSApp.mainMenu = Self.minimalMenu() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        openRepository()
    }

    @objc private func openRepository() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("Choose a repository to open.")
        panel.prompt = L("Open")
        panel.directoryURL = directory.flatMap { $0.path == "/" ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.directory = url
            self?.onChoose?(url)
        }
    }

    /// An app menu with Quit, so Command-Q works before the main window exists.
    private static func minimalMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        menu.addItem(appItem)
        return menu
    }
}
