// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum FileRevision: Sendable, Equatable {
    case commit(ObjectID), index, worktree, absent
}

public struct ExternalDiffFiles: Sendable, Equatable {
    public let oldFile: URL
    public let newFile: URL
    public let directory: URL
}

public enum ExternalDiff {
    /// Port of gitk procs `external_diff` and `external_diff_get_one_file`
    /// (gitk/gitk 3777–3872). Rename paths come from the NUL name-status parser.
    public static func prepare(from: FileRevision, to: FileRevision, path: String,
                               oldPath: String? = nil, worktree: URL?,
                               runner: GitRunner, tempFiles: TempFiles) async throws -> ExternalDiffFiles {
        let directory = try tempFiles.makeDirectory()
        do {
            let oldFile = try await materialize(from, path: oldPath ?? path, label: "old",
                                                directory: directory, worktree: worktree, runner: runner)
            let newFile = try await materialize(to, path: path, label: "new",
                                                directory: directory, worktree: worktree, runner: runner)
            return ExternalDiffFiles(oldFile: oldFile, newFile: newFile, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Runs the viewer without blocking the main actor, preserving shell-style argument quoting.
    /// The app owns the Task so quit can cancel it through ProcessRunner's process group.
    public static func launch(tool: String, files: ExternalDiffFiles,
                              environment: [String: String] = ProcessInfo.processInfo.environment) async throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let args = try ShellWords.split(tool)
        guard let command = args.first else {
            throw GitError(args: [], status: -1, stderr: "command failed:")
        }
        let executable: URL
        if command.contains("/") { executable = URL(fileURLWithPath: command) }
        else {
            let paths = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":")
            guard let found = paths.map({ URL(fileURLWithPath: String($0)).appendingPathComponent(command) })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                throw GitError(args: args, status: -1, stderr: "\(command): command not found")
            }
            executable = found
        }
        let output = try await ProcessRunner().run(executable: executable,
            arguments: Array(args.dropFirst()) + [files.oldFile.path, files.newFile.path],
            environment: GitEnvironment.childEnvironment(from: environment))
        guard output.status == 0 else {
            throw GitError(args: args, status: output.status, stderr: output.stderrText)
        }
    }

    /// Port of gitk proc `save_file_from_commit` (gitk/gitk 3763–3775).
    private static func materialize(_ revision: FileRevision, path: String, label: String,
                                    directory: URL, worktree: URL?, runner: GitRunner) async throws -> URL {
        if revision == .absent { return URL(fileURLWithPath: "/dev/null") }
        if revision == .worktree {
            guard let worktree else { return URL(fileURLWithPath: "/dev/null") }
            let file = worktree.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: file.path) ? file : URL(fileURLWithPath: "/dev/null")
        }
        let object: String
        switch revision {
        case .commit(let id): object = id.hex + ":" + path
        case .index: object = ":" + path
        default: return URL(fileURLWithPath: "/dev/null")
        }
        let data = try await runner.run(["show", object, "--"]).stdout
        let file = directory.appendingPathComponent("[\(label)] \(URL(fileURLWithPath: path).lastPathComponent)")
        try data.write(to: file)
        return file
    }
}
