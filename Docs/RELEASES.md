# Releases

Tora releases are automated from annotated Git tags.

## Local release

```sh
Scripts/create-release.sh v0.1.0
```

The script verifies a clean working tree, runs tests, creates an annotated tag, and pushes it.

## GitHub release

The `Release` workflow builds a `.app` bundle, vendors Homebrew dylib dependencies into `Contents/Frameworks`, creates a zip artifact, writes a SHA-256 checksum, and creates a GitHub Release with generated notes.

The workflow builds libtorrent from source for Tora's minimum macOS target and packages a sandboxed app. Release packaging fails if any bundled Mach-O requires a newer macOS than Tora supports or if the app is missing required sandbox/network/file entitlements.

## Notarization

Future `.app` and `.dmg` releases must add signing and notarization. Required secrets should be:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`

Do not ship unsigned app bundles as stable releases.

Local packaging:

```sh
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" Scripts/package-app.sh v0.1.0
Scripts/notarize-app.sh dist/Tora-v0.1.0-macos.zip
```
