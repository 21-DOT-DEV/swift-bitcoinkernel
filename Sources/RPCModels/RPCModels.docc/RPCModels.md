# ``RPCModels``

@Metadata {
    @TitleHeading("Framework")
}

Type-safe Swift models for every Bitcoin Core JSON-RPC response, targeting Bitcoin Core v31.x.

## Overview

RPCModels provides `Codable` structs that map directly to Bitcoin Core's JSON-RPC response objects. Each struct documents its source RPC method and handles JSON field naming via `CodingKeys`. All types are `Sendable` and `Equatable`.

Amount fields use two conventions:
- ``BTCAmount`` for BTC-denominated values (decoded from JSON decimals)
- Plain `Int64` for satoshi-denominated values (e.g., fee rates in ``BlockStats``)

Timestamp fields use ``UnixTimestamp`` for epoch-second values, while durations and millisecond fields use plain `Int64`.

## Topics

### Essentials

- <doc:DecodingRPCResponses>
- <doc:UnitConventions>

### Blockchain

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

### Transactions

- ``Transaction``
- ``DecodedTransaction``
- ``RawTransaction``
- ``Vin``
- ``Vout``
- ``ScriptSig``
- ``ScriptPubKey``
- ``SignedTransaction``
- ``DecodedScript``

### PSBT

- ``DecodedPSBT``
- ``PSBTAnalysis``
- ``FinalizedPSBT``

### Mempool

- ``MempoolInfo``
- ``MempoolEntry``
- ``MempoolFees``
- ``MempoolAcceptResult``

### Network

- ``PeerInfo``
- ``NetworkInfo``
- ``AddedNodeInfo``
- ``NodeAddress``
- ``BannedInfo``
- ``NetTotals``
- ``ZMQNotification``

### Mining

- ``MiningInfo``
- ``BlockTemplate``
- ``GeneratedBlock``

### Wallet

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

### Utility

- ``AddressValidation``
- ``DescriptorInfo``
- ``MultisigResult``
- ``SmartFeeEstimate``
- ``IndexInfo``
- ``MemoryInfo``
- ``RPCInfo``

### Shared Types

- ``BTCAmount``
- ``UnixTimestamp``
- ``RPCParam``
- ``RPCError``
- ``LastProcessedBlock``
- ``PrevTxOut``

### Scanning

- ``ScanTxOutResult``
- ``ScanTxOutProgress``
