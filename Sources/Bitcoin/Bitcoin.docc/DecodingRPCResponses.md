# Decoding RPC Responses

@Metadata {
    @TitleHeading("How-to Guide")
}

Work with the response-model types in the Bitcoin module to decode Bitcoin Core JSON-RPC responses.

## Overview

The Bitcoin module ships Swift `Codable` structs for every RPC method that returns structured data. Each struct mirrors the [JSON-RPC response shape produced by Bitcoin Core](https://developer.bitcoin.org/reference/rpc/) and is generated against the upstream [`src/rpc/`](https://github.com/bitcoin/bitcoin/tree/master/src/rpc) handlers. Decoding goes through Swift's [`Foundation.JSONDecoder`](https://developer.apple.com/documentation/foundation/jsondecoder), so the standard `Codable` rules apply.

### How models map to RPC methods

Each response-model struct corresponds to a specific Bitcoin Core RPC method's response payload. The struct's doc comment names the source method:

```swift
/// Per-block statistics from `getblockstats`.
public struct BlockStats: Codable, Sendable, Equatable { ... }
```

### Handling optional values

Many RPC responses include optional keys that depend on:
- **Bitcoin Core version** -- newer keys are absent in older releases
- **Request parameters** -- e.g., `getblock` verbosity levels surface different subsets
- **Transaction state** -- e.g., `blockhash` is nil for unconfirmed transactions

These are modeled as Swift optionals:

```swift
public struct RawTransaction: Codable, Sendable, Equatable {
    public let txid: String           // Always present
    public let blockhash: String?     // Nil if unconfirmed
    public let confirmations: Int?    // Nil if unconfirmed
}
```

### CodingKeys and JSON naming

Bitcoin Core uses `snake_case` for JSON keys, while Swift uses `camelCase`. When the Swift property name differs from the JSON key, a `CodingKeys` enum handles the mapping per the [`Codable` protocol](https://developer.apple.com/documentation/swift/codable) contract:

```swift
public struct PeerInfo: Codable, Sendable, Equatable {
    public let syncedHeaders: Int    // JSON: "synced_headers"
    public let syncedBlocks: Int     // JSON: "synced_blocks"

    enum CodingKeys: String, CodingKey {
        case syncedHeaders = "synced_headers"
        case syncedBlocks = "synced_blocks"
    }
}
```

> Note: Setting `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` is *not* sufficient on its own — Bitcoin Core uses unconventional names like `txid` and `blockhash` (no underscore between morphemes) that the heuristic mis-converts. Explicit `CodingKeys` are required for correctness.

### Version-dependent keys

Some response keys only exist in specific Bitcoin Core versions. The struct doc comments note version requirements:

```swift
/// A cluster of related mempool transactions from `getmempoolcluster` (v31+).
```

When using these models against older nodes, version-specific properties are typed as optional to avoid decoding failures. Check the [Bitcoin Core release notes](https://github.com/bitcoin/bitcoin/tree/master/doc/release-notes) for the version where a given key was introduced.

### Working with amounts

See <doc:UnitConventions> for details on how monetary values, fee rates, and timestamps are represented across the response models.
