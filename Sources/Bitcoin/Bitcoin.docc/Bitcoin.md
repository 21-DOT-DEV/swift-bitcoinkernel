# ``Bitcoin``

@Metadata {
    @TitleHeading("Framework")
}

Embed a Bitcoin Core daemon in your Swift application with a type-safe RPC client and fluent configuration builder.

## Overview

The Bitcoin module embeds [Bitcoin Core](https://github.com/bitcoin/bitcoin) in a Swift application and exposes its JSON-RPC interface as typed Swift APIs. The module provides three main capabilities:

1. **Embedded Daemon** -- Start and stop a Bitcoin Core daemon within your process using ``Daemon``. The daemon runs on a dedicated background thread; `start(with:)` returns immediately and `waitUntilStopped()` joins on shutdown.
2. **RPC Client** -- Send typed JSON-RPC commands via ``RPCClient``, with automatic transport selection between an in-process C bridge (zero serialization overhead) and HTTP (for wallet-scoped calls or remote nodes).
3. **Configuration** -- Build validated Bitcoin Core configurations using the fluent ``BitcoinConfig`` builder with compile-time network type safety. Network-specific options are encoded as phantom types so misuse is caught at compile time rather than at daemon startup.

The module pairs with [`BitcoinKernel`](https://github.com/21-DOT-DEV/swift-bitcoinkernel) (which wraps `libbitcoinkernel` for validation without the full daemon) in the [21-DOT-DEV](https://github.com/21-DOT-DEV) Swift Bitcoin ecosystem. Use `Bitcoin` when you need a full node (mempool, wallet, P2P); use `BitcoinKernel` when you only need validation primitives.

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

### Essentials

- <doc:GettingStarted>
- ``Bitcoin``

### Daemon Lifecycle

- ``Daemon``

### RPC Client

- ``RPCClient``
- ``RPCClientError``
- ``JSONRPCService``

### Transport Layer

- <doc:ChoosingAnRPCTransport>
- ``RPCTransport``
- ``WalletCapableTransport``
- ``HTTPTransport``
- ``DirectTransport``

### JSON-RPC Protocol

- ``JSONRPCRequest``
- ``JSONRPCResponse``

### Configuration

- <doc:ConfiguringBitcoinCore>
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

### Architecture Reference

- <doc:Architecture>

### RPC Response Decoding

- <doc:DecodingRPCResponses>
- <doc:UnitConventions>

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
