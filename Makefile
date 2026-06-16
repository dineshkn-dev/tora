SHELL := /bin/zsh

.PHONY: build test verify build-libtorrent test-libtorrent clean release-check

build:
	swift build

test:
	swift test

verify: test

build-libtorrent:
	TORA_LIBTORRENT_PREFIX="$$(brew --prefix libtorrent-rasterbar)" swift build

test-libtorrent:
	TORA_LIBTORRENT_PREFIX="$$(brew --prefix libtorrent-rasterbar)" swift test

clean:
	swift package clean

release-check:
	./Scripts/release-check.sh
