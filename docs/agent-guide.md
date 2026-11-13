# Agent guide

Read this before you pick up a task from
`openspec/changes/rewrite-gitk-in-swift/tasks.md`. Together with `design.md`
it covers everything a task leaves implicit. If something is still unclear,
stop and report back instead of guessing.

## Before you start

1. Read your task's line in `tasks.md`, plus its **Files**, **Port**, **Needs**
   and **Spec** sub-bullets.
2. Read the referenced spec scenarios in
   `openspec/changes/rewrite-gitk-in-swift/specs/<capability>/spec.md`.
3. Read the design sections the task depends on (D1 is the file layout; D3 is
   the concurrency model).
4. If the task has a **Port** range, read those lines of `gitk/gitk` in full
   before writing any Swift.
5. Only touch the files your task lists. If you find you need another file,
   say so in your report.

## File header

Every new Swift file, and every new shell or Tcl script (with `#` instead of
`//`), starts with:

```swift
// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
```

In `Package.swift` the header goes after the `// swift-tools-version` line,
which must stay first.

## Layout and naming

- Paths and type names come from design.md D1. Do not create new top-level
  folders or targets.
- One primary type per file, and the file is named after the type
  (`RawLogParser.swift` holds `RawLogParser`).
- **GitkCore** imports Foundation only. `CoreIsolationTests` fails on AppKit,
  SwiftUI, Cocoa or UIKit imports.
- **GitkUI** holds AppKit code. Put logic that can be tested without a window
  in GitkCore and keep UI classes thin.
- Tests go in `Tests/GitkCoreTests/<Type>Tests.swift` (or `GitkUITests`). The
  suite is a `@Suite struct <Type>Tests`, so `swift test --filter <Type>Tests`
  selects it.
- Mark things `public` only when another target needs them. Tests use
  `@testable import`.

## Porting from gitk

- Port **behaviour**, not Tk calls. Drawing, widgets and `after`/`filerun`
  scheduling become AppKit views and Swift concurrency (design D3, D6, D7).
- Algorithms (ordering, layout, colours, ancestry) are ported **literally**:
  same control flow, same tie-breaking, same off-by-one behaviour (design D5).
  Do not "improve" them. The oracle tests compare row by row.
- Put a doc comment on each ported function naming its source:

  ```swift
  /// Port of gitk proc `layoutrows` (gitk/gitk 5733–5840).
  ```

- Keep gitk's variable names as Swift property names (camelCased) when they
  carry algorithm state (`varcstart` → `varcStart`, `rowidlist` → `rowIDList`),
  so the code can be read side by side with the Tcl.
- Messages shown to users must be gitk's exact English text (it is the
  translation key; see "Strings").
- When gitk and the spec disagree, the spec wins. Write the difference down in
  `docs/architecture.md` under "Deviations".

## Tcl → Swift idioms

| Tcl | Meaning | Swift |
|---|---|---|
| `lindex $l $i` | element, or `""` if out of range (no error) | `l.indices.contains(i) ? l[i] : nil` |
| `lindex $l end`, `end-1` | last, second to last | `l.last`, `l.count >= 2 ? l[l.count - 2] : nil` |
| `lrange $l a b` | **inclusive** a…b, indexes clamped, empty if a > b | `a <= b ? Array(l[max(a, 0)...min(b, l.count - 1)]) : []` (also guard `l.isEmpty`) |
| `lsearch -exact $l x` | index or `-1` | `l.firstIndex(of: x) ?? -1` |
| `linsert $l i x` / `lreplace $l a b ...` | copy with insert/replace | `var c = l; c.insert(x, at: i)` / `c.replaceSubrange(a...b, with: ...)` |
| `lappend v x` | appends; creates `v` if unset | `dict[k, default: []].append(x)` |
| `incr v ?n?` | adds; creates `v` as 0 if unset (Tcl ≥ 8.5) | `dict[k, default: 0] += n` |
| `info exists a($k)` | key present | `dict[k] != nil` |
| `unset a($k)`, `array unset a` | remove | `dict[k] = nil`, `dict.removeAll()` |
| `set a($view,$id)` | array keyed by a composite string | per-view struct property, or a dictionary keyed by `CommitIndex` |
| `string range $s a b` | **inclusive** end index | `s[s.index(s.startIndex, offsetBy: a)...s.index(s.startIndex, offsetBy: b)]` |
| `regexp -indices` | `{start end}` with an **inclusive** end | Swift ranges are half-open; add 1 |
| `expr {$a / $b}` (ints) | division that **floors** toward −∞ | `a >= 0 ? a / b : -((-a + b - 1) / b)` for b > 0, not plain `/` |
| `expr {$a % $b}` | result takes the **sign of the divisor** | `((a % b) + b) % b` for b > 0 |
| `lsort` | ASCII string sort by default; `-integer`, `-decreasing` | `sorted()` on `String` (byte order) or `Int` |
| `foreach {a b} $l {}` | iterate pairs | `stride(from: 0, to: l.count, by: 2)` |
| `""` used as "none" | sentinel | `Optional` |
| `global x` / `upvar #0 x` | shared state | a property on the owning class |
| `catch {...}` | swallow errors | `try?` only where gitk ignores the error; otherwise propagate |

