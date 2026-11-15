// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

extension Notification.Name {
    /// Posted after the preferences window's OK applies new settings. The
    /// notification object is the new `Settings` value; observers (task 18.5)
    /// apply it live.
    static let gitkSettingsDidChange = Notification.Name("GitkSettingsDidChange")
}

/// Target object that forwards a control's action to a closure.
@MainActor
final class ClosureTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

/// A number field with a stepper, the equivalent of gitk's `ttk::spinbox`.
@MainActor
final class SpinnerField: NSView {
    let field = NSTextField()
    let stepper = NSStepper()
    var onChange: ((Int) -> Void)?

    var value: Int {
        get { Int(stepper.intValue) }
        set { stepper.integerValue = newValue; field.integerValue = newValue }
    }

    init(value: Int, range: ClosedRange<Int>) {
        super.init(frame: .zero)
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepped)
        field.target = self
        field.action = #selector(typed)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        self.value = min(max(value, range.lowerBound), range.upperBound)
        let stack = NSStackView(views: [field, stepper])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func stepped() {
        field.integerValue = Int(stepper.intValue)
        onChange?(value)
    }

    /// Typed text is clamped to the range; non-numbers revert to the old value.
    @objc private func typed() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if let n = Int(text) {
            value = min(max(n, Int(stepper.minValue)), Int(stepper.maxValue))
        } else {
            field.integerValue = Int(stepper.intValue)
        }
        onChange?(value)
    }
}

/// Port of gitk proc `doprefs` (gitk/gitk 11914–11961), `prefspage_general`
/// (11704–11801), `choose_extdiff` (11963–11970), `prefscan` and `prefsok`
/// (12078–12150).
///
/// The window edits `draft`, a copy of the settings. OK hands the draft to
/// `onApply` (which applies and saves it) and posts `.gitkSettingsDidChange`;
/// Cancel throws it away. Tabs come from `pageBuilders`: tasks 18.2 and 18.3
/// replace the Colors and Fonts entries and bind their controls to `draft` the
/// same way `makeGeneralPage()` does.
@MainActor
final class PreferencesController: NSWindowController, NSWindowDelegate {
    private(set) var draft: Settings
    let original: Settings
    let hashLength: Int
    var onApply: ((Settings) -> Void)?
    var onClose: (() -> Void)?
    private let notificationCenter: NotificationCenter

    let tabView = NSTabView()
    private(set) var showLocalChangesCheckbox: NSButton?
    private(set) var extDiffToolField: NSTextField?
    private(set) var spinners: [String: SpinnerField] = [:]
    /// The Colors page wells, keyed by `ColorSetting.id`.
    private(set) var colorWells: [String: NSColorWell] = [:]
    private(set) var okButton = NSButton()
    private(set) var cancelButton = NSButton()

    /// (title, builder) for each tab, in gitk's order.
    private(set) var pageBuilders: [(title: String, build: (PreferencesController) -> NSView)] = [
        (L("General"), { $0.makeGeneralPage() }),
        (L("Colors"), { $0.makeColorsPage() }),
        (L("Fonts"), { _ in NSView() }),
    ]

    init(settings: Settings, hashLength: Int = 40, notificationCenter: NotificationCenter = .default) {
        original = settings
        draft = settings
        self.hashLength = hashLength
        self.notificationCenter = notificationCenter
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Gitk preferences")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Window

    private func buildContent(in window: NSWindow) {
        for page in pageBuilders {
            let item = NSTabViewItem()
            item.label = page.title
            item.view = page.build(self)
            tabView.addTabViewItem(item)
        }
        okButton = NSButton(title: L("OK"), target: self, action: #selector(okAction))
        okButton.keyEquivalent = "\r"
        cancelButton = NSButton(title: L("Cancel"), target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancelButton, okButton])
        buttons.spacing = 12
        let root = NSStackView(views: [tabView, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        window.contentView = content
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tabView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
            tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 580),
        ])
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
    }

    /// Port of gitk proc `prefsok` minus applying each change (task 18.5).
    @objc func okAction() {
        window?.makeFirstResponder(nil)
        let new = draft
        close()
        onApply?(new)
        notificationCenter.post(name: .gitkSettingsDidChange, object: new)
    }

