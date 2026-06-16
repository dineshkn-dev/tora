# Tora AI Coding Instructions

Tora is a security-first native macOS BitTorrent client. AI assistants must preserve these constraints:

- Do not implement BitTorrent protocol parsing or peer wire logic manually.
- Keep libtorrent behind `TorrentServiceProtocol` and `ToraLibtorrentBridge`.
- Treat torrent files, magnet links, tracker URLs, peer data, and resume data as untrusted.
- Validate every torrent-provided path before starting or resuming a torrent.
- Never add auto-open behavior for downloaded files.
- Do not silently enable DHT, LSD, UPnP, NAT-PMP, or peer exchange.
- Do not broaden filesystem deletion without tests for path containment and symlink escape.
- Prefer small, reviewed bridge methods over exposing raw libtorrent types.
- Add tests for new input validation and persistence behavior.
