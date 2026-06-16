# AGENTS

This repository is intentionally AI-agent friendly, but not AI-agent permissive.

## Non-negotiable constraints

- No Electron.
- No custom BitTorrent protocol implementation.
- No raw libtorrent handles outside `Sources/ToraLibtorrentBridge`.
- No automatic opening of downloaded files.
- No unvalidated torrent-provided filesystem path.
- No default network-discovery setting changes without explicit review.

## Required checks

Run before proposing changes:

```sh
swift test
```

When libtorrent is installed:

```sh
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
```

Do not skip failing checks by editing workflows, hooks, or scripts unless the change is directly about fixing those checks.

## Release rule

Releases are tag-driven. Use `Scripts/create-release.sh vX.Y.Z` from a clean working tree.
