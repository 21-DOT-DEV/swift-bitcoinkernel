# Getting Started with Bitcoin (Embedded Daemon)

@Metadata {
    @TitleHeading("Tutorial")
    @Available(macOS, introduced: "15.0")
    @Available(iOS, introduced: "18.0")
}

Boot an embedded `bitcoind` inside your Swift binary, connect a typed async/await ``RPCClient`` over an in-process bridge, and verify the round-trip with ``RPCClient/getBlockchainInfo()`` on regtest. No separate Bitcoin Core install required.

## Overview

The `Bitcoin` product compiles [Bitcoin Core][bitcoin-core] as a C++ dependency and links it directly into your binary. There is no external `bitcoind` to install, supervise, or socket into. RPC calls travel through an in-process bridge instead of localhost HTTP once a bootstrap step is run.

This article walks from an empty SwiftPM project to a verified ``RPCClient/getBlockchainInfo()`` round-trip on regtest: install the dependency, build a validated configuration, start the daemon and connect, and issue one typed call.

### Prerequisites

- Swift 6.3 toolchain (Xcode 26.4 or later on Apple platforms).
- A deployment target on macOS 15.0+ or iOS 18.0+.
- Under 50 MB of free disk space for the regtest data directory this article creates.
- An additional 1–3 GB of disk for first-build C++ artifacts. Bitcoin Core compiles from source on the first build of your dependent target.
- Optional: `python3` on `PATH` to generate your own RPC credentials with Bitcoin Core's [`rpcauth.py`][rpcauth] helper.

### Add the Bitcoin product with Swift Package Manager

Add the package and depend on the `Bitcoin` product from your target:

> Important: This package is pre-1.0 ([SemVer 0.y.z](https://semver.org/#spec-item-4)). The public API may change at any release; pin with `exact:` and review the release notes before bumping.

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/21-DOT-DEV/swift-bitcoinkernel.git",
        exact: "0.1.0"
    ),
],
targets: [
    .target(
        name: "MyBitcoinApp",
        dependencies: [
            .product(name: "Bitcoin", package: "swift-bitcoinkernel"),
        ],
        swiftSettings: [
            .interoperabilityMode(.Cxx),
        ]
    ),
]
```

The `Bitcoin` product re-exports Bitcoin Core's C++ stack, so consumers must opt into Swift's [C++ interoperability mode][cxx-interop] on the dependent target.

The first build compiles Bitcoin Core and its C/C++ dependencies from source for your destination's triple. Expect several minutes on a cold cache and seconds for incremental rebuilds. The Xcode equivalent is **File → Add Package Dependencies…** and resolves to the same `Package.resolved`. In Xcode, set **C++ and Objective-C Interoperability** to `C++/Objective-C++` in the dependent target's Build Settings.

> Note: iOS is a supported platform because the API surface compiles there, but shipping a full embedded `bitcoind` inside an iOS app has practical limits worth weighing first: App Store binary size from the linked C++ artifacts, no daemon execution while the app is backgrounded, and no writable `/tmp` at the macOS location. This tutorial uses `URL.temporaryDirectory`, which resolves to the app's sandbox on iOS and `/var/folders/...` on macOS, so the snippets are copy-pasteable on both. Production iOS work should consult an app-container-aware data-directory strategy.

### Build a validated configuration

Use ``BitcoinConfig`` to assemble a network-aware, validated configuration. Start with a network factory method, then chain options:

```swift
import Bitcoin
import Foundation

let dataDirectory = URL.temporaryDirectory.appending(path: "bitcoin-regtest")
try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

let config = BitcoinConfig
    .regtest()
    .server()
    .dataDir(dataDirectory.path(percentEncoded: false))
