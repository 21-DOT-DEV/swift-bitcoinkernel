# Choosing an RPC Transport

@Metadata {
    @TitleHeading("How-to Guide")
}

Select the right delivery mechanism for your RPC calls: in-process direct bridge or HTTP.

## Overview

### The two options

The Bitcoin module ships two ``RPCTransport`` implementations against the [Bitcoin Core JSON-RPC interface](https://developer.bitcoin.org/reference/rpc/):

#### Direct bridge

``DirectTransport`` sends JSON-RPC requests directly to the in-process [Bitcoin Core dispatch table](https://github.com/bitcoin/bitcoin/blob/master/src/rpc/server.cpp) via a C bridge function, bypassing HTTP entirely. This provides the lowest latency for embedded daemon scenarios — no socket, no [JSON-RPC 1.0](https://www.jsonrpc.org/specification_v1) framing, no HTTP Basic credentials round-trip.

```swift
let client = RPCClient(transport: DirectTransport())
```

> Important: The direct bridge does not support wallet-scoped RPC calls. Calling a wallet method (e.g., `getWalletInfo(wallet: "mywallet")`) throws ``RPCClientError/walletPathNotSupported``. The reason: wallet routing in Bitcoin Core happens at the HTTP path layer (`/wallet/<name>`), which the direct bridge never traverses.

#### HTTP

``HTTPTransport`` sends requests over HTTP with [Basic authentication (RFC 7617)](https://datatracker.ietf.org/doc/html/rfc7617). It supports wallet-scoped calls by appending `/wallet/<name>` to the URL path, matching upstream's [HTTP server routing](https://github.com/bitcoin/bitcoin/blob/master/src/httprpc.cpp).

```swift
let transport = HTTPTransport(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "user",
    password: "pass"
)
let client = RPCClient(transport: transport)
```

### Auto-detection

The recommended initializer picks the right delivery path per call:

```swift
let client = RPCClient(
    url: URL(string: "http://127.0.0.1:18443")!,
    username: "user",
    password: "pass"
)
```

The selection logic:
1. **Wallet RPCs** (non-nil wallet path) always go over HTTP, because the direct bridge cannot route to a named purse.
2. **Non-wallet RPCs** check whether the in-process daemon is ready. If so, the direct bridge is used; otherwise, HTTP.

### Wallet-scoped calls

Bitcoin Core dispatches wallet-bound methods to a specific named purse via the URL path `/wallet/<name>` — documented in [`getrpcinfo`](https://developer.bitcoin.org/reference/rpc/getrpcinfo.html) and [`listwallets`](https://developer.bitcoin.org/reference/rpc/listwallets.html). The typed wallet methods handle this routing automatically:

```swift
// Routes to /wallet/mywallet via HTTP
let info = try await client.getWalletInfo(wallet: "mywallet")

// Routes to /wallet/default
let balance = try await client.getBalance(wallet: "default")
```

### Choosing the right approach

| Scenario | Recommended choice |
|----------|----------------------|
| Embedded daemon, no purse-scoped calls | Auto-detect (uses direct bridge) |
| Embedded daemon, with purse-scoped calls | Auto-detect (mixes paths per call) |
| Remote Bitcoin Core node | `HTTPTransport` explicitly |
| Custom channel (e.g., Unix socket) | Implement ``RPCTransport`` protocol |
