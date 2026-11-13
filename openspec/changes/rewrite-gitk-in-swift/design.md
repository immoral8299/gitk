# Design

## Context

- **Source of truth for behaviour:** `gitk/gitk`, a 13,031-line Tcl/Tk script cloned from `https://github.com/j6t/gitk` at `6fc42f7`. It is a nested clone that is currently untracked in this repository. Its parts are listed below by line number, so tasks can cite them:

  | Area | Lines | Key procs |
  |---|---|---|
  | Safe exec / process helpers | 160–320 | `safe_exec`, `safe_open_command*`, `filerun`, `run`, `dorunq` |
  | View args → git log | 389–720 | `parseviewargs`, `parseviewrevs`, `start_rev_list`, `stop_rev_list` |
  | Update / reload | 720–860 | `getcommits`, `updatecommits`, `reloadcommits` |
  | Ordering ("varc" virtual arcs) | 872–1600 | `varcinit`, `newvarc`, `splitvarc`, `renumbervarc`, `insertrow`, `insertfakerow`, `removefakerow`, `update_arcrows`, `make_disporder`, `commitonrow`, `rowofcommit`, `closevarcs`, `rewrite_commit` |
  | Commit streaming / parsing | 1651–2014 | `getcommitlines`, `chewcommits`, `parsecommit`, `getcommit`, `longid` |
  | Refs | 2014–2128, 11454–11556 | `readrefs`, `movehead`, `rereadrefs`, `changedrefs` |
  | Main window, menus, bindings | 2374–2913, 3223–3293 | `makewindow`, `keys` |
  | Config save | 2990–3120 | `savestuff`, `config_*` |
  | File list / tree | 3293–3730 | `treeview`, `setfilelist`, `sel_flist`, `pop_flist_menu`, `flist_hl` |
  | External diff / blame | 3729–4180 | `external_diff`, `external_blame`, `show_line_source` |
  | Shell quoting | 4179–4271 | `shellquote`, `shellsplit` |
  | Views | 4286–4765 | `known_view_options` (4303), `encode_view_opts`, `decode_view_opts`, `vieweditor`, `newviewok`, `showview`, `delview` |
  | Find / highlight | 4765–5280, 6943–7210 | `do_file_hl`, `makepatterns`, `askfindhighlight`, `doesmatch`, `dofind`, `findmore`, `markmatches` |
  | Graph layout | 5278–6075 | `ordertoken`, `idcol`, `initlayout`, `layoutmore`, `make_idlist`, `layoutrows`, `optimize_rows`, `rowranges` |
  | Local changes | 5483–5604 | `dodiffindex`, `readdiffindex`, `readdifffiles` |
  | Graph drawing | 6074–6900 | `drawlineseg`, `drawparentlinks`, `drawcmittext`, `drawcmitrow`, `assigncolor`, `findcrossings`, `drawtags` |
  | Details pane / links | 7207–7500 | `appendwithlinks`, `appendrefs`, `dispneartags` |
  | Selection / history nav | 7500–7832 | `selectline`, `selnextline`, `addtohistory`, `goback`, `goforw`, `go_to_parent` |
  | Tree & blob display | 7832–7975 | `gettree`, `showfile` |
  | Diff fetch / parse / render | 7975–8800 | `diffcmd`, `gettreediffs`, `getblobdiffs`, `parseblobdiffline`, `changediffdisp`, `nextfile`, `dosearch` |
  | Fonts | 8829–8901 | `parsefont`, `fontflags`, `incrfont` |
  | Go to commit, line hover/click | 8901–9150 | `gotocommit`, `linehover`, `lineclick`, `arrowjump` |
  | Row menu actions | 9151–10210 | `rowmenu`, `markhere`, `find_common_desc`, `do_cmp_commits`, `mkpatch`, `mktag`, `writecommit`, `mkbranch`, `mvbranch`, `cherrypick`, `revert`, `resethead`, `cobranch`, `rmbranch` |
  | Ref list window | 10209–10414 | `showrefs`, `refill_reflist` |
  | Ancestry index (nearby tags) | 10414–11454 | `getallcommits`, `getallclines`, `readcache`, `writecache`, `anc_or_desc`, `desctags`, `anctags`, `descheads` |
  | Preferences | 11610–12152 | `doprefs`, `prefspage_*`, `prefsok` |
  | Date formatting / encodings | 12152–12530 | `formatdate`, `tcl_encoding`, `gitattr` |
  | Startup / defaults / argv | 12530–13031 | defaults, `config_variables`, argv parsing, initial view setup |

