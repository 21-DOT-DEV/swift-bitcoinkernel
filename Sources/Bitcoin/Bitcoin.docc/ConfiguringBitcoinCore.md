# Configuring Bitcoin Core

@Metadata {
    @TitleHeading("How-to Guide")
}

Build type-safe, validated Bitcoin Core settings using the fluent ``BitcoinConfig`` builder.

## Overview

``BitcoinConfig`` is a Swift-side replacement for hand-editing [`bitcoin.conf`](https://github.com/bitcoin/bitcoin/blob/master/doc/bitcoin-conf.md). Every option maps to a command-line flag accepted by [`bitcoind`](https://github.com/bitcoin/bitcoin/blob/master/src/bitcoind.cpp); the builder simply produces the argument list passed to `bitcoind_main(argc, argv)`. For the canonical option reference, run `bitcoind -help` or see the [Bitcoin Core documentation](https://github.com/bitcoin/bitcoin/tree/master/doc).

### Choosing a network

Start every builder chain with a network factory method, then attach ``RPCAuth`` credentials:

```swift
let auth = RPCAuth(username: "user", salt: "abc", passwordHMAC: "def")

let mainnet = BitcoinConfig.mainnet().rpcAuth(auth)
let testnet = BitcoinConfig.testnet4().rpcAuth(auth)
let regtest = BitcoinConfig.regtest().rpcAuth(auth)
let signet  = BitcoinConfig.signet().rpcAuth(auth)
```

The return type carries the network as a phantom type parameter (e.g., `BitcoinConfig<Regtest>`), which enables network-specific methods at compile time. Generate `passwordHMAC` with Bitcoin Core's [`rpcauth.py`](https://github.com/bitcoin/bitcoin/blob/master/share/rpcauth/rpcauth.py) helper.

### Chaining options

Use the fluent builder pattern to add settings. Each method returns a new value:

```swift
let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .server()
    .dataDir("/tmp/btc")
    .txIndex()
    .dbCache(450)
    .debug(.net)
    .debug(.rpc)
```

Order matters less than completeness — the builder defers conflict checks to `validate()`, so any sequence that produces the intended argument set is acceptable. For options not exposed as typed methods, see the **The raw escape hatch** section below.

### Using presets

For common scenarios, use a preset that bundles recommended options:

```swift
// Full archival node
let full = BitcoinConfig.fullNode(rpcAuth: auth)

// Pruned node for constrained storage
let pruned = BitcoinConfig.prunedDefault(rpcAuth: auth)

// Raspberry Pi / low-resource device
let pi = BitcoinConfig.raspberryPi(rpcAuth: auth)

// Tor-only privacy node
let tor = BitcoinConfig.torNode(rpcAuth: auth)

// Lightning (Eclair) backend
let lightning = BitcoinConfig.lightningEclair(rpcAuth: auth)
```

### Validation

Call `validate()` before starting the daemon to catch conflicting flags before `bitcoind_main` rejects them at startup:

```swift
let settings = BitcoinConfig.mainnet()
    .rpcAuth(auth)
    .txIndex()
    .prune(.size(mb: 550))

do {
    let warnings = try settings.validate()
    // warnings: [ConfigWarning] — non-fatal issues
} catch let error as ConfigError {
    // error: ConfigError — fatal conflicts (e.g., txIndex + prune)
}
```

``Daemon/start(with:)`` calls `validate()` automatically, so explicit invocation is only needed when you want to surface the warnings array before launch.

### The raw escape hatch

For flags not covered by typed builder methods (recently-added options, experimental features), use `raw()`:

```swift
let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .raw("-someunknownoption=value")
```

> Warning: `raw()` bypasses the builder's validation tracking. Options set this way are not checked by `validate()`.

### Network-specific options

Some options are only available on certain networks:

```swift
// Regtest only
let regtest = BitcoinConfig.regtest()
    .rpcAuth(auth)
    .fastPrune(true)
    .testActivationHeight("segwit@0")

// Signet only
let signet = BitcoinConfig.signet()
    .rpcAuth(auth)
    .signetChallenge("5121...")
```

The phantom type parameter prevents these methods from appearing in autocomplete on the wrong network — calling `.fastPrune(true)` on a `BitcoinConfig<Mainnet>` is a compile error, not a runtime rejection at daemon startup. Compare this to the [original C++ argument parser](https://github.com/bitcoin/bitcoin/blob/master/src/init.cpp), which surfaces network/option mismatches only after `bitcoind` boots.

### See also

- ``BitcoinConfig`` -- the type reference
- ``ConfigError`` and ``ConfigWarning`` -- validation outcomes
- [Bitcoin Core configuration reference](https://github.com/bitcoin/bitcoin/blob/master/doc/bitcoin-conf.md) -- canonical option list
- [signet challenge format](https://github.com/bitcoin/bips/blob/master/bip-0325.mediawiki) -- BIP 325, for `.signetChallenge`
