// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// One row of the editor form, built from gitk's layout flags.
struct ViewEditorRow: Equatable {
    var options: [ViewOption]
    /// `..` and `*.`: the row is indented by 15 points.
    var indented: Bool
    /// `*` and `*.`: the row's widgets expand.
    var expands: Bool
    /// The first row also holds the "View Name" field.
    var hasName: Bool
}

/// The pure part of the view editor: the row model and the conversion of the
/// fields into a `ViewSpec`.
enum ViewEditorForm {
    /// Port of the layout loop of gitk proc `vieweditor` (gitk/gitk 4454–4527):
    /// `+` and `*` start a row, `..` and `*.` start an indented row, anything
    /// else continues the current row. The name row exists before the first
    /// option, so `perm` joins it.
    static func rows(for options: [ViewOption] = ViewOptions.known) -> [ViewEditorRow] {
        var rows = [ViewEditorRow(options: [], indented: false, expands: false, hasName: true)]
        for opt in options {
            switch opt.layout {
            case .newRow, .newRowExpanding:
                rows.append(ViewEditorRow(
                    options: [opt], indented: false, expands: opt.layout == .newRowExpanding, hasName: false))
            case .newRowIndented, .newRowIndentedExpanding:
                rows.append(ViewEditorRow(
                    options: [opt], indented: true, expands: opt.layout == .newRowIndentedExpanding,
                    hasName: false))
            case .same:
                rows[rows.count - 1].options.append(opt)
            }
        }
        return rows
    }

    /// Port of the file collection and `encode_view_opts` call of gitk proc
    /// `newviewok` (gitk/gitk 4534–4553): one trimmed path per non-empty line.
    static func spec(values: ViewOptionValues, pathsText: String) throws -> ViewSpec {
        let args = try ViewOptionCodec.encode(values)
        let files = pathsText.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\u{0B}\u{0C}")) }.filter { !$0.isEmpty }
        let cmd = values.text("cmd")
        return ViewSpec(
            name: values.name, args: args, files: files,
            argsCmd: cmd.isEmpty ? nil : cmd, perm: values.perm)
    }

    /// Port of gitk proc `editview` field setup (gitk/gitk 4446–4452): the
    /// values a view's editor starts with. Nil is a new, empty view.
    static func initialValues(for view: ViewSpec?) -> ViewOptionValues {
        guard let view else { return ViewOptionCodec.decode([]) }
        var v = ViewOptionCodec.decode(view.args)
        v.name = view.name
        v.perm = view.perm
        v.values["cmd"] = .text(view.argsCmd ?? "")
        return v
    }
}

/// The "Gitk: new view" / "Gitk: edit view" window. Port of gitk proc
/// `vieweditor` (gitk/gitk 4454–4527) and the dialog half of `newviewok`
/// (gitk/gitk 4534–4586).
@MainActor
final class ViewEditorController: NSWindowController, NSWindowDelegate {
    /// Called by OK and Apply with the view the fields describe. The owner
    /// adds or reloads the view; `existing` is what the editor was opened on.
    var onApply: ((ViewSpec) -> Void)?
    /// Called when the window closes by OK, Cancel or the close button.
    var onClose: (() -> Void)?

    let existing: ViewSpec?
    let nameField = NSTextField(string: "")
    let pathsView = NSTextView()
    private(set) var checkboxes: [String: NSButton] = [:]
    private(set) var radios: [String: [Int: NSButton]] = [:]
    private(set) var textFields: [String: NSTextField] = [:]
    private let alerts: Alerts

    /// - Parameters:
    ///   - view: The view to edit, or nil for "new view".
    ///   - title: gitk's window title before the criteria suffix; defaults to
    ///     "Gitk view definition" or "Gitk: edit view <name>".
    init(view: ViewSpec? = nil, title: String? = nil, alerts: Alerts = Alerts()) {
        existing = view
        self.alerts = alerts
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let base = title ?? (view.map { "\(L("Gitk: edit view")) \($0.name)" } ?? L("Gitk view definition"))
        window.title = "\(base) \(L("-- criteria for selecting revisions"))"
        super.init(window: window)
        window.delegate = self
        buildForm(initial: ViewEditorForm.initialValues(for: view), files: view?.files ?? [])
    }
    required init?(coder: NSCoder) { nil }

    // MARK: Form

