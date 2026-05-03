# Memory Management

@Metadata {
    @TitleHeading("Explanation")
}

How BitcoinKernel wraps `libbitcoinkernel`'s opaque C pointers with Swift ARC, distinguishes owner types from view types, and exposes value-like ergonomics on reference-typed wrappers.

## Overview

The [`libbitcoinkernel`](https://github.com/bitcoin/bitcoin/tree/master/src/kernel) C API uses opaque pointer types (`btck_Context*`, `btck_Block*`, etc.) that must be explicitly destroyed. BitcoinKernel wraps each C pointer in a Swift `class` whose `deinit` calls the corresponding `btck_*_destroy` function, leaving memory management to [Swift's Automatic Reference Counting](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/). The same pattern is used across the 21-DOT-DEV ecosystem — e.g., [swift-openssl](https://github.com/21-DOT-DEV/swift-openssl) and [swift-tor](https://github.com/21-DOT-DEV/swift-tor) wrap their respective C libraries the same way.

## Owner Types vs View Types

BitcoinKernel distinguishes between two kinds of types:

**Owner types** hold an independent copy of the underlying data. When the Swift object is deallocated, the C resource is destroyed. Most types are owner types:

- ``Context``, ``Block``, ``BlockHeader``, ``BlockHash``
- ``Transaction``, ``TransactionInput``, ``TransactionOutput``, ``Txid``
- ``ChainstateManager``, ``ChainstateManagerOptions``
- ``ChainParameters``, ``ContextOptions``
- ``BlockValidationState``, ``ScriptPubkey``

**View types** borrow a pointer into a parent object. They retain a strong reference to their owner to prevent use-after-free:

- ``BlockTreeEntry`` -- Views into the chainstate manager's block tree
- ``Chain`` -- Views the active chain within a chainstate manager

For example, ``BlockTreeEntry`` stores a reference to the ``ChainstateManager`` that owns the underlying block tree. As long as the entry is alive, the manager stays alive.

## Owned Copies from Views

Some properties on view types return **owned copies** to avoid dangling references:

```swift
let entry: BlockTreeEntry = manager.bestEntry  // view into manager
let hash: BlockHash = entry.blockHash          // owned copy
let header: BlockHeader = entry.blockHeader    // owned copy
```

The ``BlockTreeEntrySnapshot`` struct captures owned copies of all fields at once, useful when you need the data to outlive the view:

```swift
let snapshot = BlockTreeEntrySnapshot(entry)
// snapshot.blockHash and snapshot.blockHeader are owned copies
```

## Thread Safety

``Context`` is marked `@unchecked Sendable` and is safe to use from multiple threads simultaneously. The underlying C API synchronizes access internally.

Other types should be used from a single thread or protected by your own synchronization. The C pointers themselves are not thread-safe.

## Interrupting Long-Running Operations

Call ``Context/interrupt()`` to stop long-running operations like block importing or reindexing. This is safe to call from any thread:

```swift
// From another thread or task:
let interrupted = context.interrupt()
```

## Value-Like Ergonomics on Reference Types

Some reference-typed wrappers carry data that behaves like a value — compared by bytes, used as dictionary keys, logged as hex. ``BlockHash`` is the canonical example: it conforms to `Equatable`, `Hashable`, `RawRepresentable` (with `Data` raw value), and `CustomStringConvertible`, so it can be used like any Swift value even though the instance owns a C pointer:

```swift
let hash = BlockHash(internalBytes)
if hash == otherHash { /* compared by content */ }
var seen: Set<BlockHash> = []
seen.insert(hash)                 // used as a Hashable key
print(hash)                       // display-order hex, e.g. "00000000000019d6..."
let recovered = BlockHash(rawValue: someData)  // failable init, nil on wrong size
```

These conformances do not change the underlying ownership: the Swift object still owns a C handle and `deinit` still calls `btck_block_hash_destroy`. The `==` operator delegates to the C-side `btck_block_hash_equals` for the canonical comparison. This is closer in spirit to Swift-Evolution's [SE-0390 noncopyable types](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md) discussion of move-only resources than to a pure value type — the instance owns a unique resource, but its observable identity is its byte content.

## See Also

- <doc:GettingStarted>
- <doc:ValidatingBlocks>
- ``Context``
- ``BlockHash``