- **Toolchain on the dev machine:** Swift 6.4 (Xcode), macOS 27, git 2.54, and `tclsh`/`wish` 9.0.3 from Homebrew. The Tcl tools are used only for the differential-test oracle.
- **Decisions already made (see proposal):** macOS only, with AppKit doing the heavy lifting; full parity delivered in phases; git CLI only; gitk command line; one-way import of the gitk config; translations converted from the `.po` files.
- **Who implements it:** an orchestrating agent hands out tasks from `tasks.md` to smaller agents. This design therefore fixes file paths, type names and conventions up front, so tasks can be done in isolation without design discussion.

## Goals / Non-Goals

**Goals:**
- Keep the core logic (git I/O, parsing, ordering, layout, find, settings, view-option encoding) in a UI-free library. It must be fully unit-testable with `swift test` and must not import AppKit.
- Lay out the graph exactly as gitk does. Each ported algorithm is verified by differential tests against gitk's own Tcl procedures.
- Stay responsive on 1M-commit repositories: stream commits, lay out lazily, and draw only visible rows.
- Make every UI task verifiable by an agent without a human: a build, view-model tests, and a headless snapshot PNG.

**Non-Goals:**
- Linux or Windows builds, or a SwiftUI-only UI.
- Porting dead code that no UI can reach (view-membership and relation highlighting, `hlview`/`highlight_related`), Tk theming, X11 PRIMARY selection, or Windows-specific branches.
- Writing to the Tcl gitk config or to Tcl gitk's `gitk.cache`.
- Sandboxing or App Store distribution. The app must run `git` and other tools, so it ships as an unsandboxed binary.
- libgit2 or any other third-party Swift dependency.

## Decisions

### D1. Package layout (fixed; tasks refer to these paths)

```
Package.swift                      swift-tools-version:6.0, platforms: [.macOS(.v14)], defaultLocalization "en"
Sources/
  GitkCore/                        import Foundation only (no AppKit, enforced by a test)
    Git/        GitRunner.swift  GitProcess.swift  RecordSplitter.swift  GitEnvironment.swift  RepoContext.swift  GitVersion.swift
    Model/      ObjectID.swift  Commit.swift  CommitStore.swift  RefSet.swift  ViewSpec.swift
    Parsing/    RawLogParser.swift  RefParser.swift  DiffParser.swift  WordDiffParser.swift  TreeParser.swift  TextDecoder.swift  TclList.swift
    History/    VarcOrdering.swift  HistoryLoader.swift  LocalChanges.swift  ViewSession.swift
    Graph/      GraphLayout.swift  GraphRowGeometry.swift  GraphColors.swift
    Ancestry/   AncestryIndex.swift  AncestryCache.swift  NearbyRefs.swift
    Find/       FindQuery.swift  FindEngine.swift  PathPatterns.swift  ShellWords.swift
    Views/      ViewOptions.swift  ViewOptionCodec.swift
    Actions/    RepoActions.swift  PatchIDCompare.swift
    Settings/   Settings.swift  SettingsStore.swift  LegacyConfigImporter.swift  TkFont.swift  TkColor.swift  TkColorTable.swift
    CLI/        LaunchArguments.swift  StartupChecks.swift
    Util/       TclDateFormat.swift  TempFiles.swift  KeyBindings.swift  AppCommand.swift
  GitkUI/                          AppKit; depends on GitkCore
    App/        AppDelegate.swift  MainMenu.swift  L10n.swift  Snapshot.swift  LanguageOverride.swift
    Main/       MainWindowController.swift  MainSplitView.swift  KeyRouter.swift
    CommitList/ CommitListController.swift  GraphCellView.swift  RefLabelDrawing.swift  ListColumnsView.swift
    Bars/       CommitIDBar.swift  FindBar.swift  StatusBar.swift
    Details/    DetailsTextController.swift  DiffRenderer.swift  DiffControlsBar.swift  PaneSearch.swift  LinkHandling.swift
    FileList/   FileListController.swift
    Dialogs/    ViewEditorController.swift  PreferencesController.swift  TagDialog.swift  BranchDialog.swift  ResetDialog.swift
                PatchDialog.swift  WriteCommitDialog.swift  RefListWindowController.swift  AboutAndKeys.swift  Alerts.swift
    Resources/  <lang>.lproj/Localizable.strings   (generated, see D11)
  gitk-swift/   main.swift         executable: parses args via GitkCore, starts NSApplication
  gitk-core-dump/ main.swift       dev executable: prints ordering+layout JSON for a repo (used by differential tests)
  po2strings/   main.swift         dev executable: converts gitk/po/*.po → Resources/*.lproj
Tests/
  GitkCoreTests/                   one test file per Core source file, named <Type>Tests.swift
  GitkUITests/                     view-model / renderer tests (no window server needed)
  Fixtures/make-fixture.sh         builds deterministic fixture repos by name
  Oracle/oracle.tcl                runs gitk's own procs headless and emits JSON (D5)
Tools/                             snapshot.sh  regen-golden.sh  regen-l10n.sh  make-app.sh
Makefile                           build / test / snapshot / app / install targets
docs/                              smoke-test.md, architecture.md, agent-guide.md, spec-coverage.md
gitk/                              upstream reference (git submodule, pinned)
```

