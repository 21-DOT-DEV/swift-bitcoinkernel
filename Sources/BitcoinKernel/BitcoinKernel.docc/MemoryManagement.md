# Memory Management

@Metadata {
    @TitleHeading("Explanation")
}

Understand how BitcoinKernel wraps C opaque pointers with Swift ARC.

## Overview

The `libbitcoinkernel` C API uses opaque pointer types (`btck_Context*`, `btck_Block*`, etc.) that must be explicitly destroyed. BitcoinKernel wraps each C pointer in a Swift `class` that calls the corresponding `btck_*_destroy` function in its `deinit`, providing automatic memory management through ARC.

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
