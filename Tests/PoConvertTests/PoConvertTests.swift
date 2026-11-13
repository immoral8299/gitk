// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import PoConvert

@Suite struct PoConvertTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func placeholders() {
        #expect(PoConverter.convertPlaceholders("Reset branch %s to %s?") == "Reset branch %1$@ to %2$@?")
        #expect(PoConverter.convertPlaceholders("%d of %d") == "%1$ld of %2$ld")
        #expect(PoConverter.convertPlaceholders("%2$s before %1$s") == "%2$@ before %1$@")
        #expect(PoConverter.convertPlaceholders("%1$d files") == "%1$ld files")
        #expect(PoConverter.convertPlaceholders("100%% of %s") == "100%% of %1$@")
        #expect(PoConverter.convertPlaceholders("no placeholders") == "no placeholders")
    }

    @Test func mnemonics() {
        #expect(PoConverter.stripMnemonics("&File") == "File")
        #expect(PoConverter.stripMnemonics("Ansicht &bearbeiten ...") == "Ansicht bearbeiten ...")
        #expect(PoConverter.stripMnemonics("Tom && Jerry") == "Tom & Jerry")
    }

    @Test func lprojMapping() {
        #expect(PoConverter.lprojName(forPo: "pt_br") == "pt-BR")
        #expect(PoConverter.lprojName(forPo: "pt_pt") == "pt-PT")
        #expect(PoConverter.lprojName(forPo: "zh_cn") == "zh-Hans")
        #expect(PoConverter.lprojName(forPo: "de") == "de")
        #expect(PoConverter.lprojName(forPo: "FR") == "fr")
    }

    @Test func formattedMessageGermanAndFrench() throws {
        let de = try PoParser.parse("""
        #, tcl-format
        msgid "Reset branch %s to %s?"
        msgstr "Zweig »%s« auf »%s« zurücksetzen?"
        """)
        #expect(PoConverter.pairs(from: de).map { "\($0.key)=\($0.value)" }
                == ["Reset branch %1$@ to %2$@?=Zweig »%1$@« auf »%2$@« zurücksetzen?"])
        // A translator may reorder arguments with explicit positions.
        let swapped = try PoParser.parse("""
        #, tcl-format
        msgid "Reset branch %s to %s?"
        msgstr "Auf %2$s zurücksetzen: %1$s"
        """)
        #expect(PoConverter.pairs(from: swapped)[0].value == "Auf %2$@ zurücksetzen: %1$@")
    }

    @Test func skipsFuzzyEmptyAndNoTclFormat() throws {
        let c = try PoParser.parse("""
        msgid ""
        msgstr "Content-Type: text/plain; charset=UTF-8\\n"

        #, fuzzy
        msgid "Fuzzy one"
        msgstr "Unscharf"

        msgid "Untranslated"
        msgstr ""

        #, no-tcl-format
        msgid "Maximum graph width (% of pane)"
        msgstr "Maximale Breite (% des Bereichs)"

        msgid "&File"
        msgstr "&Datei"
        """)
        let p = PoConverter.pairs(from: c)
        #expect(p.map(\.key) == ["File", "Maximum graph width (% of pane)"])
        #expect(p[1].value == "Maximale Breite (% des Bereichs)")
    }

    @Test func sortedAndEscaped() throws {
        let c = try PoParser.parse(#"""
        msgid "b \"q\""
        msgstr "x\ny\\"

        msgid "a"
        msgstr "tab\there"
        """#)
        #expect(PoConverter.stringsFile(from: c) == """
        "a" = "tab\\there";
        "b \\"q\\"" = "x\\ny\\\\";

        """)
    }

    @Test func convertDirectoryIsDeterministicAndComplete() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("po2strings-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let po = Self.repoRoot.appendingPathComponent("po")
        let names = try PoConverter.convertDirectory(poDir: po, outDir: tmp.appendingPathComponent("a"))
        try PoConverter.convertDirectory(poDir: po, outDir: tmp.appendingPathComponent("b"))
        #expect(names == ["af", "bg", "ca", "de", "es", "fr", "hu", "it", "ja", "pt-BR", "pt-PT",
                          "ru", "sv", "ta", "vi", "zh-Hans"])
        for n in names {
            let x = try Data(contentsOf: tmp.appendingPathComponent("a/\(n).lproj/Localizable.strings"))
            let y = try Data(contentsOf: tmp.appendingPathComponent("b/\(n).lproj/Localizable.strings"))
            #expect(x == y)
            #expect(!x.isEmpty)
        }
        let de = try String(contentsOf: tmp.appendingPathComponent("a/de.lproj/Localizable.strings"),
                            encoding: .utf8)
        #expect(de.contains("\"File\" = \"Datei\";"))
        #expect(de.contains("\"Reset branch %1$@ to %2$@?\" = \"Zweig »%1$@« auf »%2$@« zurücksetzen?\";"))
    }
}
