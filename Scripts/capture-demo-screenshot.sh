#!/usr/bin/env bash
set -euo pipefail

# Ensure we have a clean environment prefix for libtorrent
export TORA_LIBTORRENT_PREFIX
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar 2>/dev/null || echo '')"
if [[ -z "$TORA_LIBTORRENT_PREFIX" ]]; then
  echo "Error: libtorrent-rasterbar is required to build the app." >&2
  exit 2
fi

# Kill any existing running Tora instances
killall Tora 2>/dev/null || true

# 1. Build the production app bundle
echo "Building the application..."
CONFIGURATION=release Scripts/package-app.sh v0.1.0-demo >/dev/null

# 2. Launch the app in Demo Mode in the background
echo "Launching Tora in demo mode..."
export TORA_DEMO=1
dist/Tora.app/Contents/MacOS/Tora &
tora_pid=$!

# 3. Wait for the UI to load and metrics to update
echo "Waiting for Tora to initialize (4 seconds)..."
sleep 4

# 4. Attempt to position and size the window using AppleScript, then capture
echo "Positioning window and taking screenshot..."
if osascript -e '
tell application "System Events"
  tell process "Tora"
    set frontmost to true
    delay 0.5
    set position of window 1 to {100, 100}
    set size of window 1 to {1120, 720}
  end tell
end tell
' 2>/dev/null; then
  echo "Captured custom window area."
  screencapture -x -R100,100,1120,720 Docs/assets/screenshot.png
else
  echo "Warning: AppleScript positioning failed (Accessibility permissions may be off). Capturing full screen as fallback..."
  screencapture -x Docs/assets/screenshot.png
fi

# 5. Clean up by terminating the background app
echo "Closing demo application..."
kill "$tora_pid" 2>/dev/null || kill -9 "$tora_pid" 2>/dev/null || true
killall Tora 2>/dev/null || true

echo "Screenshot saved successfully to Docs/assets/screenshot.png"
