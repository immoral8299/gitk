// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import PoConvert

@Suite struct PoParserTests {
    static let deSnippet = """
    # Translation of gitk to German.
    msgid ""
    msgstr ""
    "Project-Id-Version: Gitk\\n"
    "Content-Type: text/plain; charset=UTF-8\\n"
    "Content-Transfer-Encoding: 8bit\\n"

    msgid "Couldn't get list of unmerged files:"
    msgstr "Liste der nicht zusammengeführten Dateien nicht gefunden:"

    msgid "No files selected: --merge specified but no files are unmerged."
    msgstr ""
    "Keine Dateien ausgewählt: Es wurde --merge angegeben, aber es existieren "
    "keine nicht zusammengeführten Dateien."

    #, tcl-format
    msgid "Reset branch %s to %s?"
    msgstr "Zweig »%s« auf »%s« zurücksetzen?"

    msgid "&File"
    msgstr "&Datei"
    """

    @Test func headerCharsetAndEntries() throws {
        let c = try PoParser.parse(Self.deSnippet)
        #expect(c.charset == "UTF-8")
        #expect(c.header.contains("Project-Id-Version: Gitk"))
        #expect(c.entries.count == 4)
        #expect(c.entries[0].id == "Couldn't get list of unmerged files:")
        #expect(c.entries[0].string == "Liste der nicht zusammengeführten Dateien nicht gefunden:")
        #expect(c.entries[3].id == "&File")
        #expect(c.entries[3].string == "&Datei")
    }

    @Test func multilineConcatenation() throws {
        let c = try PoParser.parse(Self.deSnippet)
        #expect(c.entries[1].string
                == "Keine Dateien ausgewählt: Es wurde --merge angegeben, aber es existieren keine nicht zusammengeführten Dateien.")
    }

    @Test func flagsAreAttachedToNextEntry() throws {
        let c = try PoParser.parse(Self.deSnippet)
        #expect(c.entries[2].flags == ["tcl-format"])
        #expect(c.entries[2].isFuzzy == false)
        #expect(c.entries[3].flags.isEmpty)
    }

    @Test func fuzzyFlagAmongOthers() throws {
        let c = try PoParser.parse("""
        #, fuzzy, tcl-format
        msgid "Reset %s"
        msgstr "Zurück %s"
        """)
        #expect(c.entries.count == 1)
        #expect(c.entries[0].isFuzzy)
        #expect(c.entries[0].flags == ["fuzzy", "tcl-format"])
    }

    @Test func msgctxtAndPlural() throws {
        let c = try PoParser.parse("""
        msgctxt "menu"
        msgid "File"
        msgstr "Datei"

        msgid "one file"
        msgid_plural "%d files"
        msgstr[0] "eine Datei"
        msgstr[1] "%d Dateien"
        """)
        #expect(c.entries.count == 2)
        #expect(c.entries[0].context == "menu")
        #expect(c.entries[0].id == "File")
        #expect(c.entries[1].context == nil)
        #expect(c.entries[1].idPlural == "%d files")
        #expect(c.entries[1].strings == ["eine Datei", "%d Dateien"])
    }

    @Test func escapes() throws {
        let c = try PoParser.parse(#"""
        msgid "a\tb\n\"q\" \\ \303\244 \x41"
        msgstr "x"
        """#)
        #expect(c.entries[0].id == "a\tb\n\"q\" \\ \u{E4} A")
    }

    @Test func obsoleteEntriesSkipped() throws {
        let c = try PoParser.parse("""
        msgid "Keep"
        msgstr "Behalten"

        #, fuzzy
        #~ msgid "Gone"
        #~ msgstr "Weg"

        msgid "Also"
        msgstr "Auch"
        """)
        #expect(c.entries.map(\.id) == ["Keep", "Also"])
        #expect(c.entries.allSatisfy { !$0.isFuzzy })
    }

    @Test func entriesWithoutBlankLinesAreSeparated() throws {
        let c = try PoParser.parse("""
        msgid "A"
        msgstr "a"
        msgid "B"
        msgstr "b"
        """)
        #expect(c.entries.map(\.id) == ["A", "B"])
    }

    @Test func parseErrorsAreReported() {
        #expect(throws: PoParseError.self) { try PoParser.parse("msgid A\n") }
    }

    @Test func parsesAllShippedCatalogs() throws {
        let po = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("po")
        let files = try FileManager.default.contentsOfDirectory(atPath: po.path).filter { $0.hasSuffix(".po") }
        #expect(files.count == 16)
        for f in files {
            let c = try PoParser.parse(data: Data(contentsOf: po.appendingPathComponent(f)))
            #expect(c.charset.uppercased() == "UTF-8", "\(f)")
            #expect(c.entries.count > 100, "\(f)")
        }
    }
}
