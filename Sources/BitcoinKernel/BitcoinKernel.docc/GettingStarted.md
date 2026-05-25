# Getting Started with BitcoinKernel

@Metadata {
    @TitleHeading("How-To Guide")
    @Available(iOS, introduced: "18.0")
    @Available(macOS, introduced: "15.0")
}

Install `BitcoinKernel` via Swift Package Manager and boot Bitcoin Core's consensus-validation engine inside your own Swift process on macOS 15+, iOS 18+, iPadOS 18+, or Linux — ending with a running ``ChainstateManager`` pinned to the regtest genesis in a throwaway temporary directory.

## Overview

**Key facts.** Swift 6.3 toolchain · macOS 15+ · iOS 18+ · iPadOS 18+ · Linux · Regtest first-run · Single SwiftPM dependency.

`BitcoinKernel` wraps Bitcoin Core's [`libbitcoinkernel`][bitcoin-kernel] — the consensus-validation engine extracted from [`src/kernel`][bitcoin-kernel] with the network, wallet, and GUI subsystems excluded by design — behind a type-safe Swift API. This article walks from an empty SwiftPM project to a live engine: install the dependency, build three objects (``Context``, ``ChainstateManagerOptions``, ``ChainstateManager``), and confirm the engine has located its tip.

### Prerequisites

- Swift 6.3 toolchain (Xcode 26.4 or later on Apple platforms; matching `swift-tools-version` on Linux), so the package resolves cleanly.
- A deployment target on macOS 15.0+, iOS 18.0+, iPadOS 18.0+, or a Linux distribution with a current Swift toolchain.
- Under 50 MB of free disk space — the regtest data directory this article creates is tiny and lives in your system's temporary directory.

### Add BitcoinKernel with Swift Package Manager

Add the package, then depend on the `BitcoinKernel` product from your target:

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
            .product(name: "BitcoinKernel", package: "swift-bitcoinkernel"),
        ]
    ),
]
```

The first build compiles `libbitcoinkernel` and its C/C++ dependencies from source for your destination's triple — several minutes on a cold cache, seconds for incremental rebuilds. The Xcode equivalent is **File → Add Package Dependencies…**; both routes resolve to the same `Package.resolved`.

### Boot the validating engine

Three objects, constructed in fixed order, get a regtest consensus engine running in a throwaway temporary directory. This is `Snippets/BootValidatingEngine.swift` in the package, compile-checked on every `swift build`:

@Snippet(path: "BitcoinKernel/Snippets/BootValidatingEngine")

A ``Context`` carries the chain parameters and the interrupt handle every validation operation reads from; a ``ChainstateManagerOptions`` binds that context to a writable data directory; a ``ChainstateManager`` opens the block-index and chainstate LevelDB stores under that directory, replays any existing state, and exposes the chain tip via ``ChainstateManager/bestEntry``. On a fresh regtest data directory the kernel writes the embedded regtest genesis block and nothing else, so `bestEntry.height` returning `0` proves the engine opened both LevelDB stores, loaded the chain parameters, and now knows where its tip is — anything other than `0` against a fresh regtest directory indicates a partial boot.

### Where to go next

The snippet above uses a disposable temp directory and stops at the regtest genesis on purpose, so the article you read next depends on what you're adding:

- **Shipping inside an iPhone, iPad, or Apple Silicon Mac app.** <doc:EmbeddingOnIOS> covers the production data-directory layout (Application Support, backup exclusion), the SwiftUI `App` init pattern, background-task budgets for chain sync, and the App Store encryption-export self-classification.
- **Driving a real chain sync.** The ``BlockchainSync`` engine pulls blocks from any ``BlockSource`` conformer and feeds them into the manager you just built. The shipped ``EsploraBlockSource`` covers HTTP-served Esplora endpoints; that pair gets you from regtest genesis to a synced signet or mainnet tip with progress as a typed [`AsyncSequence`][async-sequence].
- **Talking to a running Bitcoin Core daemon over RPC instead.** The package's sibling `Bitcoin` product embeds the full `bitcoind` and exposes a typed RPC client — a different mental model than the kernel-only approach this article takes.

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
