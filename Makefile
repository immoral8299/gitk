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
#   make clean                  remove build output

SWIFT ?= swift
FIXTURE ?= linear
OUT ?=
ARGS ?=
NAME ?=

.PHONY: all build test release snapshot fixture clean

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

clean:
	$(SWIFT) package clean
	rm -rf out
