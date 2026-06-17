#!/usr/bin/env bash
set -euo pipefail

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean." >&2
  git status --short >&2
  exit 1
fi

swift test

if command -v brew >/dev/null && brew --prefix libtorrent-rasterbar >/dev/null 2>&1; then
  TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
  Scripts/package-app.sh "check"
else
  echo "Skipping libtorrent-enabled build; Homebrew libtorrent-rasterbar not installed." >&2
fi