```

The builder is phantom-typed by network. Regtest-only options like `.fastPrune()` surface only on regtest configs, so misuse fails at compile time instead of at daemon startup. The configuration is data, not state. Assemble it freely, then hand it to ``Daemon/startAndConnect(with:timeout:)`` in the next step. The data directory must exist before startup; `bitcoind` refuses to create it.

### Start the daemon and connect

``Daemon/startAndConnect(with:timeout:)`` validates the configuration, launches `bitcoind` on a detached thread, waits for the RPC server, and returns an ``RPCClient`` wired to it. Endpoint and credentials are derived from the config, so they are supplied once and no RPC password appears in your code.

```swift
let client = try await Daemon.startAndConnect(with: config)
```

Under the hood it runs three steps you can also drive yourself. ``Daemon/start(with:)`` validates the config (a thrown ``ConfigError`` means no daemon was started) and launches `bitcoind` on a detached thread, returning immediately. ``Daemon/bootstrap(cookieFile:port:timeout:)`` polls with exponential backoff (30-second default) until Bitcoin Core writes its `.cookie` and the RPC server accepts connections, then calls the hidden `_bridge_init` RPC to capture the `NodeContext` that ``DirectTransport`` dispatches against. ``RPCClient/init(url:cookieFile:)`` builds an auto-detecting client. Cookie authentication reads the credentials Bitcoin Core writes to `<datadir>/<network>/.cookie` (here `regtest/.cookie`), so non-wallet RPCs route through the in-process ``DirectTransport`` and wallet RPCs through ``HTTPTransport``, with nothing hardcoded.

> Checkpoint: `startAndConnect` returned an ``RPCClient`` without throwing. The daemon is up on regtest's default RPC port `18443`, the bridge is active, and the next call confirms the round-trip.

### Make your first call

Issue a typed RPC against the running daemon:

```swift
let info: BlockchainInfo = try await client.getBlockchainInfo()
print("Chain: \(info.chain)")    // regtest
print("Blocks: \(info.blocks)")  // 0
```

> Checkpoint: The print should report `Chain: regtest` and `Blocks: 0`. A hang usually means the data directory wasn't created before `startAndConnect`, so Bitcoin Core never wrote the cookie the client reads. A thrown ``DaemonConnectError`` means the config has no `.dataDir(_:)` for the cookie to live under.

For any RPC the typed surface doesn't model yet, ``RPCClient/send(_:params:)`` accepts a method name and decodes the result into the type you ask for: `let count: Int = try await client.send("getblockcount")`. The decoding is `JSONDecoder`-based, so any `Decodable & Sendable` type works as the return slot.

### Shut down cleanly

Send the `stop` RPC to ask Bitcoin Core to begin shutdown, then block the calling thread until `bitcoind_main()` returns:

```swift
_ = try await client.stop()
Daemon.waitUntilStopped()
```

The two calls play distinct roles. ``RPCClient/stop()`` signals the daemon to begin its shutdown sequence and returns as soon as the request is acknowledged; the daemon thread is still tearing down. ``Daemon/waitUntilStopped()`` joins that thread and returns only after `bitcoind_main()` has fully exited and released its file locks. Skipping the join can leave the LevelDB stores under your data directory in an inconsistent state if your process exits before the daemon thread finishes.

> Warning: ``Daemon/waitUntilStopped()`` blocks the calling thread synchronously. Call it from a detached `Task` or a background queue. Never call it from `@MainActor`-isolated code on iOS or macOS UI apps, or the runloop freezes until shutdown completes.

### The complete example

The walkthrough above stitched into one end-to-end block, ready to drop into a Swift file:

```swift
import Bitcoin
import Foundation

let dataDirectory = URL.temporaryDirectory.appending(path: "bitcoin-regtest")
try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

let config = BitcoinConfig
    .regtest()
    .server()
    .dataDir(dataDirectory.path(percentEncoded: false))

let client = try await Daemon.startAndConnect(with: config)

let info: BlockchainInfo = try await client.getBlockchainInfo()
print("Chain: \(info.chain)")
print("Blocks: \(info.blocks)")

_ = try await client.stop()
Daemon.waitUntilStopped()
```

### Where to go next

A first run that lands on `blocks == 0` is correct. Regtest starts at genesis with no chain on top.

- Mine regtest blocks with ``RPCClient/getNewAddress(wallet:label:addressType:)`` and ``RPCClient/generateToAddress(nBlocks:address:maxTries:)``. Bitcoin Core's `COINBASE_MATURITY = 100`, so 101 generated blocks (the coinbase block plus 100 confirmations on top) mature the first reward into spendable funds. See the [`generatetoaddress` RPC reference][gentoaddr].
- Configure for signet or mainnet by swapping `.regtest()` for `.signet()` or `.mainnet()`. Phantom-typed network-scoped extensions catch incompatible options at compile time.
- Skip the daemon entirely with the sibling `BitcoinKernel` product, which wraps `libbitcoinkernel` for consensus validation only. Start with `Getting Started with BitcoinKernel` in that module's catalog.

## See Also

- ``BitcoinConfig``
- ``Daemon``
- ``RPCClient``
- ``RPCAuth``
- ``DirectTransport``
- ``HTTPTransport``
- ``RPCTransport``
- ``ConfigError``
- ``DaemonConnectError``
- [Bitcoin Core][bitcoin-core]
- [`rpcauth.py` — Bitcoin Core][rpcauth]
- [`generatetoaddress` RPC reference — Bitcoin Developer][gentoaddr]
- [SE-0296: Async/await — Swift Evolution][se-0296]

[bitcoin-core]: https://github.com/bitcoin/bitcoin
[rpcauth]: https://github.com/bitcoin/bitcoin/blob/master/share/rpcauth/rpcauth.py
[gentoaddr]: https://developer.bitcoin.org/reference/rpc/generatetoaddress.html
[se-0296]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0296-async-await.md
