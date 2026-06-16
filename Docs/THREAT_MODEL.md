# Threat Model

## Assets

- User filesystem integrity.
- User privacy and network metadata.
- Downloaded payload isolation.
- App support data, resume data, and settings.

## Untrusted inputs

- `.torrent` files.
- Magnet links.
- Tracker URLs.
- Peer addresses and peer messages.
- Resume data restored from disk.
- Downloaded filenames and directory names.

## Primary risks

- Path traversal writes outside the selected download directory.
- Deletion outside the download root during torrent removal.
- Symlink escape during file move/delete operations.
- Network discovery leaking activity unexpectedly.
- Malicious metadata exhausting memory, CPU, or UI rendering.
- AI-generated code bypassing the `TorrentService` boundary.

## Required mitigations

- Validate torrent paths before add/resume.
- Keep discovery features explicit and default-disabled.
- Keep libtorrent types inside the bridge target.
- Add tests for new file, network, or metadata behavior.
- Never add auto-open behavior.
