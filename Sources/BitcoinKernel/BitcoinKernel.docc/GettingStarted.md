# Getting Started with BitcoinKernel

@Metadata {
    @TitleHeading("Tutorial")
}

Set up a ``Context``, configure chain parameters, initialize a ``ChainstateManager``, and read the active chain — a task-oriented walkthrough with working code for every step.

## Creating a Context

Every operation in BitcoinKernel starts with a ``Context``, a Swift wrapper around Bitcoin Core's [`libbitcoinkernel`](https://github.com/bitcoin/bitcoin/tree/master/src/kernel) `btck_Context`. The context holds chain parameters (selected from ``ChainType`` — mainnet, testnet, testnet4, signet, regtest, matching Bitcoin Core's [`chainparams.cpp`](https://github.com/bitcoin/bitcoin/blob/master/src/kernel/chainparams.cpp)) and optional notification callbacks. Create one by configuring ``ContextOptions``:

```swift
import BitcoinKernel

let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)
```

The context is thread-safe and can be shared across multiple threads.

## Setting Up Notification Callbacks

To receive updates about new blocks and chain tips, configure ``NotificationCallbacks`` before creating the context. These map to Bitcoin Core's [`KernelNotifications`](https://github.com/bitcoin/bitcoin/blob/master/src/kernel/notifications_interface.h) callback interface:

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

The ``ChainstateManager`` handles block storage and validation. It requires a data directory for the block index and chainstate databases — typically placed inside [Apple's Application Support directory](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html) on macOS/iOS (set `isExcludedFromBackup = true`, since chainstate is reproducible from network):

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

Drive a real sync with <doc:Sync>, validate blocks end-to-end with <doc:ValidatingBlocks>, or study the ownership model in <doc:MemoryManagement>.

## See Also

- <doc:Sync>
- <doc:ValidatingBlocks>
- <doc:VerifyingScripts>
- <doc:MemoryManagement>