    /// Port of gitk proc `prefscan`: the draft is dropped.
    @objc func cancelAction() {
        draft = original
        close()
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: General page

    /// Port of gitk proc `prefspage_general`. The X11 selection checkbox is
    /// omitted: macOS has no selection clipboard (`haveselectionclipboard`).
    func makeGeneralPage() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        func header(_ text: String) {
            let title = label(text)
            title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            let row = grid.addRow(with: [title, NSView(), NSView()])
            row.mergeCells(in: NSRange(location: 0, length: 3))
            row.topPadding = 6
        }
        func spinner(_ key: String, _ title: String, _ range: ClosedRange<Int>,
                     _ path: WritableKeyPath<Settings, Int>) {
            let s = SpinnerField(value: draft[keyPath: path], range: range)
            s.onChange = { [weak self] in self?.draft[keyPath: path] = $0 }
            spinners[key] = s
            grid.addRow(with: [NSView(), label(title), s])
        }
        func check(_ title: String, _ path: WritableKeyPath<Settings, Bool>) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            b.state = draft[keyPath: path] ? .on : .off
            bind(b, ClosureTarget { [weak self, weak b] in
                self?.draft[keyPath: path] = b?.state == .on
            })
            grid.addRow(with: [NSView(), b, NSView()]).mergeCells(in: NSRange(location: 1, length: 2))
            return b
        }
        func text(_ title: String, _ path: WritableKeyPath<Settings, String>, button: NSButton? = nil) -> NSTextField {
            let f = NSTextField(string: draft[keyPath: path])
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            bind(f, ClosureTarget { [weak self, weak f] in self?.draft[keyPath: path] = f?.stringValue ?? "" })
            let titleView: NSView
            if let button {
                let s = NSStackView(views: [label(title), button])
                s.spacing = 8
                titleView = s
            } else {
                titleView = label(title)
            }
            grid.addRow(with: [NSView(), titleView, f])
            return f
        }
        func wrap(_ title: String, _ path: WritableKeyPath<Settings, String>) {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["none", "char", "word"])
            popup.selectItem(withTitle: draft[keyPath: path])
            bind(popup, ClosureTarget { [weak self, weak popup] in
                self?.draft[keyPath: path] = popup?.titleOfSelectedItem ?? "none"
            })
            grid.addRow(with: [NSView(), label(title), popup])
        }

        header(L("Commit list display options"))
        spinner("maxWidth", L("Maximum graph width (lines)"), 0...100, \.maxWidth)
        spinner("maxGraphPct", L("Maximum graph width (% of pane)"), 1...100, \.maxGraphPct)
        showLocalChangesCheckbox = check(L("Show local changes"), \.showLocalChanges)
        _ = check(L("Hide remote refs"), \.hideRemotes)
        _ = text(L("Refs to hide (space-separated globs)"), \.refsToHide)
        _ = check(L("Copy commit ID to clipboard"), \.autoCopy)
        spinner("autoSelLen", L("Length of commit ID to copy"), 1...max(hashLength, 1), \.autoSelLen)
        spinner("kscroll", L("Wheel scrolling multiplier"), 1...20, \.kscroll)
        _ = text(L("Date and time format"), \.dateTimeFormat)

        header(L("Diff display options"))
        spinner("tabStop", L("Tab spacing"), 1...20, \.tabStop)
        wrap(L("Wrap comment text"), \.wrapComment)
        wrap(L("Wrap other text"), \.wrapDefault)
        _ = check(L("Display nearby tags/heads"), \.showNearTags)
        spinner("maxRefs", L("Maximum # tags/heads to show"), 1...1000, \.maxRefs)
        _ = check(L("Limit diffs to listed paths"), \.limitDiffs)
        _ = check(L("Support per-file encodings"), \.perFileAttrs)
        let choose = NSButton(title: L("Choose..."), target: nil, action: nil)
        bind(choose, ClosureTarget { [weak self] in self?.chooseExtDiff() })
        extDiffToolField = text(L("External diff tool"), \.extDiffTool, button: choose)
        _ = text(L("Web browser"), \.webBrowser)

        grid.column(at: 0).width = 12
        let page = NSView()
        page.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -12),
            grid.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
        ])
        return page
    }

    /// Port of gitk proc `choose_extdiff`: an open panel whose choice goes into
    /// the External diff tool field and the draft.
    func chooseExtDiff() {
        let panel = NSOpenPanel()
        panel.title = L("External diff tool")
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let path = panel.url?.path else { return }
            self?.setExtDiffTool(path)
        }
    }

    func setExtDiffTool(_ path: String) {
        draft.extDiffTool = path
        extDiffToolField?.stringValue = path
    }

    // MARK: Colors page

    /// One colour setting edited on the Colors page.
    struct ColorSetting {
        let id: String
        let title: String
        let set: (inout Settings, String) -> Void
        let display: @MainActor (Settings) -> NSColor
    }

    /// Port of the `coloruielems` list in gitk proc `prefspage_colors`
    /// (gitk/gitk 11836–11866), in gitk's order, followed by the two search
    /// colours.
    static let colorSettings: [ColorSetting] = [
        ColorSetting(id: "bg", title: L("Background"), set: { $0.bgColor = $1 },
                     display: { Palette.background($0) }),
        ColorSetting(id: "fg", title: L("Main text"), set: { $0.fgColor = $1 },
                     display: { Palette.foreground($0) }),
        ColorSetting(id: "selbg", title: L("Selected text background"), set: { $0.selectBgColor = $1 },
                     display: { Palette.tk($0.selectBgColor) }),
        ColorSetting(id: "linkfg", title: L("Link text"), set: { $0.linkFgColor = $1 },
                     display: { Palette.link($0) }),
        ColorSetting(id: "diffold", title: L("Old line text"), set: { $0.setList(\.diffColors, 0, $1) },
                     display: { Palette.diff($0, 0) }),
        ColorSetting(id: "diffoldbg", title: L("Old line background"), set: { $0.setList(\.diffBgColors, 0, $1) },
                     display: { Palette.diffBackground($0, 0) }),
        ColorSetting(id: "diffnew", title: L("New line text"), set: { $0.setList(\.diffColors, 1, $1) },
                     display: { Palette.diff($0, 1) }),
        ColorSetting(id: "diffnewbg", title: L("New line background"), set: { $0.setList(\.diffBgColors, 1, $1) },
                     display: { Palette.diffBackground($0, 1) }),
        ColorSetting(id: "hunksep", title: L("Hunk header text"), set: { $0.setList(\.diffColors, 2, $1) },
                     display: { Palette.diff($0, 2) }),
        ColorSetting(id: "markbg", title: L("Marked line background"), set: { $0.markBgColor = $1 },
                     display: { Palette.tk($0.markBgColor) }),
        ColorSetting(id: "foundbg", title: L("Found text background"), set: { $0.foundBgColor = $1 },
                     display: { Palette.found($0) }),
        ColorSetting(id: "currenthit", title: L("Current search hit background"),
                     set: { $0.currentSearchHitBgColor = $1 }, display: { Palette.tk($0.currentSearchHitBgColor) }),
    ]

    /// Tk colour string (`#rrggbb`) for an `NSColor`, via sRGB.
    static func tkString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ v: CGFloat) -> UInt8 { UInt8(min(max((v * 255).rounded(), 0), 255)) }
        return TkColor.hexString(RGBA(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)))
    }

    /// Port of gitk proc `prefspage_colors` (colour part) and `choosecolor`.
    /// A well edits the draft only; nothing applies until OK. The Themes
    /// section is omitted (no Tk themes; see Deviations).
    func makeColorsPage() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        let title = label(L("Colors: press to choose"))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        grid.addRow(with: [title, NSView()]).mergeCells(in: NSRange(location: 0, length: 2))
        for item in Self.colorSettings {
            let well = NSColorWell()
            well.color = item.display(draft)
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 64).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            bind(well, ClosureTarget { [weak self, weak well] in
                guard let self, let well else { return }
                item.set(&self.draft, Self.tkString(well.color))
            })
            colorWells[item.id] = well
            grid.addRow(with: [label(item.title), well])
        }
        let page = NSView()
        page.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -12),
            grid.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
        ])
        return page
    }

    // MARK: Helpers

    private var targets: [ClosureTarget] = []

    private func bind(_ control: NSControl, _ target: ClosureTarget) {
        targets.append(target)
        control.target = target
        control.action = #selector(ClosureTarget.fire)
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .left
        return l
    }
}

private extension Settings {
    /// `lset`: replaces entry `i` of a colour list, growing it if short.
    mutating func setList(_ path: WritableKeyPath<Settings, [String]>, _ i: Int, _ value: String) {
        while self[keyPath: path].count <= i { self[keyPath: path].append("") }
        self[keyPath: path][i] = value
    }
}
