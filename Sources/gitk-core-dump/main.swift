// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import GitkCore

var arguments = Array(CommandLine.arguments.dropFirst())
var repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if arguments.first == "--repo" {
    guard arguments.count >= 2 else {
        FileHandle.standardError.write(Data("usage: gitk-core-dump --repo <directory> [revision arguments]\n".utf8))
        exit(1)
    }
    repository = URL(fileURLWithPath: arguments[1])
    arguments.removeFirst(2)
}
do {
    let data = try await CoreDump.run(repoURL: repository, args: arguments)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
