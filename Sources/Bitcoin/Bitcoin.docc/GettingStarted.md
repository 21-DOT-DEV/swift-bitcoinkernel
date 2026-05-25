# Getting Started with Bitcoin (Embedded Daemon)

@Metadata {
    @TitleHeading("Tutorial")
    @Available(macOS, introduced: "15.0")
    @Available(iOS, introduced: "18.0")
}

Boot an embedded `bitcoind` inside your Swift binary on macOS 15+ or iOS 18+, connect a typed async/await ``RPCClient`` over an in-process bridge, and verify the round-trip with ``RPCClient/getBlockchainInfo()`` on regtest — no separate Bitcoin Core install required.

## Overview

**Key facts.** Swift 6.3 toolchain · macOS 15+ · iOS 18+ · In-process daemon · Regtest first-run.

The `Bitcoin` product compiles [Bitcoin Core][bitcoin-core] as a C++ dependency and links it directly into your binary — there is no external `bitcoind` to install, supervise, or socket into. RPC calls travel through an in-process bridge instead of localhost HTTP once a bootstrap step is run. This article walks from an empty SwiftPM project to a verified ``RPCClient/getBlockchainInfo()`` round-trip on regtest: install the dependency, build a validated configuration, start the daemon, activate the bridge, and issue one typed call.

### Prerequisites

- Swift 6.3 toolchain (Xcode 26.4 or later on Apple platforms), so the package resolves cleanly.
- A deployment target on macOS 15.0+ or iOS 18.0+.
- Under 50 MB of free disk space for the regtest data directory this article creates.
- An additional 1–3 GB of disk for first-build C++ artifacts — Bitcoin Core's sources compile from source on the initial build of your dependent target. Relevant if you provision CI runners.
- Optional: `python3` on `PATH` if you want to generate your own RPC credentials with Bitcoin Core's [`rpcauth.py`][rpcauth] helper. The demo credentials below are pre-generated, so this is optional for first run.

> Note: iOS is listed as a supported platform because the API surface compiles there, but shipping a full embedded `bitcoind` inside an iOS app has practical limits worth weighing first — App Store binary size from the linked C++ artifacts, no daemon execution while the app is backgrounded, and no writable `/tmp` path at the macOS location. This tutorial uses `URL.temporaryDirectory`, which resolves to the app's sandbox on iOS and `/var/folders/...` on macOS, so the snippets are copy-pasteable on both — but production iOS work should consult an app-container-aware data-directory strategy.

### Add the Bitcoin product with Swift Package Manager

Add the package and depend on the `Bitcoin` product from your target:

> Important: This package is currently pre-1.0. Track `main` until a stable tag ships, then pin with `.upToNextMajor(from:)` so a `swift package update` cannot break your build at an unmarked boundary.

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/21-DOT-DEV/swift-bitcoinkernel.git",
        branch: "main"
    ),
],
targets: [
    .target(
        name: "MyBitcoinApp",
        dependencies: [
            .product(name: "Bitcoin", package: "swift-bitcoinkernel"),
        ]
    ),
]
```

The first build compiles Bitcoin Core and its C/C++ dependencies from source for your destination's triple — several minutes on a cold cache, seconds for incremental rebuilds. The Xcode equivalent is **File → Add Package Dependencies…**; both routes resolve to the same `Package.resolved`.

### Build a validated configuration

Use ``BitcoinConfig`` to assemble a network-aware, validated configuration. Start with a network factory method, then chain options:

```swift
import Bitcoin
import Foundation

// Demo credentials — username "111", password "222".
// `passwordHMAC` is the hex HMAC-SHA256 of the password keyed by the salt.
// Generate your own with Bitcoin Core's helper:
//     python3 share/rpcauth/rpcauth.py <username> <password>
let auth = RPCAuth(
    username: "111",
    salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b",
    passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4"
)

let dataDirectory = URL.temporaryDirectory.appending(path: "bitcoin-regtest")

let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .server()
    .dataDir(dataDirectory.path(percentEncoded: false))
