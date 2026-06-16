#!/usr/bin/env bash
set -euo pipefail

version="${1:-v0.1.0-local}"

if ! command -v brew >/dev/null; then
  echo "Homebrew is required." >&2
  exit 2
fi

if ! brew --prefix libtorrent-rasterbar >/dev/null 2>&1; then
  echo "libtorrent-rasterbar is not installed. Run: brew install libtorrent-rasterbar" >&2
  exit 2
fi

export TORA_LIBTORRENT_PREFIX
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)"

Scripts/package-app.sh "$version"
xattr -dr com.apple.quarantine dist/Tora.app 2>/dev/null || true
open dist/Tora.app
