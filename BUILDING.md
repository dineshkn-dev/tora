# Building Tora

## Default development build

```sh
swift test
swift run Tora
```

This configuration builds the bridge in fail-closed mode. Calls that require libtorrent return an error until libtorrent is linked.

## Libtorrent-enabled build

```sh
brew install libtorrent-rasterbar
TORA_LIBTORRENT_PREFIX="$(brew --prefix libtorrent-rasterbar)" swift build
```

If Boost is installed outside Homebrew's default prefix, also set:

```sh
TORA_BOOST_PREFIX="/path/to/boost"
```

On systems where Homebrew bottles are built for a newer macOS than Tora's deployment target, `swift build` can succeed while `swift test` fails to load the test bundle due to macOS library policy. Build libtorrent from source for the deployment target before treating the enabled test run as authoritative.
