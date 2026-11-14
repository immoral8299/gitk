#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
#
# Builds deterministic fixture repositories for tests (design D12).
#
#   make-fixture.sh <name> <outdir>     creates <outdir>/<name> (replacing it)
#   make-fixture.sh --list              prints the available fixture names
#
# Every commit gets a fixed identity and a timestamp that starts at
# 2020-01-01T00:00:00Z and increases by 60 seconds per commit, so each
# fixture's object IDs are identical on every run and every machine.
# Expected HEADs and commit counts are listed in Tests/Fixtures/README.md.

set -euo pipefail

FIXTURES="linear merge-simple octopus evil-octopus criss-cross many-branches long-lines renames encodings tags-notes sha256 local-changes conflict random-dag huge"

usage() {
    echo "usage: $0 <name> <outdir> | --list" >&2
    echo "names: $FIXTURES" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
if [[ $1 == --list ]]; then
    tr ' ' '\n' <<<"$FIXTURES"
    exit 0
fi
[[ $# -eq 2 ]] || usage
NAME=$1
OUTDIR=$2
case " $FIXTURES " in *" $NAME "*) ;; *) echo "unknown fixture: $NAME" >&2; usage ;; esac

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# --- isolated, deterministic git environment --------------------------------
SANDBOX_HOME=$(mktemp -d "${TMPDIR:-/tmp}/gitk-fixture-home.XXXXXX")
trap 'rm -rf "$SANDBOX_HOME"' EXIT
export HOME=$SANDBOX_HOME
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Alice Author" GIT_AUTHOR_EMAIL="alice@example.com"
export GIT_COMMITTER_NAME="Carol Committer" GIT_COMMITTER_EMAIL="carol@example.com"
export TZ=UTC LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_TRACE

EPOCH=1577836800 # 2020-01-01T00:00:00Z
TICK=0

# Advances the clock by one minute and exports it as author+committer date.
tick() {
    TICK=$((TICK + 1))
    local when="$((EPOCH + TICK * 60)) +0000"
    export GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when"
}

# init [extra git-init args...]: fresh repo at $REPO on branch main.
init() {
    rm -rf "$REPO"
    mkdir -p "$REPO"
    git init -q -b main "$@" "$REPO"
    cd "$REPO"
    git config commit.gpgsign false
    git config tag.gpgsign false
    git config core.autocrlf false
}

# commit <message> [file] [content]: append (or write) content to a file and commit.
commit() {
    local msg=$1 file=${2:-file.txt} content=${3:-$1}
    tick
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$content" >>"$file"
    git add -- "$file"
    git commit -q -m "$msg"
}

# merge <message> <branch...>: --no-ff merge with a fixed timestamp.
merge() {
    local msg=$1; shift
    tick
    git merge -q --no-ff --no-edit -m "$msg" "$@"
}

REPO="$OUTDIR/$NAME"
mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)
REPO="$OUTDIR/$NAME"

case $NAME in

linear)
    # 10 commits on main, one file per commit plus a growing file.txt.
    init
    for i in $(seq 1 10); do
        printf 'file %d\n' "$i" >"f$i.txt"
        git add "f$i.txt"
        commit "Linear commit $i"
    done
    ;;

merge-simple)
    # main: m1 m2 m3 ... ; feature branches off m1 with 2 commits; merged into main.
    init
    commit "m1: initial" main.txt
    commit "m2: main work" main.txt
    git checkout -q -b feature HEAD~1
    commit "f1: feature work" feature.txt
    commit "f2: more feature work" feature.txt
    git checkout -q main
    commit "m3: more main work" main.txt
    merge "Merge branch 'feature'" feature
    commit "m4: after merge" main.txt
    ;;

octopus|evil-octopus)
    # A three-parent (octopus) merge of b1 and b2 into main.
    init
    commit "base" base.txt
    git checkout -q -b b1
    commit "b1 work" b1.txt
    git checkout -q main
    git checkout -q -b b2
    commit "b2 work" b2.txt
    git checkout -q main
    commit "main work" main.txt
    merge "Octopus merge of b1 and b2" b1 b2
    if [[ $NAME == evil-octopus ]]; then
        printf 'evil line\n' >>base.txt
        git add base.txt
        tick
        git commit -q --amend --no-edit
    else
        commit "after octopus" main.txt
    fi
    ;;

