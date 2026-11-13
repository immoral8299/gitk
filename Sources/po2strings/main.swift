// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import PoConvert

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: po2strings <po-dir> <out-resources-dir>\n".utf8))
    exit(2)
}
do {
    let names = try PoConverter.convertDirectory(
        poDir: URL(fileURLWithPath: args[1], isDirectory: true),
        outDir: URL(fileURLWithPath: args[2], isDirectory: true))
    print("po2strings: wrote \(names.count) catalogs")
} catch {
    FileHandle.standardError.write(Data("po2strings: \(error.localizedDescription)\n".utf8))
    exit(1)
}
