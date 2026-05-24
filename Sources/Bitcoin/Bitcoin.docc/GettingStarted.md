# Getting Started with Bitcoin

@Metadata {
    @TitleHeading("Tutorial")
}

Learn how to start an embedded Bitcoin Core daemon, connect an RPC client, and make your first call.

## Overview

### Prerequisites

Before you begin, make sure you have:

- A Swift toolchain (Swift 6.0 or later) — install via [swift.org](https://www.swift.org/install/) or Xcode.
- A working `python3` on `PATH` if you want to generate fresh RPC credentials with Bitcoin Core's [`rpcauth.py`](https://github.com/bitcoin/bitcoin/blob/master/share/rpcauth/rpcauth.py) helper (the demo credentials below are pre-generated, so this is optional for first run).
- ~250 MB of free disk space for the regtest data directory.

You do **not** need to install `bitcoind` separately — the `Bitcoin` module compiles [Bitcoin Core](https://github.com/bitcoin/bitcoin) as a C++ dependency and links it into your binary.

> Checkpoint: Run `swift --version` and confirm it reports 6.0 or later before continuing.

### Step 1: Add Bitcoin to your project

Add `swift-bitcoinkernel` as a Swift Package Manager dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/21-DOT-DEV/swift-bitcoinkernel.git", branch: "main"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "Bitcoin", package: "swift-bitcoinkernel"),
        ]
    ),
]
```

Then import the module:

```swift
import Bitcoin
```

> Checkpoint: Run `swift build` from your package root. You should see the dependency resolve and the build complete without errors. The first build compiles Bitcoin Core and may take several minutes.

### Step 2: Build a configuration

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

### Step 3: Start the daemon

Pass the config to ``Daemon/start(with:)`` to validate it and launch the daemon:

```swift
try Daemon.start(with: config)
```

This validates the configuration (throwing ``ConfigError`` on fatal conflicts), prints any warnings, and starts `bitcoind` on a background thread. The method returns immediately.

> Checkpoint: You should see Bitcoin Core's startup log messages on stderr, ending with `init message: Done loading`. The daemon is now running and accepting RPC calls on port 18443 (regtest default).

### Step 4: Connect an RPC client

Create an ``RPCClient`` that auto-detects the best transport:

```swift
let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "111",
    password: "222"
)
```

When the embedded daemon is running, calls are routed through an in-process bridge for minimal latency. When connecting to a remote node, HTTP is used automatically.

### Step 5: Make your first call

Use the typed RPC methods to query the blockchain:

```swift
let info = try await client.getBlockchainInfo()
print("Chain: \(info.chain)")
print("Blocks: \(info.blocks)")
print("Difficulty: \(info.difficulty)")
```

> Checkpoint: You should see output like `Chain: regtest`, `Blocks: 0`, `Difficulty: 4.6565...e-10`. If you see an authentication error instead, double-check the credentials match `RPCAuth`.

Or use the generic `send` method for any RPC:

```swift
let blockCount: Int = try await client.send("getblockcount")
```

### Step 6: Generate blocks (regtest only)

On regtest, generate blocks for testing — see the [`generatetoaddress` RPC reference](https://developer.bitcoin.org/reference/rpc/generatetoaddress.html):

```swift
let address = try await client.getNewAddress(wallet: "default")
let hashes = try await client.generateToAddress(nBlocks: 101, address: address)
print("Generated \(hashes.count) blocks")
```

> Checkpoint: The print should report `Generated 101 blocks`. Calling `getBlockchainInfo()` again now reports `Blocks: 101`. The first 100 coinbase rewards are still maturing; the 101st makes the first one spendable.

### Step 7: Stop the daemon

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
