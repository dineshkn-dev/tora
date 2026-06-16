#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null; then
  echo "Homebrew is required." >&2
  exit 2
fi

if ! brew --prefix libtorrent-rasterbar >/dev/null 2>&1; then
  echo "libtorrent-rasterbar is not installed. Run: brew install libtorrent-rasterbar" >&2
  exit 2
fi

if ! command -v fswatch >/dev/null; then
  echo "fswatch is required for watch mode. Installing with Homebrew..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew install fswatch
fi

export TORA_LIBTORRENT_PREFIX
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)"

app_pid=""

cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

run_app() {
  cleanup
  echo "Building and launching Tora..."
  TORA_LIBTORRENT_PREFIX="$TORA_LIBTORRENT_PREFIX" swift run Tora &
  app_pid="$!"
}

run_app

fswatch -0 \
  --exclude '(^|/)\\.build(/|$)' \
  --exclude '(^|/)dist(/|$)' \
  --exclude '(^|/)\\.git(/|$)' \
  --include '.*\\.swift$' \
  --include '.*\\.mm$' \
  --include '.*\\.h$' \
  --include '.*\\.hpp$' \
  --include '.*\\.cpp$' \
  --include '.*/Package\\.swift$' \
  --include '.*/CMakeLists\\.txt$' \
  --exclude '.*' \
  Sources Tests Package.swift CMakeLists.txt |
while IFS= read -r -d '' _; do
  sleep 0.4
  run_app
done
