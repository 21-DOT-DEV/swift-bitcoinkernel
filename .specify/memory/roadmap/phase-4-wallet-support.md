# Phase 4: Wallet Support

**Goal**: Implement the `BitcoinWalletSupport` library with BerkeleyDB integration and typed wallet RPC methods.

**Status**: 🔜 Planned  
**Last Updated**: 2025-12-05

---

## Features

### 4.1 BerkeleyDB Integration

**Purpose & User Value**: Integrate swift-berkeleydb to enable Bitcoin Core's wallet functionality, allowing users to manage wallets locally.

**Success Metrics**:
- `BitcoinWalletSupport` target depends on swift-berkeleydb
- BerkeleyDB links correctly on supported platforms
- Wallet database files created and read successfully
- Platform support documented (some platforms may not support BDB)

**Dependencies**: Phase 3 complete

**Notes**:
- BerkeleyDB may have platform limitations (watchOS, WASM unlikely)
- Consider SQLite wallet backend as alternative for broader support
- Document minimum BerkeleyDB version requirements

---

### 4.2 Wallet RPC Methods - Core

**Purpose & User Value**: Provide typed wrappers for essential wallet RPCs, enabling balance queries and address management.

**Success Metrics**:
- Typed methods implemented:
  - `getBalance(wallet: String?) async throws -> Decimal`
  - `getBalances(wallet: String?) async throws -> WalletBalances`
  - `listWallets() async throws -> [String]`
  - `loadWallet(name: String) async throws -> WalletInfo`
  - `unloadWallet(name: String) async throws`
  - `createWallet(name: String, options: CreateWalletOptions) async throws -> WalletInfo`
  - `getWalletInfo(wallet: String?) async throws -> WalletInfo`
- Wallet parameter optional (uses default wallet if nil)

**Dependencies**: 4.1 BerkeleyDB Integration, 3.1 BitcoinClient Protocol

**Notes**:
- Some methods require wallet to be loaded first
- Consider wallet selection pattern (context vs parameter)

---

### 4.3 Wallet RPC Methods - Addresses

**Purpose & User Value**: Provide typed wrappers for address generation and management.

**Success Metrics**:
- Typed methods implemented:
  - `getNewAddress(label: String?, type: AddressType?) async throws -> String`
  - `getAddressInfo(address: String) async throws -> AddressInfo`
  - `listReceivedByAddress() async throws -> [AddressReceived]`
  - `getAddressesByLabel(label: String) async throws -> [String: AddressInfo]`
  - `setLabel(address: String, label: String) async throws`
- `AddressType` enum: `.legacy`, `.p2shSegwit`, `.bech32`, `.bech32m`

**Dependencies**: 4.2 Wallet RPC Methods - Core

---

### 4.4 Wallet RPC Methods - Transactions

**Purpose & User Value**: Provide typed wrappers for wallet transaction operations.

**Success Metrics**:
- Typed methods implemented:
  - `sendToAddress(address: String, amount: Decimal, options: SendOptions?) async throws -> String`
  - `listTransactions(count: Int?, skip: Int?) async throws -> [WalletTransaction]`
  - `getTransaction(txid: String) async throws -> WalletTransaction`
  - `listUnspent(minConf: Int?, maxConf: Int?) async throws -> [UnspentOutput]`
  - `createRawTransaction(inputs: [TxInput], outputs: [TxOutput]) async throws -> String`
  - `signRawTransactionWithWallet(hex: String) async throws -> SignedTransaction`
  - `sendRawTransaction(hex: String) async throws -> String`

**Dependencies**: 4.2 Wallet RPC Methods - Core

---

### 4.5 Wallet RPC Methods - Descriptors

**Purpose & User Value**: Provide typed wrappers for descriptor wallet operations (modern wallet format).

**Success Metrics**:
- Typed methods implemented:
  - `listDescriptors(wallet: String?) async throws -> [DescriptorInfo]`
  - `importDescriptors(requests: [ImportDescriptorRequest]) async throws -> [ImportResult]`
  - `getDescriptorInfo(descriptor: String) async throws -> DescriptorInfo`
  - `deriveAddresses(descriptor: String, range: Range<Int>?) async throws -> [String]`
- Support for both legacy and descriptor wallets

**Dependencies**: 4.2 Wallet RPC Methods - Core

**Notes**:
- Descriptor wallets are the modern standard
- Consider helper methods for common descriptor patterns

---

### 4.6 Wallet Events

**Purpose & User Value**: Expose wallet-related events via AsyncSequence for reactive UI updates.

**Success Metrics**:
- `WalletClient.transactionUpdates: AsyncStream<WalletTransaction>` (new/updated txs)
- `WalletClient.balanceUpdates: AsyncStream<WalletBalances>` (balance changes)
- Events wired to appropriate Bitcoin Core notifications
- Backpressure handling for high-frequency updates

**Dependencies**: 4.2 Wallet RPC Methods - Core, 2.3 Sync Progress & State Callbacks

**Notes**:
- May require additional C++ callback wiring
- Consider debouncing for balance updates during sync

---

## Phase Dependencies & Sequencing

```
4.1 BerkeleyDB Integration
    └── 4.2 Wallet RPC Methods - Core
            ├── 4.3 Wallet RPC Methods - Addresses
            ├── 4.4 Wallet RPC Methods - Transactions
            ├── 4.5 Wallet RPC Methods - Descriptors
            └── 4.6 Wallet Events
```

Features 4.3-4.6 can be developed in parallel.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms (with documented exceptions) |
| Test coverage | ≥80% of wallet API |
| RPC coverage | 20+ typed wallet methods |
| Documentation | All public types documented |
| Examples | ≥1 working example (create wallet, send tx) |
| Binary size | Delta from Bitcoin target documented |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| BerkeleyDB platform availability | Document limitations; consider SQLite alternative |
| Wallet security concerns | Document best practices; never log sensitive data |
| Complex wallet state management | Extensive integration tests with regtest |
