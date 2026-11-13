// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct ViewOptionDecodeTests {
    @Test func editCommandLineView() {
        let v = ViewOptionCodec.decode(["--author=bob", "-20", "--no-merges"])
        #expect(v.text("author") == "bob")
        #expect(v.text("limit") == "20")
        #expect(v.text("args") == "--no-merges")
        #expect(v.text("refs") == "")
    }

    @Test func defaults() {
        let v = ViewOptionCodec.decode([])
        #expect(v.bool("allrefs") == false)
        #expect(v.radio("pickaxe_") == 0)
        #expect(v.text("since") == "")
        #expect(v.text("args") == "")
    }

    @Test func refsAndFlags() {
        let v = ViewOptionCodec.decode(["main", "--all", "--date-order", "my tag", "--first-parent"])
        #expect(v.text("refs") == "main \"my tag\"")
        #expect(v.bool("allrefs"))
        #expect(v.bool("dorder"))
        #expect(v.bool("first"))
        #expect(v.text("args") == "")
    }

    @Test func alternatePatternsAndShortOption() {
        let v = ViewOptionCodec.decode(["--after=2026-01-01", "--before=2026-02-01", "-d"])
        #expect(v.text("since") == "2026-01-01")
        #expect(v.text("until") == "2026-02-01")
        #expect(v.bool("dorder"))
    }

    @Test func pickaxeRegexp() {
        let v = ViewOptionCodec.decode(["--pickaxe-regex", "-Sfoo.*bar"])
        #expect(v.radio("pickaxe_") == 1)
        #expect(v.text("pickaxe") == "foo.*bar")
    }

    @Test func secondOccurrenceGoesToExtraArgs() {
        let v = ViewOptionCodec.decode(["-5", "-6", "--author=a", "--author=b"])
        #expect(v.text("limit") == "5")
        #expect(v.text("author") == "a")
        #expect(v.text("args") == "-6 --author=b")
    }

    @Test func maxCountThenDashNumber() {
        let v = ViewOptionCodec.decode(["--max-count=3", "-9"])
        #expect(v.text("limit") == "3")
        #expect(v.text("args") == "-9")
    }

    @Test func roundTripFromValues() throws {
        let samples: [ViewOptionValues] = [
            ViewOptionValues(values: ["author": .text("alice"), "since": .text("2026-03-01")]),
            ViewOptionValues(values: ["pickaxe": .text("foo.*bar"), "pickaxe_": .radio(1)]),
            ViewOptionValues(values: [
                "refs": .text("main \"my tag\""), "allrefs": .bool(true), "tags": .bool(true),
                "limit": .text("20"), "skip": .text("5"), "dorder": .bool(true),
                "committer": .text("c d"), "loginfo": .text("fix"), "until": .text("yesterday"),
                "allmatch": .bool(true), "igrep": .bool(true), "lright": .bool(true),
                "first": .bool(true), "smplhst": .bool(true), "remotes": .bool(true),
                "branches": .bool(true), "args": .text("--no-merges --topo-order"),
            ]),
        ]
        for s in samples {
            let a1 = try ViewOptionCodec.encode(s)
            let a2 = try ViewOptionCodec.encode(ViewOptionCodec.decode(a1))
            #expect(a1 == a2)
        }
    }

    @Test func roundTripFromArgs() throws {
        let argsets: [[String]] = [
            ["--author=bob", "-20", "--no-merges"],
            ["--pickaxe-regex", "-Sx", "v1.0", "--", "weird"],
            ["--merge", "-n", "4", "--skip=2"],
        ]
        for a in argsets {
            let e1 = try ViewOptionCodec.encode(ViewOptionCodec.decode(a))
            let e2 = try ViewOptionCodec.encode(ViewOptionCodec.decode(e1))
            #expect(e1 == e2)
        }
    }
}
