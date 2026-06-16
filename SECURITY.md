# Security Policy

Tora is designed around a hostile-input model. Torrent metadata, magnet links, tracker URLs, peer data, and resume data must be considered untrusted.

## Rules

- Never auto-open downloaded files.
- Never trust torrent-provided paths.
- Never write outside the selected download directory.
- Never delete data outside a Tora-approved download root.
- Never expose raw libtorrent handles outside the bridge.
- Make DHT, LSD, UPnP/NAT-PMP, peer exchange, and encryption settings explicit.

## Test from day one

- Path traversal using `..`, absolute paths, home-relative paths, and backslashes.
- Symlink escapes from the download directory.
- Duplicate and Unicode-normalized file path collisions.
- Malformed, huge, or control-character-containing magnet links.
- Resume data restoring unsafe save paths.
- Build configurations where libtorrent is absent must fail closed at runtime.
