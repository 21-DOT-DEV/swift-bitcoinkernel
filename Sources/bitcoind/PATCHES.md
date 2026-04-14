# Upstream Bitcoin Core Patches

Modifications to vendored Bitcoin Core source files required for Swift Package Manager builds and embedded (iOS/macOS) use. These patches must be reapplied when updating the upstream source.

**Upstream version**: Bitcoin Core v31.x

---

## 1. `src/common/netif.cpp` — iOS build compatibility

**Problem**: `<net/route.h>` and `<sys/sysctl.h>` are not available in the iOS SDK. The existing `__APPLE__` guards include iOS, causing build failures.

**Fix**: Narrow `__APPLE__` to `__APPLE__ && TARGET_OS_OSX` for the route-based network interface detection code.

```cpp
// Line ~27: Include guard
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#include <net/route.h>
#include <sys/sysctl.h>
#endif

// Line ~232: Implementation guard
#elif defined(__APPLE__) && TARGET_OS_OSX
```

**Affected API**: `QueryDefaultGatewayImpl()` — returns `std::nullopt` on iOS (no route socket access).

---

## 2. `src/init.cpp` — In-process restart support

**Problem**: `g_shutdown` (`std::optional<util::SignalInterrupt>`) is emplaced in `InitContext()` with `assert(!g_shutdown)`, but never reset in `Shutdown()`. Calling `bitcoind_main()` a second time in the same process (e.g., an embedded app restarting the daemon) hits this assertion.

**Fix**: Reset global state at the end of `Shutdown()`, after all cleanup and before the "Shutdown done" log. Also replace `std::once_flag` in RPC interrupt/stop with resettable guards.

```cpp
// After RemovePidFile(*node.args), before LogInfo("Shutdown done"):
g_shutdown.reset();
gArgs.ClearArgs();
ResetRPC();
LogInstance().DisconnectTestLogger();
```

Additionally, `src/rpc/server.cpp` is modified:
- `InterruptRPC()` / `StopRPC()`: replaced `std::once_flag` + `std::call_once` with simple boolean guards (since `std::once_flag` cannot be reset per C++ spec)
- Added `ResetRPC()` function to reset `fRPCInWarmup`, `g_rpc_running`, `g_rpc_stopped`, and `rpcWarmupStatus`
- Declared `ResetRPC()` in `rpc/server.h`

**Context**: `NodeContext` is stack-allocated fresh each `bitcoind_main()` call. Four globals block restart:
- `g_shutdown` (`std::optional<util::SignalInterrupt>`) — emplaced in `InitContext()`, asserts empty on re-entry
- `gArgs.m_available_args` — populated by `SetupServerArgs()`, asserts on duplicate insertion in `AddArg()`
- `LogInstance().m_buffering` — set to `false` by `StartLogging()`, asserts `true` on re-entry
- `fRPCInWarmup` / `std::once_flag` guards — `SetRPCWarmupFinished()` asserts warmup is active; `std::once_flag` prevents `InterruptRPC()`/`StopRPC()` from running again

---

## Non-patch custom files

The following files are **not** upstream patches but custom SPM build configuration replacements for the CMake-generated `bitcoin-build-config.h`:

- `include/bitcoin-build-config.h` (bitcoind target)
- `../libbitcoinkernel/src/bitcoin-build-config.h` (libbitcoinkernel target)

These contain `TARGET_OS_OSX` guards for `HAVE_GETENTROPY_RAND` and `HAVE_SYSTEM` to support iOS builds.
