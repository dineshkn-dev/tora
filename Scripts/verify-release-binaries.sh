#!/usr/bin/env bash
set -euo pipefail

app="${1:-}"
minimum_macos="${TORA_MINIMUM_MACOS:-14.0}"

if [[ -z "$app" || ! -d "$app" ]]; then
  echo "Usage: $0 dist/Tora.app" >&2
  exit 2
fi

if [[ ! -x "$app/Contents/MacOS/Tora" ]]; then
  echo "Missing app executable: $app/Contents/MacOS/Tora" >&2
  exit 1
fi

compare_versions() {
  awk -v left="$1" -v right="$2" '
    BEGIN {
      n = split(left, l, ".")
      m = split(right, r, ".")
      max = n > m ? n : m
      for (i = 1; i <= max; i++) {
        a = l[i] == "" ? 0 : l[i] + 0
        b = r[i] == "" ? 0 : r[i] + 0
        if (a > b) { print 1; exit }
        if (a < b) { print -1; exit }
      }
      print 0
    }'
}

check_binary_minos() {
  local binary="$1"
  local minos
  minos="$(otool -l "$binary" | awk '
    /LC_BUILD_VERSION/ { in_build = 1; next }
    in_build && /minos/ { print $2; exit }
    /LC_VERSION_MIN_MACOSX/ { in_min = 1; next }
    in_min && /version/ { print $2; exit }
  ')"

  if [[ -z "$minos" ]]; then
    echo "Could not determine minimum macOS version for $binary" >&2
    exit 1
  fi

  if [[ "$(compare_versions "$minos" "$minimum_macos")" == "1" ]]; then
    echo "$binary requires macOS $minos, above Tora minimum $minimum_macos" >&2
    exit 1
  fi
}

check_binary_minos "$app/Contents/MacOS/Tora"
if [[ -d "$app/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' dylib; do
    check_binary_minos "$dylib"
  done < <(find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0)
fi

entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"
for key in \
  com.apple.security.app-sandbox \
  com.apple.security.network.client \
  com.apple.security.network.server \
  com.apple.security.files.downloads.read-write \
  com.apple.security.files.user-selected.read-write
do
  if ! grep -q "$key" <<<"$entitlements"; then
    echo "Missing required entitlement: $key" >&2
    exit 1
  fi
done

spctl --assess --type execute "$app" >/dev/null 2>&1 || {
  echo "Warning: spctl assessment failed for $app. This is expected for local ad-hoc builds but not for notarized releases." >&2
}

echo "Release binary verification passed for $app"
