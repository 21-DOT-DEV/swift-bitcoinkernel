# Getting Started with BitcoinKernel

@Metadata {
    @TitleHeading("Tutorial")
}

Learn how to set up a kernel context, configure chain parameters, and manage chainstate.

## Creating a Context

Every operation in BitcoinKernel starts with a ``Context``. The context holds chain parameters and optional notification callbacks. Create one by configuring ``ContextOptions``:

```swift
import BitcoinKernel

let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)
```

The context is thread-safe and can be shared across multiple threads.

## Setting Up Notification Callbacks

To receive updates about new blocks and chain tips, configure ``NotificationCallbacks`` before creating the context:

```swift
let notifications = NotificationCallbacks(
    blockTip: { state, entry, progress in
        print("New tip at height \(entry.height)")
    },
    headerTip: { state, height, timestamp, presync in
        print("Header tip: \(height)")
    }
)
options.setNotifications(notifications)
```

## Initializing a Chainstate Manager

The ``ChainstateManager`` handles block storage and validation. It requires a data directory for the block index and chainstate databases:

```swift
let managerOptions = try ChainstateManagerOptions(
    context: context,
    dataDirectory: "/tmp/bitcoin-kernel",
    blocksDirectory: "/tmp/bitcoin-kernel/blocks"
)
let manager = try ChainstateManager(options: managerOptions)
```

For testing, you can use in-memory databases:

```swift
managerOptions.setBlockTreeDBInMemory(true)
managerOptions.setChainstateDBInMemory(true)
```

## Reading the Active Chain

Once the chainstate manager is initialized, you can query the active chain:

```swift
let chain = manager.activeChain
let tip = manager.bestEntry
print("Chain height: \(chain.height)")
print("Best block height: \(tip.height)")
```

## Next Steps

- <doc:ValidatingBlocks> -- Learn how to process and validate blocks.
- <doc:VerifyingScripts> -- Learn how to verify transaction scripts.
- <doc:MemoryManagement> -- Understand the ARC-based ownership model.
