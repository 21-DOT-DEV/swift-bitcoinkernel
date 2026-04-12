# Validating Blocks

@Metadata {
    @TitleHeading("How-to Guide")
}

Process block headers and full blocks through Bitcoin Core's consensus validation.

## Processing Block Headers

Before processing a full block, validate its header. Create a ``BlockValidationState`` to capture the result:

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

Process a full block for validation and potential inclusion in the chain:

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
