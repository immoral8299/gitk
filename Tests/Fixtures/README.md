# Fixture repositories

`make-fixture.sh <name> <outdir>` builds `<outdir>/<name>` deterministically:

- fixed identities: author "Alice Author", committer "Carol Committer"
- the clock starts at 2020-01-01T00:00:00Z and advances 60 seconds per commit
- `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null`, so no user config is read

`make-fixture.sh --list` prints the names. Tests build fixtures with the
`FixtureRepo.make(_:)` helper (`Tests/GitkCoreTests/Support/FixtureRepo.swift`).
It caches each fixture under `$TMPDIR/gitk-swift-fixtures/<script-hash>/`, so a
fixture is rebuilt automatically whenever this script changes.

If you change a fixture, update its row below. The values must be identical on
every run.

| Name | What it exercises | `git rev-parse HEAD` | `git rev-list --all --count` |
|---|---|---|---|
| `linear` | 10 commits on `main` | `b7729902a3f81cc7da12ad56b4af698ee6ad444c` | 10 |
| `merge-simple` | `feature` (2 commits off m1) merged into `main` | `f27c29fa5ea3afbdb540a7475337378f2957d577` | 7 |
| `octopus` | 3-parent merge of `b1` and `b2` (HEAD~1) | `c945a83731862f6bd5090c6e792479c5fcd13232` | 6 |
| `criss-cross` | `x`/`y` merge each other, then both merge into `main` | `5e26926cc99a659f0fe8eaa623105773d3b97605` | 10 |
| `many-branches` | 40 branches `b01`–`b40`, merged one by one into `main` | `2d613f11ab5679b193386d332b9456c30907bb47` | 121 |
| `long-lines` | early `side` commit merged after 300 main commits | `e6ce0a438bcbaa4971271964e6487646af316dea` | 303 |
| `renames` | rename with an edit (`widget.c → gadget.c`), delete, mode change | `20a197dc624bdf764188a7dab39a0e6925056964` | 3 |
| `encodings` | ISO-8859-1 commit (HEAD~2, author `José Muñoz`), Shift-JIS `sjis.txt` with `encoding` attribute | `9493c064e5c30b77541141b249745174b1b29dfd` | 4 |
| `tags-notes` | lightweight `v0.1`; annotated `v1.0`, `v2.0`; `t1`–`t4` on one commit; note on commit 5; `release`, `origin/main`, `origin/release` | `b9060be228b8bba1efda611b2ff7c98eb76192c7` | 9 (8 + notes commit) |
| `sha256` | SHA-256 object format with a merge | `eb4823297e6cacabfef8b93e7cb96f2353a3c8d8c4e90b27a2898b8e1de9d7e8` | 5 |
| `local-changes` | staged edit to `a.txt`, unstaged edit to `b.txt` | `bc331ab057015993835b0634eea6716440cf0a5f` | 3 |
| `conflict` | merge of `theirs` stopped with a conflict in `conflict.txt` | `422d0a61358da657b9bce9a1ed72c6d32966df10` | 4 |
| `random-dag` | 1,500 generated commits (seeded LCG in awk, `git fast-import`): branches `main`, `b1`–`b5` plus 111 `fork/<n>` refs; 575 merges (480 with 2 parents, 95 with 3) whose extra parents lie within the previous 80 commits; up to 29 lanes wide. Oracle golden uses `--all` | `57449d57b6681e5287e71abf05fdde7b277cb46b` | 1500 |
| `huge` | 200,000 generated commits (`make-huge.sh`): main line, a side commit every 50 commits merged back (3,999 merges); perf tests only | `08dc3dcba3385c84dd25064b842bd9667114f6b9` | 200000 |

Build times on an M-series Mac: most fixtures take 1–2 s; `many-branches` takes about 15 s,
`long-lines` about 35 s and `huge` about 13 s.