    private func buildForm(initial: ViewOptionValues, files: [String]) {
        guard let window else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = EditorBackgroundView()
        window.contentView = content
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 680),
        ])

        nameField.stringValue = initial.name
        for row in ViewEditorForm.rows() {
            var views: [NSView] = []
            if row.hasName {
                views.append(NSTextField(labelWithString: L("View Name")))
                nameField.widthAnchor.constraint(equalToConstant: 160).isActive = true
                views.append(nameField)
            }
            for opt in row.options {
                switch opt.kind {
                case .path:
                    // gitk packs the paths label and box straight into the window.
                    stack.addArrangedSubview(NSTextField(labelWithString: L(opt.title)))
                    stack.addArrangedSubview(makePathsBox(files: files))
                case .textStacked(let width):
                    stack.addArrangedSubview(NSTextField(labelWithString: L(opt.title)))
                    let field = makeField(opt, width: width, initial: initial)
                    stack.addArrangedSubview(field)
                    field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
                default:
                    views += controls(for: opt, initial: initial)
                }
            }
            guard !views.isEmpty else { continue }
            let rowStack = NSStackView(views: views)
            rowStack.orientation = .horizontal
            rowStack.alignment = .firstBaseline
            rowStack.spacing = 8
            rowStack.edgeInsets = NSEdgeInsets(top: 0, left: row.indented ? 15 : 0, bottom: 0, right: 0)
            stack.addArrangedSubview(rowStack)
            if row.expands {
                rowStack.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
            }
        }
        stack.addArrangedSubview(makeButtons())
        window.setContentSize(stack.fittingSize)
        window.initialFirstResponder = pathsView
        window.center()
    }

    private func controls(for opt: ViewOption, initial: ViewOptionValues) -> [NSView] {
        switch opt.kind {
        case .label:
            return [NSTextField(labelWithString: L(opt.title))]
        case .checkbox:
            let b = NSButton(checkboxWithTitle: L(opt.title), target: nil, action: nil)
            b.state = initial.bool(opt.id) ? .on : .off
            checkboxes[opt.id] = b
            return [b]
        case .radio(let value):
            let b = NSButton(radioButtonWithTitle: L(opt.title), target: self, action: #selector(radioChosen(_:)))
            if let group = opt.radioGroup {
                b.state = initial.radio(group) == value ? .on : .off
                b.tag = value
                b.identifier = NSUserInterfaceItemIdentifier(group)
                radios[group, default: [:]][value] = b
            }
            return [b]
        case .text(let width):
            let label = NSTextField(labelWithString: L(opt.title))
            let field = makeField(opt, width: width, initial: initial)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return [label, field]
        case .textStacked, .path:
            return []
        }
    }

    private func makeField(_ opt: ViewOption, width: Int, initial: ViewOptionValues) -> NSTextField {
        let field = NSTextField(string: initial.text(opt.id))
        // gitk's -width counts characters; 8 points approximates one.
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(width) * 8).isActive = true
        textFields[opt.id] = field
        return field
    }

    private func makePathsBox(files: [String]) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        pathsView.isRichText = false
        pathsView.isAutomaticQuoteSubstitutionEnabled = false
        pathsView.isAutomaticDashSubstitutionEnabled = false
        pathsView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        pathsView.string = files.joined(separator: "\n")
        pathsView.isVerticallyResizable = true
        pathsView.autoresizingMask = [.width]
        scroll.documentView = pathsView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 656).isActive = true
        return scroll
    }

    private func makeButtons() -> NSView {
        let ok = NSButton(title: L("OK"), target: self, action: #selector(okAction))
        ok.keyEquivalent = "\r"
        let apply = NSButton(title: L("Apply (F5)"), target: self, action: #selector(applyAction))
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        let row = NSStackView(views: [ok, apply, cancel])
        row.distribution = .fillEqually
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 656).isActive = true
        return row
    }

    // MARK: Values and actions

    /// The fields as gitk's `newviewname` and `newviewopts`.
    func currentValues() -> ViewOptionValues {
        var v = ViewOptionValues(name: nameField.stringValue)
        for (id, b) in checkboxes { v.values[id] = .bool(b.state == .on) }
        for (group, buttons) in radios {
            v.values[group] = .radio(buttons.first { $0.value.state == .on }?.key ?? 0)
        }
        for (id, f) in textFields { v.values[id] = .text(f.stringValue) }
        return v
    }

    /// Port of gitk proc `newviewok` (gitk/gitk 4534–4586), dialog half:
    /// encodes the fields, reports an encoding error with `error_popup`
    /// (leaving the editor open), otherwise hands the view to `onApply`.
    /// Returns whether the fields were accepted.
    @discardableResult
    func apply() -> Bool {
        do {
            let spec = try ViewEditorForm.spec(values: currentValues(), pathsText: pathsView.string)
            onApply?(spec)
            return true
        } catch let e as ViewArgsError {
            alerts.errorPopup("\(L(e.prefix)) \(e.detail)", parent: window)
        } catch {
            alerts.errorPopup("\(error)", parent: window)
        }
        return false
    }

    @objc private func radioChosen(_ sender: NSButton) {
        guard let group = sender.identifier?.rawValue else { return }
        for (value, b) in radios[group] ?? [:] { b.state = value == sender.tag ? .on : .off }
    }

    @objc func okAction() {
        if apply() { window?.close() }
    }

    @objc func applyAction() { apply() }

    @objc func cancelAction() { window?.close() }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    /// gitk binds F5 to Apply (Escape is Cancel's key equivalent, Return OK's).
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 96 { applyAction() } else { super.keyDown(with: event) }
    }
}

/// Content view that paints the window background itself, so a snapshot of it
/// (which skips the window's own background) is not transparent.
private final class EditorBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
