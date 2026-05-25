# ``BitcoinKernel``

@Metadata {
    @TitleHeading("Framework")
}

BitcoinKernel is a Swift library wrapping Bitcoin Core's [`libbitcoinkernel`][bitcoin-kernel] C API for block validation, chainstate management, chain sync, and script verification on iOS, iPadOS, macOS, and Linux.

## Overview

The BitcoinKernel module wraps Bitcoin Core's [`libbitcoinkernel`][bitcoin-kernel] behind a type-safe Swift API designed to match the style of Apple's [`swift-crypto`][swift-crypto] framework. It surfaces the consensus-validation engine extracted from Bitcoin Core's [`src/kernel`][bitcoin-kernel] subtree — block validation, chainstate management, chain sync, and script verification — with the network, wallet, and GUI subsystems excluded by design.

Every opaque C handle is owned by a Swift `class` whose `deinit` calls the matching `btck_*_destroy`, so memory management is invisible to callers — no manual cleanup, no `OpaquePointer` in public signatures. The module also ships a sync engine (``BlockchainSync``) that drives a ``ChainstateManager`` from any ``BlockSource`` while emitting typed [`AsyncSequence`][async-sequence] progress, per the Swift Concurrency model introduced in [SE-0298][se-0298].

The package is part of the [21-DOT-DEV][21dotdev] Swift Bitcoin ecosystem alongside [swift-tor][swift-tor] (embedded Tor for privacy-routed sync), [swift-event][swift-event] (async TCP sockets, a future P2P block-source substrate), and [swift-openssl][swift-openssl] (TLS/crypto).

```swift
import BitcoinKernel

let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)
```

### Where to start

Shipping `BitcoinKernel` inside an iPhone, iPad, or Apple Silicon Mac app? <doc:EmbeddingOnIOS> walks through the SwiftPM target topology, the sandbox-friendly data-directory placement, the cross-compile invocation, and the iOS-specific caveats that determine whether your app survives App Store review.

## Topics

### Guides

- <doc:EmbeddingOnIOS>

### Essentials

- ``Context``
- ``ContextOptions``

### Context and Configuration

- ``ChainParameters``
- ``ChainType``
- ``KernelError``
- ``NotificationCallbacks``
- ``ValidationInterfaceCallbacks``

### Chainstate Management

- ``ChainstateManager``
- ``ChainstateManagerOptions``
- ``Chain``
- ``Coin``

### Chain Sync

- ``BlockchainSync``
- ``BlockSource``
- ``EsploraBlockSource``
- ``BlockTip``
- ``BlockSourceError``

### Blocks

- ``Block``
- ``BlockHeader``
- ``BlockHash``
- ``BlockTreeEntry``
- ``BlockTreeEntrySnapshot``
- ``BlockSpentOutputs``

### Transactions

- ``Transaction``
- ``TransactionInput``
- ``TransactionOutput``
- ``TransactionOutPoint``
- ``Txid``
- ``TransactionSpentOutputs``
- ``PrecomputedTransactionData``

### Script Verification

- ``ScriptPubkey``
- ``ScriptVerificationFlags``
- ``ScriptVerifyStatus``

### Validation

- ``BlockValidationState``
- ``BlockValidationResult``
- ``ValidationMode``
- ``SynchronizationState``
- ``Warning``

### Logging

- ``LoggingConnection``
- ``LogCategory``
- ``LogLevel``

[21dotdev]: https://github.com/21-DOT-DEV
[async-sequence]: https://developer.apple.com/documentation/swift/asyncsequence
[bitcoin-kernel]: https://github.com/bitcoin/bitcoin/tree/master/src/kernel
[se-0298]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0298-asyncsequence.md
[swift-crypto]: https://github.com/apple/swift-crypto
[swift-event]: https://github.com/21-DOT-DEV/swift-event
[swift-openssl]: https://github.com/21-DOT-DEV/swift-openssl
[swift-tor]: https://github.com/21-DOT-DEV/swift-tor
