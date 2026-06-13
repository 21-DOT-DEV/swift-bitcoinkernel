# Patches

Modifications to vendored upstream Bitcoin Core sources required for Swift Package Manager builds and embedded (iOS/macOS) use. Each patch is documented as a `.md` narrative with a machine-applicable `.patch` file beside it; the `.patch` is the artifact of record and must reapply cleanly after a subtree sync. These patches never touch consensus code; see the [patch policy](../SECURITY.md#patch-policy).

Organized following the [Bitcoin Core `depends/patches/` convention](https://github.com/bitcoin/bitcoin/tree/master/depends/patches): one subdirectory per upstream dependency, with individual files per patch.

> **Filing these upstream?** Start with [`UPSTREAMING.md`](UPSTREAMING.md) — the sequenced filing plan (which PR first, how to frame each off the *open* issues, the umbrella-issue draft, and the per-PR checklist), verified against current `bitcoin/bitcoin` master. It is the authority on sequencing and framing where the per-patch drafts below differ.

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

### 4. [MAIN_FUNCTION guard](bitcoin/main-function-guard.md) — `src/compat/compat.h`

**Problem**: `main()` symbol conflicts with the Swift entry point when embedding Bitcoin Core.
**Fix**: An `#ifndef MAIN_FUNCTION` guard in `src/compat/compat.h` lets the build system rename the entry point to `bitcoind_main()` via `-DMAIN_FUNCTION=...`. The macro is consumed in `src/bitcoind.cpp`.

### 5. [Logging teardown assertion](bitcoin/logging-teardown-assertion.md) — `src/logging.cpp`

**Problem**: `DisconnectTestLogger()` leaves `m_print_to_file` true after closing the log file, so a late background-thread log hits `assert(m_fileout != nullptr)` during teardown.
**Fix**: Set `m_print_to_file = false` in `DisconnectTestLogger()`.

### Feasibility memos

[`tvos-execvp-feasibility.md`](bitcoin/tvos-execvp-feasibility.md) is a scoping analysis, not an applied patch: it documents why the `Bitcoin` product cannot build for tvOS (`execvp` is `__TVOS_PROHIBITED`) and the options if tvOS support is ever requested.

### Non-patch custom files

The following are **not** upstream patches but custom SPM build configuration files committed alongside the vendored Bitcoin Core sources. They live under `Sources/` and look like they could be subtree-extracted, but they're not — the subtree patterns in `subtree.yaml` only match `*.{h,c,cc,cpp}`, so these survive `swift package plugin subtree-sync`.

**`bitcoin-build-config.h` replacements** (stand in for what CMake would have generated; contain `TARGET_OS_OSX` guards for `HAVE_GETENTROPY_RAND` and `HAVE_SYSTEM` to support iOS):

- `Sources/bitcoind/include/bitcoin-build-config.h` (bitcoind target)
- `Sources/libbitcoinkernel/src/bitcoin-build-config.h` (libbitcoinkernel target)

**Clang modulemap stubs** (`module <target> { requires !cplusplus; export * }` — tell SwiftPM not to auto-generate a modulemap, which under Linux's `-fno-implicit-modules` + Swift C++ interop would otherwise fail with "module needed but not provided"):

- `Sources/secp256k1/include/module.modulemap`
- `Sources/crc32c/include/module.modulemap`
- `Sources/leveldb/include/module.modulemap`
- `Sources/minisketch/include/module.modulemap`

The stub form (no `umbrella` / `header` declarations) means the module owns no headers, so C++ consumers continue to resolve `#include "secp256k1.h"` etc. via the `-I` search path as textual includes — and Swift consumers never `import` these targets (they're C/C++ hosts for the higher-level `BitcoinKernel` Swift target).

## Status

Upstreaming progresses: Local → Issue filed → PR open → Merged in vX → Patch dropped.

| Patch | File(s) | `.patch` | Upstream status |
|-------|---------|----------|-----------------|
| iOS netif guard | `src/common/netif.cpp` | [`ios-netif-guard.patch`](bitcoin/ios-netif-guard.patch) | Local |
| RPC once_flag removal + ResetRPC | `src/rpc/server.{cpp,h}` | [`rpc-server-reset.patch`](bitcoin/rpc-server-reset.patch) | Local |
| Shutdown global resets | `src/init.cpp` | [`shutdown-reset.patch`](bitcoin/shutdown-reset.patch) | Local |
| MAIN_FUNCTION guard | `src/compat/compat.h` | [`main-function-guard.patch`](bitcoin/main-function-guard.patch) | Local |
| Logging teardown assertion | `src/logging.cpp` | [`logging-teardown-assertion.patch`](bitcoin/logging-teardown-assertion.patch) | Local |

## Cited upstream issues

States last verified 2026-06-13. Re-check before filing anything that references them.

| Issue / PR | State | Subject |
|------------|-------|---------|
| [#31289](https://github.com/bitcoin/bitcoin/issues/31289) | Closed (completed) 2024-11-20 | `bitcoin-qt` startup assertion; the `StopRPC()` race. No fixing commit linked. |
| [#11720](https://github.com/bitcoin/bitcoin/issues/11720) | Closed (completed) 2023-04-27 | iOS deployment target for RPC |
| [#24303](https://github.com/bitcoin/bitcoin/issues/24303) | Closed | The libbitcoinkernel Project |
| [#27587](https://github.com/bitcoin/bitcoin/issues/27587) | Open | Bitcoin Kernel Library project tracking |
| [#27711](https://github.com/bitcoin/bitcoin/pull/27711) | Closed, unmerged | Remove shutdown from kernel library |
| [#31382](https://github.com/bitcoin/bitcoin/pull/31382) | Closed, unmerged | Flush in ChainstateManager destructor |
| [#18702](https://github.com/bitcoin/bitcoin/pull/18702) | Merged | Introduced `MAIN_FUNCTION` |
| [#18452](https://github.com/bitcoin/bitcoin/pull/18452) | Merged 2020-05-29 | GUI shutdown when waitfor* called from RPC console |
| [#35141](https://github.com/bitcoin/bitcoin/pull/35141) | Merged 2026-05-23 | Node-context reset pattern for fuzz |
| [#12557](https://github.com/bitcoin/bitcoin/pull/12557) | Closed, unmerged | 64-bit iOS device support (WIP) |

## Upstreaming playbook

These patches are local until merged upstream. The path that worked for this project (#35293 → #35304):

1. Open an issue on `bitcoin/bitcoin` with a reproducible branch on `21-DOT-DEV/bitcoin` that demonstrates the bug or the missing capability.
2. Keep the first PR minimal; land the fix or guard before any larger refactor.
3. Disclose AI assistance with an `Assisted-by:` trailer when applicable.
4. No `@`-mentions; ping via follow-up comments. DrahtBot assigns labels, so do not request them.
5. On merge, delete the local patch and move its Status row to "dropped".

## swift-boost

| # | Patch | Description |
|---|---|---|
| 1 | [Inter-target dependencies](swift-boost/inter-target-deps.md) | Dependency structure for swift-boost SPM targets |
| 2 | [Linux module compilation](swift-boost/linux-module-compilation.md) | ✅ Resolved upstream in `pruned-umbrella-1.90.0` |
