# Getting Started with Bitcoin

@Metadata {
    @TitleHeading("Tutorial")
}

Learn how to start an embedded Bitcoin Core daemon, connect an RPC client, and make your first call.

## Overview

### Adding Bitcoin to Your Project

Add `swift-bitcoin` as a Swift Package Manager dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/21-DOT-DEV/swift-bitcoin.git", branch: "main"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "Bitcoin", package: "swift-bitcoin"),
        ]
    ),
]
```

Then import the module:

```swift
import Bitcoin
```

### Building a Configuration

Use ``BitcoinConfig`` to create a type-safe, validated configuration. Start with a network factory method:

```swift
// Demo credentials — username "111", password "222".
// `passwordHMAC` is the hex HMAC-SHA256 of the password keyed by the salt.
// Generate your own with Bitcoin Core's helper:
//     python3 share/rpcauth/rpcauth.py <username> <password>
let auth = RPCAuth(
    username: "111",
    salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b",
    passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4"
)

let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .server()
    .dataDir("/tmp/bitcoin-regtest")
    .txIndex()
```

The builder uses phantom types to enforce network-specific options at compile time. For example, `.fastPrune()` is only available on `Regtest` configs.

### Starting the Daemon

Pass the config to ``Daemon/start(with:)`` to validate it and launch the daemon:

```swift
try Daemon.start(with: config)
```

This validates the configuration (throwing ``ConfigError`` on fatal conflicts), prints any warnings, and starts `bitcoind` on a background thread. The method returns immediately.

### Connecting an RPC Client

Create an ``RPCClient`` that auto-detects the best transport:

```swift
let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "111",
    password: "222"
)
```

When the embedded daemon is running, calls are routed through an in-process bridge for minimal latency. When connecting to a remote node, HTTP is used automatically.

### Making Your First Call

Use the typed RPC methods to query the blockchain:

```swift
let info = try await client.getBlockchainInfo()
print("Chain: \(info.chain)")
print("Blocks: \(info.blocks)")
print("Difficulty: \(info.difficulty)")
```

Or use the generic `send` method for any RPC:

```swift
let blockCount: Int = try await client.send("getblockcount")
```

### Generating Blocks (Regtest)

On regtest, generate blocks for testing:

```swift
let address = try await client.getNewAddress(wallet: "default")
let hashes = try await client.generateToAddress(nBlocks: 101, address: address)
print("Generated \(hashes.count) blocks")
```

### Stopping the Daemon

Send the `stop` RPC to signal Bitcoin Core to begin shutdown, then block until the daemon thread has exited:

```swift
_ = try await client.stop()
Daemon.waitUntilStopped()
```

``Daemon/waitUntilStopped()`` blocks the calling thread until `bitcoind_main` returns. Pair it with the `stop` RPC (or any other shutdown trigger Bitcoin Core honors) to ensure clean teardown before your process exits.

### Next Steps

- <doc:ConfiguringBitcoinCore> -- Explore the full configuration builder API.
- <doc:ChoosingAnRPCTransport> -- Understand transport selection and wallet routing.
- <doc:Architecture> -- Learn about the embedded daemon architecture.