```

The builder is phantom-typed by network: regtest-only options (like `.fastPrune()`) surface only on regtest configs, so misuse fails at compile time instead of at daemon startup. The configuration is data, not state — assemble it freely, then hand it to ``Daemon/start(with:)`` in the next step.

> Warning: The credentials above are published in this documentation and exist only to make this tutorial copy-pasteable on regtest. Never reuse them on signet, testnet, or mainnet, and never reuse them outside throwaway development setups. Generate your own with `rpcauth.py` for anything that touches a real network.

### Start the embedded daemon

``Daemon/start(with:)`` validates the configuration, prints any non-fatal warnings, and launches `bitcoind` on a detached thread — the call returns immediately. Validation runs before any thread is spawned, so a thrown ``ConfigError`` means no daemon process exists and no shutdown coordination is required.

```swift
try Daemon.start(with: config)
```

The typed throw covers fatal conflicts the builder can't catch at compile time. Non-fatal warnings print to stdout with a `⚠️ BitcoinConfig:` prefix; the daemon still starts. Bitcoin Core itself writes its startup log to stderr ending with `init message: Done loading` — useful as a confirmation aid, but not your success contract.

> Checkpoint: ``Daemon/start(with:)`` returned without throwing. The daemon is now listening on regtest's default RPC port `18443`. The real success signal is the RPC round-trip two steps below — if that call returns a `BlockchainInfo` value, the daemon is genuinely up.

### Bootstrap the direct RPC bridge

Call ``Daemon/bootstrap(cookieFile:port:timeout:)`` before issuing any ``RPCClient`` request — without it, the auto-detecting transport has no in-process dispatch target and falls back to HTTP for every call, defeating the point of running the daemon in your binary.

```swift
// Same `dataDirectory` passed to `.dataDir()` above.
let cookieFile = dataDirectory.appending(path: "regtest/.cookie")
try await Daemon.bootstrap(cookieFile: cookieFile, port: 18443)
```

`bootstrap` polls until Bitcoin Core finishes writing the cookie file and the RPC server is accepting connections (exponential backoff, 30-second default timeout). It then calls the hidden `_bridge_init` RPC over HTTP to capture the `NodeContext` that ``DirectTransport`` dispatches against. After this call returns, the client built in the next step routes non-wallet RPCs through the in-process bridge instead of HTTP.

> Note: For non-mainnet networks, the cookie file lives under the network subdirectory — `regtest/.cookie` on regtest, `signet/.cookie` on signet. Mainnet writes directly to `<datadir>/.cookie`. The cookie-auth form is preferred over ``Daemon/bootstrap(url:username:password:timeout:)`` because it sidesteps stashing credentials in your code path.

### Connect a typed RPC client

Construct an ``RPCClient`` with the same URL and credentials you configured the daemon with:

```swift
let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "111",
    password: "222"
)
```

With the bootstrap above complete, this initializer assembles an auto-detecting transport that routes non-wallet RPCs through ``DirectTransport`` (in-process, no socket) and falls back to ``HTTPTransport`` for wallet calls and any RPC the bridge doesn't service. The decision is made per-call. To opt out of auto-selection — for testing, for a remote-only deployment, or to wire a custom transport — pass an explicit conformer to ``RPCClient/init(transport:)`` instead.

### Make your first call

Issue a typed RPC against the running daemon:

```swift
let info: BlockchainInfo = try await client.getBlockchainInfo()
print("Chain: \(info.chain)")    // regtest
print("Blocks: \(info.blocks)")  // 0
```

> Checkpoint: The print should report `Chain: regtest` and `Blocks: 0`. If you see an authentication error instead, the credentials passed to ``RPCClient`` don't match the ``RPCAuth`` baked into the config — re-check that the `username`/`password` strings (`"111"`, `"222"`) are the cleartext pair the `salt`/`passwordHMAC` were derived from. If the call hangs, the bootstrap step was likely skipped and the cookie file isn't yet present.

For any RPC the typed surface doesn't model yet, ``RPCClient/send(_:params:)`` accepts a method name and decodes the result into the type you ask for — `let count: Int = try await client.send("getblockcount")`. The decoding is `JSONDecoder`-based, so any `Decodable & Sendable` type works as the return slot.

### Shut down cleanly

Send the `stop` RPC to ask Bitcoin Core to begin shutdown, then block the calling thread until `bitcoind_main()` returns:

```swift
_ = try await client.stop()
Daemon.waitUntilStopped()
```

The two calls play distinct roles. ``RPCClient/stop()`` *signals* the daemon to begin its shutdown sequence and returns as soon as the request is acknowledged; the daemon thread is still tearing down. ``Daemon/waitUntilStopped()`` *joins* that thread — it returns only after `bitcoind_main()` has fully exited and released its file locks. Skipping the join can leave the LevelDB stores under your data directory in an inconsistent state if your process exits before the daemon thread finishes.

> Warning: ``Daemon/waitUntilStopped()`` blocks the calling thread synchronously. Call it from a detached `Task` or a background queue — never from `@MainActor`-isolated code on iOS or macOS UI apps, or the runloop freezes until shutdown completes.

### The complete example

The walkthrough above stitched into one end-to-end block, ready to drop into a Swift file:

```swift
import Bitcoin
import Foundation

