# Tora

Tora is a macOS-first BitTorrent client built with Swift, SwiftUI, and libtorrent-rasterbar.

## Status

Early development. The security-first project skeleton, validation layer, bridge boundary, CI, and release automation are in place.

## Security posture

- Tora does not implement the BitTorrent protocol manually.
- `.torrent` files and magnet links are treated as untrusted input.
- Download paths are validated before any torrent is started.
- Downloaded files are never opened automatically.
- A dedicated download directory is used by default: `~/Downloads/Tora`.
- Libtorrent is isolated behind a small `TorrentService` boundary.

## Initial build

```sh
swift test
swift run Tora
```

See [BUILDING.md](BUILDING.md) for libtorrent-enabled builds. CI intentionally runs the fail-closed test suite only; release builds verify libtorrent linkage.

## Local git automation

```sh
Scripts/install-git-hooks.sh
```

The hooks run tests before commits and run the libtorrent-enabled build before pushes when libtorrent is installed.

## Libtorrent bridge

The bridge builds without libtorrent so core security tests can run on clean machines. To enable the real bridge, install libtorrent-rasterbar and pass its prefix to SwiftPM:

```sh
brew install libtorrent-rasterbar
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift test
```

The Swift app should continue to depend on `TorrentServiceProtocol`; raw libtorrent types must stay inside `ToraLibtorrentBridge`.
