# Embedding BitcoinKernel on iOS without an xcframework

@Metadata {
    @TitleHeading("How-To Guide")
    @Available(iOS, introduced: "18.0")
    @Available(macOS, introduced: "15.0")
}

Ship Bitcoin Core's consensus-validation engine inside an iPhone, iPad, or Apple Silicon Mac app by adding `BitcoinKernel` as a Swift Package Manager dependency. SwiftPM compiles [`libbitcoinkernel`][bitcoin-kernel] and its C++ dependencies from source for each platform and architecture, so no hand-built xcframework or `lipo` step is required.

## Overview

Swift Package Manager builds C and C++ targets through the same toolchain it uses for Swift, invoking `clang` and `clang++` with the appropriate target triple for each destination. This package's entire dependency cascade is declared with [SwiftPM source targets][wrapping-c-cpp] rather than binary targets: [`libbitcoinkernel`][bitcoin-kernel], [`boost`][swift-boost], `crc32c`, `leveldb`, and `secp256k1`. The build system produces fresh per-arch object files every time it sees a new destination and links the result into your app.

The Swift seam is plain C: `libbitcoinkernel` exposes a `btck_*`-prefixed API via `extern "C"` headers. The ``BitcoinKernel`` module itself does not need Swift's [C++ interoperability feature][cxx-interop]. That feature is used by the sibling `Bitcoin` module for its higher-level wrappers, independent of how the kernel is embedded.

`libbitcoinkernel` is the consensus-validation engine extracted from Bitcoin Core's [`src/kernel`][bitcoin-kernel] subtree, with the network, wallet, and GUI subsystems excluded by design. That covers the surface area a wallet, block explorer, or Lightning node front-end actually needs from a full node, and nothing more. `BitcoinKernel` wraps the same C++ that runs on every Bitcoin Core full node. It is distinct from [`libbitcoin`][libbitcoin], an independent C++ reimplementation of Bitcoin, and from [`BlockchainCommons/iOS-Bitcoin`][bc-ios-bitcoin], a Swift wrapper over libbitcoin.

### Prerequisites

