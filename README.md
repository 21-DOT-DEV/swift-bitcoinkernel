[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Apple Platforms](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/apple-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/apple-builds.yml)
[![Docker Builds](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/docker-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-bitcoinkernel/actions/workflows/docker-builds.yml)

# ₿ swift-bitcoinkernel

Swift package for Bitcoin consensus validation, optionally embedding a full Bitcoin node in-process. The `BitcoinKernel` product wraps [`libbitcoinkernel`](https://github.com/bitcoin/bitcoin/tree/master/src/kernel) from [Bitcoin Core](https://github.com/bitcoin/bitcoin); the `Bitcoin` product adds an embedded `bitcoind` and a typed `async`/`await` JSON-RPC client.

📚 [BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/) · [Bitcoin](https://docs.21.dev/documentation/bitcoin/)

> [!CAUTION]
> Pre-1.0 ([SemVer 0.y.z](https://semver.org/#spec-item-4)) — the public API may change at any release; pin with `exact:`. Mainnet operations move real value; test on `regtest` or `signet` first.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Package Traits](#package-traits)
- [Usage Examples](#usage-examples)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

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
> Xcode doesn't resolve SwiftPM trait conditions for Swift settings. Wallet sources are guarded with `#if Xcode || ENABLE_WALLET`, so Xcode consumers always compile the wallet API surface regardless of the trait. The trait is honored fully under `swift build`.

## Usage Examples

### Validate consensus with `BitcoinKernel`

Boot the validation engine against a fresh regtest data directory and confirm the chainstate has loaded by reading the tip height:

```swift
import BitcoinKernel
import Foundation

let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)

let dataDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .path(percentEncoded: false)

let managerOptions = try ChainstateManagerOptions(
    context: context,
    dataDirectory: dataDirectory
)
let manager = try ChainstateManager(options: managerOptions)

print(manager.bestEntry.height)  // 0 on a fresh regtest directory
```

*→ Full guide: [Getting Started — BitcoinKernel](https://docs.21.dev/documentation/bitcoinkernel/gettingstarted)*

### Embed `bitcoind` and query it with `RPCClient`

Run an embedded `bitcoind` on regtest and call a typed JSON-RPC method:

```swift
import Bitcoin
import Foundation

// Demo credentials — username "111", password "222". Regtest only.
// Generate your own with Bitcoin Core's helper:
//     python3 share/rpcauth/rpcauth.py <username> <password>
let auth = RPCAuth(
    username: "111",
    salt: "14c1e13a71b7d6a4dab6c9d8f107bb5b",
    passwordHMAC: "73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4"
)

// Bitcoin Core requires the data directory to exist before startup.
let dataDir = URL.temporaryDirectory.appending(path: "bitcoin-regtest")
try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

let config = BitcoinConfig
    .regtest()
    .rpcAuth(auth)
    .server()
    .dataDir(dataDir.path(percentEncoded: false))

try Daemon.start(with: config)

// `Daemon.start(with:)` returns as soon as the daemon thread is launched.
// `bootstrap` polls until the RPC server is ready before the first call.
try await Daemon.bootstrap(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "111",
    password: "222"
)

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

*→ Full guide: [Getting Started — Bitcoin](https://docs.21.dev/documentation/bitcoin/gettingstarted)*

## Documentation

The DocC catalogs under [`Sources/Bitcoin/Bitcoin.docc/`](Sources/Bitcoin/Bitcoin.docc/) and [`Sources/BitcoinKernel/BitcoinKernel.docc/`](Sources/BitcoinKernel/BitcoinKernel.docc/) cover the embedded daemon and consensus-validation surfaces:

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

For vulnerability reports, see [SECURITY.md](SECURITY.md).

## License

Released under the MIT License — see [LICENSE](LICENSE). Vendored dependencies carry their own licenses:

- [Bitcoin Core](https://github.com/bitcoin/bitcoin/blob/master/COPYING) — MIT
- [LevelDB](https://github.com/google/leveldb/blob/main/LICENSE) — BSD-3-Clause (Google)
- [crc32c](https://github.com/google/crc32c/blob/main/LICENSE) — BSD-3-Clause (Google)
- [secp256k1](https://github.com/bitcoin-core/secp256k1/blob/master/COPYING) — MIT
- [minisketch](https://github.com/bitcoin-core/minisketch/blob/master/COPYING) — MIT
