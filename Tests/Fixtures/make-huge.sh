#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
#
# Generates the `huge` perf fixture: exactly 200,000 commits, built with
# `git fast-import` so it takes seconds instead of hours.
#
#   make-huge.sh <repo-dir> [commit-count]
#
# Shape: a long `main` line. Every 50th commit is a side commit forked 20
# commits back (on refs/heads/side), and the next main commit merges it. That
# gives regular branches and merges with long-ish lines. Dates start at
# 2020-01-01T00:00:00Z and advance 60s per commit, so output is deterministic.
# Normally called through make-fixture.sh, which sets up the git environment.

set -euo pipefail

REPO=${1:?usage: make-huge.sh <repo-dir> [commit-count]}
COUNT=${2:-200000}

rm -rf "$REPO"
mkdir -p "$REPO"
git init -q -b main "$REPO"
cd "$REPO"

awk -v n="$COUNT" 'BEGIN {
    epoch = 1577836800
    lastmain = 0
    for (i = 1; i <= n; i++) {
        when = epoch + i * 60
        if (i % 50 == 0) {
            # side commit forked from main commit i-20
            printf "commit refs/heads/side\nmark :%d\n", i
            printf "author Bob Branch <bob@example.com> %d +0000\n", when
            printf "committer Carol Committer <carol@example.com> %d +0000\n", when
            msg = sprintf("side commit %d", i)
            printf "data %d\n%s\n", length(msg), msg
            printf "from :%d\n", i - 20
            fdata = sprintf("side %d\n", i)
            printf "M 644 inline side/s%d.txt\ndata %d\n%s\n", i % 10, length(fdata), fdata
        } else {
            printf "commit refs/heads/main\nmark :%d\n", i
            printf "author Alice Author <alice@example.com> %d +0000\n", when
            printf "committer Carol Committer <carol@example.com> %d +0000\n", when
            if (i > 1 && (i - 1) % 50 == 0) {
                msg = sprintf("Merge side commit %d", i - 1)
            } else {
                msg = sprintf("main commit %d", i)
            }
            printf "data %d\n%s\n", length(msg), msg
            if (lastmain > 0) printf "from :%d\n", lastmain
            if (i > 1 && (i - 1) % 50 == 0) printf "merge :%d\n", i - 1
            fdata = sprintf("main %d\n", i)
            printf "M 644 inline f%d.txt\ndata %d\n%s\n", i % 100, length(fdata), fdata
            lastmain = i
        }
    }
}' | git fast-import --quiet

git reset -q --hard main
echo "$REPO"
