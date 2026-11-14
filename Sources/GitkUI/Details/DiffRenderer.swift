// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
struct DiffRenderer {
    var settings: Settings
    var mode: DiffDisplayMode = .diff
    var wordMode: WordDiffMode = .line
    var encoding: String = "utf-8"
    private var words = WordDiffParser()

    init(settings: Settings, mode: DiffDisplayMode = .diff, wordMode: WordDiffMode = .line) {
        self.settings = settings
        self.mode = mode
        self.wordMode = wordMode
    }

    static func color(_ value: String) -> NSColor {
        guard let rgba = TkColor.parse(value) else { return .textColor }
        return NSColor(srgbRed: CGFloat(rgba.r) / 255, green: CGFloat(rgba.g) / 255, blue: CGFloat(rgba.b) / 255, alpha: CGFloat(rgba.a) / 255)
    }

    var base: [NSAttributedString.Key: Any] {
        [.font: MainLayoutMetrics.nsFont(settings.textFont), .foregroundColor: Self.color(settings.fgColor)]
    }

    /// Port of gitk proc `parseblobdiffline` (gitk/gitk 8272–8542).
    mutating func render(_ line: DiffLine) -> NSAttributedString {
        if wordMode != .line {
            switch words.feed(line) {
            case .pending: return NSAttributedString(string: "")
            case .line(let runs):
                let result = NSMutableAttributedString(string: "")
                for run in runs {
                    var attrs = base
                    let data: Data
                    var pre = "", post = ""
                    switch run {
                    case .same(let value): data = value
                    case .added(let value):
                        if mode == .old { continue }
                        data = value
                        attrs[.foregroundColor] = Self.color(settings.diffColors[1])
                        attrs[.backgroundColor] = Self.color(settings.diffBgColors[1])
                        if wordMode == .markup { pre = "{+"; post = "+}" }
                    case .removed(let value):
                        if mode == .new { continue }
                        data = value
                        attrs[.foregroundColor] = Self.color(settings.diffColors[0])
                        attrs[.backgroundColor] = Self.color(settings.diffBgColors[0])
                        if wordMode == .markup { pre = "[-"; post = "-]" }
                    }
                    result.append(NSAttributedString(string: pre + decode(data) + post, attributes: attrs))
                }
                result.append(NSAttributedString(string: "\n", attributes: base))
                return result
            case .passthrough: break
            }
        }
        var attrs = base
        let text: String
        switch line {
        case .fileHeader(let old, let new, _):
            text = old != new ? "\(old ?? "/dev/null") → \(new ?? "/dev/null")" : (new ?? old ?? "")
            attrs[.foregroundColor] = Self.color(settings.fileSepFgColor)
            attrs[.backgroundColor] = Self.color(settings.fileSepBgColor)
            let paragraph = NSMutableParagraphStyle()
            let block = NSTextBlock()
            block.backgroundColor = Self.color(settings.fileSepBgColor)
            block.setValue(100, type: .percentageValueType, for: .width)
            paragraph.textBlocks = [block]
            attrs[.paragraphStyle] = paragraph
        case .add(let data):
            if mode == .old { return NSAttributedString(string: "") }
            text = (mode == .diff ? "+" : "") + decode(data)
            attrs[.foregroundColor] = Self.color(settings.diffColors[1])
            attrs[.backgroundColor] = Self.color(settings.diffBgColors[1])
        case .remove(let data):
            if mode == .new { return NSAttributedString(string: "") }
            text = (mode == .diff ? "-" : "") + decode(data)
            attrs[.foregroundColor] = Self.color(settings.diffColors[0])
            attrs[.backgroundColor] = Self.color(settings.diffBgColors[0])
        case .context(let data): text = (mode == .diff ? " " : "") + decode(data)
        case .hunkHeader(let data, _):
            text = decode(data)
            attrs[.foregroundColor] = Self.color(settings.diffColors[2])
        case .combined(let markers, let data):
            let result = NSMutableAttributedString(string: "")
            for (index, marker) in markers.enumerated() {
                var markerAttrs = base
                markerAttrs[.foregroundColor] = Self.color(settings.mergeColors[index % settings.mergeColors.count])
                result.append(NSAttributedString(string: String(marker), attributes: markerAttrs))
            }
            result.append(NSAttributedString(string: decode(data) + "\n", attributes: attrs))
            return result
        case .headerLine(let data), .binary(let data), .submodule(let data), .other(let data): text = decode(data)
        }
        return NSAttributedString(string: text + "\n", attributes: attrs)
    }

    private func decode(_ data: Data) -> String { TextDecoder.decode(data, encodingName: encoding) }
}
