// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// What `Tests/Oracle/oracle.tcl --repo <dir>` prints (design D5): gitk's own
/// ordering, layout and colouring for one repository.
struct OracleResult: Decodable, Equatable, Sendable {
    /// One row of the laid-out graph.
    struct Row: Decodable, Equatable, Sendable {
        /// `lsearch -exact idlist id`: the column of the commit on its row.
        let col: Int
        let id: String
        /// `rowidlist[row]` after `optimize_rows`; padding entries are `""`.
        let idlist: [String]
    }

    /// The arc tables (`varcstart`, `varccommits`, ...) of view 0. Index 0 of
    /// every array is gitk's sentinel arc.
    struct Varcs: Decodable, Equatable, Sendable {
        let varcstart: [String]
        let varccommits: [[String]]
        let varctok: [String]
        let vupptr: [Int]
        let vdownptr: [Int]
        let vleftptr: [Int]
        let vbackptr: [Int]
        let varcrow: [Int?]
    }

    /// Commit IDs in gitk's display order (`commitonrow 0..n-1`).
    let order: [String]
    let varcs: Varcs
    let rows: [Row]
    /// `rowranges $id` for every commit.
    let ranges: [String: [Int]]
    /// Index into gitk's `colors` list, as chosen by `assigncolor`.
    let colors: [String: Int]
}

/// Loads the checked-in oracle outputs in `Tests/GitkCoreTests/Golden/`.
/// Regenerate them with `Tools/regen-golden.sh`; never edit them by hand.
enum OracleGolden {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    /// `Tests/GitkCoreTests/Golden`, found relative to this file.
    static var directory: URL {
        // <repo>/Tests/GitkCoreTests/Support/Oracle.swift → .../GitkCoreTests/Golden
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Golden", isDirectory: true)
    }

    static func url(_ fixture: String) -> URL {
        directory.appendingPathComponent("\(fixture).json")
    }

    /// Names of all fixtures that have a golden file, sorted.
    static func fixtureNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    static func load(_ fixture: String) throws -> OracleResult {
        let file = url(fixture)
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw LoadError(description: "no golden file for \(fixture) at \(file.path); run Tools/regen-golden.sh")
        }
        return try JSONDecoder().decode(OracleResult.self, from: data)
    }
}

/// Runs the Tcl oracle when `tclsh` and the `gitk/` submodule are present, and
/// falls back to the golden file otherwise.
enum OracleRunner {
    struct RunError: Error, CustomStringConvertible {
        let description: String
    }

    static var oracleScript: URL {
        FixtureRepo.repoRoot.appendingPathComponent("Tests/Oracle/oracle.tcl")
    }

    static var gitkScript: URL {
        FixtureRepo.repoRoot.appendingPathComponent("gitk/gitk")
    }

    /// `/opt/homebrew/bin/tclsh`, or the first `tclsh` in `PATH`.
    static var tclshURL: URL? {
        let fm = FileManager.default
        var candidates = ["/opt/homebrew/bin/tclsh"]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in path.split(separator: ":") where !dir.isEmpty {
            candidates.append("\(dir)/tclsh")
        }
        for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// True when `result(for:)` will run the live oracle.
    static var liveAvailable: Bool {
        tclshURL != nil && FileManager.default.fileExists(atPath: gitkScript.path)
    }

    /// The oracle output for a fixture: live when possible, else golden.
    static func result(for fixture: String) throws -> OracleResult {
        guard liveAvailable else { return try OracleGolden.load(fixture) }
        return try live(fixture)
    }

    /// Always runs `tclsh Tests/Oracle/oracle.tcl --repo <fixture>`.
    static func live(_ fixture: String) throws -> OracleResult {
        guard let tclsh = tclshURL else { throw RunError(description: "tclsh not found") }
        let repo = try FixtureRepo.make(fixture)

        let process = Process()
        process.executableURL = tclsh
        process.arguments = [oracleScript.path, "--repo", repo.path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Read stderr on another thread so a full pipe cannot block the child
        // while this thread waits for stdout to close.
        let errorBox = DataBox()
        let errorReader = Thread {
            errorBox.set(stderr.fileHandleForReading.readDataToEndOfFile())
        }
        errorReader.start()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        while !errorBox.isSet { Thread.sleep(forTimeInterval: 0.001) }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorBox.get(), as: UTF8.self)
            throw RunError(description: "oracle.tcl --repo \(fixture) failed (\(process.terminationStatus)): \(message)")
        }
        return try JSONDecoder().decode(OracleResult.self, from: output)
    }
}

/// A one-shot hand-off of `Data` between two threads.
private final class DataBox: @unchecked Sendable {
    // Safe: every access to `data` is under `lock`.
    private let lock = NSLock()
    private var data: Data?

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return data != nil
    }

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data ?? Data()
    }
}
