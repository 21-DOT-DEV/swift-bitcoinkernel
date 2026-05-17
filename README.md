[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Apple Platforms](https://github.com/21-DOT-DEV/swift-bitcoin/actions/workflows/apple-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoin/actions/workflows/apple-builds.yml)
[![Docker Builds](https://github.com/21-DOT-DEV/swift-bitcoin/actions/workflows/docker-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoin/actions/workflows/docker-builds.yml)

# ₿ swift-bitcoin

Swift framework for embedding a full Bitcoin node and consensus engine. Typed `async`/`await` JSON-RPC, in-process `bitcoind` lifecycle, and a standalone `BitcoinKernel` consensus-validation product. Uses Swift's [C++ interoperability](https://www.swift.org/documentation/cxx-interop/) with [Bitcoin Core](https://github.com/bitcoin/bitcoin).

📚 [Bitcoin](https://docs.21.dev/documentation/bitcoin/) · [BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/)

> [!CAUTION]
> This package is pre-1.0 ([SemVer major version zero](https://semver.org/#spec-item-4)). The public API is not stable and may change with any release. Pin a version using `exact:` to avoid unexpected breaking changes. Mainnet operations move real value — test on `regtest` or `signet` first.

## Contents

- [Why swift-bitcoin?](#why-swift-bitcoin)
- [Features](#features)
- [Installation](#installation)
- [Package Traits](#package-traits)
- [Quick Start](#quick-start)
- [Hosted documentation](#hosted-documentation)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Why swift-bitcoin?

Reach for swift-bitcoin when you want Bitcoin Core's reference implementation embedded directly in a Swift binary instead of running `bitcoind` out-of-process: no IPC overhead, single-binary deploy, deterministic regtest fixtures inside the same test runner. This is a *node* layer, not a wallet SDK — pair it with a wallet library, or opt into Bitcoin Core's wallet via the `wallet` package trait. For consumers that need consensus rules without the full daemon (wallets, light clients, block-validation services), the standalone `BitcoinKernel` product wraps `libbitcoinkernel` and links cleanly without dragging in networking, mempool, or RPC.

## Features

- **Embedded daemon** — in-process `bitcoind` lifecycle via `Daemon.start(with:)`, configured with the type-safe `BitcoinConfig` builder (phantom-typed `mainnet()` / `testnet()` / `signet()` / `regtest()` factories with compile-time-checked options).
- **Typed JSON-RPC** — `RPCClient` with async/await methods covering all 171 [Bitcoin Core v31.0](https://github.com/bitcoin/bitcoin/releases/tag/v31.0) RPCs across 8 categories, decoded into ~90 `Codable` `Sendable` response models.
- **Pluggable transports** — `DirectTransport` (in-process C bridge), `HTTPTransport` (Basic auth), `CookieTransport` (cookie-file auth), and `AutoTransport` (routes wallet RPCs over HTTP, everything else direct). The `RPCClient(url:username:password:)` initializer wires up `AutoTransport` for you.
- **`BitcoinKernel` standalone product** — wraps `libbitcoinkernel` for consensus validation without the daemon. Includes the `BlockchainSync` API (typed `AsyncSequence<Update>` with KVO-observable `Foundation.Progress`) and the `BlockSource` protocol for plugging in custom block providers (`EsploraBlockSource` ships in-tree). Used by wallets and SDKs that need consensus rules but not a full node.
- **Bitcoin Core v31.0 statically vendored** via [subtree](https://github.com/21-DOT-DEV/subtree) — pinned commit, audited patches under `patches/`, no system `bitcoind` dependency at runtime.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-bitcoin.git", from: "0.1.0"),
```

> [!WARNING]
> Pin with `exact:` while the package is pre-1.0 ([SemVer 0.y.z](https://semver.org/#spec-item-4) reserves this range as "anything may change at any time").

Include `Bitcoin` (or `BitcoinKernel`) in your target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "Bitcoin", package: "swift-bitcoin"),
    // .product(name: "BitcoinKernel", package: "swift-bitcoin"),
]),
```

Or use Xcode: **File → Add Packages…**, then enter `https://github.com/21-DOT-DEV/swift-bitcoin`.

## Package Traits

This package uses [SE-0450 Package Traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md) to gate optional functionality. By default, no traits are enabled.

### `wallet`

Opts into Bitcoin Core's wallet functionality. Off by default to keep binary size and the dependency graph small. Enable when you need wallet RPCs (`createwallet`, `sendtoaddress`, `walletProcessPSBT`, etc.):

```swift
.package(
    url: "https://github.com/21-DOT-DEV/swift-bitcoin.git",
    from: "0.1.0",
    traits: ["wallet"]
),
```

> [!NOTE]
> Xcode does not currently resolve SwiftPM package trait conditions for Swift settings. As a workaround, wallet sources are guarded with `#if Xcode || ENABLE_WALLET` so the wallet API is always visible in Xcode builds. This means the "small binary size" benefit only applies to `swift build` from the command line — Xcode consumers always compile the wallet Swift API surface, regardless of whether they opt into the `wallet` trait. Package traits are fully respected when building with `swift build`.

## Quick Start

Run an embedded `bitcoind` on regtest and query it through `RPCClient`:

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

let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .server()
    .dataDir("/tmp/bitcoin-regtest")
    .txIndex()

try Daemon.start(with: config)

let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "111",
    password: "222"
)

let info = try await client.getBlockchainInfo()
print("Chain: \(info.chain), blocks: \(info.blocks)")

_ = try await client.stop()
Daemon.waitUntilStopped()
```

`Daemon.start(with:)` validates the config, starts `bitcoind` on a background thread, and returns immediately. Shut down by sending the `stop` RPC and then calling `Daemon.waitUntilStopped()`.

*→ Full walkthrough: [Getting Started](https://docs.21.dev/documentation/bitcoin/gettingstarted)*

## Hosted documentation

The DocC catalogs under [`Sources/Bitcoin/Bitcoin.docc/`](Sources/Bitcoin/Bitcoin.docc/) and [`Sources/BitcoinKernel/BitcoinKernel.docc/`](Sources/BitcoinKernel/BitcoinKernel.docc/) cover every shipping capability:

- [Getting Started](https://docs.21.dev/documentation/bitcoin/gettingstarted) — full node walkthrough from `Daemon.start` to wallet PSBT signing
- [Configuring Bitcoin Core](https://docs.21.dev/documentation/bitcoin/configuringbitcoincore) — `BitcoinConfig` builder, network presets, Tor/SOCKS5 proxy
- [Choosing an RPC Transport](https://docs.21.dev/documentation/bitcoin/choosinganrpctransport) — `Direct` vs `HTTP` vs `Cookie` vs `Auto`
- [Architecture](https://docs.21.dev/documentation/bitcoin/architecture) — daemon ↔ RPC ↔ kernel boundaries, Swift C++ interop, vendored sources
- BitcoinKernel: [Validating Blocks](https://docs.21.dev/documentation/bitcoinkernel/validatingblocks) · [Verifying Scripts](https://docs.21.dev/documentation/bitcoinkernel/verifyingscripts) · [Sync](https://docs.21.dev/documentation/bitcoinkernel/sync) · [Memory Management](https://docs.21.dev/documentation/bitcoinkernel/memorymanagement)

Build the full hyperlinked archive locally with `swift package generate-documentation --target Bitcoin`.

## Requirements

| Tool | Minimum version |
| --- | --- |
| Swift | 6.3 |
| Xcode | 17 |
| macOS | 15 |
| iOS / iPadOS | 18 |
| Linux | Ubuntu 22.04+ (Tier 2)¹ |
| tvOS / visionOS | Tier 2¹ |

¹ Tier 2 platforms are aspirational — they may build but are not exercised in CI on every change. See [`AGENTS.md`](AGENTS.md) for current platform tier definitions.

## Contributing

Bug reports and pull requests are welcome. Start with:

- [AGENTS.md](AGENTS.md) — project architecture, target boundaries, subtree extraction flow, C++ interop rules.
- [Projects/AGENTS.md](Projects/AGENTS.md) — Tuist project, demo apps, XCFramework workflows.
- [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) — branching and commit conventions.

> [!IMPORTANT]
> Files under `Sources/{bitcoind,libbitcoinkernel,secp256k1,leveldb,minisketch,crc32c}/` are extracted from upstream and are overwritten on the next subtree sync. Local changes for SPM/embedded use live in `patches/` — see [`patches/README.md`](patches/README.md).

## Security

For vulnerability reports, see [SECURITY.md](SECURITY.md). It routes by component: Swift wrapper bugs go to the local report path, Bitcoin Core consensus/network/wallet vulnerabilities go upstream to [bitcoincore.org/en/contact/](https://bitcoincore.org/en/contact/), and other 21-DOT-DEV components follow the [organization Security Policy](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md).

## License

Released under the MIT License — see [LICENSE](LICENSE). Bitcoin Core is itself MIT-licensed (see [`Vendor/bitcoin/COPYING`](https://github.com/bitcoin/bitcoin/blob/master/COPYING)). Vendored dependencies carry their own licenses:

- [LevelDB](https://github.com/google/leveldb/blob/main/LICENSE) — BSD-3-Clause (Google)
- [crc32c](https://github.com/google/crc32c/blob/main/LICENSE) — BSD-3-Clause (Google)
- [secp256k1](https://github.com/bitcoin-core/secp256k1/blob/master/COPYING) — MIT (Bitcoin Core developers)
- [minisketch](https://github.com/bitcoin-core/minisketch/blob/master/COPYING) — MIT (Bitcoin Core developers)