- Swift 6.3 toolchain (Xcode 26.4 or later), matching the package's `swift-tools-version` and the version pinned by CI.
- iOS 18.0+, macOS 15.0+, tvOS 18.0+, or visionOS 2.0+ deployment target, matching the package's declared minimums.
- Approximately 50 MB of free storage for a regtest data directory. Larger chains require substantially more disk; see [iOS-specific caveats](#ios-specific-caveats) below.

### How the target compiles for iOS

The ``BitcoinKernel`` target declares one runtime dependency: the C++ `libbitcoinkernel` target built from the Bitcoin Core sources vendored under `Sources/libbitcoinkernel/`. That target in turn depends on header-only [`boost`][swift-boost], the C++ libraries `crc32c` and `leveldb`, and the C library `secp256k1`. Every one of these is a SwiftPM source target rather than a binary target. SwiftPM compiles the entire stack at build time using your host's clang toolchain, invoked with the target triple your iOS destination requires.

That fact is the entire reason no xcframework is required. An xcframework exists to bundle multiple prebuilt slices of the same library, one per platform-arch combination, so a consumer can link without invoking the original compiler. When the compiler is invoked anyway, the bundle's reason to exist disappears. The [wrapping pattern this package follows][wrapping-c-cpp] places a Swift overlay on top of a C-API-exposing C++ target. This is the standard Swift.org-recommended approach for shipping a C/C++ codebase to all Apple platforms from one SwiftPM target.

### Add BitcoinKernel to your app

Add the package and depend on the `BitcoinKernel` product from your app target:

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

When you build the app for the first time, SwiftPM walks the dependency graph and compiles `libbitcoinkernel` and every transitive C/C++ target with your selected destination's triple. The first build takes several minutes on a clean derived-data directory; subsequent incremental builds finish in seconds because SwiftPM caches per-arch object files.

### Place the kernel data directory inside the app container

iOS sandboxing prohibits writing outside the app's container. `libbitcoinkernel` writes blocks and the chainstate LevelDB store to a developer-supplied path. Place that path inside the [Application Support directory][file-manager-url] and exclude it from iCloud backup. Chainstate is reproducible from the network, so backing it up wastes the user's iCloud quota for no recovery benefit.

```swift
import Foundation

enum KernelStorage {
    static func dataDirectory() throws -> URL {
        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var url = supportURL.appendingPathComponent("bitcoin-kernel", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        return url
    }
}
```

The bootstrap snippet in the next section calls `KernelStorage.dataDirectory()` directly, so the two examples compose into one runnable flow.

### Bootstrap the kernel at app launch

Set up a process-wide ``Context`` and ``ChainstateManager`` in the SwiftUI `App` initializer so the rest of your app can read them from the environment or pass them down explicitly:

```swift
import BitcoinKernel
import SwiftUI

@main
struct BitcoinApp: App {
    let manager: ChainstateManager

    init() {
        do {
            let dataDirectory = try KernelStorage.dataDirectory()
            let blocksDirectory = dataDirectory.appendingPathComponent("blocks", isDirectory: true)
            try FileManager.default.createDirectory(
                at: blocksDirectory,
                withIntermediateDirectories: true
            )

            let params = ChainParameters(.signet)
            let options = ContextOptions()
            options.setChainParams(params)
            let context = try Context(options: options)

            let managerOptions = try ChainstateManagerOptions(
                context: context,
                dataDirectory: dataDirectory.path,
                blocksDirectory: blocksDirectory.path
            )
            self.manager = try ChainstateManager(options: managerOptions)
        } catch {
            fatalError("BitcoinKernel bootstrap failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup { ContentView(manager: manager) }
    }
}
```

> Important: `fatalError` is reasonable for a wallet that cannot start without the kernel, but production code should surface the failure to the user. Corrupt data directories and full disks are recoverable through a wipe-and-resync UI flow; a crash on launch is not.

> Note: ``Context`` is `Sendable` and the kernel documents the underlying handle as thread-safe; share one instance freely. ``ContextOptions`` is not `Sendable`; configure on a single thread, build the ``Context``, then discard the options reference. ``ChainstateManager`` is `Sendable` and safe to hand across actors. The view types it returns (``BlockTreeEntry``, ``Block``, ``Transaction``) are also `Sendable` but their lifetimes are bound to the manager. Promote to an owned snapshot (``BlockTreeEntrySnapshot``) for storage that may outlive a read scope.

### Cross-compile from the command line

To verify your iOS configuration outside Xcode, drive `xcodebuild` against the package's auto-generated scheme. The scheme name is derived from the package name; for this package it's `BitcoinKernel-Package`:

```sh
xcrun xcodebuild \
    build \
    -scheme BitcoinKernel-Package \
    -destination 'generic/platform=iOS'
```

The same invocation with `-destination 'generic/platform=visionOS'` builds for visionOS. This is the exact pattern the project's CI runs; see [`.github/workflows/apple-builds.yml`][workflows].

`swift build --triple arm64-apple-ios18.0` will also succeed against the package, but it produces only the library. It does not link an iOS-runnable app and is not a substitute for `xcodebuild` when you intend to ship. Use it for fast compile-only verification while iterating on `Package.swift`.

### iOS-specific caveats

#### Disk budget

A regtest data directory occupies under 50 MB. Signet, the closest mainnet-shaped test network for iOS prototyping, settles in the single-digit GB range (blocks plus chainstate) after a full sync. Mainnet's block storage sums to roughly 700 GB as of May 2026 ([mainnet.observer blockchain size chart][mainnet-observer]), plus an additional ~12 GB chainstate. That's not a practical target for any consumer iOS app. Plan for signet or pruned-mode mainnet only.

#### No `fork`/`exec`

iOS sandboxing forbids both system calls. `libbitcoinkernel` does not require either because its NET, wallet, and GUI subsystems, which would otherwise spawn helper processes or threads tied to those features, are excluded at compile time. The kernel runs entirely within the calling app's process.

#### Background-task budgets

An initial chain sync takes longer than any iOS foreground session, so drive sync work from a background task and checkpoint progress through ``BlockchainSync`` so the next task resumes where the last one yielded. On iOS 26+, use [`BGContinuedProcessingTask`][bg-continued-task]; that's the API the package's sync engine is designed to integrate with. On iOS 18–25, fall back to [`BGProcessingTask`][bg-processing-task]. A sync that runs only in the foreground will never catch up.

#### Thread-safety

``Context`` and ``ChainstateManager`` are safe to share across actors. View types returned from the manager are `Sendable` but lifetime-bound to it. Use ``BlockTreeEntrySnapshot`` for storage that outlives a read scope.

> Warning: App Store encryption export compliance. `libbitcoinkernel` links libsecp256k1, which is cryptographic code, so App Store Connect will surface the [encryption export compliance question][export-compliance] during your first submission. Most apps embedding it can correctly claim the open-source-cryptography exemption, but you must answer the question and file the appropriate annual self-classification or year-end report on time.

### Troubleshooting

#### Undefined symbol `_btck_*` at link time

Your app target's dependency list is missing the `BitcoinKernel` product from the `swift-bitcoinkernel` package. Add it explicitly. Transitive resolution does not pull a library target into your app's link line.

#### Cold build takes five minutes or more

Expected. The entire Bitcoin Core C++ tree compiles once per platform-arch combination on a fresh derived-data directory. Incremental rebuilds reuse cached object files and finish in seconds. Use `xcodebuild -derivedDataPath ./Build` and cache that directory in CI to amortize the cost across runs.

## See Also

- ``Context``
- ``ChainstateManager``
- ``BlockchainSync``
- [Mixing Swift and C++ — Swift.org][cxx-interop]
- [Wrapping a C/C++ Library in Swift — Swift.org][wrapping-c-cpp]
- [Bitcoin Core `src/kernel`][bitcoin-kernel]

[bc-ios-bitcoin]: https://github.com/BlockchainCommons/iOS-Bitcoin
[bg-continued-task]: https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
[bg-processing-task]: https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask
[bitcoin-kernel]: https://github.com/bitcoin/bitcoin/tree/master/src/kernel
[cxx-interop]: https://www.swift.org/documentation/cxx-interop/
[export-compliance]: https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations
[file-manager-url]: https://developer.apple.com/documentation/foundation/filemanager/url(for:in:appropriatefor:create:)
[libbitcoin]: https://github.com/libbitcoin/libbitcoin-system
[mainnet-observer]: https://mainnet.observer/charts/block-chain-size/
[swift-boost]: https://github.com/21-DOT-DEV/swift-boost
[workflows]: https://github.com/21-DOT-DEV/swift-bitcoinkernel/blob/main/.github/workflows/apple-builds.yml
[wrapping-c-cpp]: https://www.swift.org/documentation/articles/wrapping-c-cpp-library-in-swift.html
