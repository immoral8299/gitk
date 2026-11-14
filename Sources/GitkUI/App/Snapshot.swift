// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// The verification hook of design D12: with `GITK_SWIFT_SNAPSHOT=<png>` the
/// app waits until its window is ready, renders the content view into a PNG
/// with `cacheDisplay(in:to:)` (no Screen Recording permission needed) and
/// exits 0. `GITK_SWIFT_SNAPSHOT_SIZE=WxH` sets the content size first.
@MainActor
final class Snapshot {
    static let pathKey = "GITK_SWIFT_SNAPSHOT"
    static let sizeKey = "GITK_SWIFT_SNAPSHOT_SIZE"

    /// Settle time after the window is laid out, in milliseconds.
    static let settleMilliseconds = 400

    let outputURL: URL
    let size: NSSize?

    /// Suspends until the window shows what the snapshot should capture.
    /// Injectable so tests, and later the history loader, can supply their own.
    var ready: @MainActor (NSWindow) async -> Void = Snapshot.defaultReady

    init(outputURL: URL, size: NSSize?) {
        self.outputURL = outputURL
        self.size = size
    }

    /// Returns a snapshot request when `GITK_SWIFT_SNAPSHOT` is set and non-empty.
    static func fromEnvironment(_ environment: [String: String]) -> Snapshot? {
        guard let path = environment[pathKey], !path.isEmpty else { return nil }
        return Snapshot(
            outputURL: URL(fileURLWithPath: path),
            size: environment[sizeKey].flatMap(parseSize))
    }

    /// Parses `WxH` (positive integers); nil for anything else.
    static func parseSize(_ text: String) -> NSSize? {
        let parts = text.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
            return nil
        }
        return NSSize(width: w, height: h)
    }

    /// Default readiness: the window is on screen and laid out, plus a short
    /// settle delay.
    static func defaultReady(_ window: NSWindow) async {
        for _ in 0..<100 where !window.isVisible {
            try? await Task.sleep(for: .milliseconds(20))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(settleMilliseconds))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Applies the requested size to `window`.
    func applySize(to window: NSWindow) {
        if let size { window.setContentSize(size) }
    }

    /// Renders `view` as PNG data.
    static func pngData(of view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        // Pixel size equals point size, so the PNG has the requested dimensions on
        // Retina and non-Retina displays alike.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width.rounded()),
            pixelsHigh: Int(view.bounds.height.rounded()), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Waits for readiness, writes the PNG and exits: 0 on success, 1 on failure.
    func run(window: NSWindow) async -> Never {
        applySize(to: window)
        await ready(window)
        guard let view = window.contentView, let data = Snapshot.pngData(of: view) else {
            FileHandle.standardError.write(Data("gitk: snapshot failed: cannot render window\n".utf8))
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("gitk: snapshot failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}
