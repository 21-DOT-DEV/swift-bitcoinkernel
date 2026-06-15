[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Apple Platforms](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/apple-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/apple-builds.yml)
[![Docker Builds](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/docker-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/docker-builds.yml)
[![Tuist Apps](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/tuist-apps.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/tuist-apps.yml)

# ₿ swift-bitcoinkernel

Swift package for Bitcoin consensus validation, optionally embedding a full Bitcoin node in-process. The `BitcoinKernel` product wraps [`libbitcoinkernel`](https://github.com/bitcoin/bitcoin/tree/master/src/kernel) from [Bitcoin Core](https://github.com/bitcoin/bitcoin); the `Bitcoin` product adds an embedded `bitcoind` and a typed `async`/`await` JSON-RPC client.

📚 [BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/) · [Bitcoin](https://docs.21.dev/documentation/bitcoin/)

> [!CAUTION]
> Pre-1.0 ([SemVer 0.y.z](https://semver.org/#spec-item-4)) — the public API may change at any release; pin with `exact:`. Mainnet operations move real value; test on `regtest` or `signet` first.

## Contents

- [Which product?](#which-product)
- [Features](#features)
- [Installation](#installation)
- [Package Traits](#package-traits)
- [Platform notes](#platform-notes)
- [Usage Examples](#usage-examples)
- [Demo Apps](#demo-apps)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Which product?

| Goal | Product | Demo app | Getting started |
|------|---------|----------|-----------------|
| Validate consensus or sync a chain, no networking | `BitcoinKernel` | `KernelApp` | [Guide](https://docs.21.dev/documentation/bitcoinkernel/gettingstarted) |
| Run a full node with in-process RPC | `Bitcoin` | `NodeApp` | [Guide](https://docs.21.dev/documentation/bitcoin/gettingstarted) |

## Features

- Wrap Bitcoin Core's `libbitcoinkernel` for consensus validation without a daemon
- Embed `bitcoind` in-process via a typed `BitcoinConfig` builder and `Daemon` lifecycle
- Cover all 171 [Bitcoin Core v31.0](https://github.com/bitcoin/bitcoin/releases/tag/v31.0) JSON-RPCs through an async/await `RPCClient`
- Route RPCs through pluggable transports: direct in-process, HTTP, cookie-file, or auto-detect
- Ship a `BlockchainSync` engine and a `BlockSource` protocol for custom block providers
- Track chain-sync progress with KVO-observable `Foundation.Progress` for SwiftUI bindings and `BGContinuedProcessingTask` budgets
- Route block downloads or RPC traffic through Tor with a SOCKS5-configured `URLSession`

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-bitcoinkernel.git", exact: "0.1.0"),
```

Include `BitcoinKernel` in your target:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "BitcoinKernel", package: "swift-bitcoinkernel"),
]),
```

For the `Bitcoin` product (embedded daemon and RPC client), opt your target into Swift's C++ interoperability mode:

```swift
.target(name: "<target>",
    dependencies: [
        .product(name: "Bitcoin", package: "swift-bitcoinkernel"),
    ],
    swiftSettings: [
        .interoperabilityMode(.Cxx),
    ]
),
```

Or use Xcode: **File → Add Packages…**, then enter `https://github.com/21-DOT-DEV/swift-bitcoinkernel`. For the `Bitcoin` product in Xcode, set **C++ and Objective-C Interoperability** to `C++/Objective-C++` in the target's Build Settings.

Pin with a version tag. At a tagged release the package excludes its development plugins (tuist, subtree, docc); pinning a commit or branch instead resolves that full toolchain into your dependency graph.

## Package Traits

The package uses [SE-0450 Package Traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md) to gate optional functionality. No traits are enabled by default.

### `wallet`

Opts into Bitcoin Core's wallet RPCs (`createwallet`, `sendtoaddress`, `walletProcessPSBT`, etc.). Off by default to keep the dependency graph small.

```swift
.package(
    url: "https://github.com/21-DOT-DEV/swift-bitcoinkernel.git",
    exact: "0.1.0",
    traits: ["wallet"]
),
```

> [!NOTE]
> The `wallet` trait is a dependency and binary-size optimization, not a security boundary. Under `swift build` the trait is honored fully. Under Xcode it is not: Xcode doesn't resolve SwiftPM trait conditions, so wallet sources guarded by `#if Xcode || ENABLE_WALLET` always compile and the wallet API surface is always present. If your threat model requires wallet code to be absent, do not rely on the trait; run the daemon with `-disablewallet`.

## Platform notes

- **tvOS** builds `BitcoinKernel` only. The `Bitcoin` product depends on `execvp` (marked `__TVOS_PROHIBITED`) and does not compile for tvOS.
- **Linux** consumers of `Bitcoin` link the system SQLite. Install `libsqlite3-dev` (Debian/Ubuntu) or `sqlite-devel` (Fedora/RHEL).
- **Storage**: regtest and signet stay in the tens of MB. Pruned mainnet keeps roughly 12 GB of UTXO chainstate plus the pruned block target (≥ 550 MiB). A full mainnet node is ~700 GB and growing.

## Usage Examples

### Validate consensus with `BitcoinKernel`

Boot the validation engine against a fresh regtest data directory and read the tip height to confirm the chainstate loaded. `Context(chain:)` wraps the options builder for the common case:

```swift
import BitcoinKernel
import Foundation

let context = try Context(chain: .regtest)

let dataDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .path(percentEncoded: false)

let manager = try ChainstateManager(context: context, dataDirectory: dataDirectory)

print(manager.bestEntry.height)  // 0 on a fresh regtest directory
```

*→ Full guide: [Getting Started — BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/gettingstarted)*

### Embed `bitcoind` and query it with `RPCClient`

Start an embedded `bitcoind` on regtest and call a typed JSON-RPC method. Cookie authentication derives the endpoint and credentials from the config, so they are supplied once and no RPC password lives in your code:

```swift
import Bitcoin
import Foundation

// Bitcoin Core requires the data directory to exist before startup.
let dataDir = URL.temporaryDirectory.appending(path: "bitcoin-regtest")
try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

let config = BitcoinConfig
    .regtest()
    .server()
    .dataDir(dataDir.path(percentEncoded: false))

let client = try await Daemon.startAndConnect(with: config)

let info = try await client.getBlockchainInfo()
print("Chain: \(info.chain), blocks: \(info.blocks)")

_ = try await client.stop()
Daemon.waitUntilStopped()
```

*→ Full guide: [Getting Started — Bitcoin](https://docs.21.dev/documentation/bitcoin/gettingstarted)*

## Demo Apps

Two SwiftUI apps in the [`Projects/`](Projects/) Tuist workspace exercise the package end to end. `NodeApp` drives the embedded `bitcoind` lifecycle, the typed `RPCClient`, and an optional Tor SOCKS proxy. `KernelApp` runs a `BitcoinKernel` chain sync through `BlockchainSync` over an Esplora block source.

```sh
swift package --disable-sandbox tuist generate -p Projects/ --no-open
open Projects/Bitcoin.xcworkspace
```

Pick the `NodeApp` or `KernelApp` scheme and run. [`Projects/README.md`](Projects/README.md) has the full tour, including the Tor wiring and the macOS/iOS build-and-test commands.

## Documentation

The DocC catalogs for [Bitcoin](https://docs.21.dev/documentation/bitcoin/) and [BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/) cover the embedded daemon and consensus-validation surfaces:

- [Getting Started — Bitcoin](https://docs.21.dev/documentation/bitcoin/gettingstarted) — full node walkthrough from `Daemon.start` through the first RPC round-trip
- [Getting Started — BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/gettingstarted) — boot `libbitcoinkernel` with a `Context`, `ChainstateManagerOptions`, and `ChainstateManager`
- [Embedding BitcoinKernel on iOS](https://docs.21.dev/documentation/bitcoinkernel/embeddingonios) — shipping the consensus engine inside an iPhone, iPad, or Apple Silicon Mac app

Build the hyperlinked archive locally:

```sh
swift package generate-documentation --target Bitcoin
swift package generate-documentation --target BitcoinKernel
```

Each tagged release also publishes a downloadable `.doccarchive.zip` on the corresponding [GitHub Release](https://github.com/21-DOT-DEV/swift-bitcoinkernel/releases).

## Contributing

Contributions are welcome. Read [AGENTS.md](AGENTS.md) for project architecture and the subtree extraction flow, [Projects/AGENTS.md](Projects/AGENTS.md) for the Tuist workspace, and the [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) for branching conventions.

> [!IMPORTANT]
> Files under `Sources/{bitcoind,libbitcoinkernel,secp256k1,leveldb,minisketch,crc32c}/` are extracted from upstream and overwritten on every subtree sync. Local changes for SPM/embedded use live in `patches/` — see [`patches/README.md`](patches/README.md).

## Security

For vulnerability reports, see [SECURITY.md](SECURITY.md). Patches to the vendored Bitcoin Core never touch consensus code; see the [patch policy](SECURITY.md#patch-policy).

## License

Released under the MIT License — see [LICENSE](LICENSE). Vendored dependencies carry their own licenses:

- [Bitcoin Core](https://github.com/bitcoin/bitcoin/blob/master/COPYING) — MIT
- [LevelDB](https://github.com/google/leveldb/blob/main/LICENSE) — BSD-3-Clause (Google)
- [crc32c](https://github.com/google/crc32c/blob/main/LICENSE) — BSD-3-Clause (Google)
- [secp256k1](https://github.com/bitcoin-core/secp256k1/blob/master/COPYING) — MIT
- [minisketch](https://github.com/bitcoin-core/minisketch/blob/master/COPYING) — MIT
