# Decoding RPC Responses

@Metadata {
    @TitleHeading("How-to Guide")
}

Work with the response-model types under ``Bitcoin/Models/`` to decode Bitcoin Core JSON-RPC responses.

## How Models Map to RPC Methods

Each response-model struct corresponds to a specific Bitcoin Core RPC method's response. The struct's doc comment names the source method:

```swift
/// Per-block statistics from `getblockstats`.
public struct BlockStats: Codable, Sendable, Equatable { ... }
```

## Handling Optional Fields

Many RPC responses include optional fields that depend on:
- **Bitcoin Core version** -- newer fields are absent in older versions
- **Request parameters** -- e.g., `getblock` verbosity levels
- **Transaction state** -- e.g., `blockhash` is nil for unconfirmed transactions

These are modeled as Swift optionals:

```swift
public struct RawTransaction: Codable, Sendable, Equatable {
    public let txid: String           // Always present
    public let blockhash: String?     // Nil if unconfirmed
    public let confirmations: Int?    // Nil if unconfirmed
}
```

## CodingKeys and Field Naming

Bitcoin Core uses `snake_case` for JSON field names. When the Swift property name differs, a `CodingKeys` enum handles the mapping:

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

## Version-Dependent Fields

Some fields only exist in specific Bitcoin Core versions. The struct doc comments note version requirements:

```swift
/// A cluster of related mempool transactions from `getmempoolcluster` (v31+).
```

When using these models against older nodes, version-specific fields should be optional to avoid decoding failures.

## Working with Amounts

See <doc:UnitConventions> for details on how monetary values are represented.
