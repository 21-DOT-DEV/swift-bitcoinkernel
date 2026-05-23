# Validating Blocks

@Metadata {
    @TitleHeading("How-to Guide")
}

Process block headers and full blocks through Bitcoin Core's consensus validation with ``ChainstateManager/processBlockHeader(_:state:)`` and ``ChainstateManager/processBlock(_:)`` — Swift wrappers around the upstream [`validation.h`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.h) checks (`CheckBlock`, `ContextualCheckBlock`, `ConnectBlock`).

## Overview

Validation in BitcoinKernel runs in two stages, mirroring the upstream Bitcoin Core flow. First, the header is checked against the consensus rules that don't require the full payload — proof-of-work, version-bit activation, ancestry. Then, if the header is acceptable, the full payload is checked against transaction-structure rules, the Merkle commitment, and (on extension of the active tip) the connection rules that update the UTXO set.

Separating header validation from payload validation matters when you're driving a sync from an untrusted source: rejecting a bogus header (cheap) is far better than fetching megabytes of payload first. See <doc:Sync> for how ``BlockchainSync`` uses this separation.

## Processing headers

Before submitting a full payload, validate its header. Header validation runs the context-free and contextual checks from Bitcoin Core's [`AcceptBlockHeader`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.cpp) — proof-of-work, timestamp bounds, version-bit activation (per [BIP 9](https://github.com/bitcoin/bips/blob/master/bip-0009.mediawiki)), and linkage to a known parent. Create a ``BlockValidationState`` to capture the result:

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

## Processing full payloads

Process a full payload for validation and potential inclusion in the chain. The kernel runs transaction-structure checks, Merkle-root verification, coinbase rules (including [BIP 34](https://github.com/bitcoin/bips/blob/master/bip-0034.mediawiki) height-in-coinbase and [BIP 141](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki) witness commitment where applicable), then connects to the active tip if the payload extends it:

```swift
let blockData: Data = ... // serialized payload
let block = try Block(blockData)

let (success, isNew) = manager.processBlock(block)
if success && isNew {
    print("Accepted at height \(manager.bestEntry.height)")
}
```

## Reading from disk

Retrieve a previously validated payload by its tree entry:

```swift
if let entry = manager.blockTreeEntry(byHash: blockHash) {
    if let payload = manager.readBlock(at: entry) {
        print("Found \(payload.transactionCount) transactions")
    }
}
```

## Checking validation results

The ``BlockValidationResult`` enum provides granular rejection reasons. These map to the rejection codes returned by Bitcoin Core's [`BlockValidationResult`](https://github.com/bitcoin/bitcoin/blob/master/src/consensus/validation.h) in `consensus/validation.h`:

| Result | Meaning |
|--------|---------|
| ``BlockValidationResult/consensus`` | Violates consensus rules |
| ``BlockValidationResult/invalidHeader`` | Invalid proof-of-work or timestamp |
| ``BlockValidationResult/mutated`` | Payload bytes were mutated |
| ``BlockValidationResult/missingPrev`` | Parent entry not found |
| ``BlockValidationResult/timeFuture`` | Timestamp more than 2 hours in the future |

The two-hour future-time bound is set by Bitcoin Core's [`MAX_FUTURE_BLOCK_TIME`](https://github.com/bitcoin/bitcoin/blob/master/src/chain.h) constant and is part of consensus — payloads from nodes with a badly-skewed clock are rejected on receipt.

## See Also

- <doc:GettingStarted>
- <doc:Sync>
- ``ChainstateManager``
- ``BlockValidationResult``
