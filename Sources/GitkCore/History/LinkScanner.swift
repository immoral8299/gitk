// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct TextLink: Sendable, Equatable {
    public enum Target: Sendable, Equatable { case commit(ObjectID), web(URL) }
    public var range: NSRange
    public var target: Target
}

public enum LinkScanner {
    /// Port of gitk procs `appendwithlinks`, `setlink`, `setwlink`
    /// (gitk/gitk 7222–7304). Only uniquely resolved hashes become links.
    public static func scan(_ text: String, hashLength: Int, resolve: (String) -> ObjectID?) -> [TextLink] {
        let all = NSRange(location: 0, length: (text as NSString).length)
        var result: [TextLink] = []
        if let regex = try? NSRegularExpression(pattern: "(?:\\b|-g)[0-9a-f]{6,\(hashLength)}\\b") {
            for match in regex.matches(in: text, range: all) {
                let raw = (text as NSString).substring(with: match.range)
                let prefix = raw.hasPrefix("-g") ? String(raw.dropFirst(2)) : raw
                if let id = resolve(prefix) { result.append(TextLink(range: match.range, target: .commit(id))) }
            }
        }
        if let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+") {
            for match in regex.matches(in: text, range: all) {
                if let url = URL(string: (text as NSString).substring(with: match.range)) {
                    result.removeAll { NSIntersectionRange($0.range, match.range).length > 0 }
                    result.append(TextLink(range: match.range, target: .web(url)))
                }
            }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }
}
