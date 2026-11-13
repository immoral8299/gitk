// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A command line gitk refuses to start with.
public enum LaunchArgumentsError: Error, Sendable, Equatable {
    /// An argument that is both a revision and an existing file.
    case ambiguousArgument(String)
    /// `git rev-parse` rejected the arguments; the payload is git's message with
    /// everything up to and including "fatal:" removed.
    case badArguments(String)

    /// gitk's English message id (the localization key), with `%s` placeholders.
    public var msgid: String {
        switch self {
        case .ambiguousArgument: return "Ambiguous argument '%s': both revision and filename"
        case .badArguments: return "Bad arguments to gitk:"
        }
    }

    /// The `%s` arguments for `msgid`, in order.
    public var arguments: [String] {
        switch self {
        case .ambiguousArgument(let arg): return [arg]
        case .badArguments: return []
        }
    }

    /// Text that follows the (localized) message, separated by a newline; "" if none.
    public var detail: String {
        switch self {
        case .ambiguousArgument: return ""
        case .badArguments(let err): return err
        }
    }
}

/// The parsed gitk command line.
public struct LaunchArguments: Sendable, Equatable {
    /// gitk's `revtreeargs`.
    public var revisionArgs: [String] = []
    /// gitk's `cmdline_files`.
    public var paths: [String] = []
    /// gitk's `selecthead`; nil for none or for `HEAD`.
    public var selectCommit: String?
    /// gitk's `revtreeargscmd`; nil when not given.
    public var argsCmd: String?

    public init(
        revisionArgs: [String] = [], paths: [String] = [],
        selectCommit: String? = nil, argsCmd: String? = nil
    ) {
        self.revisionArgs = revisionArgs
        self.paths = paths
        self.selectCommit = selectCommit
        self.argsCmd = argsCmd
    }

    /// Port of the argument handling in gitk/gitk 12836–12895.
    ///
    /// Deviation: gitk only strips git's message when "fatal:" is found at an
    /// index greater than 0, which never happens for git's usual "fatal: ..." text.
    /// The cli-launch spec ("Bad revision") says the text up to and including
    /// `fatal:` is removed, so it is stripped when found at any index.
    /// - Parameters:
    ///   - repo: the working directory; also where `[file exists $arg]` is evaluated.
    ///   - runner: replaces the real git runner (tests).
    public static func parse(
        argv: [String], repo: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: (any GitRunning)? = nil
    ) async throws -> LaunchArguments {
        var result = LaunchArguments()
        var selectHead = ""
        var argsCmd = ""
        var sawDashDash = false

        for (i, arg) in argv.enumerated() {
            if arg.isEmpty {
                continue
            } else if arg == "--" {
                result.paths = Array(argv[(i + 1)...])
                sawDashDash = true
                break
            } else if arg.hasPrefix("--select-commit=") {
                selectHead = String(arg.dropFirst(16))
            } else if arg.hasPrefix("--argscmd=") {
                argsCmd = String(arg.dropFirst(10))
            } else {
                result.revisionArgs.append(arg)
            }
        }

        if selectHead == "HEAD" { selectHead = "" }
        result.selectCommit = selectHead.isEmpty ? nil : selectHead
        result.argsCmd = argsCmd.isEmpty ? nil : argsCmd

        if !sawDashDash && !result.revisionArgs.isEmpty {
            // no -- on command line, but some arguments (other than --argscmd)
            let git: any GitRunning = runner ?? GitRunner(cwd: repo, baseEnvironment: environment)
            let out: GitOutput
            do {
                out = try await git.run(
                    ["rev-parse", "--no-revs", "--no-flags"] + result.revisionArgs,
                    stdin: nil, cwd: nil)
            } catch let e as GitError {
                // Tcl's exec error text is stderr without its trailing newline.
                var err = e.stderr
                if err.hasSuffix("\n") { err.removeLast() }
                if let r = err.range(of: "fatal:") {
                    err = String(err[r.upperBound...])
                }
                throw LaunchArgumentsError.badArguments(err)
            }
            var text = String(decoding: out.stdout, as: UTF8.self)
            if text.hasSuffix("\n") { text.removeLast() }
            result.paths = text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let n = result.paths.count
            result.revisionArgs = Array(result.revisionArgs.prefix(max(0, result.revisionArgs.count - n)))
            // git rev-parse doesn't error when something is both a revision and a
            // filename, so check the remaining revision arguments for files.
            for arg in result.revisionArgs {
                let path = arg.hasPrefix("/") ? arg : repo.appendingPathComponent(arg).path
                if FileManager.default.fileExists(atPath: path) {
                    throw LaunchArgumentsError.ambiguousArgument(arg)
                }
            }
        }
        return result
    }
}
