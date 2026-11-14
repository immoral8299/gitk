# Tasks

## How to run these tasks

This section is reference material, not tracked work.

Each task is meant to be done by one agent in one session without asking questions. Every task has the same shape:

- **Checkbox line:** `ID [size] summary — Verify: <command or observable check>`.
  - `[S]` is mechanical work, under about 150 lines of Swift (Haiku is fine).
  - `[M]` is a careful port or UI piece, under about 400 lines (Sonnet).
  - `[L]` is algorithm-critical: assign to Sonnet at high effort or keep with the orchestrator. Never give it to Haiku.
- **Files:** the files to create or edit. Paths follow design.md D1; do not invent other layouts.
- **Port:** the gitk Tcl line range to translate, in `gitk/gitk` at commit `6fc42f7`. Read it before writing code.
- **Needs:** task IDs that must be done first. The orchestrator schedules from this dependency graph, and tasks whose Needs are all done can run in parallel.
- **Spec:** the spec scenarios the task satisfies (`<capability>: <scenario>`). Add each one to `docs/spec-coverage.md` together with the test name or snapshot check that proves it.

Every task, in addition to its own Verify, must leave the repo in this state (definition of done):

1. `swift build` passes with no new warnings, and `swift test` passes.
2. New Swift files start with the SPDX header from `docs/agent-guide.md`.
3. Ported functions carry a `/// Port of gitk proc \`name\`` doc comment.
4. User-visible strings go through `L("<exact gitk msgid>")`.
5. One commit per task, with message `gitk-swift: <ID> <summary>`. Stage only that task's files (never `git add -A`), because other agents may be working in the same tree.

Rules for agents:

- Do not change spec files, design.md or other tasks' files beyond what your task says.
- If the Tcl code contradicts the spec, follow the spec and write the discrepancy down in `docs/architecture.md` under "Deviations".

Agents check UI work with snapshots:

```
Tools/snapshot.sh <fixture> /tmp/out.png [args]
```

Then read the PNG and compare it with the description in the task. Set `GITK_SWIFT_HEADLESS_ERRORS=1` to get errors on stderr instead of in dialogs.

Order of work:

- After group 2, groups 3, 4 and 5 can run in parallel.
- Groups 6 and 7 are on the critical path.
- From group 10 onwards, the UI groups 11–18 can run in parallel as their Needs allow.

## 1. Repository scaffolding

- [x] 1.1 [S] Turn `gitk/` into a git submodule of `https://github.com/j6t/gitk` pinned at `6fc42f7` — Verify: `git submodule status` prints a line starting with ` 6fc42f7` and the path `gitk`.
  - Files: `.gitmodules`, `gitk` (gitlink). Remove the nested clone first, then run `git submodule add`.
  - Needs: none.
- [x] 1.2 [S] Add `.gitignore`, a GPLv2 `COPYING` (from gnu.org `gpl-2.0.txt`) and a root `README.md` (purpose, build/test commands, credit to gitk, GPL-2.0-or-later) — Verify: `head -3 COPYING` contains "GNU GENERAL PUBLIC LICENSE" and "Version 2"; `git check-ignore .build` prints `.build`.
  - Files: `.gitignore` (D13 entries), `COPYING`, `README.md`.
  - Needs: none.
- [x] 1.3 [S] Create `Package.swift` and a placeholder source file for every target in design D1 (`GitkCore`, `GitkUI`, `gitk-swift`, `gitk-core-dump`, `po2strings`, `GitkCoreTests`, `GitkUITests`), using Swift 6 language mode, macOS 14 and `defaultLocalization: "en"` — Verify: `swift build` and `swift test` both exit 0.
  - Files: `Package.swift`, `Sources/*/Placeholder.swift` or `main.swift`, `Tests/*/SmokeTests.swift`.
  - Needs: none.
- [x] 1.4 [S] Add `CoreIsolationTests`, which fails if any file under `Sources/GitkCore` contains `import AppKit`, `import SwiftUI` or `import Cocoa` — Verify: `swift test --filter CoreIsolationTests` passes; temporarily adding `import AppKit` to a Core file makes it fail.
  - Files: `Tests/GitkCoreTests/CoreIsolationTests.swift`.
  - Needs: 1.3.
- [x] 1.5 [M] Write `Tests/Fixtures/make-fixture.sh <name> <outdir>`, which builds every fixture named in design D12 except `huge` deterministically (fixed `GIT_AUTHOR_*`/`GIT_COMMITTER_*` names and dates, `GIT_CONFIG_NOSYSTEM=1`, `HOME` set to a temp dir) — Verify: running it twice for each name gives identical `git rev-parse HEAD`; record each name's expected HEAD and commit count in `Tests/Fixtures/README.md`.
  - Files: `Tests/Fixtures/make-fixture.sh`, `Tests/Fixtures/README.md`.
  - Needs: none.
- [x] 1.6 [S] Add the `FixtureRepo.make(_ name:) -> URL` test helper. It runs the script once per process into `$TMPDIR/gitk-swift-fixtures/<name>` and can copy a fixture to a fresh temp dir for tests that change it — Verify: `swift test --filter FixtureRepoTests` checks that the `linear` commit count matches the README.
  - Files: `Tests/GitkCoreTests/Support/FixtureRepo.swift`, `Tests/GitkCoreTests/FixtureRepoTests.swift`.
  - Needs: 1.3, 1.5.
- [x] 1.7 [M] Add a `huge` fixture generator using `git fast-import`: 200,000 commits, with branches and merges every 50 commits — Verify: `Tests/Fixtures/make-fixture.sh huge /tmp/fx` finishes in under 120s and `git -C /tmp/fx/huge rev-list --all --count` prints 200000.
  - Files: `Tests/Fixtures/make-huge.sh`; `make-fixture.sh` calls it for `huge`.
  - Needs: 1.5.
- [x] 1.8 [S] Write `docs/agent-guide.md` with these sections: SPDX header text; naming and file conventions (D1); the "Port of gitk proc" comment rule; a Tcl→Swift idiom table (`lindex`/`lrange` with `end-N`, `lsearch -exact`, `incr` on an unset var, `info exists`, array vs dict, `string range` end-inclusive, `regexp -indices`); how to run tests, fixtures, the oracle and snapshots; the commit message format; the `L()` rule — Verify: all listed headings are in the file (`grep -c '^## ' docs/agent-guide.md` ≥ 7).
  - Files: `docs/agent-guide.md`, `docs/architecture.md` (skeleton with a "Deviations" section), `docs/spec-coverage.md` (a table with one row per spec scenario, all marked "pending").
  - Needs: none.
- [x] 1.9 [S] Add a `Makefile` with `build`, `test`, `release`, `snapshot FIXTURE=… OUT=…` and `clean` targets wrapping `swift` commands — Verify: `make build test` exits 0.
  - Files: `Makefile`.
  - Needs: 1.3.

## 2. Core: processes and repository context

- [x] 2.1 [M] Implement `ObjectID` (D4): inline 32-byte storage, `init?(hex:)` for 40 or 64 hex characters, `hex`, `abbreviated(_ n:)`, the constants `.localUnstaged` and `.localStaged` (gitk `nullid`/`nullid2`, sized to the hash length), `Hashable` and `Comparable` — Verify: `swift test --filter ObjectIDTests` covers valid and invalid lengths, uppercase rejection, round-trip, and the abbreviation lengths.
  - Files: `Sources/GitkCore/Model/ObjectID.swift`, `Tests/GitkCoreTests/ObjectIDTests.swift`.
  - Needs: 1.3.
- [x] 2.2 [M] Implement `ProcessRunner`/`GitRunner.run(args, stdin:, cwd:)`. It returns `GitOutput{stdout, stderr, status}` and throws `GitError` on a non-zero exit. It removes `GIT_TRACE` from the child environment and never uses a shell (D2) — Verify: `swift test --filter GitRunnerTests` checks `git --version` succeeds; `git rev-parse nope` throws with "unknown revision" in stderr; `/usr/bin/env` run with `GIT_TRACE=1` in the parent does not list `GIT_TRACE`.
  - Files: `Sources/GitkCore/Git/GitRunner.swift`, `Sources/GitkCore/Git/GitEnvironment.swift`, tests.
  - Port: 160–245 (`safe_exec*`, `make_arg_safe` — only the argument array semantics apply in Swift).
  - Needs: 1.3.
- [x] 2.3 [M] Implement streaming: `GitProcess` with `records(separator:)` as an `AsyncThrowingStream<Data, Error>`, backed by `RecordSplitter`, plus `cancel()`, which sends SIGTERM to the process group — Verify: `swift test --filter RecordSplitterTests` (records split across chunk boundaries, a trailing record with no separator, empty records) and `GitProcessCancelTests` (cancelling an endless `sh -c 'while :; do printf "a\0"; done'` leaves `isRunning == false` within 1s).
  - Files: `Sources/GitkCore/Git/GitProcess.swift`, `Sources/GitkCore/Git/RecordSplitter.swift`, tests.
  - Port: 283–354 (`run`, `filerun`, `dorunq` — the purpose only; replaced by async streams).
  - Needs: 2.2.
- [x] 2.4 [S] Implement `GitVersion` parsing and comparison, with a minimum of 2.20 — Verify: `swift test --filter GitVersionTests` with inputs `git version 2.54.0 (Apple Git-157)`, `git version 2.19.1`, `git version 2.45.0.windows.1`, `git version 2.20`.
  - Files: `Sources/GitkCore/Git/GitVersion.swift`, tests.
  - Port: 20–34.
  - Needs: 1.3.
- [x] 2.5 [M] Implement `RepoContext.discover(cwd:)`. It finds `gitDir`, `worktree`, `cdup`, `isBare`, `hasWorktree`, `hashAlgorithm` and `hashLength`, `logShowRoot`, `gitEncoding` (logOutputEncoding > commitEncoding > utf-8) and `guiEncoding` — Verify: `swift test --filter RepoContextTests` on `linear`, `sha256` (hashLength 64), a bare clone (`hasWorktree == false`), a subdirectory cwd (`cdup == "../"`), and a non-repository (throws `.notARepository`).
  - Files: `Sources/GitkCore/Git/RepoContext.swift`, tests.
  - Port: 245–283, 12572–12615, 12941–12952.
  - Needs: 2.2, 1.6.
