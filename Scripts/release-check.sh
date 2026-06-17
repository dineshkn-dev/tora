#!/usr/bin/env bash
set -euo pipefail

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean." >&2
  git status --short >&2
  exit 1
fi

swift test

if command -v brew >/dev/null; then
  host_macos_major="$(sw_vers -productVersion | cut -d. -f1)"
  minimum_macos_major="${TORA_MINIMUM_MACOS:-14.0}"
  minimum_macos_major="${minimum_macos_major%%.*}"
  if (( host_macos_major > minimum_macos_major )); then
    TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
    echo "Skipping local app packaging on macOS $(sw_vers -productVersion); release artifacts are built on macos-${minimum_macos_major}." >&2
    exit 0
  fi
  Scripts/bootstrap-release-deps.sh
  TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
  Scripts/package-app.sh "check"
else
  echo "Skipping libtorrent-enabled build; Homebrew libtorrent-rasterbar not installed." >&2
fi
