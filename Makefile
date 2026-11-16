# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
#
#   make build                  debug build
#   make test                   run all tests
#   make release                optimized build
#   make snapshot FIXTURE=linear OUT=/tmp/s.png [ARGS="..."]
#                               headless PNG of the main window (needs task 9.4)
#   make fixture NAME=linear OUT=/tmp/fx
#                               build one fixture repository
#   make app                    out/gitk (Native).app (Tools/make-app.sh)
#   make install PREFIX=/usr/local
#                               $(PREFIX)/bin/gitk-swift plus its resource bundle
#   make clean                  remove build output

SWIFT ?= swift
FIXTURE ?= linear
OUT ?=
ARGS ?=
NAME ?=
PREFIX ?= /usr/local

.PHONY: all build test release snapshot fixture app install clean

all: build

build:
	$(SWIFT) build

test:
	$(SWIFT) test

release:
	$(SWIFT) build -c release

snapshot:
	@test -n "$(OUT)" || { echo "usage: make snapshot FIXTURE=<name> OUT=<file.png> [ARGS=...]" >&2; exit 2; }
	@test -x Tools/snapshot.sh || { echo "Tools/snapshot.sh does not exist yet (task 9.4)" >&2; exit 2; }
	Tools/snapshot.sh $(FIXTURE) $(OUT) $(ARGS)

fixture:
	@test -n "$(NAME)" -a -n "$(OUT)" || { echo "usage: make fixture NAME=<name> OUT=<dir>" >&2; exit 2; }
	Tests/Fixtures/make-fixture.sh $(NAME) $(OUT)

app:
	Tools/make-app.sh

# Bundle.module looks for the resource bundles next to the executable, so both
# go into $(PREFIX)/bin.
install: release
	@test -n "$(PREFIX)" || { echo "usage: make install PREFIX=<dir>" >&2; exit 2; }
	@bin=$$($(SWIFT) build -c release --show-bin-path) && \
	install -d "$(PREFIX)/bin" && \
	install -m 755 "$$bin/gitk-swift" "$(PREFIX)/bin/gitk-swift" && \
	for b in "$$bin"/*.bundle; do \
	    [ -d "$$b" ] || continue; \
	    case "$$b" in *Tests.bundle) continue ;; esac; \
	    ditto "$$b" "$(PREFIX)/bin/$$(basename "$$b")"; \
	done && \
	echo "installed $(PREFIX)/bin/gitk-swift"

clean:
	$(SWIFT) package clean
	rm -rf out