- [x] 2.6 [S] Implement `TextDecoder.decode(_ data: Data, encodingName: String?) -> String`. IANA names map through `CFStringConvertIANACharSetNameToEncoding`. Invalid sequences fall back to decoding each byte as ISO-8859-1 (matching Tcl's tcl8 profile). Unknown names fall back to UTF-8 and report a warning — Verify: `swift test --filter TextDecoderTests` covers UTF-8, Latin-1, Shift-JIS, invalid UTF-8 bytes kept, and an unknown name.
  - Files: `Sources/GitkCore/Parsing/TextDecoder.swift`, tests.
  - Port: 36–55, 12420–12460 (`tcl_encoding`).
  - Needs: 1.3.

## 3. Core: parsers and text utilities

- [x] 3.1 [M] Implement `RawLogParser.parse(record: Data) -> ParsedCommit`. `ParsedCommit` is a `Sendable` struct: id, parents, boundary flag, left/right side mark, tree, author/committer (name+email, epoch, tz offset), encoding, headline, raw message bytes and notes — Verify: `swift test --filter RawLogParserTests` uses real records from `git log -z --pretty=raw --parents --boundary --show-notes` on `merge-simple`, `tags-notes` (notes present), a range `A..B` (boundary `-` prefix) and `--left-right` (`<`/`>`).
  - Files: `Sources/GitkCore/Parsing/RawLogParser.swift`, tests.
  - Port: 1651–1700 (record framing in `getcommitlines`), 1907–1972 (`parsecommit`).
  - Needs: 2.1, 2.6, 1.6.
- [x] 3.2 [S] Implement `CommitStore`: interns `ObjectID` to `CommitIndex` (`Int32`) and holds parallel arrays for the fields from 3.1, decoding text lazily — Verify: `swift test --filter CommitStoreTests` (interning is idempotent; 100k inserts take under 0.5s in release; text is decoded on first access).
  - Files: `Sources/GitkCore/Model/CommitStore.swift`, `Sources/GitkCore/Model/Commit.swift`, tests.
  - Needs: 3.1.
- [x] 3.3 [M] Implement `RefParser`/`RefSet`. It loads `git show-ref -d` and `git symbolic-ref -q HEAD`, peels annotated tags, and classifies refs as heads, remotes, tags or other. It applies `hideremotes` and the `refstohide` globs — Verify: `swift test --filter RefParserTests` on `tags-notes` (annotated tag attached to its commit), detached HEAD (no main head name, main head ID set), and hiding globs.
  - Files: `Sources/GitkCore/Parsing/RefParser.swift`, `Sources/GitkCore/Model/RefSet.swift`, tests.
  - Port: 2014–2128 (`readrefs`, `movehead`, `removehead`), 12518–12530 (`is_other_ref_visible`).
  - Needs: 2.2, 2.1.
- [x] 3.4 [M] Implement `DiffParser`, a streaming line classifier for `diff-tree -p --cc` output. It yields `DiffLine` values (`.fileHeader(old,new,status)`, `.hunkHeader`, `.add`, `.remove`, `.context`, `.combined(markers:[Character])`, `.binary`, `.submodule`, `.other`) and file-section boundaries — Verify: `swift test --filter DiffParserTests` on `merge-simple`, `octopus` (3 marker columns) and `renames` (rename old→new paths).
  - Files: `Sources/GitkCore/Parsing/DiffParser.swift`, tests.
  - Port: 8272–8542 (`makediffhdr`, `parseblobdiffline`).
  - Needs: 1.6.
- [x] 3.5 [M] Implement `WordDiffParser` for `--word-diff=porcelain`, producing token runs (`.same`, `.added`, `.removed`) per line — Verify: `swift test --filter WordDiffParserTests` with a sample containing additions, removals and `~` newlines.
  - Files: `Sources/GitkCore/Parsing/WordDiffParser.swift`, tests.
  - Port: the word-diff branches inside 8328–8542.
  - Needs: 3.4.
- [x] 3.6 [S] Implement `TreeParser` for `git ls-tree -r -z --full-name` and `git diff-tree -r -z --name-status -C` (the Changed Files list) — Verify: `swift test --filter TreeParserTests` on `renames` and `linear`.
  - Files: `Sources/GitkCore/Parsing/TreeParser.swift`, tests.
  - Port: 7832–7900 (`gettree`, `gettreeline`), 8103–8169 (`gettreediffs`, `gettreediffline`).
  - Needs: 1.6.
- [x] 3.7 [S] Implement the `TclList` tokenizer: split a Tcl list string into elements, handling braces, quotes, backslash escapes and nested braces — Verify: `swift test --filter TclListTests` with at least 12 cases, including `{Lucida Grande} 9`, `{"#00ff00" red}`, `a\ b`, `{}`, `{a {b c}}`.
  - Files: `Sources/GitkCore/Parsing/TclList.swift`, tests.
  - Needs: 1.3.
- [x] 3.8 [S] Implement `ShellWords` as ports of `shellquote`, `shellarglist`, `shelldequote` and `shellsplit` — Verify: `swift test --filter ShellWordsTests`, including quoted spaces, single quotes and unterminated quotes (error).
  - Files: `Sources/GitkCore/Find/ShellWords.swift`, tests.
  - Port: 4179–4271.
  - Needs: 1.3.
- [x] 3.9 [M] Implement `TclDateFormat.format(epoch:, tzOffsetSeconds:, format:)` (D10) — Verify: `swift test --filter TclDateFormatTests` checks fixed epochs against the expected strings for `%Y-%m-%d %H:%M:%S`, a `%z` format (the commit's zone is used), `%a %b %e`, and `%%`.
  - Files: `Sources/GitkCore/Util/TclDateFormat.swift`, tests.
  - Port: 12152–12180 (`formatdate`).
  - Needs: 1.3.

## 4. Core: settings model and legacy import

- [x] 4.1 [S] Generate `TkColorTable` (X11/Tk colour name → RGB) from Tk's `xlib/xcolors.c` (tcltk/tk tag `core-9-0-3`). Include the `grayNN`/`greyNN` names. Commit the generator script under `Tools/` — Verify: `swift test --filter TkColorTableTests` checks `gray85`=(217,217,217), `darkgrey`=(169,169,169), `LightSkyBlue`, and that lookup ignores case.
  - Files: `Sources/GitkCore/Settings/TkColorTable.swift`, `Tools/gen-tk-colors.sh`, tests.
  - Needs: 1.3.
- [x] 4.2 [S] Implement `TkColor.parse(_:) -> RGBA?` for `#rgb`, `#rrggbb`, `#rrrrggggbbbb` and names — Verify: `swift test --filter TkColorTests`.
  - Files: `Sources/GitkCore/Settings/TkColor.swift`, tests.
  - Needs: 4.1.
- [x] 4.3 [S] Implement `TkFont.parse(_:) -> FontSpec{family, pointSize, bold, italic}` and `format`, using `TclList` — Verify: `swift test --filter TkFontTests` with `{Lucida Grande} 9`, `Monaco 9`, `{sans} 9 bold`, `Helvetica -12` (negative size = pixels, converted to points 1:1).
  - Files: `Sources/GitkCore/Settings/TkFont.swift`, tests.
  - Port: 8829–8873 (`parsefont`, `fontflags`, `fontname`).
  - Needs: 3.7.
- [x] 4.4 [M] Implement the `Settings` `Codable` struct, with one property per supported `config_variables` entry plus `geometry` and `views: [SavedView]`. Defaults are gitk's aqua values, except the fonts (D9) — Verify: `swift test --filter SettingsDefaultsTests` checks every default against a table copied from gitk lines 12616–12730, with the unsupported variables (`theme`, `themeloader`, `uicolor`, `uifgcolor`, `uifgdisabledcolor`) listed as excluded.
  - Files: `Sources/GitkCore/Settings/Settings.swift`, tests.
  - Port: 12616–12810.
  - Needs: 4.2, 4.3.
- [x] 4.5 [S] Implement `SettingsStore.load()`/`save()` as JSON in `~/Library/Application Support/gitk-swift/` (overridable with `GITK_SWIFT_CONFIG_DIR`), with atomic writes. A corrupt file gives defaults plus a warning, and the bad file is not overwritten until the first change — Verify: `swift test --filter SettingsStoreTests` (round-trip, corrupt file, override dir).
  - Files: `Sources/GitkCore/Settings/SettingsStore.swift`, tests.
  - Needs: 4.4.
- [x] 4.6 [M] Implement `LegacyConfigImporter`. It finds the file (`$XDG_CONFIG_HOME/git/gitk` > `~/.config/git/gitk` > `~/.gitk`), splits it into commands, imports `set var value`, `set geometry(k) v` and `set permviews {…}`, and ignores anything else without evaluating it — Verify: `swift test --filter LegacyConfigImporterTests` with a sample config containing fonts, colours, two permviews, a `proc` line (skipped) and an `exec` line (skipped); the source file's bytes and mtime are unchanged afterwards.
  - Files: `Sources/GitkCore/Settings/LegacyConfigImporter.swift`, `Tests/GitkCoreTests/Resources/sample-gitk-config`, tests.
  - Port: 12733–12746 (lookup), 3024–3120 (`savestuff`, for the file format).
  - Needs: 4.4, 3.7.

## 5. Differential-test oracle (Tcl)

- [x] 5.1 [L] Spike: write `Tests/Oracle/oracle.tcl` so it loads every `proc` from `gitk/gitk` under plain `tclsh`, splitting top-level commands with `info complete` and evaluating only those starting with `proc `. It must stub UI procs and initialize the globals listed in the agent guide — Verify: `tclsh Tests/Oracle/oracle.tcl --selftest` prints `ok` and the number of procs loaded (≥ 420).
  - Files: `Tests/Oracle/oracle.tcl`, `Tests/Oracle/README.md` (stub list and the reason for each stub).
  - Needs: 1.1.
- [x] 5.2 [L] Make the oracle load and order commits: `--repo <dir> [args]` runs `git log` as `start_rev_list` does (blocking), feeds the output through `getcommitlines` until EOF, and prints JSON `{order:[ids…], varcs:{…}}`, where `varcs` dumps `varcstart`, `varccommits`, `varctok`, `vupptr`, `vdownptr`, `vleftptr`, `vbackptr` and `varcrow` — Verify: on `linear` and `merge-simple`, `order` contains exactly the `git rev-list --all` IDs and every parent comes after its children.
  - Files: `Tests/Oracle/oracle.tcl`.
  - Port: 587–672, 1651–1884.
  - Needs: 5.1, 1.5.
- [x] 5.3 [M] Make the oracle lay out and colour rows: drive `layoutmore` (with `drawcommits` and `drawvisible` stubbed) until every row is laid out, then add `rows:[{id,col,idlist}]`, `ranges:{id:[…]}` and `colors:{id:n}` (calling `assigncolor` for each id in row order) — Verify: on `linear` every `col` is 0; on `merge-simple` the merge's second parent line is in column 1.
  - Files: `Tests/Oracle/oracle.tcl`.
  - Port: 5373–5443, 6668–6731.
  - Needs: 5.2.
- [x] 5.4 [S] Write `Tools/regen-golden.sh`, which runs the oracle on every fixture (not `huge`) and writes `Tests/GitkCoreTests/Golden/<fixture>.json` — Verify: running it twice gives no `git diff`.
  - Files: `Tools/regen-golden.sh`, `Tests/GitkCoreTests/Golden/*.json`.
  - Needs: 5.3.
- [x] 5.5 [S] Add the Swift `OracleGolden.load(_ fixture:) -> OracleResult` (`Decodable`) helper, and an `OracleRunner` that uses live `tclsh` when it is present and the golden file otherwise — Verify: `swift test --filter OracleGoldenTests` decodes all golden files.
  - Files: `Tests/GitkCoreTests/Support/Oracle.swift`, tests.
  - Needs: 5.4.

- [x] 5.6 [M] Make the oracle's results match how gitk actually draws. (a) Add a seeded `random-dag` fixture to `make-fixture.sh`: 1,500 commits, `--all`, about 40% with extra parents up to 80 commits back, built with `git fast-import`, deterministic. Add its README row. (b) Assign colours the way gitk does, during drawing: let the drawing procs `drawcmitrow`, `drawlineseg` and `drawparentlinks` run with only their canvas calls stubbed, so `assigncolor` happens in gitk's order. Do not assign in row order afterwards. (c) Regenerate the goldens, including `random-dag` (chunked 50/50) — Verify: `Tools/regen-golden.sh` run twice leaves no diff; `ORACLE_TRACE_LAYOUT=1` on `random-dag` shows the chunked `layoutrows` calls; `swift test --filter OracleGoldenTests` passes.
  - Files: `Tests/Fixtures/make-fixture.sh`, `Tests/Fixtures/README.md`, `Tests/Oracle/oracle.tcl`, `Tests/Oracle/README.md`, `Tests/GitkCoreTests/Golden/*.json`.
  - Port: 6309–6459 (`drawlines`, `drawcmittext`, `drawcmitrow`), 6074–6309.
  - Needs: 5.5.
  - Why: on random graphs gitk's columns depend on the chunks it lays out while drawing (see `Tests/Oracle/README.md`, "Layout modes"), and its colours depend on drawing order. The fixtures shipped so far don't show either effect.

## 6. Core: display ordering (port of gitk "varc")

- [x] 6.1 [L] Port `varcinit`, `resetvarcs`, `seeds` and `newvarc` into `VarcOrdering`, keeping gitk's state names as Swift properties — Verify: `swift test --filter VarcOrderingInitTests` (unit tests on hand-built 5-commit graphs) passes.
  - Files: `Sources/GitkCore/History/VarcOrdering.swift`, tests.
  - Port: 872–1001.
  - Needs: 3.2.
- [x] 6.2 [L] Port `splitvarc`, `renumbervarc` and `fix_reversal` — Verify: `swift test --filter VarcOrderingSplitTests` covers a child arriving after its parent, using hand-built graphs.
  - Files: `VarcOrdering.swift`, tests.
  - Port: 1001–1185.
  - Needs: 6.1.
- [x] 6.3 [M] Port `insertrow`, `insertfakerow`, `removefakerow`, `real_children`, `first_real_child` and `last_real_child` — Verify: `swift test --filter VarcOrderingInsertTests` (insert a fake row under HEAD, then remove it, and the order is restored).
  - Files: `VarcOrdering.swift`, tests.
  - Port: 1185–1324.
  - Needs: 6.2.
- [x] 6.4 [M] Port `vtokcmp`, `modify_arc`, `update_arcrows`, `commitinview`, `rowofcommit`, `comes_before`, `bsearch`, `make_disporder`, `commitonrow`, `closevarcs` and `rewrite_commit` — Verify: `swift test --filter VarcOrderingRowTests` (`rowofcommit` and `commitonrow` are inverses on a 50-commit graph).
  - Files: `VarcOrdering.swift`, tests.
  - Port: 1324–1623.
  - Needs: 6.3.
- [x] 6.5 [M] Port the graph-building half of `getcommitlines` as `VarcOrdering.add(_ commit: ParsedCommit)`, plus `chewcommits`; I/O is not part of this — Verify: `swift test --filter OrderingParityTests`, where the display order and the `varcs` dump equal `OracleRunner` output for every fixture.
  - Files: `VarcOrdering.swift`, `Tests/GitkCoreTests/OrderingParityTests.swift`.
  - Port: 1700–1884.
  - Needs: 6.4, 5.5.
  - Spec: history-loading "Parents below children", "Late-arriving child".

## 7. Core: graph layout and geometry

- [x] 7.1 [M] Port `ordertoken`, `idcol`, `initlayout`, `setcanvscroll` (the logic only), `nextuse` and `prevuse` into `GraphLayout` — Verify: `swift test --filter GraphLayoutBasicsTests`.
  - Files: `Sources/GitkCore/Graph/GraphLayout.swift`, tests.
  - Port: 5306–5404, 5604–5638.
  - Needs: 6.5.
- [x] 7.2 [L] Port `make_idlist`, `rowsequal`, `makeupline` and `layoutrows` — Verify: `swift test --filter LayoutRowsParityTests` (the `idlist` of each row equals the oracle for `linear`, `merge-simple`, `octopus`).
  - Files: `GraphLayout.swift`, tests.
  - Port: 5638–5840.
  - Needs: 7.1.
- [x] 7.3 [L] Port `changedrow`, `insert_pad` and `optimize_rows` — Verify: `swift test --filter LayoutParityTests` (every row's `idlist` and `col` equal the oracle for all fixtures, including `criss-cross`, `many-branches`, `long-lines`).
  - Files: `GraphLayout.swift`, tests.
  - Port: 5840–5998.
  - Needs: 7.2.
  - Spec: commit-graph "Matches gitk on reference repositories", "Linear history".
- [x] 7.4 [M] Port `rowranges`, plus the row-range arithmetic of `drawcommits`/`drawvisible` (6459–6612). Implement the lazy `ensureLaid(visibleRows:)` (D3) so it calls `layoutrows`/`optimize_rows` with exactly the ranges gitk uses for that viewport. Layout results depend on these chunks (see 5.6) — Verify: `swift test --filter RowRangesParityTests`, where `ranges` and rows equal the oracle on every fixture, including `random-dag`, when the test scrolls a 50-row viewport down in 50-row steps like the oracle's default; plus a test that laying out only the first viewport of `many-branches` does not touch later rows.
  - Files: `GraphLayout.swift`, tests.
  - Port: 5423–5443, 6018–6074, 6459–6612.
  - Needs: 7.3, 5.6.
- [x] 7.5 [M] Port `findcrossings` and `assigncolor` as `GraphColors`, assigning colours in gitk's drawing order (the order `drawcmitrow`/`drawlineseg`/`drawparentlinks` would call it for each drawn viewport, see 5.6) — Verify: `swift test --filter ColorParityTests` (equal to the oracle `colors` for all fixtures).
  - Files: `Sources/GitkCore/Graph/GraphColors.swift`, tests.
  - Port: 6633–6731.
  - Needs: 7.4.
  - Spec: commit-graph "Straight branch keeps colour".
- [x] 7.6 [M] Implement `GraphRowGeometry.make(row:)`, which gives line segments (from/to column and top/mid/bottom), the dot column and style (normal, boundary, main head, unstaged, staged), arrows, and `textX` capped by `maxwidth` and `maxgraphpct` (pass in the column width) — Verify: `swift test --filter GraphRowGeometryTests` on `linear`, `merge-simple`, `long-lines` (arrow rows where the oracle `ranges` say), and `many-branches` (textX capped at 16 lanes).
  - Files: `Sources/GitkCore/Graph/GraphRowGeometry.swift`, tests.
  - Port: 5998–6018 (`xc`, `yc`, `linewidth`), 6074–6309 (`drawlineseg`, `drawparentlinks`), 6315–6417 (`drawcmittext` positioning only), 6740–6753.
  - Needs: 7.5.
  - Spec: commit-graph "Distant parent", "Very wide graph", "HEAD marker", "Local-changes markers".
- [x] 7.7 [S] Add ref labels to the geometry: ordered label list (tags, then heads, then other refs), "n tags..." collapse when there are more than 3 tags or they do not fit (width via an injected measuring closure), `remotes/<x>/` prefix split, current branch bold, notes marker flag — Verify: `swift test --filter RefLabelLayoutTests`.
  - Files: `Sources/GitkCore/Graph/GraphRowGeometry.swift` (extension), tests.
  - Port: 6753–6881 (`drawtags`, `drawnotesign`).
  - Needs: 7.6, 3.3.
  - Spec: commit-graph "Current branch label", "Remote label", "Many tags on one commit".

## 8. Core: launch, views and history loading

- [x] 8.1 [M] Implement `LaunchArguments.parse(argv:, repo:)`: split out `--select-commit=` and `--argscmd=`, treat `--` as the start of paths, skip empty arguments, use `git rev-parse --no-revs --no-flags` to find trailing paths, detect ambiguous arguments, and clean up the "Bad arguments" text — Verify: `swift test --filter LaunchArgumentsTests` covers every cli-launch scenario that does not need the UI.
  - Files: `Sources/GitkCore/CLI/LaunchArguments.swift`, tests.
  - Port: 12836–12895.
  - Needs: 2.5.
  - Spec: cli-launch "Revision range and paths", "Bare path argument", "Ambiguous argument", "Bad revision", "HEAD as select-commit".
- [x] 8.2 [S] Implement `StartupChecks.run() throws -> StartupContext`, which performs the git version, repository and hash algorithm checks in gitk's order and throws typed errors carrying gitk's exact messages — Verify: `swift test --filter StartupChecksTests` (not a repository, an unknown hash algorithm via a stubbed runner, and git too old via a stubbed runner).
  - Files: `Sources/GitkCore/CLI/StartupChecks.swift`, tests.
  - Port: 20–34, 12601–12610, 12828–12831.
  - Needs: 2.4, 2.5.
  - Spec: cli-launch "Git too old", "Not a repository", "Unknown hash algorithm", "SHA-256 repository".
- [x] 8.3 [M] Implement `ViewSpec` (name, args, files, argscmd, perm) and ports of `parseviewargs` and `parseviewrevs`, including running argscmd with `sh -c` and the `--merge` handling via `unmerged_files` — Verify: `swift test --filter ViewSpecTests` (`--merge` on the `conflict` fixture gives the unmerged files; both "No files selected" messages; argscmd output lines are appended).
  - Files: `Sources/GitkCore/Model/ViewSpec.swift`, tests.
  - Port: 363–587.
  - Needs: 2.2, 1.6.
  - Spec: cli-launch "Args command"; views "Merge in progress".
- [x] 8.4 [M] Implement `HistoryLoader`: build the `git log` command and stdin exactly as `start_rev_list` does, stream it, parse it off the main actor, and send batches (2,000 commits or 50ms) tagged with a generation number. `cancel()` kills the process — Verify: `swift test --filter HistoryLoaderTests` (`merge-simple` yields every commit; cancelling halfway on `huge` leaves no running child and no further batches).
  - Files: `Sources/GitkCore/History/HistoryLoader.swift`, tests.
  - Port: 587–720.
  - Needs: 8.3, 3.1, 2.3.
  - Spec: history-loading "Switch view mid-load", "git log fails".
- [x] 8.5 [M] Implement `@MainActor ViewSession`: owns the store, ordering, layout, colours and refs; `ingest(batch:)`; publishes `rowsChanged(range)`, `refsChanged`, `loadProgress`, `loadFinished`; exposes `rowCount`, `commit(at:)`, `geometry(row:)` and `row(of:)` — Verify: `swift test --filter ViewSessionTests` (loading `merge-simple` gives the same order as the oracle; events arrive in the order started → progress → finished).
  - Files: `Sources/GitkCore/History/ViewSession.swift`, tests.
  - Needs: 8.4, 7.7.
- [x] 8.6 [M] Port local changes into `LocalChanges`: run `diff-index --cached --ignore-submodules=dirty HEAD` and then `diff-files` (both with path limits), and insert or remove the fake rows through `VarcOrdering` — Verify: `swift test --filter LocalChangesTests` on copies of `local-changes` (staged+unstaged gives the unstaged, staged, HEAD order; after committing everything both rows are gone; a path limit outside the changes gives no rows; a bare repository gives no rows).
  - Files: `Sources/GitkCore/History/LocalChanges.swift`, tests.
  - Port: 5483–5604.
  - Needs: 8.5.
  - Spec: history-loading "Staged and unstaged changes", "Changes resolved", "Path-limited view".
- [x] 8.7 [M] Port `updatecommits`, `reloadcommits` and `rereadrefs`/`changedrefs` into `ViewSession` — Verify: `swift test --filter UpdateReloadTests` (on a temp copy of `linear`: add a commit, call `update()`, the new row is at the top and the selected ID is kept; force-move a branch, call `reload()`, the unreachable commits are gone).
  - Files: `ViewSession.swift`, tests.
  - Port: 720–860, 11454–11538.
  - Needs: 8.6.
  - Spec: history-loading "New commit then Update", "Reload after a ref moved away".
- [x] 8.8 [S] Implement the `gitk-core-dump` executable, which prints oracle-schema JSON for `--repo <dir> [args]` using `ViewSession`, and the end-to-end `CoreDumpParityTests` — Verify: `swift run gitk-core-dump --repo <fixture>` output equals the golden file for every fixture.
  - Files: `Sources/gitk-core-dump/main.swift`, tests.
  - Needs: 8.5.
- [x] 8.9 [M] Add a performance test, enabled by `GITK_PERF=1`, on `huge`: first 100 rows laid out in under 1.5s, full load in under 10s, resident memory under 1.5GB (`task_info`) — Verify: `GITK_PERF=1 swift test -c release --filter PerfTests` passes; record the timings in `docs/architecture.md`.
  - Files: `Tests/GitkCoreTests/PerfTests.swift`.
  - Needs: 8.5, 1.7.
  - Spec: history-loading "Large repository".
- [x] 8.10 [M] Add `RawLogParser`/`ViewSession` support for encodings, as gitk does it: `git log --pretty=raw` re-encodes messages to `i18n.logOutputEncoding` (default UTF-8) and drops the `encoding` header, so do not pass `--encoding`; decode the stream with the repository's `gitEncoding` (`RepoContext`), and use a commit's `encoding` header only if one is present — Verify: `swift test --filter EncodingTests` on `encodings` (the Latin-1 author name decodes correctly).
  - Files: `RawLogParser.swift`, `CommitStore.swift`, tests.
  - Needs: 8.5.
  - Spec: history-loading "Non-UTF-8 commit", "Unsupported encoding".

## 9. App shell

- [x] 9.1 [S] Add `AppCommand` (an enum of every menu, key, button and context command in the specs) and `KeyBindings` (key descriptor → command, from gitk 2592–2850 and `keys` 3223–3293, with ⌘ in place of Ctrl) to Core — Verify: `swift test --filter KeyBindingsTests` asserts each binding in the commit-list, diff-viewer and commit-find specs.
  - Files: `Sources/GitkCore/Util/AppCommand.swift`, `Sources/GitkCore/Util/KeyBindings.swift`, tests.
  - Needs: 1.3.
- [x] 9.2 [M] Implement `main.swift` and `AppDelegate`: run `LanguageOverride` (a stub for now), `StartupChecks` and `LaunchArguments`; on failure show an alert (or print to stderr with `GITK_SWIFT_HEADLESS_ERRORS=1`) and exit 1; on success set the `.regular` activation policy, activate, and open the main window — Verify: `GITK_SWIFT_HEADLESS_ERRORS=1 swift run gitk-swift` run in `/tmp` exits 1 and prints "Cannot find a git repository here."
  - Files: `Sources/gitk-swift/main.swift`, `Sources/GitkUI/App/AppDelegate.swift`, `Sources/GitkUI/App/Alerts.swift`.
  - Needs: 8.1, 8.2.
  - Spec: cli-launch "Launch from terminal".
- [x] 9.3 [S] Implement `L()` in `L10n.swift` (`Bundle.module` lookup; returns the English key until group 19) and the `Alerts` helpers `showError`, `errorPopup` and `confirmPopup`, which honour the headless env vars (D12) — Verify: `swift test --filter AlertsTests` (headless confirm reads `GITK_SWIFT_CONFIRM`).
  - Files: `Sources/GitkUI/App/L10n.swift`, `Alerts.swift`, `Tests/GitkUITests/AlertsTests.swift`.
  - Needs: 1.3.
- [x] 9.4 [M] Implement `Snapshot` (D12): when `GITK_SWIFT_SNAPSHOT` is set, wait for `loadFinished` and the selection to be displayed, render the window with `cacheDisplay`, write the PNG and exit 0; also write `Tools/snapshot.sh` — Verify: `Tools/snapshot.sh linear /tmp/s.png` creates a non-empty PNG of the requested size.
  - Files: `Sources/GitkUI/App/Snapshot.swift`, `Tools/snapshot.sh`.
  - Needs: 9.2.
- [x] 9.5 [M] Implement `MainWindowController` and `MainSplitView` with the Zed-inspired layout (D16): a search-strip slot in the unified titlebar on systems that support it (otherwise the same slot as the first content row; task 14.4 fills it), a vertical split with the history list on top and the diff pane below at half height, a full-height details sidebar on the right, and a slim status strip at the bottom. Remove the Commit ID bar, the "Find"/"Show" labels and the text arrow buttons beside the traffic lights. Add View → Details Sidebar and the sidebar's close button. Default sizes follow gitk 2453–2462 where they still apply — Verify: snapshots of `linear` at 1400×900 and 700×900 show the list, the sidebar and the empty diff pane, with the sidebar collapsed at the narrow size.
  - Files: `Sources/GitkUI/Main/MainWindowController.swift`, `MainSplitView.swift`, `Sources/GitkUI/Style/Chrome.swift`.
  - Port: 2374–2913 (structure only, relocated).
  - Needs: 9.4.
  - Spec: commit-list "Window layout", "Narrow window".
- [x] 9.6 [M] Implement `MainMenu` with the app menu (About, Settings…, Quit), File, Edit, View and Help menus with every item and shortcut from gitk 2398–2442, plus View → Details Sidebar (a checkable item that shows or hides the sidebar), all sending `AppCommand` through `perform(_:)` — Verify: `swift test --filter MainMenuTests` compares the menu tree with an expected table (titles, key equivalents, enabled and checked state).
  - Files: `Sources/GitkUI/App/MainMenu.swift`, tests.
  - Needs: 9.1, 9.5.
- [x] 9.7 [M] Implement `KeyRouter`: an `NSWindow.sendEvent` hook that maps unmodified keys through `KeyBindings` only when the first responder is not an editable text view or field — Verify: `swift test --filter KeyRouterTests` (an offscreen window with a field: `j` with focus in the field is not routed; `j` with focus on the table is routed to `.selectNext`).
  - Files: `Sources/GitkUI/Main/KeyRouter.swift`, tests.
  - Needs: 9.1, 9.5.
  - Spec: commit-list "Letter keys inside a field".
- [ ] 9.8 [S] Implement quit and close: ⌘-Q and File→Quit stop loaders, save settings and remove temp files; ⌘-W in the main window quits; ⌘-W in other windows closes them — Verify: on `huge` (no snapshot env) with `GITK_SWIFT_QUIT_AFTER_MS=500`, `pgrep -f "git log"` is empty after the process exits.
  - Files: `AppDelegate.swift`, `MainWindowController.swift`.
  - Port: 11610–11623 (`doquit`).
  - Needs: 9.6, 8.4.
  - Spec: preferences "Quit during load".

## 10. Commit list UI

- [x] 10.1 [M] Implement `CommitListController`: an `NSTableView` with 3 resizable columns bound to `ViewSession` (subject, author, date via `TclDateFormat`), a fixed row height from the main font, and incremental row insertion — Verify: a snapshot of `linear` shows subjects, authors and dates; `swift test --filter CommitListDataSourceTests` checks row values.
  - Files: `Sources/GitkUI/CommitList/CommitListController.swift`, tests.
  - Needs: 9.5, 8.5, 3.9.
  - Spec: commit-list "Synchronized scrolling", "Date format with timezone".
- [x] 10.2 [M] Implement `GraphCellView`, which draws `GraphRowGeometry` (segments, dots, arrows, colours, line thickness) and the subject text at `textX` — Verify: snapshots of `merge-simple`, `octopus`, `long-lines` and `local-changes` show the lines, arrows and coloured dots as the spec describes; attach the PNGs to the task report.
  - Files: `Sources/GitkUI/CommitList/GraphCellView.swift`.
  - Needs: 10.1, 7.6.
- [ ] 10.3 [M] Implement `RefLabelDrawing`: draw the labels from the geometry with the head, remote, tag and other colours and a bold current branch; clicking a tag label shows the tag (calls into 11.12); secondary-clicking a head label opens the head menu (filled in by 16.13) — Verify: a snapshot of `tags-notes` shows the labels; `swift test --filter RefLabelHitTests` checks hit-testing.
  - Files: `Sources/GitkUI/CommitList/RefLabelDrawing.swift`, tests.
  - Needs: 10.2, 7.7.
  - Spec: commit-graph "Context menu on a head label".
- [x] 10.4 [M] Implement `SelectionModel` (Core) and its wiring: select a row, fill the details sidebar, stream the diff into the bottom pane, put the full ID in the sidebar and "Row N / M" in the status strip, and copy to the clipboard when enabled; default selection is HEAD or the first row; honour `--select-commit` — Verify: `swift test --filter SelectionModelTests`; `Tools/snapshot.sh merge-simple /tmp/s.png --select-commit=<id>` shows that row selected, the sidebar filled and the diff below the list.
  - Files: `Sources/GitkCore/History/SelectionModel.swift`, `CommitListController.swift`, `Sources/GitkUI/Bars/StatusBar.swift`, tests.
  - Port: 7500–7560, 708–720.
  - Needs: 10.1.
  - Spec: commit-list "Select a commit", "Auto-copy", "Default selection"; cli-launch "Select a commit at startup".
- [x] 10.5 [M] Implement the navigation commands: next/previous line, page, first/last, scroll-only ⌘ variants, and go to the n-th parent — Verify: `swift test --filter NavigationCommandTests` (view-model level).
  - Files: `SelectionModel.swift`, `MainWindowController.swift`, tests.
  - Port: 7668–7726, 7824–7832.
  - Needs: 10.4, 9.7.
  - Spec: commit-list "j/k navigation", "Go to parent".
- [x] 10.6 [M] Implement `NavigationHistory` (Core): entries for a commit selection, a line click and a link, each with a saved diff scroll position; back/forward with button enablement — Verify: `swift test --filter NavigationHistoryTests`; the titlebar ← → buttons enable and disable as the history changes.
  - Files: `Sources/GitkCore/History/NavigationHistory.swift`, `Sources/GitkUI/Bars/SearchBar.swift` (← → buttons), tests.
  - Port: 7726–7824.
  - Needs: 10.4.
  - Spec: commit-list "Back after following a link".
- [x] 10.7 [M] Implement `CommitResolver` (Core) and the titlebar field's go-to-commit mode (`g`): full or short ID, `git rev-parse --verify <rev>^{commit}`, the placeholder change, Escape back to search mode, and the four error messages — Verify: `swift test --filter CommitResolverTests` (ambiguous prefix, unknown revision, not in view) and a manual check that `g` then a prefix selects the commit and returns the field to search mode.
  - Files: `Sources/GitkCore/History/CommitResolver.swift`, `Sources/GitkUI/Bars/SearchBar.swift`, tests.
  - Port: 8901–8967, 1989–2014 (`longid`).
  - Needs: 10.4, 14.4.
  - Spec: commit-list "Abbreviated ID", "Not in view".
- [ ] 10.8 [S] Implement the slim bottom status strip in `StatusBar` (Row N / M, Reading, Searching, …), its progress bar and the busy cursor — Verify: a snapshot of `huge` taken right after the first batch (`GITK_SWIFT_SNAPSHOT_EARLY=1`) shows "Reading", the row counter and a partial progress bar along the bottom.
  - Files: `StatusBar.swift`, `Snapshot.swift`.
  - Port: 2973–2990, 6893–6943.
  - Needs: 10.1.
  - Spec: commit-list "Status during load".
- [ ] 10.9 [M] Implement line interaction: a hover tooltip with the parent subject; clicking a line draws it thicker and puts the parent and children text in the details sidebar (a provider interface filled in by 11.1); clicking an arrow scrolls to the other end — Verify: `swift test --filter LineHitTests` (Core hit-testing on the geometry) and a manual check in `docs/smoke-test.md`.
  - Files: `GraphCellView.swift`, `Sources/GitkCore/Graph/LineHitTest.swift`, tests.
  - Port: 8967–9136.
  - Needs: 10.2, 10.6.
  - Spec: commit-graph "Click a line", "Arrow jump".
- [ ] 10.10 [S] Apply the wheel multiplier and middle-button drag panning; give the first column its own horizontal scroll — Verify: `swift test --filter ScrollScalingTests` (multiplier maths).
  - Files: `CommitListController.swift`, `ListColumnsView.swift`, tests.
  - Port: 2316–2374, 2925–2945.
  - Needs: 10.1.
  - Spec: commit-list "Wheel multiplier".
- [ ] 10.11 [S] Build the row context menu and the reduced menu for local-changes rows, with enablement rules; the actions stay stubs until group 16 — Verify: `swift test --filter RowMenuTests` (item titles and order; mark-dependent items are disabled with no mark).
  - Files: `Sources/GitkUI/CommitList/RowMenus.swift`, tests.
  - Port: 2880–2905, 9151–9188.
  - Needs: 10.4.
  - Spec: commit-list "Context menu on a fake row"; repository-actions "No mark set".

## 11. Commit details and diff pane

- [x] 11.1 [M] Implement `DetailsSidebar`: the identity header (author monogram, name, date and time, email, full commit ID and refs), the metadata rows (Author, Committer, Tags, Parent lines in merge colours, Child lines, Branch, Follows, Precedes), a collapsible Message section with the message and notes, and the mount point for the Changed Files section. Add the close button and the View → Details Sidebar state — Verify: `swift test --filter DetailsHeaderTests` (Core `DetailsHeaderBuilder` produces the expected rows and attribute runs for a merge on `merge-simple` and for a note on `tags-notes`); a snapshot shows the sidebar beside the list.
  - Files: `Sources/GitkCore/History/DetailsHeaderBuilder.swift`, `Sources/GitkUI/Details/DetailsSidebar.swift` (replaces `DetailsTextController.swift`), tests.
  - Port: 7207–7222, 7590–7668.
  - Needs: 10.4, 9.5.
  - Spec: commit-details "Merge commit", "Commit with notes", "Message section collapses", "Sidebar follows selection".
- [x] 11.2 [M] Implement `LinkScanner` (Core) for hex IDs of 6 to hashLength characters and `-g<hex>`, and for http(s) URLs, plus click handling: commit links select the commit (and record history); URLs run the `web_browser` command — Verify: `swift test --filter LinkScannerTests` (a revert message, an unknown hash that is not a link, URLs).
  - Files: `Sources/GitkCore/History/LinkScanner.swift`, `Sources/GitkUI/Details/LinkHandling.swift`, tests.
  - Port: 7222–7340.
  - Needs: 11.1, 10.6.
  - Spec: commit-details "Revert message link", "Unknown hash", "Open a URL".
- [ ] 11.3 [S] Implement comment wrapping (none, char, word) for the sidebar message and other text — Verify: `swift test --filter WrapModeTests` (mapping to text container settings).
  - Files: `DetailsSidebar.swift`, tests.
  - Needs: 11.1.
  - Spec: commit-details "Word wrap".
- [x] 11.4 [M] Implement `DiffCommandBuilder` (Core) as a port of `diffcmd`, with the `getblobdiffs` flags (context, `-w`, `--word-diff=porcelain`, `--root` when showRoot is set, limitdiffs path filter) for every combination of IDs, including the local-changes rows — Verify: `swift test --filter DiffCommandBuilderTests` (a table of the 8 combinations).
  - Files: `Sources/GitkCore/History/DiffCommandBuilder.swift`, tests.
  - Port: 8059–8103, 8203–8231.
  - Needs: 3.4.
  - Spec: diff-viewer "Unstaged row", "Index row", "Limited view".
- [x] 11.5 [M] Implement `DiffDocument` (Core model with file-section offsets) and `DiffRenderer` (UI attributes: diff colours and backgrounds, full-width file separators), with streaming append into a TextKit 1 `NSTextView` in the bottom pane below the history list — Verify: a snapshot of `merge-simple` (a non-merge commit selected) shows the sidebar, the coloured +/- lines and the file separators in the bottom pane; `swift test --filter DiffDocumentTests`.
  - Files: `Sources/GitkCore/History/DiffDocument.swift`, `Sources/GitkUI/Details/DiffRenderer.swift`, tests.
  - Port: 8231–8328, 8603–8638.
  - Needs: 11.4, 11.1.
  - Spec: diff-viewer "Selection shows the diff", "Ordinary commit", "Rename", "Large diff".
- [ ] 11.6 [S] Colour combined-diff markers by parent — Verify: a snapshot of a merge with a non-trivial combined diff shows 3 coloured marker columns. The fixture merges are clean, so `--cc` prints nothing for them; first add an `evil-octopus` fixture to `make-fixture.sh` (the `octopus` merge amended with an extra edit, as `DiffParserTests` does) and its row in `Tests/Fixtures/README.md`.
  - Files: `DiffRenderer.swift`.
  - Needs: 11.5.
  - Spec: diff-viewer "Octopus merge".
- [x] 11.7 [M] Build `DiffControlsBar`: Diff/Old/New (re-render from the model), the Lines of context field, Ignore space change, and the Line/Markup/Color words dropdown (re-fetch) — Verify: `swift test --filter DiffModeTests` (Old mode hides adds); a snapshot after setting context to 10 shows the longer hunks.
  - Files: `Sources/GitkUI/Details/DiffControlsBar.swift`, `DiffRenderer.swift`, tests.
  - Port: 8169–8192, 8542–8549.
  - Needs: 11.5.
  - Spec: diff-viewer "Old version", "Context lines".
- [x] 11.8 [M] Render word diffs in Markup words and Color words styles from `WordDiffParser` output — Verify: a snapshot of `linear` with `Color words` shows inline coloured words and no +/- lines.
  - Files: `DiffRenderer.swift`.
  - Needs: 11.7, 3.5.
  - Spec: diff-viewer "Color words".
- [ ] 11.9 [M] Implement `PaneSearch`: incremental highlighting, next and previous, the current-hit colour, and ⌘-S/⌘-R — Verify: `swift test --filter PaneSearchTests` (match ranges and the next/previous cursor logic).
  - Files: `Sources/GitkUI/Details/PaneSearch.swift`, tests.
  - Port: 8638–8800.
  - Needs: 11.5.
  - Spec: diff-viewer "Incremental search".
- [x] 11.10 [S] Add the pane scroll keys (Space, Delete, Backspace, d, u) and next/previous file (f, b) using the `DiffDocument` section offsets — Verify: `swift test --filter FileJumpTests`.
  - Files: `DiffRenderer.swift`, tests.
  - Port: 8574–8603.
  - Needs: 11.5, 9.7.
  - Spec: diff-viewer "Next file".
- [ ] 11.11 [M] Implement per-file encodings: `GitAttributes` (Core) runs `git check-attr encoding` (cached per path), and file text is decoded with fallbacks — Verify: `swift test --filter GitAttributesTests` on `encodings` (Shift-JIS file text decodes).
  - Files: `Sources/GitkCore/Parsing/GitAttributes.swift`, `DiffDocument.swift`, tests.
  - Port: 12460–12518.
  - Needs: 11.5, 2.6.
  - Spec: diff-viewer "Shift-JIS file".
- [ ] 11.12 [S] Implement tag display: `git cat-file tag <tag>` shows the tag name, tagger and message with a link to the tagged commit in the sidebar, and clears the Changed Files section; also the "n tags..." list — Verify: `swift test --filter TagDisplayTests` on `tags-notes`.
  - Files: `DetailsSidebar.swift`, `Sources/GitkCore/History/TagInfo.swift`, tests.
  - Port: 11556–11610.
  - Needs: 11.1.
  - Spec: commit-details "Click a tag".
- [ ] 11.13 [S] Cap very large diffs at 200,000 lines with a "load the rest" control (D7 risk) — Verify: `swift test --filter DiffTruncationTests`; record the deviation in `docs/architecture.md`.
  - Files: `DiffDocument.swift`, `DiffRenderer.swift`, tests.
  - Needs: 11.5.

## 12. Ancestry index (nearby tags and branches)

- [x] 12.1 [L] Port `getallcommits`, `getallclines`, `recalcarc`, `splitarc` and `addnewchild` into `AncestryIndex` (`git rev-list --parents --all`, streamed off the main actor) — Verify: `swift test --filter AncestryIndexBuildTests` (arc count and arc endpoints equal values dumped by a new oracle mode `--allcommits` on `merge-simple` and `criss-cross`; extend `oracle.tcl` as part of this task).
  - Files: `Sources/GitkCore/Ancestry/AncestryIndex.swift`, `Tests/Oracle/oracle.tcl`, tests.
  - Port: 10414–10701.
  - Needs: 5.3, 3.2.
- [x] 12.2 [M] Implement `AncestryCache` read/write in gitk's text format, stored in `<gitdir>/gitk-swift.cache` with a `gitk-swift-cache 1` header line — Verify: `swift test --filter AncestryCacheTests` (round-trip; a corrupt cache is ignored and rebuilt).
  - Files: `Sources/GitkCore/Ancestry/AncestryCache.swift`, tests.
  - Port: 10701–10866.
  - Needs: 12.1.
  - Spec: commit-details "Index reused across launches".
- [x] 12.3 [L] Port `anc_or_desc`, `is_certain`, `validate_arctags` and `validate_archeads` — Verify: `swift test --filter AncestryQueryTests` (results for 20 random commit pairs on `criss-cross` equal `git merge-base --is-ancestor`).
  - Files: `AncestryIndex.swift`, tests.
  - Port: 10866–11098.
  - Needs: 12.1.
- [x] 12.4 [M] Port `desctags`, `anctags` and `descheads`, and implement `NearbyRefs` (`maxrefs`, `visiblerefs`, "and many more"/"many") — Verify: `swift test --filter NearbyRefsTests` (on `tags-notes`, Follows/Precedes match `git describe --tags` and `git describe --contains` for 5 commits; the overflow text appears).
  - Files: `Sources/GitkCore/Ancestry/NearbyRefs.swift`, tests.
  - Port: 11098–11454, 7358–7472.
  - Needs: 12.3.
  - Spec: commit-details "Too many branches".
- [x] 12.5 [S] Fill in the Branch/Follows/Precedes rows asynchronously in the details sidebar when "Display nearby tags/heads" is on — Verify: a snapshot of `tags-notes` with a middle commit selected shows all three rows filled.
  - Files: `DetailsSidebar.swift`.
  - Port: 7633–7668.
  - Needs: 12.4, 11.1.
  - Spec: commit-details "Nearby tags computed in the background".

## 13. File list

- [x] 13.1 [M] Implement `FileListController` in Patch mode inside the sidebar's Changed Files section: the "N Changed Files" and +/− header, the Patch/Tree switch, and the files in diff order with click-to-jump in the bottom diff pane — Verify: `swift test --filter FileListPatchTests` (entries for `renames`, the header counts); a snapshot shows the list below the message.
  - Files: `Sources/GitkUI/FileList/FileListController.swift`, `Sources/GitkUI/Details/DetailsSidebar.swift`, tests.
  - Port: 3504–3662. Note: gitk builds this list from `git diff-tree -r --no-commit-id [--root] <id>` raw output (no `-z`, no `-C`), while `TreeParser.parseNameStatus` parses `-z --name-status -C`. Use the parser, keep the diff pane's rename detection consistent, and record the choice in `docs/architecture.md`.
  - Needs: 11.5, 11.1.
  - Spec: file-list "Changed Files section", "Jump to file", "Change totals".
- [x] 13.2 [S] Keep the Changed Files highlight in sync with the bottom diff's scroll position — Verify: `swift test --filter FileHighlightSyncTests` (scroll offset → file index).
  - Files: `FileListController.swift`, tests.
  - Port: 8549–8574, 8775–8800.
  - Needs: 13.1.
  - Spec: file-list "Scroll the diff".
- [ ] 13.3 [M] Implement Tree mode in the sidebar section: an outline of `ls-tree` (directories collapsed), clicking a file shows the blob decoded with its encoding in the bottom pane, and the Patch/Tree switch re-selects — Verify: `swift test --filter TreeModeTests` (outline structure); a snapshot in Tree mode shows the file content in the bottom pane.
  - Files: `FileListController.swift`, `DiffRenderer.swift`, tests.
  - Port: 3293–3504, 7900–7975.
  - Needs: 13.1, 3.6, 11.11.
  - Spec: file-list "Expand a directory"; diff-viewer "View a file at a revision".
- [x] 13.4 [M] Implement `TempFiles` (Core: per-run directory under `GITK_TMPDIR` or `$TMPDIR`, deleted on quit) and External diff (write the old and new blobs, handling renames, then launch the configured tool) — Verify: `swift test --filter ExternalDiffTests` (with a fake tool script that records its arguments, the right files are passed for a rename on `renames`; the directory is removed by `cleanup()`).
  - Files: `Sources/GitkCore/Util/TempFiles.swift`, `Sources/GitkCore/Actions/ExternalDiff.swift`, tests.
  - Port: 3729–3874.
  - Needs: 13.1.
  - Spec: file-list "External diff", "External diff with a renamed file", "Quit after external diff".
- [ ] 13.5 [S] Implement the file context menu: Highlight this too/only (sets the search bar), Copy path, and Blame parent commit (`git gui blame`) — Verify: `swift test --filter FileMenuTests` (the commands produced).
  - Files: `FileListController.swift`, tests.
  - Port: 3662–3729, 4003–4033.
  - Needs: 13.1, 14.4.
  - Spec: file-list "Highlight this only", "Copy path".
- [ ] 13.6 [M] Implement Show origin of this line and Run git gui blame on this line in the diff context menu — Verify: `swift test --filter LineOriginTests` (`find_hunk_blamespec` port on sample hunks; the blame output parser).
  - Files: `Sources/GitkCore/Actions/LineOrigin.swift`, `DiffRenderer.swift`, tests.
  - Port: 3874–4003, 4033–4179.
  - Needs: 11.5.
  - Spec: diff-viewer "Origin of an added line".

## 14. Find

- [x] 14.1 [M] Implement `FindQuery` (Core: type, match mode, field, pattern) and `doesmatch` text matching over the headline, comments, author and committer — Verify: `swift test --filter FindQueryTests` (IgnCase author, an invalid regexp gives no matches and no throw).
  - Files: `Sources/GitkCore/Find/FindQuery.swift`, tests.
  - Port: 4936–4975, 5079–5150.
  - Needs: 3.2.
  - Spec: commit-find "Case-insensitive author search", "Invalid regexp".
- [x] 14.2 [S] Port `makepatterns` and path matching into `PathPatterns`, with backslash-to-slash for Exact — Verify: `swift test --filter PathPatternsTests` (a directory matches its children; quoted spaces via `ShellWords`).
  - Files: `Sources/GitkCore/Find/PathPatterns.swift`, tests.
  - Port: 4975–4989.
  - Needs: 3.8.
  - Spec: commit-find "Directory path", "Quoted path with spaces".
- [x] 14.3 [M] Implement `FindEngine`: for path, `-S` and `-G` types it runs `git diff-tree -r -s --stdin <args>`, feeding the view's commits, and streams back the matching IDs; it is cancellable — Verify: `swift test --filter FindEngineTests` (`-S` on `linear` matches `git log -S` for the same string).
  - Files: `Sources/GitkCore/Find/FindEngine.swift`, tests.
  - Port: 4989–5079.
  - Needs: 14.1, 14.2, 2.3.
  - Spec: commit-find "Pickaxe search".
- [ ] 14.4 [M] Build `SearchBar` in the titlebar: the search field ("Search commits…"), the Advanced ("Aa") popover with kind, match mode and field (Exact and All fields hidden by default), the "N / M" counter, ‹ › stepping, and the ← → history buttons. Draw matches as rounded background boxes in the found colour, with the current match in the current-search-hit colour, instead of bolding rows. No "Find" label, no text ↑/↓ buttons and no controls beside the traffic lights — Verify: a snapshot with `GITK_SWIFT_FIND="containing:Exact:All fields:merge"` shows a box around every visible match and no bold rows; a snapshot with the popover open shows the three option groups.
  - Files: `Sources/GitkUI/Bars/SearchBar.swift`, `CommitListController.swift`, `GraphCellView.swift`, `Snapshot.swift`.
  - Port: 2560–2580, 4892–4936, 5024–5042.
  - Needs: 14.3, 10.1, 9.5.
  - Spec: commit-find "Highlight while typing", "Match boxes", "Current match box", "Advanced filters", "Defaults".
- [ ] 14.5 [M] Port `dofind`, `findmore`, `findselectline`, `markmatches` and `stopfinding`: next and previous match with wrap or no wrap, progress, the current-match box, and the same boxes in the sidebar message — Verify: `swift test --filter FindSteppingTests` (wraps around; Shift-Down/⌘-G do not wrap); a snapshot shows one orange current box and yellow other boxes.
  - Files: `Sources/GitkCore/Find/FindStepper.swift`, `SearchBar.swift`, `DetailsSidebar.swift`, tests.
  - Port: 6943–7187.
  - Needs: 14.4.
  - Spec: commit-find "Wraparound", "No wrap with Shift", "Matches in visible text", "Current match box".
- [x] 14.6 [S] Wire the focus keys: `/` and keypad-divide focus the titlebar search field; `g` clears it and switches it to go-to-commit mode — Verify: `swift test --filter FocusKeyTests`.
  - Files: `MainWindowController.swift`, `SearchBar.swift`, tests.
  - Needs: 14.4, 9.7.
  - Spec: commit-find "Slash to search".
- [ ] 14.7 [M] Make search fast: `SearchIndex` with immutable chunks of searchable fields, scanning off the main actor, a 100 ms debounce, prefix narrowing (when the pattern extends, scan only the previous matches), field pruning, and generation cancellation. Add `FindPerfTests` behind `GITK_PERF=1` on `huge` for a common pattern and a no-match pattern — Verify: first visible boxes appear in ≤ 120 ms, the full result arrives in ≤ 1 s, a superseded search stops in ≤ 50 ms, and the main thread is never blocked for more than 16 ms; record the numbers in `docs/architecture.md`.
  - Files: `Sources/GitkCore/Find/SearchIndex.swift`, `Sources/GitkCore/Find/SearchScanner.swift`, `SearchBar.swift`, tests, `docs/architecture.md`.
  - Needs: 14.3, 14.4, 3.2.
  - Spec: commit-find "Responsive search on a large repo", "Stale results never appear", "Prefix refinement reuses results", "Cancellation".

## 15. Views

- [x] 15.1 [M] Implement `ViewOptions` (the `known_view_options` table as data) and `ViewOptionCodec.encode` — Verify: `swift test --filter ViewOptionEncodeTests` (Author + Since gives `--author=alice --since=2026-03-01`; regexp pickaxe gives `-Sfoo.*bar --pickaxe-regex`).
  - Files: `Sources/GitkCore/Views/ViewOptions.swift`, `ViewOptionCodec.swift`, tests.
  - Port: 4303–4372.
  - Needs: 8.3.
  - Spec: views "Pickaxe as regexp".
- [x] 15.2 [M] Implement `ViewOptionCodec.decode` (pattern matching, `-<n>` as the limit, leftovers into extra args) — Verify: `swift test --filter ViewOptionDecodeTests` (`--author=bob -20 --no-merges`; round-trip of `encode` results).
  - Files: `ViewOptionCodec.swift`, tests.
  - Port: 4372–4434.
  - Needs: 15.1.
  - Spec: views "Edit a command-line view".
- [ ] 15.3 [M] Build the `ViewEditorController` form from the `ViewOptions` table (layout flags `+`, `..`, `*`, `*.`), with OK, Apply (F5) and Cancel — Verify: a snapshot of the editor (`GITK_SWIFT_OPEN=viewEditor`) shows every field in gitk's order.
  - Files: `Sources/GitkUI/Dialogs/ViewEditorController.swift`, `Snapshot.swift`.
  - Port: 4434–4634.
  - Needs: 15.2, 9.5.
  - Spec: views "Create a view", "Apply without closing", "Paths field".
- [ ] 15.4 [M] Implement the View menu: All files and Command line entries, plus new, edit, delete and switch (keeping the selection) and enablement — Verify: `swift test --filter ViewMenuTests` (the no-arguments state disables Edit and Delete; switching keeps the selection at view-model level).
  - Files: `MainMenu.swift`, `Sources/GitkCore/Views/ViewManager.swift`, tests.
  - Port: 4286–4303, 4559–4576, 4634–4765.
  - Needs: 15.3, 8.7.
  - Spec: views "No arguments", "Switch keeps selection".
- [ ] 15.5 [S] Persist remembered views in `Settings.views`, importing them from the legacy `permviews` on first launch — Verify: `swift test --filter RememberedViewsTests` (persist and reload; an unchecked view is not saved).
  - Files: `ViewManager.swift`, tests.
  - Needs: 15.4, 4.5, 4.6.
  - Spec: views "Persist across launches", "Unchecked view not saved".

## 16. Repository actions

- [x] 16.1 [M] Implement `RepoActions` (Core) wrappers for branch create, rename and delete, tag create, checkout, reset, cherry-pick, revert and patch-id, each returning typed results or errors that carry git's stderr — Verify: `swift test --filter RepoActionsTests` on temp copies of fixtures (one test per operation, including the failure paths).
  - Files: `Sources/GitkCore/Actions/RepoActions.swift`, tests.
  - Needs: 2.2, 1.6.
- [ ] 16.2 [M] Implement diff this ↔ selected and diff this ↔ marked: a two-commit diff in the bottom pane with both IDs as links in the details sidebar — Verify: `swift test --filter TwoCommitDiffTests` (command and header text).
  - Files: `DetailsSidebar.swift`, `DiffRenderer.swift`, tests.
  - Port: 9345–9424.
  - Needs: 11.5, 10.11.
  - Spec: repository-actions "Diff against selection".
- [ ] 16.3 [M] Implement mark this commit, return to mark, and find descendant of this and mark (marked-row background) — Verify: `swift test --filter MarkTests` (`find_common_desc` on `criss-cross`).
  - Files: `SelectionModel.swift`, `CommitListController.swift`, tests.
  - Port: 9188–9241.
  - Needs: 10.11, 12.3.
- [ ] 16.4 [M] Implement compare with marked commit (`PatchIDCompare`: `git patch-id` for each side, then report the unmatched commits in the diff pane) — Verify: `swift test --filter PatchIDCompareTests` (on a cherry-picked series built in a temp repo).
  - Files: `Sources/GitkCore/Actions/PatchIDCompare.swift`, tests.
  - Port: 9241–9345.
  - Needs: 16.1, 16.3.
  - Spec: repository-actions "Compare cherry-picked series".
- [ ] 16.5 [M] Build the Make patch dialog (From, To, Reverse, Output file defaulting to `patch<n>.patch`, Generate, Cancel) — Verify: `swift test --filter MakePatchTests` (the generated file applies with `git apply --check` on the parent).
  - Files: `Sources/GitkUI/Dialogs/PatchDialog.swift`, tests.
  - Port: 9424–9514.
  - Needs: 16.1.
  - Spec: repository-actions "Make patch".
- [ ] 16.6 [M] Build the Create tag dialog (ID, name, optional message giving an annotated tag; empty and duplicate names refused); the label appears without a reload — Verify: `swift test --filter CreateTagTests`.
  - Files: `Sources/GitkUI/Dialogs/TagDialog.swift`, tests.
  - Port: 9514–9632.
  - Needs: 16.1, 10.3.
  - Spec: repository-actions "Annotated tag".
- [x] 16.7 [S] Implement Copy commit reference (`git show -s --pretty=format:'%h ("%s", %ad)' --date=short` plus `--abbrev` from the copy length) — Verify: `swift test --filter CopyReferenceTests`.
  - Files: `RepoActions.swift`, tests.
  - Port: 9632–9647.
  - Needs: 16.1.
  - Spec: repository-actions "Copy reference".
- [ ] 16.8 [M] Build the Write commit to file dialog (command defaults to `git diff-tree --stdin -p --pretty=email`, run with `sh -c`, ID on stdin) — Verify: `swift test --filter WriteCommitTests`.
  - Files: `Sources/GitkUI/Dialogs/WriteCommitDialog.swift`, tests.
  - Port: 9647–9706.
  - Needs: 16.1.
- [ ] 16.9 [M] Build the Create new branch and Rename branch dialogs (empty name refused; overwrite confirmation) — Verify: `swift test --filter BranchDialogTests` with `GITK_SWIFT_HEADLESS_ERRORS=1`.
  - Files: `Sources/GitkUI/Dialogs/BranchDialog.swift`, tests.
  - Port: 9706–9858.
  - Needs: 16.1, 10.3.
  - Spec: repository-actions "Create branch".
- [ ] 16.10 [M] Implement Cherry-pick: re-apply confirmation, local-changes error naming the file, conflict prompt that runs `git citool`, "No changes committed", and on success a new row on top of HEAD with the label moved and selected — Verify: `swift test --filter CherryPickTests` (success, conflict and no-op on temp repos with headless confirm).
  - Files: `RepoActions.swift`, `MainWindowController.swift`, tests.
  - Port: 9858–9947.
  - Needs: 16.1, 8.7.
  - Spec: repository-actions "Successful cherry-pick", "Conflict", "Nothing to commit".
- [ ] 16.11 [M] Implement Revert, with the same handling as cherry-pick — Verify: `swift test --filter RevertTests`.
  - Files: `RepoActions.swift`, tests.
  - Port: 9947–10008.
  - Needs: 16.10.
- [ ] 16.12 [M] Build the Reset dialog (Soft, Mixed (the default) or Hard; confirm; labels and local rows refreshed afterwards) — Verify: `swift test --filter ResetTests`.
  - Files: `Sources/GitkUI/Dialogs/ResetDialog.swift`, tests.
  - Port: 10008–10082.
  - Needs: 16.1, 8.6.
  - Spec: repository-actions "Hard reset".
- [ ] 16.13 [M] Build the head label menu: check out (with the local-changes failure path), rename, remove (refuses the current branch; confirms when commits are unmerged), copy branch name — Verify: `swift test --filter HeadMenuTests`.
  - Files: `Sources/GitkUI/CommitList/RowMenus.swift`, tests.
  - Port: 10082–10209.
  - Needs: 16.9.
  - Spec: repository-actions "Remove current branch", "Checkout with local changes".
- [ ] 16.14 [S] Implement Start git gui (launch in the background; failure shows an alert) and the shared busy/error handling for write actions — Verify: `swift test --filter ExternalToolLaunchTests` (a missing tool gives an error string, no crash); `GITK_SWIFT_HEADLESS_ERRORS=1` prints git's message.
  - Files: `RepoActions.swift`, `MainWindowController.swift`, tests.
  - Port: 2403, 9858–9884.
  - Needs: 16.1.
  - Spec: repository-actions "git gui missing", "Branch already exists outside the app".

## 17. Reference list window

- [ ] 17.1 [M] Build `RefListWindowController`: titled "Tags and heads: <repo>", glob filter, Sort refs by type, click to select the commit; a single instance that is brought to the front if already open — Verify: `swift test --filter RefListModelTests` (filtering and both sort orders on `tags-notes`).
  - Files: `Sources/GitkUI/Dialogs/RefListWindowController.swift`, `Sources/GitkCore/Model/RefListModel.swift`, tests.
  - Port: 10209–10414.
  - Needs: 10.4, 3.3.
  - Spec: reference-list "Open with F2", "Filter refs", "Ref outside view".
- [ ] 17.2 [S] Refresh on `refsChanged`, persist the window frame, and close on Escape or Close — Verify: `swift test --filter RefListRefreshTests` (the model updates after a branch is created).
  - Files: `RefListWindowController.swift`, tests.
  - Needs: 17.1, 18.4.
  - Spec: reference-list "Branch created while open".

## 18. Preferences UI and persistence wiring

- [ ] 18.1 [M] Build the General page of `PreferencesController` (all fields from the spec; external diff chooser), with OK and Cancel — Verify: a snapshot with `GITK_SWIFT_OPEN=prefs` shows the General page; `swift test --filter PrefsGeneralTests` (Cancel discards).
  - Files: `Sources/GitkUI/Dialogs/PreferencesController.swift`, tests.
  - Port: 11700–11803, 11914–11972, 12078–12152.
  - Needs: 4.5, 9.6.
  - Spec: preferences "Cancel", "Toggle local changes".
- [ ] 18.2 [M] Build the Colors page (colour wells for each colour setting, including "Found text background" and "Current search hit background"; changes apply on OK) — Verify: `swift test --filter PrefsColorsTests` (a changed colour reaches `DiffRenderer` attributes and the search match boxes).
  - Files: `PreferencesController.swift`, tests.
  - Port: 11803–11903, 12017–12078.
  - Needs: 18.1.
  - Spec: preferences "Change a colour", "Change a search colour".
- [ ] 18.3 [M] Build the Fonts page (NSFontPanel for the main, text and UI fonts) and the ⌘+/⌘−/⌘= font size commands (persisted) — Verify: `swift test --filter FontSettingsTests`.
  - Files: `PreferencesController.swift`, `MainWindowController.swift`, tests.
  - Port: 8873–8901, 11623–11700, 11903–11914.
  - Needs: 18.1.
  - Spec: preferences "Change the text font", "Increase font".
- [ ] 18.4 [M] Save and restore window geometry (window frame, the history/diff split, the history/sidebar split, the sidebar width and collapsed state, column widths, ref-list frame), load settings at startup, and import legacy settings on first launch — Verify: `swift test --filter GeometryPersistenceTests`; with `GITK_SWIFT_CONFIG_DIR` pointing at a temp dir and an `XDG_CONFIG_HOME` holding the sample config, the first launch imports it (the snapshot shows the imported font).
  - Files: `MainWindowController.swift`, `MainSplitView.swift`, `AppDelegate.swift`, tests.
  - Needs: 4.6, 9.5.
  - Spec: preferences "Geometry restored", "Sidebar state restored", "Import existing config", "Config with code", "Legacy file untouched", "Corrupt settings", "Fresh install".
- [ ] 18.5 [S] Apply the "Hide remote refs", "Refs to hide", "Show local changes" and "Limit diffs" settings live (redraw or reload as needed) — Verify: `swift test --filter LiveSettingsTests`.
  - Files: `ViewSession.swift`, `MainWindowController.swift`, tests.
  - Needs: 18.1, 8.7.

## 19. Localization

- [x] 19.1 [M] Write the `po2strings` parser: msgctxt, multiline msgid/msgstr, escapes, fuzzy and empty entries skipped — Verify: `swift test --filter PoParserTests` with sample snippets taken from `gitk/po/de.po`.
  - Files: `Sources/po2strings/main.swift`, `Sources/po2strings/PoParser.swift` (or a small shared library target if needed), tests.
  - Needs: 1.3.
- [x] 19.2 [S] Convert placeholders (`%s`/`%d`/`%n$s` to positional `%n$@`/`%n$ld`), strip `&` mnemonics, map lproj names (D11), and write sorted `.strings` output — Verify: `swift test --filter PoConvertTests`.
  - Files: `Sources/po2strings/*`, tests.
  - Needs: 19.1.
  - Spec: localization "Formatted message".
- [x] 19.3 [S] Write `Tools/regen-l10n.sh` and commit the generated `Sources/GitkUI/Resources/*.lproj/Localizable.strings` for all 16 languages — Verify: running the script twice leaves `git status` clean; there are 16 lproj directories.
  - Files: `Tools/regen-l10n.sh`, `Sources/GitkUI/Resources/**`.
  - Needs: 19.2, 1.1.
  - Spec: localization "Idempotent conversion".
- [x] 19.4 [S] Implement `LanguageOverride` (`LC_ALL` > `LC_MESSAGES` > `LANG` → lproj; C/POSIX ignored) and make `L()` convert its Tcl-style key with `PoConvert`'s placeholder function (add the `GitkUI` → `PoConvert` dependency), then look it up in `Bundle.module` with an English fallback (design D11) — Verify: `swift test --filter LanguageOverrideTests`; `LANG=de_DE.UTF-8 Tools/snapshot.sh linear /tmp/de.png` shows German labels ("Suchen", "Zeile").
  - Files: `Sources/GitkUI/App/LanguageOverride.swift`, `L10n.swift`, tests.
  - Needs: 19.3, 9.3.
  - Spec: localization "German system", "Untranslated string", "Override from terminal", "C locale".
- [x] 19.5 [S] Add `L10nCoverageTests`: scan `Sources/GitkUI` for `L("…")` literals and fail on any key that is not a gitk msgid (from `gitk/po/de.po` msgids, after `&` stripping) unless it is listed in `docs/architecture.md` under new strings — Verify: `swift test --filter L10nCoverageTests` passes.
  - Files: `Tests/GitkUITests/L10nCoverageTests.swift`.
  - Needs: 19.3.

## 20. Integration, packaging and parity sign-off

- [ ] 20.1 [S] Write `Tools/make-app.sh` (an `.app` bundle with `Info.plist`, a placeholder icon and the resource bundle) and Makefile `app`/`install PREFIX=` targets — Verify: `make app && open -a ./out/gitk-swift.app --args` from within a fixture opens the window; `make install PREFIX=/tmp/gs` produces `/tmp/gs/bin/gitk-swift`, which runs.
  - Files: `Tools/make-app.sh`, `Makefile`.
  - Needs: 9.2.
- [ ] 20.2 [M] Fill in `docs/spec-coverage.md` so every scenario in `specs/**/spec.md` maps to a passing test or a numbered step in `docs/smoke-test.md`; write the smoke steps for the UI-only scenarios — Verify: a script `Tools/check-coverage.sh` reports 0 scenarios without a mapping.
  - Files: `docs/spec-coverage.md`, `docs/smoke-test.md`, `Tools/check-coverage.sh`.
  - Needs: all of groups 1–19.
- [ ] 20.3 [M] Run the full smoke test on `merge-simple`, `local-changes` and `huge`, saving snapshots for every step that has one under `docs/smoke/` — Verify: every smoke step is marked pass in `docs/smoke-test.md`; failures are filed as new tasks under a "Follow-up fixes" group.
  - Files: `docs/smoke-test.md`, `docs/smoke/*.png`.
  - Needs: 20.2.
- [ ] 20.4 [S] Final checks: `swift build -c release` with zero warnings, `swift test`, `GITK_PERF=1` perf tests, and `openspec validate rewrite-gitk-in-swift --strict` — Verify: all four commands exit 0; paste their summaries in the task report.
  - Needs: 20.3, 8.9.

## Workflow follow-up

- Side-by-side review of the Swift app against Tcl gitk (`gitk/gitk` run with Homebrew `wish`) on the user's own repositories; this needs a human.
- Archive the change with `/openspec-archive-change` once the review is accepted.
