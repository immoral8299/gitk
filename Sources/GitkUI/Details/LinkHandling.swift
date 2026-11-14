// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Commit and web links in the sidebar text (gitk's `appendwithlinks`,
/// `setlink`, `setwlink` and `browseweb`).
@MainActor
enum LinkHandling {
    static let commitScheme = "gitk-commit:"

    /// Port of gitk proc `appendwithlinks` (gitk/gitk 7222–7262): hex IDs that
    /// resolve to exactly one commit in the view, and http(s) URLs unless
    /// `web_browser` is empty.
    static func addLinks(to text: NSMutableAttributedString, session: ViewSession, settings: Settings) {
        let ids = (0..<session.rowCount).compactMap { session.id(at: $0) }
        let links = LinkScanner.scan(text.string, hashLength: session.repo.hashLength) { prefix in
            let matches = ids.filter { $0.hex.hasPrefix(prefix) }
            return matches.count == 1 ? matches.first : nil
        }
        let browser = WebBrowser.action(setting: settings.webBrowser)
        for link in links {
            let value: String
            switch link.target {
            case .commit(let id): value = commitScheme + id.hex
            case .web(let url):
                if browser == .none { continue }
                value = url.absoluteString
            }
            text.addAttributes([.link: value, .foregroundColor: Palette.link(settings)], range: link.range)
        }
    }

    /// The commit a link value points at, if it is a commit link.
    static func commit(in link: Any) -> ObjectID? {
        let value = (link as? String) ?? (link as? URL)?.absoluteString ?? ""
        guard value.hasPrefix(commitScheme) else { return nil }
        return ObjectID(hex: String(value.dropFirst(commitScheme.count)))
    }

    /// Port of gitk proc `browseweb` (gitk/gitk 7329–7340).
    static func openWeb(_ link: Any, settings: Settings, parent: NSWindow?) {
        let value = (link as? String) ?? (link as? URL)?.absoluteString ?? ""
        guard let url = URL(string: value) else { return }
        switch WebBrowser.action(setting: settings.webBrowser) {
        case .none: return
        case .systemDefault: NSWorkspace.shared.open(url)
        case .command(let words):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = words + [value]
            do { try process.run() } catch {
                Alerts().showError("\(L("Error starting web browser:")) \(error.localizedDescription)", parent: parent)
            }
        }
    }
}
