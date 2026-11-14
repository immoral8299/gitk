# gitk-swift

A native macOS rewrite of [gitk](https://github.com/j6t/gitk), the Tcl/Tk git
repository browser, in Swift. It keeps gitk's workflow: the same command line,
the same panes, the same keys, and your saved views.

```bash
gitk-swift                     # history of the current repository
gitk-swift v1.0..v2.0 -- src/  # a revision range, limited to paths
```

> Status: under construction. The plan lives in
> `openspec/changes/rewrite-gitk-in-swift/` (proposal, specs, design, tasks).

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or the Swift.org toolchain)
- `git` 2.20 or later at runtime
- Optional: `tclsh` 9 (e.g. Homebrew `tcl-tk`) for differential tests against gitk

## Build and test

```bash
make build     # swift build
make test      # swift test
make release   # swift build -c release
```

## Run against any repository

Pass the repository as the first argument, or start the app inside it as with
gitk (it runs `git rev-parse --git-dir` in the working directory). Starting in
a subdirectory or a linked worktree works too.

```bash
swift run gitk-swift ~/code/any-repo                  # that repository's history
swift run gitk-swift ~/code/any-repo --all            # every branch and tag
swift run gitk-swift ~/code/any-repo v1.0..v2.0 -- src/

bin="$(swift build --show-bin-path)/gitk-swift"
cd ~/code/any-repo && "$bin"                          # gitk style: the working directory
cd ~/code/any-repo && "$bin" src/                     # a subdirectory is a path limit
```

The first argument is taken as the repository only when it is the top level
of a repository (or the working directory is not in one). A subdirectory of
the current repository stays a path limit, as in `gitk src/`. `swift run`
needs the gitk-swift checkout as its working directory, or
`--package-path /path/to/gitk-swift`.

After `make release`, the binary is at
`"$(swift build -c release --show-bin-path)/gitk-swift"`.

Notes:

- The executable is a plain binary, not an `.app` bundle, so launch it from a
  terminal; it activates itself and shows its own window. For a PNG of the
  window instead, see `Tools/snapshot.sh` in
  [docs/agent-guide.md](docs/agent-guide.md).
- Starting it from a terminal blocks that terminal until the window closes. Add
  `&` to keep the terminal, for example `cd /path/to/repo && "$bin" &`.
- Everything after the binary is gitk's command line: revisions, `--` followed
  by paths, `--select-commit=<rev>`, `--argscmd=<command>`. Unknown flags such
  as `--all` are passed to `git rev-list`, as in gitk.
- Settings live in `~/Library/Application Support/gitk-swift/settings.json`.
  Set `GITK_SWIFT_CONFIG_DIR` to use another directory, which is also how to
  run the app without touching your real preferences.

## Repository layout

| Path | Contents |
|---|---|
| `Sources/GitkCore` | UI-free core: git processes, parsing, ordering, graph layout, settings |
| `Sources/GitkUI` | AppKit user interface |
| `Sources/gitk-swift` | The executable |
| `Tests/` | Unit tests, fixture-repository scripts, the Tcl oracle |
| `po/` | Translation catalogs copied from gitk |
| `gitk/` | Upstream gitk (git submodule, pinned). Read-only reference, never built |
| `docs/` | Agent guide, architecture notes, spec coverage |

After cloning, fetch the reference submodule with `git submodule update --init`.

## Credits and license

gitk was written by Paul Mackerras and is maintained by the Git community.
Because this project ports gitk's code and translations, it is distributed
under the GNU General Public License, version 2 or (at your option) any later
version. See [COPYING](COPYING).

This is an independent project. It is not affiliated with or submitted to the
upstream gitk or Git projects.
