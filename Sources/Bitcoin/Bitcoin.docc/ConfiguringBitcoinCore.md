# Configuring Bitcoin Core

@Metadata {
    @TitleHeading("How-to Guide")
}

Build type-safe, validated Bitcoin Core configurations using the fluent ``BitcoinConfig`` builder.

## Overview

### Choosing a Network

Start every configuration with a network factory method, then chain ``RPCAuth`` credentials:

```swift
let auth = RPCAuth(username: "user", salt: "abc", passwordHMAC: "def")

let mainnet = BitcoinConfig.mainnet().rpcAuth(auth)
let testnet = BitcoinConfig.testnet4().rpcAuth(auth)
let regtest = BitcoinConfig.regtest().rpcAuth(auth)
let signet  = BitcoinConfig.signet().rpcAuth(auth)
```

The return type carries the network as a phantom type parameter (e.g., `BitcoinConfig<Regtest>`), which enables network-specific methods at compile time.

### Chaining Options

Use the fluent builder pattern to add options. Each method returns a new config value:

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

### Using Presets

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

Call `validate()` before starting the daemon to catch configuration conflicts:

```swift
let config = BitcoinConfig.mainnet()
    .rpcAuth(auth)
    .txIndex()
    .prune(.size(mb: 550))

do {
    let warnings = try config.validate()
    // warnings: [ConfigWarning] — non-fatal issues
} catch let error as ConfigError {
    // error: ConfigError — fatal conflicts (e.g., txIndex + prune)
}
```

``Daemon/start(with:)`` calls `validate()` automatically.

### The Raw Escape Hatch

For options not covered by the builder, use `raw()`:

```swift
let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .raw("-someunknownoption=value")
```

> Warning: `raw()` bypasses the builder's validation tracking. Options set this way are not checked by `validate()`.

### Network-Specific Options

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