The executable is named `gitk-swift` so it does not clash with git's own `gitk`. Users can alias it.

### D2. Git access: `GitRunner` over `Foundation.Process`
- `GitRunner.run(_ args: [String], stdin: Data?) async throws -> GitOutput`. It returns stdout, stderr and the exit status. A non-zero exit throws `GitError(stderr:)`.
- `GitRunner.stream(_ args:, stdin:) -> GitProcess` exposes `records(separator: 0x00 or 0x0A) -> AsyncThrowingStream<Data, Error>` and `cancel()`. Cancelling sends SIGTERM to the child, which is in its own process group.
- Executables are always run with an argument array, never through a shell. The only exceptions mirror gitk exactly: `--argscmd` and the "write commit" command run under `/bin/sh -c`.
- The environment is inherited, with `GIT_TRACE` removed and `LC_ALL`/`LANG` left as they are. The working directory is the launch cwd.
- *Alternative considered: libgit2.* Rejected: it cannot reproduce all of `git log`'s revision and pathspec semantics, `--show-notes`, textconv, or `--word-diff=porcelain`.

### D3. Concurrency model
- `ViewSession` is `@MainActor`. It owns `CommitStore`, `VarcOrdering`, `GraphLayout` and `RefSet` for one view. These are plain, non-`Sendable` final classes, used only on the main actor, as in gitk's single-threaded design.
- Parsing happens off the main actor. A `HistoryLoader` task reads records, parses them with `RawLogParser` into `Sendable` `ParsedCommit` structs, and hands batches to `ViewSession.ingest(_:)`. A batch is sent at 2,000 commits or every 50 ms, whichever comes first.
- Layout is lazy, like gitk's `layoutmore`/`drawvisible`. `GraphLayout.ensureLaid(upTo: row)` is called for the visible range plus a margin.
- Every load carries a generation number. Batches from a cancelled generation are dropped, which covers the spec's "late output ignored" rule.
- Swift 6 language mode is on, with strict concurrency. No `@unchecked Sendable` without a comment explaining why.

### D4. Data representation
- `ObjectID` is a 32-byte inline value (`(UInt64, UInt64, UInt64, UInt64)` plus a length byte) holding SHA-1 or SHA-256. It is `Hashable`, has a hex initializer and `abbreviated(_:)`. There are special constants `.localUnstaged` (gitk `nullid`, `000…0`) and `.localStaged` (gitk `nullid2`, `000…1`).
- `CommitStore` interns IDs to `CommitIndex` (`Int32`) and keeps parallel arrays: parents, children per view, headline, author, date, committer, and the raw message as `Data`. Text is decoded on demand. This keeps 1M commits within a few hundred MB.
- `RefSet` holds heads, remotes, tags (peeled to commits), other refs, the main head name and the main head ID.