criss-cross)
    # x and y merge each other (criss-cross), then both merge into main.
    init
    commit "base" base.txt
    git branch x
    git branch y
    git checkout -q x
    commit "x1" x.txt
    git checkout -q y
    commit "y1" y.txt
    git checkout -q x
    merge "x2: merge y1 into x" y~0
    git checkout -q y
    merge "y2: merge x1 into y" x~1
    git checkout -q x
    commit "x3" x.txt
    git checkout -q y
    commit "y3" y.txt
    git checkout -q main
    commit "main work" main.txt
    merge "Merge x" x
    merge "Merge y" y
    ;;

many-branches)
    # 40 branches b01..b40 off a common base, commits interleaved in time,
    # then merged into main one by one, so 40 lines run in parallel.
    init
    commit "base" base.txt
    for round in 1 2; do
        for i in $(seq -w 1 40); do
            if [[ $round == 1 ]]; then git checkout -q -b "b$i" main; else git checkout -q "b$i"; fi
            commit "b$i commit $round" "b$i.txt"
        done
    done
    git checkout -q main
    for i in $(seq -w 1 40); do
        merge "Merge b$i" "b$i"
    done
    ;;

long-lines)
    # A side commit made early, merged after 300 main commits, so the merge's
    # second-parent line spans ~300 rows (drawn truncated with arrows).
    init
    commit "base" base.txt
    git checkout -q -b side
    commit "side: early work" side.txt
    git checkout -q main
    for i in $(seq 1 300); do
        commit "main $i" main.txt
    done
    merge "Merge long-lived side branch" side
    ;;

renames)
    # A rename with small edits, a copy, a delete and a mode change.
    init
    {
        echo "/* widget.c */"
        for i in $(seq 1 40); do echo "int widget_fn_$i(void) { return $i; }"; done
    } >widget.c
    printf 'remove me\n' >old.txt
    printf '#!/bin/sh\necho hi\n' >tool.sh
    git add widget.c old.txt tool.sh
    commit "add widget, old, tool" README "readme"
    git mv widget.c gadget.c
    sed -i.bak 's/widget_fn_7/gadget_fn_7/' gadget.c && rm gadget.c.bak
    git add gadget.c
    commit "rename widget.c to gadget.c with a small edit" README "rename"
    git rm -q old.txt
    chmod +x tool.sh
    git add tool.sh
    commit "delete old.txt, make tool.sh executable" README "delete"
    ;;

encodings)
    # A Latin-1 encoded commit, and a Shift-JIS file declared in .gitattributes.
    init
    commit "UTF-8 commit: café" notes.txt
    git config i18n.commitEncoding ISO-8859-1
    tick
    printf 'latin1\n' >>notes.txt
    git add notes.txt
    GIT_AUTHOR_NAME=$(printf 'Jos\351 Mu\361oz') \
        git commit -q -m "$(printf 'Latin-1 message: se\361or, fa\347ade')"
    git config --unset i18n.commitEncoding
    printf 'sjis.txt encoding=shift_jis\n' >.gitattributes
    printf '日本語のテキスト\n二行目\n' | iconv -f UTF-8 -t SHIFT_JIS >sjis.txt
    git add .gitattributes sjis.txt
    commit "add Shift-JIS file" notes.txt
    printf '三行目\n' | iconv -f UTF-8 -t SHIFT_JIS >>sjis.txt
    git add sjis.txt
    commit "edit Shift-JIS file" notes.txt
    ;;

tags-notes)
    # Lightweight and annotated tags, >3 tags on one commit, a note,
    # an extra branch and a remote-tracking ref.
    init
    for i in $(seq 1 8); do commit "commit $i"; done
    tick
    git tag v0.1 HEAD~6                                  # lightweight, commit 2
    git tag -a v1.0 -m "Release 1.0" HEAD~4              # annotated, commit 4
    tick
    git tag -a v2.0 -m "Release 2.0" HEAD~1              # annotated, commit 7
    git tag t1 HEAD~2; git tag t2 HEAD~2; git tag t3 HEAD~2; git tag t4 HEAD~2  # commit 6
    tick
    git notes add -m "A note on commit 5" HEAD~3
    git branch release HEAD~4
    git update-ref refs/remotes/origin/main HEAD
    git update-ref refs/remotes/origin/release HEAD~4
    ;;

sha256)
    # SHA-256 object format with a merge.
    init --object-format=sha256
    commit "s1" a.txt
    git checkout -q -b topic
    commit "t1" t.txt
    git checkout -q main
    commit "s2" a.txt
    merge "Merge topic" topic
    commit "s3" a.txt
    ;;

