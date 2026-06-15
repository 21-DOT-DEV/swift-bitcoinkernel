# Getting Started with BitcoinKernel

@Metadata {
    @TitleHeading("How-To Guide")
    @Available(iOS, introduced: "18.0")
    @Available(macOS, introduced: "15.0")
}

Install `BitcoinKernel` via Swift Package Manager and boot Bitcoin Core's consensus-validation engine inside your own Swift process, ending with a running ``ChainstateManager`` pinned to the regtest genesis in a throwaway temporary directory.

## Overview

`BitcoinKernel` wraps Bitcoin Core's [`libbitcoinkernel`][bitcoin-kernel] behind a type-safe Swift API. `libbitcoinkernel` is the consensus-validation engine extracted from [`src/kernel`][bitcoin-kernel] with the network, wallet, and GUI subsystems excluded by design.

This article walks from an empty SwiftPM project to a live engine. Install the dependency, build two objects (``Context`` and ``ChainstateManager``), and confirm the engine has located its tip.

### Prerequisites

- Swift 6.3 toolchain (Xcode 26.4 or later on Apple platforms, matching `swift-tools-version` on Linux).
- A deployment target on macOS 15.0+, iOS 18.0+, iPadOS 18.0+, or a Linux distribution with a current Swift toolchain.
- Under 50 MB of free disk space for the regtest data directory this article creates.

### Add BitcoinKernel with Swift Package Manager

Add the package, then depend on the `BitcoinKernel` product from your target:

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
            .product(name: "BitcoinKernel", package: "swift-bitcoinkernel"),
        ]
    ),
]
```

The first build compiles `libbitcoinkernel` and its C/C++ dependencies from source for your destination's triple. Expect several minutes on a cold cache and seconds for incremental rebuilds. The Xcode equivalent is **File → Add Package Dependencies…** and resolves to the same `Package.resolved`.

### Boot the validating engine

Two objects get a regtest consensus engine running in a throwaway temporary directory. The example below is `Snippets/BootValidatingEngine.swift` in the package and is compile-checked on every `swift build`.

@Snippet(path: "BitcoinKernel/Snippets/BootValidatingEngine")

A ``Context`` carries the chain parameters and the interrupt handle every validation operation reads from. A ``ChainstateManager`` opens the block-index and chainstate LevelDB stores under a writable data directory, replays any existing state, and exposes the chain tip via ``ChainstateManager/bestEntry``. The convenience initializer builds a ``ChainstateManagerOptions`` for you; reach for that type directly when you need worker-thread counts or in-memory databases.

On a fresh regtest data directory the kernel writes the embedded regtest genesis block and nothing else, so `bestEntry.height` returning `0` proves the engine opened both LevelDB stores, loaded the chain parameters, and now knows where its tip is. Anything other than `0` against a fresh regtest directory indicates a partial boot.

### Where to go next

The snippet above uses a disposable temp directory and stops at the regtest genesis on purpose. What to read next depends on what you're adding.

- To ship inside an iPhone, iPad, or Apple Silicon Mac app, see <doc:EmbeddingOnIOS> for production data-directory layout, the SwiftUI `App` init pattern, background-task budgets for chain sync, and App Store encryption-export self-classification.
- To drive a real chain sync, pair ``BlockchainSync`` with any ``BlockSource`` conformer; the shipped ``EsploraBlockSource`` covers HTTP-served Esplora endpoints and emits progress as a typed [`AsyncSequence`][async-sequence].
- To talk to a running Bitcoin Core daemon over RPC instead, use the sibling `Bitcoin` product, which embeds the full `bitcoind` and exposes a typed RPC client.

## See Also

- ``Context``
- ``ChainstateManager``
- ``ChainstateManagerOptions``
- ``BlockchainSync``
- ``EsploraBlockSource``
- <doc:EmbeddingOnIOS>
- [Bitcoin Core `src/kernel`][bitcoin-kernel]
- [Wrapping a C/C++ Library in Swift — Swift.org][wrapping-c-cpp]
- [`FileManager.temporaryDirectory` — Apple][file-manager-temp]

[async-sequence]: https://developer.apple.com/documentation/swift/asyncsequence
[bitcoin-kernel]: https://github.com/bitcoin/bitcoin/tree/master/src/kernel
[file-manager-temp]: https://developer.apple.com/documentation/foundation/filemanager/temporarydirectory
[wrapping-c-cpp]: https://www.swift.org/documentation/articles/wrapping-c-cpp-library-in-swift.html
