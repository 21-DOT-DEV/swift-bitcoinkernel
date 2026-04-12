# ``BitcoinKernel``

@Metadata {
    @TitleHeading("Framework")
}

BitcoinKernel provides idiomatic Swift types for the `libbitcoinkernel` C API, enabling block validation, chainstate management, and script verification.

## Overview

The BitcoinKernel module wraps Bitcoin Core's consensus engine with a type-safe Swift API. All types use Swift ARC for lifecycle management -- no manual `destroy` calls needed.

```swift
import BitcoinKernel

let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)
```

## Topics

### Essentials

- <doc:GettingStarted>
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

- <doc:VerifyingScripts>
- ``ScriptPubkey``
- ``ScriptVerificationFlags``
- ``ScriptVerifyStatus``

### Validation

- <doc:ValidatingBlocks>
- ``BlockValidationState``
- ``BlockValidationResult``
- ``ValidationMode``
- ``SynchronizationState``
- ``Warning``

### Logging

- ``LoggingConnection``
- ``LogCategory``
- ``LogLevel``

### Articles

- <doc:MemoryManagement>
