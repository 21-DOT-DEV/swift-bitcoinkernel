# Validating Blocks

@Metadata {
    @TitleHeading("How-to Guide")
}

Process block headers and full blocks through Bitcoin Core's consensus validation with ``ChainstateManager/processBlockHeader(_:state:)`` and ``ChainstateManager/processBlock(_:)`` — Swift wrappers around the upstream [`validation.h`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.h) checks (`CheckBlock`, `ContextualCheckBlock`, `ConnectBlock`).

## Processing Block Headers

Before processing a full block, validate its header. Header validation runs the context-free and contextual checks from Bitcoin Core's [`AcceptBlockHeader`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.cpp) — proof-of-work, timestamp bounds, version-bit activation (per [BIP 9](https://github.com/bitcoin/bips/blob/master/bip-0009.mediawiki)), and linkage to a known parent. Create a ``BlockValidationState`` to capture the result:

```swift
let headerData: Data = ... // 80-byte serialized block header
let header = try BlockHeader(headerData)
let state = BlockValidationState()

let accepted = manager.processBlockHeader(header, state: state)
```

A `true` return means the header passed initial checks (proof-of-work, timestamps, structure). Inspect the state for details:

```swift
if state.validationMode == .invalid {
    print("Rejected: \(state.blockValidationResult)")
}
```

## Processing Full Blocks

Process a full block for validation and potential inclusion in the chain. The kernel runs transaction-structure checks, Merkle-root verification, coinbase rules (including [BIP 34](https://github.com/bitcoin/bips/blob/master/bip-0034.mediawiki) height-in-coinbase and [BIP 141](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki) witness commitment where applicable), then connects to the best chain if the block extends it:

```swift
let blockData: Data = ... // serialized block
let block = try Block(blockData)

let (success, isNew) = manager.processBlock(block)
if success && isNew {
    print("New block accepted at height \(manager.bestEntry.height)")
}
```

## Reading Blocks from Disk

Retrieve a previously validated block by its block tree entry:

```swift
if let entry = manager.blockTreeEntry(byHash: blockHash) {
    if let block = manager.readBlock(at: entry) {
        print("Block has \(block.transactionCount) transactions")
    }
}
```

## Checking Validation Results

The ``BlockValidationResult`` enum provides granular rejection reasons:

| Result | Meaning |
|--------|---------|
| ``BlockValidationResult/consensus`` | Violates consensus rules |
| ``BlockValidationResult/invalidHeader`` | Invalid proof-of-work or timestamp |
| ``BlockValidationResult/mutated`` | Block data was mutated |
| ``BlockValidationResult/missingPrev`` | Previous block not found |
| ``BlockValidationResult/timeFuture`` | Timestamp more than 2 hours in the future |

## See Also

- <doc:GettingStarted>
- <doc:Sync>
- ``ChainstateManager``
- ``BlockValidationResult``
