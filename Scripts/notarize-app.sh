#!/usr/bin/env bash
set -euo pipefail

zip_path="${1:-}"
if [[ -z "$zip_path" || ! -f "$zip_path" ]]; then
  echo "Usage: $0 dist/Tora-vX.Y.Z-macos.zip" >&2
  exit 2
fi

required=(APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "$name is required for notarization." >&2
    exit 2
  fi
done

xcrun notarytool submit "$zip_path" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait
