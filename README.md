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
