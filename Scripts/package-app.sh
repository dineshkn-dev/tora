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
entitlements="$root/BuildSupport/Tora.entitlements"
minimum_macos="${TORA_MINIMUM_MACOS:-14.0}"

rm -rf "$app"
mkdir -p "$macos" "$resources" "$frameworks"

TORA_LIBTORRENT_PREFIX="${TORA_LIBTORRENT_PREFIX:-$(brew --prefix libtorrent-rasterbar 2>/dev/null || true)}"
if [[ -z "$TORA_LIBTORRENT_PREFIX" ]]; then
  echo "TORA_LIBTORRENT_PREFIX is required for release packaging." >&2
  exit 2
fi

MACOSX_DEPLOYMENT_TARGET="$minimum_macos" TORA_LIBTORRENT_PREFIX="$TORA_LIBTORRENT_PREFIX" swift build -c "$configuration"
cp "$root/.build/$configuration/Tora" "$macos/Tora"
cp "$root/Sources/ToraApp/AppIcon.icns" "$resources/AppIcon.icns"
sparkle_framework="$root/.build/$configuration/Sparkle.framework"
if [[ -d "$sparkle_framework" ]]; then
  ditto "$sparkle_framework" "$frameworks/Sparkle.framework"
else
  echo "Missing Sparkle.framework in SwiftPM build output." >&2
  exit 1
fi

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
  <key>NSDownloadsFolderUsageDescription</key><string>Tora stores downloaded torrent payloads in the Tora downloads folder.</string>
  <key>SUFeedURL</key><string>https://github.com/dineshkn-dev/tora/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>IGuTVqfGXgXeYu/enWFCtCO4EYxPlHUpraLUCqA+m9w=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAllowsAutomaticUpdates</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUEnableInstallerLauncherService</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$frameworks/Sparkle.framework"
  find "$frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' dylib; do
    codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$dylib"
  done
  codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$DEVELOPER_ID_APPLICATION" "$app"
else
  echo "Ad-hoc signing frameworks for local run..."
  codesign --force --deep -s - "$frameworks/Sparkle.framework"
  find "$frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' dylib; do
    codesign --force -s - "$dylib"
  done
  echo "Ad-hoc signing app bundle..."
  codesign --force --entitlements "$entitlements" -s - "$app"
fi

Scripts/verify-release-binaries.sh "$app"

mkdir -p "$dist"
(cd "$dist" && zip -qry "Tora-${version}-macos.zip" "Tora.app")
shasum -a 256 "$dist/Tora-${version}-macos.zip" > "$dist/Tora-${version}-macos.zip.sha256"

echo "Creating DMG installer..."
dmg_temp=$(mktemp -d)
cp -R "$app" "$dmg_temp/"
ln -s /Applications "$dmg_temp/Applications"
rm -f "$dist/Tora-${version}-macos.dmg"
hdiutil create -volname "Tora" -srcfolder "$dmg_temp" -ov -format UDZO "$dist/Tora-${version}-macos.dmg" >/dev/null
rm -rf "$dmg_temp"
shasum -a 256 "$dist/Tora-${version}-macos.dmg" > "$dist/Tora-${version}-macos.dmg.sha256"

echo "$dist/Tora-${version}-macos.zip"
echo "$dist/Tora-${version}-macos.dmg"
