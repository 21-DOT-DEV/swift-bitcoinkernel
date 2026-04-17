# Patches

Modifications to vendored upstream source files required for Swift Package Manager builds and embedded (iOS/macOS) use. These patches must be reapplied when updating the upstream source.

Organized following the [Bitcoin Core `depends/patches/` convention](https://github.com/bitcoin/bitcoin/tree/master/depends/patches) — one subdirectory per upstream dependency, with individual files per patch.

## Bitcoin Core (v31.x)

### 1. [iOS build compatibility](bitcoin/ios-netif-guard.md) — `src/common/netif.cpp`

**Problem**: `<net/route.h>` and `<sys/sysctl.h>` unavailable in iOS SDK; `__APPLE__` guards include iOS.
**Fix**: Narrow to `__APPLE__ && TARGET_OS_OSX`. `QueryDefaultGatewayImpl()` returns `std::nullopt` on iOS.

### 2. [Remove `std::once_flag` from RPC lifecycle](bitcoin/rpc-server-reset.md) — `src/rpc/server.cpp`, `src/rpc/server.h`

**Problem**: `std::once_flag` in `InterruptRPC()`/`StopRPC()` is permanently one-shot; blocks restart and causes [#31289](https://github.com/bitcoin/bitcoin/issues/31289) race.
**Fix**: Remove `std::once_flag` — both functions are naturally idempotent. Add `ResetRPC()` to restore `fRPCInWarmup`/`rpcWarmupStatus`.

### 3. [In-process restart support](bitcoin/shutdown-reset.md) — `src/init.cpp`

**Problem**: Four globals block second `bitcoind_main()` call: `g_shutdown` (asserts empty), `gArgs` (asserts fresh), `LogInstance().m_buffering` (asserts true), `fRPCInWarmup` (asserts active).
**Fix**: Reset all four at end of `Shutdown()`: `g_shutdown.reset()`, `gArgs.ClearArgs()`, `ResetRPC()`, `LogInstance().DisconnectTestLogger()`.

### 4. [MAIN_FUNCTION guard](bitcoin/main-function-guard.md) — `src/bitcoind.cpp`

**Problem**: `main()` symbol conflicts with Swift entry point when embedding Bitcoin Core.
**Fix**: Header-based `#define MAIN_FUNCTION` allowing rename to `bitcoind_main()`.

### Non-patch custom files

The following are **not** upstream patches but custom SPM build configuration replacements for the CMake-generated `bitcoin-build-config.h`:

- `Sources/bitcoind/include/bitcoin-build-config.h` (bitcoind target)
- `Sources/libbitcoinkernel/src/bitcoin-build-config.h` (libbitcoinkernel target)

These contain `TARGET_OS_OSX` guards for `HAVE_GETENTROPY_RAND` and `HAVE_SYSTEM` to support iOS builds.

## swift-boost

| # | Patch | Description |
|---|---|---|
| 1 | [Inter-target dependencies](swift-boost/inter-target-deps.md) | Dependency structure for swift-boost SPM targets |
