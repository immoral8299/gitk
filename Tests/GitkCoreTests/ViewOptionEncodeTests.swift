// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct ViewOptionEncodeTests {
    @Test func tableOrderAndShape() {
        let ids = ViewOptions.known.map(\.id)
        #expect(ids.count == 31)
        #expect(ids.first == "perm")
        #expect(ids.last == "cmd")
        #expect(ViewOptions.known.first { $0.id == "refs" }?.title == "Branches & tags:")
        #expect(ViewOptions.known.first { $0.id == "pickaxe_t" }?.radioGroup == "pickaxe_")
        #expect(ViewOptions.known.first { $0.id == "since" }?.patterns == ["--since=*", "--after=*"])
        #expect(ViewOptions.known.first { $0.id == "cmd" }?.kind == .textStacked(width: 50))
        #expect(ViewOptions.known.first { $0.id == "dorder" }?.layout == .newRowIndentedExpanding)
    }

    @Test func authorAndSince() throws {
        let v = ViewOptionValues(values: [
            "author": .text("alice"), "since": .text("2026-03-01"),
        ])
        #expect(try ViewOptionCodec.encode(v) == ["--author=alice", "--since=2026-03-01"])
    }

    @Test func pickaxeRegexp() throws {
        let v = ViewOptionValues(values: [
            "pickaxe": .text("foo.*bar"), "pickaxe_": .radio(1),
        ])
        let args = try ViewOptionCodec.encode(v)
        // gitk's table order puts the radio before the search string.
        #expect(args == ["--pickaxe-regex", "-Sfoo.*bar"])
        #expect(Set(args) == ["-Sfoo.*bar", "--pickaxe-regex"])
    }

    @Test func pickaxeFixedHasNoRegexFlag() throws {
        let v = ViewOptionValues(values: ["pickaxe": .text("foo"), "pickaxe_": .radio(0)])
        #expect(try ViewOptionCodec.encode(v) == ["-Sfoo"])
    }

    @Test func checkboxesAndTrim() throws {
        let v = ViewOptionValues(values: [
            "allrefs": .bool(true), "dorder": .bool(true), "tags": .bool(false),
            "limit": .text("  20 "), "skip": .text("  "),
        ])
        #expect(try ViewOptionCodec.encode(v) == ["--all", "--max-count=20", "--date-order"])
    }

    @Test func refsAndArgsAppendedLast() throws {
        let v = ViewOptionValues(values: [
            "refs": .text("main \"my tag\""), "args": .text("--no-merges"),
            "author": .text("bob"),
        ])
        #expect(try ViewOptionCodec.encode(v)
            == ["--author=bob", "main", "my tag", "--no-merges"])
    }

    @Test func permAndCmdAreNotEncoded() throws {
        let v = ViewOptionValues(values: ["perm": .bool(true), "cmd": .text("echo x")])
        #expect(try ViewOptionCodec.encode(v).isEmpty)
    }

    @Test func quotingErrorIsReported() {
        let v = ViewOptionValues(values: ["args": .text("'oops")])
        #expect(throws: ViewArgsError.self) { try ViewOptionCodec.encode(v) }
    }
}
