#!/usr/bin/env bash
set -euo pipefail

minimum_macos="${TORA_MINIMUM_MACOS:-14.0}"

if ! command -v brew >/dev/null; then
  echo "Homebrew is required for release dependency bootstrap." >&2
  exit 2
fi

export MACOSX_DEPLOYMENT_TARGET="$minimum_macos"
export CMAKE_OSX_DEPLOYMENT_TARGET="$minimum_macos"
export CFLAGS="${CFLAGS:-} -mmacosx-version-min=$minimum_macos"
export CXXFLAGS="${CXXFLAGS:-} -mmacosx-version-min=$minimum_macos"
export LDFLAGS="${LDFLAGS:-} -mmacosx-version-min=$minimum_macos"
export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"

brew_source_install() {
  local formula="$1"
  if brew list --versions "$formula" >/dev/null 2>&1; then
    brew reinstall --build-from-source "$formula"
  else
    brew install --build-from-source "$formula"
  fi
}

brew_source_install openssl@3
brew_source_install libtorrent-rasterbar

echo "Release dependencies are available for macOS $minimum_macos."