### D5. Port gitk's ordering and layout algorithms literally, checked by a Tcl oracle
- `VarcOrdering` ports lines 872–1600 and `GraphLayout` ports 5278–6075. Each is a proc-by-proc translation that keeps gitk's names in doc comments (for example `/// Port of gitk proc \`layoutrows\``). Tcl arrays become Swift dictionaries or arrays keyed by `CommitIndex`, and Tcl lists become `[CommitIndex]`.
- *Why literal:* the spec requires the same columns as gitk, and a reinvented algorithm would drift. A faithful translation lets agents check their work one proc at a time.
- **Oracle:** `Tests/Oracle/oracle.tcl` runs under plain `tclsh` (no Tk):
  1. It reads `gitk/gitk` and uses `info complete` to split it into top-level commands.
  2. It evaluates only the `proc` definitions, after stubbing UI procs (`mc`, `nowbusy`, `notbusy`, `drawvisible`, `drawcommits`, `show_status`, `error_popup`, `update`, `filerun`, …) and setting the globals they need.
  3. It runs `git log` synchronously on a fixture, feeds the output through `getcommitlines`, and drives `layoutmore` to the end.
  4. It prints JSON: `{rows:[{id, col, idlist:[…]}], ranges:{id:[…]}, colors:{id:n}}`.

  `gitk-core-dump` prints the same JSON from Swift. `OracleParityTests` runs both on every fixture and diffs the results. The tests are skipped when `tclsh` is missing.
- *Alternative:* golden JSON files written by hand. Rejected, because they are too error-prone for crossing-minimization logic. Golden files produced by the oracle are checked in as a fallback for CI machines without tclsh (`Tests/GitkCoreTests/Golden/*.json`).

