# Security Test Plan

## Torrent paths

- Reject absolute paths.
- Reject `..`, `.`, empty components, and trailing separators.
- Reject Windows drive paths and backslash traversal.
- Reject control characters.
- Reject duplicate paths after normalization.
- Reject paths that collide on case-insensitive filesystems.

## Download roots

- Use `~/Downloads/Tora` by default.
- Do not delete outside the configured download root.
- Treat symlink resolution as hostile before deletion or move operations.

## Network settings

- DHT, LSD, UPnP, NAT-PMP, and peer exchange are explicit.
- Tests must fail if defaults silently enable discovery.

## Release automation

- CI must run on pull requests.
- Security scanning is manual until the project is public and runner-minute budget is clear.
- Releases must be tag-driven and include checksums.
