# Choosing an RPC Transport

@Metadata {
    @TitleHeading("How-to Guide")
}

Select the right transport for your RPC calls: in-process direct bridge or HTTP.

## Overview

### Transport Options

The Bitcoin module provides two transport implementations:

#### Direct Transport

``DirectTransport`` sends JSON-RPC requests directly to the in-process Bitcoin Core dispatch table via a C bridge function, bypassing HTTP entirely. This provides the lowest latency for embedded daemon scenarios.

```swift
let client = RPCClient(transport: DirectTransport())
```

**Limitation:** Direct transport does not support wallet-scoped RPC calls. Calling a wallet RPC (e.g., `getWalletInfo(wallet: "mywallet")`) throws ``RPCClientError/walletPathNotSupported``.

#### HTTP Transport

``HTTPTransport`` sends requests over HTTP with Basic authentication. It supports wallet-scoped calls by appending `/wallet/<name>` to the URL path.

```swift
let transport = HTTPTransport(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "user",
    password: "pass"
)
let client = RPCClient(transport: transport)
```

### Auto-Detection

The recommended initializer auto-detects the best transport per call:

```swift
let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "user",
    password: "pass"
)
```

The auto-detection logic:
1. **Wallet RPCs** (non-nil wallet path) always use HTTP, because the direct transport cannot route to specific wallets.
2. **Non-wallet RPCs** check if the in-process daemon is ready. If so, the direct bridge is used; otherwise, HTTP.

### Wallet-Scoped Calls

Bitcoin Core routes wallet RPCs to a specific wallet via the URL path `/wallet/<name>`. The typed wallet methods handle this automatically:

```swift
// Routes to /wallet/mywallet via HTTP
let info = try await client.getWalletInfo(wallet: "mywallet")

// Routes to /wallet/default
let balance = try await client.getBalance(wallet: "default")
```

### Choosing the Right Approach

| Scenario | Recommended Transport |
|----------|----------------------|
| Embedded daemon, no wallet RPCs | Auto-detect (uses direct bridge) |
| Embedded daemon, with wallet RPCs | Auto-detect (uses HTTP for wallet, direct for others) |
| Remote Bitcoin Core node | `HTTPTransport` explicitly |
| Custom transport (e.g., Unix socket) | Implement ``RPCTransport`` protocol |
