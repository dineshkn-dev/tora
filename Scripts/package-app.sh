#!/usr/bin/env bash
set -euo pipefail

version="${1:-dev}"
configuration="${CONFIGURATION:-release}"
root="$(git rev-parse --show-toplevel)"
dist="$root/dist"
app="$dist/Tora.app"
contents="$app/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"
frameworks="$contents/Frameworks"

rm -rf "$app"
mkdir -p "$macos" "$resources" "$frameworks"

TORA_LIBTORRENT_PREFIX="${TORA_LIBTORRENT_PREFIX:-$(brew --prefix libtorrent-rasterbar 2>/dev/null || true)}"
if [[ -z "$TORA_LIBTORRENT_PREFIX" ]]; then
  echo "TORA_LIBTORRENT_PREFIX is required for release packaging." >&2
  exit 2
fi

TORA_LIBTORRENT_PREFIX="$TORA_LIBTORRENT_PREFIX" swift build -c "$configuration"
cp "$root/.build/$configuration/Tora" "$macos/Tora"
cp "$root/Sources/ToraApp/AppIcon.icns" "$resources/AppIcon.icns"

rewrite_dependencies() {
  local binary="$1"
  local changed=0
  while IFS= read -r dependency; do
    [[ "$dependency" == /opt/homebrew/* ]] || continue
    local name
    name="$(basename "$dependency")"
    if [[ ! -f "$frameworks/$name" ]]; then
      cp "$dependency" "$frameworks/$name"
      chmod u+w "$frameworks/$name"
      changed=1
    fi
    install_name_tool -change "$dependency" "@executable_path/../Frameworks/$name" "$binary" || true
  done < <(otool -L "$binary" | awk 'NR > 1 { print $1 }')
  return "$changed"
}

rewrite_dependencies "$macos/Tora" || true
while true; do
  copied=0
  for dylib in "$frameworks"/*.dylib; do
    [[ -e "$dylib" ]] || continue
    install_name_tool -id "@executable_path/../Frameworks/$(basename "$dylib")" "$dylib" || true
    if rewrite_dependencies "$dylib"; then
      copied=1
    fi
  done
  [[ "$copied" -eq 1 ]] || break
done

cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Tora</string>
  <key>CFBundleIdentifier</key><string>dev.dineshkn.tora</string>
  <key>CFBundleName</key><string>Tora</string>
  <key>CFBundleDisplayName</key><string>Tora</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version#v}</string>
  <key>CFBundleVersion</key><string>${version#v}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  find "$frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' dylib; do
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$dylib"
  done
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$app"
else
  echo "Ad-hoc signing frameworks for local run..."
  find "$frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' dylib; do
    codesign --force -s - "$dylib"
  done
  echo "Ad-hoc signing app bundle..."
  codesign --force -s - "$app"
fi

mkdir -p "$dist"
(cd "$dist" && zip -qry "Tora-${version}-macos.zip" "Tora.app")
shasum -a 256 "$dist/Tora-${version}-macos.zip" > "$dist/Tora-${version}-macos.zip.sha256"

echo "$dist/Tora-${version}-macos.zip"