local-changes)
    # Three commits, then a staged edit (a.txt) and an unstaged edit (b.txt).
    init
    commit "c1" a.txt
    commit "c2" b.txt
    commit "c3" a.txt
    printf 'staged change\n' >>a.txt
    git add a.txt
    printf 'unstaged change\n' >>b.txt
    ;;

conflict)
    # A merge stopped with a conflict in conflict.txt (MERGE_HEAD present).
    init
    commit "base" conflict.txt "line"
    commit "unrelated" other.txt
    git checkout -q -b theirs HEAD~1
    printf 'theirs\n' >conflict.txt
    git add conflict.txt
    commit "theirs edits conflict.txt" theirs.txt
    git checkout -q main
    printf 'ours\n' >conflict.txt
    git add conflict.txt
    commit "ours edits conflict.txt" ours.txt
    tick
    if git merge -q --no-edit theirs >/dev/null 2>&1; then
        echo "conflict fixture: merge unexpectedly succeeded" >&2
        exit 1
    fi
    ;;

random-dag)
    # 1,500 generated commits (seeded LCG, no $RANDOM): six branches main,
    # b1..b5 grow side by side, about 8% of commits fork onto their own
    # refs/heads/fork/<n>, and about 40% of commits carry 1-2 extra parents
    # chosen among the previous 80 commits. Every commit is reachable from a
    # ref, so `--all` sees all of them. Dates: 2020-01-01T00:00:00Z + 60s*n.
    init
    awk 'BEGIN {
        n = 1500
        epoch = 1577836800
        seed = 20200101
        split("main b1 b2 b3 b4 b5", bname, " ")
        for (i = 1; i <= n; i++) {
            # Park-Miller LCG; seed * 16807 stays below 2^46, so it is exact.
            seed = (seed * 16807) % 2147483647
            r1 = int(seed * 100 / 2147483647)
            seed = (seed * 16807) % 2147483647
            r2 = int(seed * 6 / 2147483647) + 1
            seed = (seed * 16807) % 2147483647
            r3 = int(seed * 100 / 2147483647)
            seed = (seed * 16807) % 2147483647
            r4 = int(seed * 30 / 2147483647)
            nparents = 0
            fork = 0
            if (i == 1) {
                ref = "refs/heads/main"
                r2 = 1
            } else if (tip[r2] == 0) {
                # first commit of a branch: start it at a recent commit
                ref = "refs/heads/" bname[r2]
                nparents = 1
                par[1] = i - 1 - (r4 % (i - 1 < 30 ? i - 1 : 30))
            } else if (r1 < 8) {
                # fork: a new ref whose parent is a recent commit
                ref = "refs/heads/fork/" i
                fork = 1
                nparents = 1
                par[1] = i - 1 - (r4 % (i - 1 < 30 ? i - 1 : 30))
            } else {
                ref = "refs/heads/" bname[r2]
                nparents = 1
                par[1] = tip[r2]
            }
            if (i > 1 && r3 < 40) {
                # extra parents among the previous 80 commits
                seed = (seed * 16807) % 2147483647
                extra = 1 + (int(seed * 100 / 2147483647) < 15 ? 1 : 0)
                for (e = 0; e < extra; e++) {
                    seed = (seed * 16807) % 2147483647
                    back = int(seed * (i - 1 < 80 ? i - 1 : 80) / 2147483647)
                    q = i - 1 - back
                    dup = 0
                    for (k = 1; k <= nparents; k++) if (par[k] == q) dup = 1
                    if (!dup) {
                        nparents++
                        par[nparents] = q
                    }
                }
            }
            when = epoch + i * 60
            printf "commit %s\nmark :%d\n", ref, i
            printf "author Alice Author <alice@example.com> %d +0000\n", when
            printf "committer Carol Committer <carol@example.com> %d +0000\n", when
            msg = sprintf("random commit %d", i)
            printf "data %d\n%s\n", length(msg), msg
            if (nparents > 0) printf "from :%d\n", par[1]
            for (k = 2; k <= nparents; k++) printf "merge :%d\n", par[k]
            fdata = sprintf("commit %d\n", i)
            printf "M 644 inline f%d.txt\ndata %d\n%s\n", i % 7, length(fdata), fdata
            if (!fork) tip[r2] = i
        }
    }' | git fast-import --quiet
    git reset -q --hard main
    ;;

huge)
    exec "$SCRIPT_DIR/make-huge.sh" "$REPO"
    ;;
esac

echo "$REPO"
