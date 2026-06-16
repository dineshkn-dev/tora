# Architecture

Tora is split into narrow layers:

- `ToraApp`: macOS app entry and composition root.
- `ToraUI`: SwiftUI views and interaction surfaces.
- `ToraCore`: domain models, security validation, and `TorrentServiceProtocol`.
- `ToraPersistence`: app support, resume data, session data, and future metadata storage.
- `ToraLibtorrentBridge`: Objective-C++/C++ adapter around libtorrent-rasterbar.

## Boundary rule

SwiftUI must not call libtorrent directly. Libtorrent must not receive torrent input, filesystem paths, or settings that bypass `ToraCore` validation.

## Add torrent flow

1. User selects a `.torrent` file or enters a magnet link.
2. `TorrentService` validates the source shape.
3. The bridge inspects metadata through libtorrent only.
4. `ToraCore` validates all proposed file paths.
5. The UI presents file selection.
6. Tora adds the torrent paused, applies file priorities, then starts only after confirmation.

## Persistence

Application data belongs under:

```text
~/Library/Application Support/Tora/
```

Payload downloads default to:

```text
~/Downloads/Tora/
```
