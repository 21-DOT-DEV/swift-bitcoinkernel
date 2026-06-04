# ``Bitcoin``

@Metadata {
    @TitleHeading("Framework")
}

Embed a Bitcoin Core daemon in your Swift application with a type-safe RPC client and fluent configuration builder.

## Overview

The Bitcoin module embeds [Bitcoin Core](https://github.com/bitcoin/bitcoin) in a Swift application and exposes its JSON-RPC interface as typed Swift APIs.

- Start and stop an in-process `bitcoind` with ``Daemon`` on a dedicated background thread; `start(with:)` returns immediately and `waitUntilStopped()` joins on shutdown
- Send typed JSON-RPC commands via ``RPCClient`` over an in-process C bridge for non-wallet calls and HTTP for wallet calls or remote nodes
- Build Bitcoin Core configurations with the fluent ``BitcoinConfig`` builder
- Catch network-specific option misuse at compile time via phantom-typed networks

The module pairs with [`BitcoinKernel`](https://github.com/21-DOT-DEV/swift-bitcoinkernel) in the [21.dev](https://github.com/21-DOT-DEV) Swift Bitcoin ecosystem. `BitcoinKernel` wraps `libbitcoinkernel` for consensus validation without a full node. Use `Bitcoin` for a full node with mempool, wallet, and P2P. Use `BitcoinKernel` for validation primitives only.

```swift
import Bitcoin

// Configure a regtest node
let auth = RPCAuth(username: "user", salt: "abc", passwordHMAC: "def")
let config = BitcoinConfig.regtest().rpcAuth(auth).server()

// Start the embedded daemon
try Daemon.start(with: config)

// Create an RPC client
let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "user",
    password: "pass"
)

// Query the blockchain
let info = try await client.getBlockchainInfo()
print("Chain: \(info.chain), Height: \(info.blocks)")
```

## Topics

### Getting Started

- <doc:GettingStarted>

### Essentials

- ``Bitcoin``

### Daemon Lifecycle

- ``Daemon``

### RPC Client

- ``RPCClient``
- ``RPCClientError``
- ``JSONRPCService``

### Transport Layer

- ``RPCTransport``
- ``WalletCapableTransport``
- ``HTTPTransport``
- ``DirectTransport``

### JSON-RPC Protocol

- ``JSONRPCRequest``
- ``JSONRPCResponse``

### Configuration

- ``BitcoinConfig``
- ``BitcoinNetwork``
- ``Mainnet``
- ``Testnet``
- ``Testnet4``
- ``Regtest``
- ``Signet``

### Configuration Value Types

- ``IPAddress``
- ``RPCAuth``
- ``PruneMode``
- ``BlockFilterMode``
- ``FeeRate``
- ``NetworkType``
- ``AddressType``
- ``ZMQEndpoint``
- ``DebugCategory``

### Configuration Validation

- ``ConfigError``
- ``ConfigWarning``

### Response Models — Blockchain

- ``Block``
- ``BlockHeader``
- ``BlockWithTransactions``
- ``BlockWithPrevouts``
- ``BlockStats``
- ``BlockFilter``
- ``BlockchainInfo``
- ``ChainTip``
- ``ChainTxStats``
- ``DeploymentInfo``
- ``TxOut``
- ``TxOutSetInfo``
- ``TxSpendingPrevout``

### Response Models — Transactions

- ``Transaction``
- ``DecodedTransaction``
- ``RawTransaction``
- ``Vin``
- ``Vout``
- ``ScriptSig``
- ``ScriptPubKey``
- ``SignedTransaction``
- ``DecodedScript``

### Response Models — PSBT

- ``DecodedPSBT``
- ``PSBTAnalysis``
- ``FinalizedPSBT``

### Response Models — Mempool

- ``MempoolInfo``
- ``MempoolEntry``
- ``MempoolFees``
- ``MempoolAcceptResult``

### Response Models — Network

- ``PeerInfo``
- ``NetworkInfo``
- ``AddedNodeInfo``
- ``NodeAddress``
- ``BannedInfo``
- ``NetTotals``
- ``ZMQNotification``

### Response Models — Mining

- ``MiningInfo``
- ``BlockTemplate``
- ``GeneratedBlock``

### Response Models — Wallet

- ``WalletInfo``
- ``WalletTransaction``
- ``WalletBalances``
- ``UnspentOutput``
- ``ListSinceBlockResult``
- ``CreateWalletResult``
- ``BumpFeeResult``
- ``SendResult``
- ``FundRawTransactionResult``
- ``RescanResult``

### Response Models — Utility

- ``AddressValidation``
- ``DescriptorInfo``
- ``MultisigResult``
- ``SmartFeeEstimate``
- ``IndexInfo``
- ``MemoryInfo``
- ``RPCInfo``

### Response Models — Shared Types

- ``BTCAmount``
- ``UnixTimestamp``
- ``RPCParam``
- ``RPCError``
- ``LastProcessedBlock``
- ``PrevTxOut``

### Response Models — Scanning

- ``ScanTxOutResult``
- ``ScanTxOutProgress``
