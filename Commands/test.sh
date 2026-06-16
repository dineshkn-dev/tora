#!/usr/bin/env bash
set -euo pipefail

swift test

if command -v brew >/dev/null && brew --prefix libtorrent-rasterbar >/dev/null 2>&1; then
  TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
fi
