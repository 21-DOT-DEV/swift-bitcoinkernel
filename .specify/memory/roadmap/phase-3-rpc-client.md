# Phase 3: RPC Client

**Goal**: Create a type-safe RPC client protocol with a direct (in-process) implementation using Bitcoin Core's `executeRpc()` method.

**Status**: 🔜 Planned  
**Last Updated**: 2025-12-05

---

## Features

### 3.1 BitcoinClient Protocol

**Purpose & User Value**: Define a protocol for RPC access that abstracts the underlying transport, enabling future network implementations without API changes.

**Success Metrics**:
- `BitcoinClient` protocol defined with:
  - `func execute<T: Decodable>(_ method: String, params: [Any]) async throws -> T`
  - Typed methods for core RPCs
- `Bitcoin.Error` enum for RPC errors
- Protocol is transport-agnostic
- Documentation with usage examples

**Dependencies**: Phase 2 complete (Daemon must be running for RPC)

**Notes**:
- Design for testability (mock implementations)
- Consider generic JSON passthrough for untyped methods

---

### 3.2 DirectClient Implementation

**Purpose & User Value**: Implement `BitcoinClient` using Bitcoin Core's in-process `executeRpc()` method for fast, zero-latency RPC access.

**Success Metrics**:
- `DirectClient` class implements `BitcoinClient`
- Uses `interfaces::Node::executeRpc()` internally
- No network overhead (in-process call)
- Proper error mapping from Bitcoin Core error codes
- Thread-safe for concurrent calls

**Dependencies**: 3.1 BitcoinClient Protocol, 2.1 Node Interface Wrapper

**Notes**:
- DirectClient requires embedded node to be running
- Consider lazy initialization pattern

---

### 3.3 Blockchain RPC Methods

**Purpose & User Value**: Provide fully-typed Swift wrappers for blockchain query RPCs, enabling type-safe access to chain state.

**Success Metrics**:
- Typed methods implemented:
  - `getBlockchainInfo() async throws -> BlockchainInfo`
  - `getBlock(hash: String, verbosity: BlockVerbosity) async throws -> Block`
  - `getBlockHash(height: Int) async throws -> String`
  - `getBlockCount() async throws -> Int`
  - `getBestBlockHash() async throws -> String`
  - `getBlockHeader(hash: String) async throws -> BlockHeader`
  - `getDifficulty() async throws -> Double`
  - `getChainTips() async throws -> [ChainTip]`
- Response types are `Codable` and documented
- Unit tests with regtest validation

**Dependencies**: 3.2 DirectClient Implementation

**Notes**:
- `BlockVerbosity` enum: `.hashOnly`, `.json`, `.jsonWithTransactions`
- Consider pagination for large responses

---

### 3.4 Transaction RPC Methods

**Purpose & User Value**: Provide typed wrappers for transaction-related RPCs, enabling raw transaction handling and broadcasting.

**Success Metrics**:
- Typed methods implemented:
  - `getRawTransaction(txid: String, verbose: Bool) async throws -> Transaction`
  - `sendRawTransaction(hex: String, maxFeeRate: Double?) async throws -> String`
  - `decodeRawTransaction(hex: String) async throws -> DecodedTransaction`
  - `testMempoolAccept(txHexes: [String]) async throws -> [MempoolAcceptResult]`
  - `getTxOut(txid: String, vout: Int) async throws -> TxOut?`
- Response types are `Codable`
- Error handling for invalid transactions

**Dependencies**: 3.2 DirectClient Implementation

**Notes**:
- Transaction hex validation before sending
- Consider convenience methods for common patterns

---

### 3.5 Network RPC Methods

**Purpose & User Value**: Provide typed wrappers for network and peer information RPCs.

**Success Metrics**:
- Typed methods implemented:
  - `getNetworkInfo() async throws -> NetworkInfo`
  - `getPeerInfo() async throws -> [PeerInfo]`
  - `getConnectionCount() async throws -> Int`
  - `getNodeAddresses() async throws -> [NodeAddress]`
  - `addNode(address: String, command: AddNodeCommand) async throws`
  - `disconnectNode(address: String) async throws`
- Response types are `Codable`

**Dependencies**: 3.2 DirectClient Implementation

**Notes**:
- `AddNodeCommand` enum: `.add`, `.remove`, `.oneTry`

---

### 3.6 Mempool RPC Methods

**Purpose & User Value**: Provide typed wrappers for mempool query RPCs.

**Success Metrics**:
- Typed methods implemented:
  - `getMempoolInfo() async throws -> MempoolInfo`
  - `getRawMempool(verbose: Bool) async throws -> [String]` or `[MempoolEntry]`
  - `getMempoolEntry(txid: String) async throws -> MempoolEntry`
  - `getMempoolAncestors(txid: String) async throws -> [String]`
  - `getMempoolDescendants(txid: String) async throws -> [String]`
- Response types are `Codable`

**Dependencies**: 3.2 DirectClient Implementation

---

### 3.7 Raw RPC Passthrough

**Purpose & User Value**: Provide a generic method to call any RPC method, ensuring users are never blocked by missing typed wrappers.

**Success Metrics**:
- Generic method: `func call(_ method: String, params: [Any]) async throws -> JSONValue`
- Works with any valid Bitcoin Core RPC method
- Returns decoded JSON (dictionary, array, or primitive)
- Documented as escape hatch for advanced users

**Dependencies**: 3.2 DirectClient Implementation

**Notes**:
- Use `JSONValue` type or `Any` with proper decoding
- Document that this bypasses type safety

---

## Phase Dependencies & Sequencing

```
3.1 BitcoinClient Protocol
    └── 3.2 DirectClient Implementation
            ├── 3.3 Blockchain RPC Methods
            ├── 3.4 Transaction RPC Methods
            ├── 3.5 Network RPC Methods
            ├── 3.6 Mempool RPC Methods
            └── 3.7 Raw RPC Passthrough
```

RPC method groups (3.3-3.7) can be developed in parallel.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms |
| Test coverage | ≥80% of RPC client API |
| RPC coverage | 25+ typed methods |
| RPC latency | p50 < 10ms for DirectClient |
| Documentation | All public types documented |
| Examples | ≥2 working examples (query block, send tx) |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Response types drift from Bitcoin Core | Generate types from RPC help, test against regtest |
| Error code mapping incomplete | Start with common errors, expand as discovered |
| JSON decoding edge cases | Comprehensive test vectors |
