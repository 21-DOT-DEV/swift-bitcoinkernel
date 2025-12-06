# Phase 5: Network Client

**Goal**: Implement a network-based `BitcoinClient` that connects to remote Bitcoin Core nodes via HTTP JSON-RPC.

**Status**: 🔜 Planned  
**Last Updated**: 2025-12-05

---

## Features

### 5.1 NetworkClient Implementation

**Purpose & User Value**: Implement `BitcoinClient` protocol using HTTP JSON-RPC, enabling connection to remote Bitcoin Core nodes without embedding.

**Success Metrics**:
- `NetworkClient` class implements `BitcoinClient`
- Connects via HTTP/HTTPS to remote bitcoind
- Supports Basic authentication (username/password)
- Supports cookie-based authentication
- Configurable timeout and retry behavior
- Works on all Tier 1 platforms

**Dependencies**: 3.1 BitcoinClient Protocol

**Notes**:
- Use URLSession for cross-platform HTTP (Foundation)
- Consider swift-nio as future optimization (per constitution)
- Connection pooling for performance

---

### 5.2 Authentication & Security

**Purpose & User Value**: Support all Bitcoin Core authentication methods securely.

**Success Metrics**:
- Basic auth (username:password in header)
- Cookie auth (read from `.cookie` file)
- HTTPS support with certificate validation
- Credentials never logged or exposed in errors
- Secure storage recommendations documented

**Dependencies**: 5.1 NetworkClient Implementation

**Notes**:
- `rpcauth` format: `username:salt$hash`
- Cookie file typically at `~/.bitcoin/.cookie`
- Consider Keychain integration for credential storage

---

### 5.3 Connection Management

**Purpose & User Value**: Handle connection lifecycle, retries, and health checking for reliable remote node access.

**Success Metrics**:
- Automatic retry with configurable policy:
  - `retryCount: Int`
  - `retryDelay: TimeInterval`
  - `backoffMultiplier: Double`
- Connection health check via `getBlockchainInfo()`
- Timeout configuration (connect, read)
- Connection state observable: `.connected`, `.disconnected`, `.connecting`
- Graceful handling of node restarts

**Dependencies**: 5.1 NetworkClient Implementation

**Notes**:
- Consider exponential backoff with jitter
- Health check interval configurable

---

### 5.4 Batch RPC Support

**Purpose & User Value**: Support JSON-RPC batch requests for reduced latency when making multiple calls.

**Success Metrics**:
- `func batch(_ calls: [RPCCall]) async throws -> [RPCResult]`
- Single HTTP request for multiple RPC calls
- Results returned in order
- Mixed success/failure handling per call
- Performance improvement documented (latency comparison)

**Dependencies**: 5.1 NetworkClient Implementation

**Notes**:
- Bitcoin Core supports JSON-RPC 2.0 batch format
- Consider builder pattern for batch construction

---

### 5.5 Network Client Examples

**Purpose & User Value**: Provide working examples demonstrating remote node connection patterns.

**Success Metrics**:
- Example: Connect to local bitcoind
- Example: Connect to remote node with auth
- Example: Handle connection failures gracefully
- Example: Batch multiple RPC calls
- All examples compile and run

**Dependencies**: 5.1-5.4 complete

---

## Phase Dependencies & Sequencing

```
5.1 NetworkClient Implementation
    ├── 5.2 Authentication & Security
    ├── 5.3 Connection Management
    └── 5.4 Batch RPC Support
            └── 5.5 Network Client Examples
```

Features 5.2-5.4 can be developed in parallel.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms |
| Test coverage | ≥80% of NetworkClient API |
| RPC latency | p50 < 100ms (localhost), p99 < 500ms |
| Documentation | All public types documented |
| Examples | ≥3 working examples |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Network latency variability | Configurable timeouts, async patterns |
| Authentication complexity | Support multiple methods, clear docs |
| HTTPS certificate issues | Allow custom trust policies for testing |
| Platform HTTP differences | Use Foundation URLSession consistently |

---

## Future Considerations

- **swift-nio integration**: For improved performance and connection pooling (requires constitutional review)
- **WebSocket support**: For real-time notifications (ZMQ alternative)
- **Tor/onion support**: For privacy-focused connections
- **Multi-node failover**: Automatic fallback to backup nodes