// Demo credentials — username "111", password "222". Regtest only.
let auth = RPCAuth(
    username: "111",
    salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b",
    passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4"
)

let dataDirectory = URL.temporaryDirectory.appending(path: "bitcoin-regtest")

let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .server()
    .dataDir(dataDirectory.path(percentEncoded: false))

try Daemon.start(with: config)

let cookieFile = dataDirectory.appending(path: "regtest/.cookie")
try await Daemon.bootstrap(cookieFile: cookieFile, port: 18443)

let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "111",
    password: "222"
)

let info: BlockchainInfo = try await client.getBlockchainInfo()
print("Chain: \(info.chain)")
print("Blocks: \(info.blocks)")

_ = try await client.stop()
Daemon.waitUntilStopped()
```

### Where to go next

A first run that lands on `blocks == 0` is correct — regtest starts at genesis with no chain on top. What you do next depends on what you're building:

- **Mining blocks on regtest for test fixtures.** Pair ``RPCClient/getNewAddress(wallet:label:addressType:)`` with ``RPCClient/generateToAddress(nBlocks:address:maxTries:)`` to mint blocks under your control — 101 blocks matures the first coinbase reward into spendable funds. See the canonical [`generatetoaddress` RPC reference][gentoaddr] for parameter semantics.
- **Configuring for signet or mainnet.** Swap `.regtest()` for `.signet()` or `.mainnet()` on the builder; the phantom-typed network-scoped extensions catch any option that no longer applies at compile time. Browse the ``BitcoinConfig`` symbol page for the full builder surface and the ``RPCTransport`` protocol page for transport-selection details.
- **Skipping the daemon entirely.** If you only need consensus validation (block-index, chainstate, header verification) without the full node and its RPC server, the sibling `BitcoinKernel` product wraps `libbitcoinkernel` instead — a smaller surface and a different mental model. Start with `Getting Started with BitcoinKernel` in that module's catalog.

## See Also

- ``BitcoinConfig``
- ``Daemon``
- ``RPCClient``
- ``RPCAuth``
- ``DirectTransport``
- ``HTTPTransport``
- ``RPCTransport``
- ``ConfigError``
- [Bitcoin Core][bitcoin-core]
- [`rpcauth.py` — Bitcoin Core][rpcauth]
- [`generatetoaddress` RPC reference — Bitcoin Developer][gentoaddr]
- [SE-0296: Async/await — Swift Evolution][se-0296]

[bitcoin-core]: https://github.com/bitcoin/bitcoin
[rpcauth]: https://github.com/bitcoin/bitcoin/blob/master/share/rpcauth/rpcauth.py
[gentoaddr]: https://developer.bitcoin.org/reference/rpc/generatetoaddress.html
[se-0296]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0296-async-await.md
