// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public actor GitAttributes {
    private let runner: GitRunner
    private var encodings: [String: String] = [:]
    public init(runner: GitRunner) { self.runner = runner }

    /// Port of gitk procs `gitattr`, `get_path_encoding` (gitk/gitk 12460–12518).
    public func encoding(for path: String, fallback: String) async -> String {
        if let cached = encodings[path] { return cached == "unspecified" ? fallback : cached }
        guard let output = try? await runner.run(["check-attr", "-z", "encoding", "--", path]) else { return fallback }
        let values = output.stdout.split(separator: 0, omittingEmptySubsequences: false)
        guard values.count >= 3 else { return fallback }
        let value = String(decoding: values[2], as: UTF8.self)
        encodings[path] = value
        return value == "unspecified" ? fallback : value
    }
    public func invalidate() { encodings = [:] }

    /// Port of gitk proc `get_path_encoding` (gitk/gitk 12504–12514): the
    /// encoding for `path`'s text. An empty or nil path, or `perFileAttrs` off,
    /// gives `guiEncoding`.
    public func pathEncoding(_ path: String?, guiEncoding: String, perFileAttrs: Bool) async -> String {
        guard perFileAttrs, let path, !path.isEmpty else { return guiEncoding }
        return await encoding(for: path, fallback: guiEncoding)
    }

    /// Decodes file text (a diff line or blob) for `path` with its `encoding`
    /// attribute, else `guiEncoding`. Unknown names and invalid bytes fall back
    /// as in ``TextDecoder``.
    public func decode(_ data: Data, path: String?, guiEncoding: String, perFileAttrs: Bool) async -> String {
        let name = await pathEncoding(path, guiEncoding: guiEncoding, perFileAttrs: perFileAttrs)
        return TextDecoder.decode(data, encodingName: name)
    }
}