## Swift conventions

- Swift 6 language mode with strict concurrency (the package sets
  `swiftLanguageModes: [.v6]`). Fix warnings rather than suppressing them.
- `@unchecked Sendable` only with a comment explaining why it is safe.
- The concurrency model is design D3. Algorithm state lives on `@MainActor`
  classes; parsing and process I/O run off the main actor and pass `Sendable`
  structs across.
- No third-party packages. Use only Foundation, AppKit, and Swift Testing
  (`import Testing`).
- Never start a shell, except where gitk does (`--argscmd`, the "write commit"
  command). Run git through `GitRunner` with an argument array.
- No force-unwraps on data that comes from git output. Treat malformed input as
  an error or skip it.

## Tests, fixtures and the oracle

- `swift test` runs everything; `swift test --filter <Suite>` runs one suite.
- Fixture repositories: `FixtureRepo.make("<name>")` gives a shared, read-only
  checkout; `FixtureRepo.makeCopy("<name>")` gives a private copy you may
  change. Names and their expected HEADs are in `Tests/Fixtures/README.md`. To
  build one by hand, run `Tests/Fixtures/make-fixture.sh <name> <outdir>`.
- Never hard-code paths under `/tmp` or the user's home in tests. Use
  `FileManager.default.temporaryDirectory`.
- Oracle (design D5): `tclsh Tests/Oracle/oracle.tcl --repo <dir> [args]` runs
  gitk's own Tcl procs and prints JSON. In Swift, `OracleRunner` uses it when
  `tclsh` is installed and falls back to `Tests/GitkCoreTests/Golden/*.json`
  otherwise. Regenerate the golden files with `Tools/regen-golden.sh`, and
  never edit them by hand.
- Performance tests run only with `GITK_PERF=1` and in release
  (`swift test -c release`).

## UI verification

- Snapshot: `Tools/snapshot.sh <fixture> /tmp/out.png [gitk-swift args]` runs
  the app in that fixture, saves a PNG of the main window and exits. Read the
  PNG and check it against what the task describes. Window size:
  `GITK_SWIFT_SNAPSHOT_SIZE=1400x900`.
- Headless errors: `GITK_SWIFT_HEADLESS_ERRORS=1` prints alerts to stderr
  instead of showing dialogs. `GITK_SWIFT_CONFIRM=yes|no` answers
  confirmations.
- Settings isolation: point `GITK_SWIFT_CONFIG_DIR` at a temp dir so you never
  read or write the real settings.
- These hooks arrive with tasks 9.2–9.4. Before that, verify UI code by
  building it and testing the view model.

## Strings and localization

- Every user-visible string goes through `L("<exact gitk msgid>", args...)`.
- Use gitk's English text exactly as it appears inside `[mc "..."]` in
  `gitk/gitk`, without the `&` mnemonic marker. That text is the key that
  finds the translations.
- Placeholders: write `%@` for strings and `%ld` for integers, in gitk's
  order. The `.po` converter maps gitk's `%s`/`%d` to these.
- A new string with no gitk equivalent is allowed only if you list it under
  "New strings" in `docs/architecture.md`.

## Commits

- Make one commit per task, with the message `gitk-swift: <task ID> <summary>`
  (for example `gitk-swift: 2.1 ObjectID`).
- Stage only the files your task lists, plus its ticked checkbox in `tasks.md`
  and its rows in `docs/spec-coverage.md`. Never use `git add -A` or
  `git commit -a`: other agents may be editing the same tree.
- Never commit build output, fixture repositories or snapshots, except the
  ones a task explicitly lists (such as `docs/smoke/*.png`).

### Worktree runs dispatched by the orchestrator

When the orchestrator gives you a task in an isolated git worktree:

- Work and commit only inside your worktree. Never write to the main checkout.
- Do **not** edit `tasks.md` or `docs/spec-coverage.md`. Your report gives the
  covered scenarios and their test names, and the orchestrator updates both
  files when it cherry-picks your commits.
- The `gitk/` submodule is not checked out in a new worktree. To read gitk
  source, use the main checkout's copy (the path is in your prompt). If a task
  needs `gitk/gitk` at its repo-relative path (oracle tasks), run
  `git submodule update --init gitk` inside your worktree first.
- Each commit's message is `gitk-swift: <task ID> <summary>`, as above.
## Definition of done

A task is done when all of the following hold:

1. Its own **Verify** passes, and you have reported the command and its output.
2. `swift build` passes with no new warnings, and `swift test` passes.
3. Every new file has the header; every ported function has its
   "Port of gitk proc" comment.
4. Each spec scenario the task covers is updated in `docs/spec-coverage.md`
   (the test or snapshot that proves it, with status `covered`).
5. Its checkbox in `tasks.md` is ticked (`- [x]`), and the task is committed
   (see "Commits").
