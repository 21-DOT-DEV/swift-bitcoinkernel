# Bitcoin

A Swift package for running an embedded Bitcoin node and interacting with Bitcoin Core via JSON-RPC.

## Overview

This package provides:

- **`Bitcoin`** — High-level `RPCClient` with typed async/await methods for every Bitcoin Core v31.x RPC, plus an embedded daemon bridge for in-process operation.
- **`RPCModels`** — 95 `Codable` model types covering all RPC response schemas, with `BTCAmount` (satoshi-precision arithmetic) and `UnixTimestamp` value types.
- **`BitcoinKernel`** — Low-level bindings to `libbitcoinkernel` for consensus validation.

## Requirements

- Swift 6.0+
- macOS 13+ / iOS 16+ / Linux

## RPC Coverage

**171 methods** across all 8 Bitcoin Core RPC categories. All RPCs target **Bitcoin Core v31.x**.

| Category | Methods | File | Notes |
|---|---|---|---|
| **Blockchain** | 51 | `RPCClient+Blockchain.swift` | Block, mempool, UTXO set, chain state, tx proofs |
| **Wallet** | 55 | `RPCClient+Wallet.swift` | Balance, send, PSBT, descriptors, encryption, backup |
| **Raw Transactions** | 21 | `RPCClient+RawTransactions.swift` | Create/sign/send raw tx, PSBT lifecycle |
| **Network** | 19 | `RPCClient+Network.swift` | Peers, banning, ZMQ, addrman |
| **Util** | 9 | `RPCClient+Util.swift` | Fee estimation, address validation, descriptors |
| **Mining** | 7 | `RPCClient+Mining.swift` | Block templates, hashrate, priority |
| **Control** | 6 | `RPCClient+Control.swift` | Memory, RPC info, logging, stop |
| **Generating** | 3 | `RPCClient+Generating.swift` | `generatetoaddress`, `generatetodescriptor`, `generateblock` |

## Key Types

| Type | Description |
|---|---|
| `BTCAmount` | Satoshi-precision amount. Stores `Int64` sats, decodes/encodes BTC `Decimal`. Supports arithmetic. |
| `UnixTimestamp` | Epoch seconds wrapper with `Date` conversion. |
| `RPCError` | Server-originated JSON-RPC error with code + message. |
| `LastProcessedBlock` | Block hash + height, included in wallet RPC responses. |

## Quick Start

```swift
import Bitcoin

// In-process (embedded daemon)
let client = RPCClient()

// Remote node
let client = RPCClient(url: "http://127.0.0.1:8332", username: "rpc", password: "pass")

// Blockchain
let info = try await client.getBlockchainInfo()
print(info.chain, info.blocks)

// Wallet (wallet-scoped RPCs require wallet name)
let balances = try await client.getBalances(wallet: "default")
print(balances.mine.trusted) // "1.5 BTC"
```

## Testing

177 decode tests covering all model types, including test vectors derived from Bitcoin Core's functional test suite.

```bash
swift test --filter RPCModelsTests
```

## License

Distributed under the MIT software license. See [LICENSE](LICENSE) for details.
