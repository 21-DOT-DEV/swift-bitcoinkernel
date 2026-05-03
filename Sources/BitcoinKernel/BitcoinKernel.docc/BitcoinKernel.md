# ``BitcoinKernel``

@Metadata {
    @TitleHeading("Framework")
}

BitcoinKernel is a Swift library wrapping Bitcoin Core's `libbitcoinkernel` C API for block validation, chainstate management, chain sync, and script verification on macOS and Linux.

## Overview

BitcoinKernel wraps Bitcoin Core's [`libbitcoinkernel`](https://github.com/bitcoin/bitcoin/tree/master/src/kernel) behind a type-safe Swift API. Every opaque C handle is owned by a Swift `class` whose `deinit` calls the matching `btck_*_destroy`, so memory management is invisible to callers — no manual cleanup, no `OpaquePointer` in public signatures. The module also ships a sync engine (``BlockchainSync``) that drives a ``ChainstateManager`` from any ``BlockSource`` while emitting typed `AsyncSequence` progress.

The package is part of the [21-DOT-DEV](https://github.com/21-DOT-DEV) Swift Bitcoin ecosystem alongside [swift-tor](https://github.com/21-DOT-DEV/swift-tor) (embedded Tor for privacy-routed sync), [swift-event](https://github.com/21-DOT-DEV/swift-event) (async TCP sockets, a future P2P block-source substrate), and [swift-openssl](https://github.com/21-DOT-DEV/swift-openssl) (TLS/crypto).

```swift
import BitcoinKernel

let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)
```

### Where to start

New to BitcoinKernel? Start with <doc:GettingStarted> for a task-oriented walkthrough of context and chainstate setup. To drive a real sync from an HTTP block source, read <doc:Sync>. For block- and script-validation recipes, see <doc:ValidatingBlocks> and <doc:VerifyingScripts>. The ARC-based ownership model that underpins every type is explained in <doc:MemoryManagement>.

## Topics

### Guides

- <doc:GettingStarted>
- <doc:Sync>
- <doc:ValidatingBlocks>
- <doc:VerifyingScripts>

### Concepts

- <doc:MemoryManagement>

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