### D6. Commit list UI: `NSTableView` with three columns
- A view-based `NSTableView` with a fixed row height (the font's line spacing) and three `NSTableColumn`s: graph+subject, author, date. Resizable columns stand in for gitk's three canvases in a paned window, and they scroll together for free.
- Column 0's cell, `GraphCellView`, draws from `GraphRowGeometry`. This is a pure core value giving, for each row:
  - line segments as (fromColumn, fromY∈{top,mid,bottom}, toColumn, toY, colorIndex, thick)
  - the dot column and dot style
  - arrows
  - ref labels
  - the x position where the text starts

  The geometry is computed in Core and unit-tested, so the cell only draws.
- Bold rows (find highlight), the selection, and the "marked" background are row attributes held by `CommitListController`.
- Horizontal scroll applies only to the first column, which sits in its own clip view with a horizontal scroller.
- *Alternative:* one custom canvas `NSView` (closer to Tk). Rejected: the table gives virtualization, accessibility, column resizing and native scrolling with momentum for free.

### D7. Details/diff pane: `NSTextView` with TextKit 1
- `NSTextView(usingTextLayoutManager: false)`, non-contiguous layout, append-only during streaming. Parsed lines from `DiffParser` (typed enum: `.fileHeader`, `.hunkHeader`, `.add`, `.remove`, `.context`, `.combined(markers:)`, `.wordDiff(tokens)`, `.binary`, `.other`) are stored in a `DiffDocument` model.
- `DiffRenderer` turns the model into attributed text for the current Diff/Old/New mode. Changing the mode re-renders from the model without fetching again.
- File section offsets are recorded so the file list can stay in sync and `f`/`b` can jump between files.
- *Alternative:* TextKit 2. Rejected for now because of known performance problems with multi-MB append-heavy documents.

### D8. Keyboard routing
- `KeyBindings` (Core) maps key descriptors to `AppCommand` values. `AppCommand` is an enum covering every command reachable from menus, keys, buttons and context menus.
- `KeyRouter` (UI) overrides `NSWindow.sendEvent`. If the first responder is not an editable `NSText`/`NSTextField` editor, it resolves unmodified letter and navigation keys through `KeyBindings`. ⌘-shortcuts come from `MainMenu` key equivalents.
- All actions go through `MainWindowController.perform(_ command: AppCommand)`. This single entry point keeps behaviour testable.

### D9. Settings and legacy import
- `Settings` is a `Codable` struct with one property per gitk config variable that we support (the names are listed in `config_variables`, gitk lines 12748–12810), plus `geometry` and `views`. Defaults come from gitk's aqua defaults (lines 12616–12730). The exception is fonts: Tk's aqua sizes (9pt Lucida Grande/Monaco) render tiny and Lucida Grande is deprecated, so the defaults are the system font at 12pt, monospaced system font at 12pt, and bold system font at 12pt.
- `SettingsStore` reads and writes `~/Library/Application Support/gitk-swift/settings.json` with `Data.write(options: .atomic)`. The `GITK_SWIFT_CONFIG_DIR` environment variable overrides the directory, which tests use.
- `LegacyConfigImporter` tokenizes with `TclList` (brace/quote/backslash rules from Tcl's list syntax), accepts only `set <name> <value>` and `set geometry(<k>) <value>`, and maps the values. `TkFont` parses `{family} size ?bold? ?italic?`. `TkColor` resolves `#rgb`/`#rrggbb` and X11/Tk colour names through `TkColorTable` (generated from Tk's `xlib/xcolors.c`).
- *Alternative:* writing back to the Tcl file. Rejected: it could clobber settings that Tcl gitk users rely on, and it ties the format to Tcl.

### D10. Date formatting
`TclDateFormat` implements the strftime subset used by Tcl's `clock format` (`%Y %m %d %H %M %S %y %b %B %a %A %e %j %p %I %z %Z %%`, plus `%c %x %X` via `DateFormatter` in the POSIX locale), with an explicit timezone offset. As in gitk's `formatdate`, if the format contains `%z` or `%Z` the commit's own offset is used; otherwise the local zone is used.

### D11. Localization pipeline
- `po2strings` (a dev executable) parses `.po` files:
  - It handles msgctxt, multiline strings and the fuzzy flag. Fuzzy and empty entries are skipped.
  - It strips `&` mnemonics from both key and value.
  - It converts `%s`/`%d`/`%n$s` into positional `%n$@`/`%n$ld`.
  - It writes `Sources/GitkUI/Resources/<lproj>/Localizable.strings` sorted by key. Output is deterministic.
  - Language folder mapping: `pt_br → pt-BR.lproj`, `pt_pt → pt-PT.lproj`, `zh_cn → zh-Hans.lproj`; others are lowercased as they are.
- The UI calls `L("<gitk msgid, verbatim, with Tcl %s/%d>", args...)`. `L()` converts the key with the same `PoConvert` placeholder function used for the catalogs (`%s`→`%n$@`, `%d`→`%n$ld`), looks the result up in `Bundle.module`, and formats it. So the source keeps gitk's exact text, and `L10nCoverageTests` can compare keys with the `.po` msgids directly. Placeholder conversion lives in the `PoConvert` library target, which `GitkUI` depends on.
- `LanguageOverride` runs first thing in `main`. It maps `LC_ALL`/`LC_MESSAGES`/`LANG` to an lproj and sets `AppleLanguages` in the process's `UserDefaults` volatile domain.

### D12. Verification hooks for agents
- **Snapshot:** `GITK_SWIFT_SNAPSHOT=/path/out.png` makes the app wait until the initial view has loaded and the selection (from `--select-commit`, if given) has been displayed. It then renders the main window into a PNG with `cacheDisplay(in:to:)` and exits with status 0. `GITK_SWIFT_SNAPSHOT_SIZE=1400x900` sets the window size. No screen-recording permission is needed. Agents check UI tasks by reading the PNG.
- **Fixtures:** `Tests/Fixtures/make-fixture.sh <name> <outdir>` builds deterministic repos with fixed author/committer dates and identities and `GIT_CONFIG_NOSYSTEM=1`. Names: `linear`, `merge-simple`, `octopus`, `criss-cross`, `many-branches` (40 parallel branches), `long-lines` (a parent 300 rows away), `renames`, `encodings` (Latin-1 commit and Shift-JIS file attribute), `tags-notes`, `sha256` (`git init --object-format=sha256`), `local-changes` (staged and unstaged edits), `conflict` (unmerged merge state), `huge` (generated on demand: 200k commits via `git fast-import`; used only by perf tests behind `GITK_PERF=1`).
- **Headless errors:** `GITK_SWIFT_HEADLESS_ERRORS=1` sends every alert (startup errors, `error_popup`, `confirm_popup`) to stderr instead of a dialog. Confirmations then take the answer from `GITK_SWIFT_CONFIRM=yes|no` (default `no`). This lets CLI and action tasks be checked from a shell.
- **Snapshot wrapper:** `Tools/snapshot.sh <fixture> <out.png> [gitk-swift args…]` builds the fixture, runs the app in it with `GITK_SWIFT_SNAPSHOT`, and prints the PNG path.
- **Core test helper:** `FixtureRepo.make("<name>")` builds each fixture once per test process, under `$TMPDIR/gitk-swift-fixtures/<name>`.

### D13. Repository and licensing hygiene
- Convert `gitk/` into a git submodule pointing at `https://github.com/j6t/gitk` and pinned to `6fc42f7`. This gives a reproducible oracle and `.po` source.
- Add `COPYING` (GPLv2) and `LICENSE` notes. Every Swift source file gets the header `// SPDX-License-Identifier: GPL-2.0-or-later` and a line crediting gitk (Paul Mackerras et al.).
- `.gitignore`: `.build/`, `.swiftpm/`, `*.xcodeproj`, `/out/`.

### D14. Packaging
`swift build -c release` produces `gitk-swift`, which runs from the terminal as a regular foreground app (cli-launch "Foreground activation"). It calls `NSApplication.shared.setActivationPolicy(.regular)` and `activate()`, and resources come from the SwiftPM resource bundle next to the binary. `Tools/make-app.sh` also wraps it into `gitk-swift.app` with an `Info.plist` and icon. `make install PREFIX=…` installs the binary and its resource bundle.

## Risks / Trade-offs

- **[Risk] The Tcl oracle cannot run gitk's procs headless because they depend on Tk.** → Mitigation: stubs are limited to procs that do UI work. A spike task (2.4) proves it on `linear` and `merge-simple` before any layout porting starts. If the spike fails, fall back to golden JSON taken from a `wish` instrumentation run (same script under `wish` with the window withdrawn).
- **[Risk] Smaller agents translate Tcl idioms wrongly** (`lsearch`, `lrange` end-indexes, `incr` on unset vars, `upvar`). → Mitigation: `docs/agent-guide.md` contains a Tcl→Swift idiom table. Each ported proc has its own oracle-backed test, and ports are split into tasks of at most about 150 Tcl lines.
- **[Risk] Memory use and time to first paint on 1M-commit repos.** → Mitigation: interned indices and lazy text decoding (D4), batched ingest (D3), lazy layout, and a perf test on the generated `huge` fixture with budgets (first rows in under 1.5s, 200k commits fully loaded in under 10s, RSS under 1.5GB).
- **[Risk] Single-letter shortcuts fire while the user is typing.** → Mitigation: `KeyRouter` checks the first responder (D8), with an explicit test matrix.
- **[Trade-off] Default fonts differ from gitk's (D9).** This is a visible deviation, accepted because the Tk aqua defaults render too small. Imported fonts are honoured exactly.
- **[Trade-off] The view-highlight and relation-highlight code is not ported** because nothing in gitk's UI can reach it.
- **[Risk] TextKit 1 with very large diffs.** → Mitigation: streaming append, plus a cap that shows "diff truncated — N more lines" past 200k lines, with a button to load the rest. This deviation is recorded in `docs/architecture.md`.
- **[Risk] GPL obligations.** → Mitigation: D13 headers and COPYING. This stays a standalone project and is never sent upstream.

## Migration Plan

Not applicable for deployment. This is a new binary installed alongside Tcl gitk. Users start it as `gitk-swift`, and their gitk settings are imported on first launch. Rollback means deleting the binary and `~/Library/Application Support/gitk-swift`; the legacy config is never touched.

## Open Questions

- App icon artwork. Packaging uses a placeholder until one is provided, and nothing else depends on it.
- Whether to register a `gitk` alias in `make install`. This can be decided at packaging time; the default is no alias.
