# Contributing

Tora accepts changes that preserve the security-first architecture.

## Development

```sh
Scripts/install-git-hooks.sh
swift test
swift run Tora
```

For libtorrent-enabled development:

```sh
brew install libtorrent-rasterbar
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
```

## Commit style

Use Conventional Commits:

- `feat: add torrent inspection view`
- `fix: reject duplicate normalized torrent paths`
- `test: cover magnet validation edge cases`
- `docs: explain release process`

## Pull requests

Every PR that touches input parsing, file writes, deletion, resume data, or network settings must include tests.
