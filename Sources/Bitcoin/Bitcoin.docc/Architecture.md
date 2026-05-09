# Architecture

@Metadata {
    @TitleHeading("Explanation")
}

Understand how the Bitcoin module embeds Bitcoin Core and bridges Swift to C++.

## Overview

### Embedded Daemon Design

The Bitcoin module compiles Bitcoin Core's `bitcoind` entry point as a C++ target (`bitcoind`) and calls it from Swift via C interop. When you call ``Daemon/start(with:)``, the module spawns a dedicated background thread and returns immediately. On that thread, it:

1. **Registers the RPC bridge** -- Calls `bitcoin_rpc_register()` to install a hidden `_bridge_init` RPC command before the RPC server starts.
2. **Launches bitcoind** -- Calls `bitcoind_main(argc, argv)`, passing the configuration arguments.

The daemon runs until shutdown is signaled (via the `stop` RPC), at which point `bitcoind_main` returns and the completion semaphore is signaled.

### Transport Abstraction

The ``RPCTransport`` protocol abstracts how JSON-RPC requests reach Bitcoin Core:

```
┌─────────────┐
│  RPCClient   │
└──────┬───────┘
       │ send(request, path)
       ▼
┌──────────────┐     ┌─────────────────┐
│ DirectTransport│     │  HTTPTransport   │
│ (C bridge)    │     │ (URLSession)     │
└──────┬────────┘     └────────┬─────────┘
       │                       │
       ▼                       ▼
  bitcoin_rpc()         HTTP POST to
  (in-process)         127.0.0.1:port
       │                       │
       └───────────┬───────────┘
                   ▼
           Bitcoin Core RPC
            dispatch table
```

The ``DirectTransport`` calls `bitcoin_rpc(method, params)` directly -- a C function that dispatches into Bitcoin Core's RPC table and returns JSON as a C string. This avoids HTTP serialization, authentication, and network overhead.

The ``HTTPTransport`` sends a standard HTTP POST with Basic authentication, which Bitcoin Core's built-in HTTP server handles normally.

### Auto-Detection

When using `RPCClient(url:username:password:)`, an internal transport checks `bitcoin_rpc_ready()` on each call. If the embedded daemon is running and the call does not require wallet scoping, the direct bridge is used. Otherwise, HTTP transport handles the request.

### Thread Safety

- ``Daemon`` methods are static and use a `DispatchSemaphore` for synchronization.
- ``RPCClient`` is `Sendable` and safe to use from any task or thread.
- Each `send` call creates a fresh `JSONDecoder` to avoid shared mutable state.
- The `bitcoin_rpc()` C function is internally synchronized by Bitcoin Core's RPC dispatch table.

### Configuration Validation

``BitcoinConfig`` uses a phantom type parameter (`BitcoinConfig<N: BitcoinNetwork>`) to encode the network at the type level. This enables:

- **Compile-time safety** -- Network-specific options (e.g., `fastPrune`) are only available on the correct network type.
- **O(1) validation** -- A `ConfigFlags` bitfield tracks which options have been set, enabling conflict detection without re-parsing the argument list.
- **Immutable builder** -- Each method returns a new value, preventing accidental mutation.
