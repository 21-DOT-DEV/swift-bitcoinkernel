# Bitcoin Core Upstream PR: Remove `std::once_flag` from RPC Lifecycle

Prepared draft for removing unnecessary `std::once_flag` from `InterruptRPC()`/`StopRPC()` and adding `ResetRPC()` in Bitcoin Core's `src/rpc/server.cpp` and `src/rpc/server.h`.

> **Upstream strategy**: This is **PR 1 of 2** (pure refactor). PR 2 (`upstream-shutdown-reset-pr.md`) adds `ResetRPC()` call + other global resets in `Shutdown()` for restart support. PR 1 stands alone — it simplifies code and fixes #31289.

## PR Title

```
rpc: replace std::once_flag with resettable guards in InterruptRPC/StopRPC
```

## PR Description

```markdown
Remove `static std::once_flag` + `std::call_once` from `InterruptRPC()`
and `StopRPC()`. Both functions are naturally idempotent without them.
Add `ResetRPC()` to restore RPC warmup state to initial values.

**Motivation:**

`InterruptRPC()` and `StopRPC()` each use a `static std::once_flag` to
ensure their bodies execute at most once. The original intent was
idempotency — these functions can be called twice when the GUI is started
with `-server=1`.

However, `std::once_flag` is **stronger than needed**:

1. **`InterruptRPC()`** sets `g_rpc_running = false`. Setting an atomic
   bool to `false` when it's already `false` is a no-op — the function
   is naturally idempotent. An `if (!g_rpc_running) return` guard is
   clearer and avoids the lambda indirection.

2. **`StopRPC()`** calls `DeleteAuthCookie()`, which internally calls
   `fs::remove()` — returns `false` on a missing file, no error. The
   body is naturally idempotent.

3. **Race in #31289**: `std::once_flag` in `InterruptRPC()` can be
   consumed before `StartRPC()` sets `g_rpc_running = true`, leaving
   `StopRPC()`'s `assert(!g_rpc_running)` to crash. Checking
   `g_rpc_running` directly eliminates this race.

4. **`std::once_flag` is permanently one-shot** per C++ spec and cannot
   be reset between daemon lifecycles, blocking in-process restart for
   library embedders.

**Changes:**

1. `InterruptRPC()`: remove `std::once_flag`, add `if (!g_rpc_running)
   return` — natural idempotency.

2. `StopRPC()`: remove `std::once_flag`, unwrap lambda — body is
   idempotent (`DeleteAuthCookie` handles missing file).

3. Remove `#include <mutex>` — no longer needed (`GlobalMutex`/`LOCK`
   come from `<sync.h>`).

4. Add `ResetRPC()`: resets `fRPCInWarmup` and `rpcWarmupStatus` to
   initial values. These are the only RPC globals with assertions that
   block restart (`SetRPCWarmupFinished()` asserts `fRPCInWarmup`).

5. Declare `ResetRPC()` in `src/rpc/server.h`.

**Impact:**

- Preserves the existing double-call safety for GUI + server shutdown
- Zero behavior change for single-run invocations
- Fixes #31289 (race between InterruptRPC and StartRPC)
- Enables `ResetRPC()` to be called from `Shutdown()` for restart support
- No test changes required for existing tests
- Does not affect consensus code
```

## Commit Message

```
rpc: remove std::once_flag from InterruptRPC/StopRPC

Remove static std::once_flag + std::call_once from InterruptRPC() and
StopRPC(). Both functions are naturally idempotent without them:

- InterruptRPC() sets g_rpc_running (atomic bool) to false; a second
  call is a no-op. An explicit if-guard makes this clear.
- StopRPC() calls DeleteAuthCookie() which handles missing files.

std::once_flag was stronger than needed — the requirement is per-
lifecycle idempotency, not permanent one-shot-per-process. Removing
it also fixes the race in #31289 where the once_flag is consumed
before StartRPC() completes.

Add ResetRPC() to restore fRPCInWarmup and rpcWarmupStatus to their
initial values, enabling callers to prepare for a new RPC lifecycle.
```

## Files Changed

**`src/rpc/server.cpp`** — Remove `std::once_flag`, remove `#include <mutex>`, add `ResetRPC()`
**`src/rpc/server.h`** — Declare `ResetRPC()`

### Diff (against current `master`)

```diff
diff --git a/src/rpc/server.cpp b/src/rpc/server.cpp
--- a/src/rpc/server.cpp
+++ b/src/rpc/server.cpp
@@ -27,7 +27,6 @@
 #include <cassert>
 #include <chrono>
 #include <memory>
-#include <mutex>
 #include <string_view>
 #include <unordered_map>

@@ -279,22 +278,26 @@ void StartRPC()

 void InterruptRPC()
 {
-    static std::once_flag g_rpc_interrupt_flag;
-    // This function could be called twice if the GUI has been started with -server=1.
-    std::call_once(g_rpc_interrupt_flag, []() {
-        LogDebug(BCLog::RPC, "Interrupting RPC\n");
-        // Interrupt e.g. running longpolls
-        g_rpc_running = false;
-    });
+    // Guard: this function could be called twice if the GUI has been started with -server=1.
+    if (!g_rpc_running) return;
+    LogDebug(BCLog::RPC, "Interrupting RPC\n");
+    // Interrupt e.g. running longpolls
+    g_rpc_running = false;
 }

 void StopRPC()
 {
-    static std::once_flag g_rpc_stop_flag;
-    // This function could be called twice if the GUI has been started with -server=1.
+    // Guard: this function could be called twice if the GUI has been started with -server=1.
     assert(!g_rpc_running);
-    std::call_once(g_rpc_stop_flag, [&]() {
-        LogDebug(BCLog::RPC, "Stopping RPC\n");
-        DeleteAuthCookie();
-        LogDebug(BCLog::RPC, "RPC stopped.\n");
-    });
+    LogDebug(BCLog::RPC, "Stopping RPC\n");
+    DeleteAuthCookie();
+    LogDebug(BCLog::RPC, "RPC stopped.\n");
+}
+
+void ResetRPC()
+{
+    LOCK(g_rpc_warmup_mutex);
+    fRPCInWarmup = true;
+    rpcWarmupStatus = "RPC server started";
 }

diff --git a/src/rpc/server.h b/src/rpc/server.h
--- a/src/rpc/server.h
+++ b/src/rpc/server.h
@@ -133,6 +133,7 @@ extern CRPCTable tableRPC;
 void StartRPC();
 void InterruptRPC();
 void StopRPC();
+void ResetRPC();
 UniValue JSONRPCExec(const JSONRPCRequest& jreq, bool catch_errors);
```

> **Note:** Line numbers are approximate. The actual PR branch must be rebased
> onto `master` before opening.

## Bitcoin Core PR Process Checklist

Per [CONTRIBUTING.md](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md):

- [ ] Fork `bitcoin/bitcoin` and create a branch from `master`
- [ ] Rebase the change onto current `master`
- [ ] Verify the diff applies cleanly
- [ ] Run the existing test suite: `ctest --test-dir build`
- [ ] PR title uses area prefix: `rpc:` (matches module area)
- [ ] Commit message follows project conventions (imperative mood, no `@` mentions)
- [ ] No `@` mentions in PR description (use follow-up comments for pings)
- [ ] Consider pinging reviewers who last touched `src/rpc/server.cpp` (use `git blame`)

## Context & Prior Art

### Why `std::once_flag` was used

The original code comments explain: "This function could be called twice if the
GUI has been started with `-server=1`." Both the GUI shutdown path and the server
shutdown path can call `InterruptRPC()` and `StopRPC()`, so idempotency is
required.

`std::once_flag` was chosen as a strong guarantee — but it's **stronger than
needed**. The actual requirement is idempotency within a single daemon lifecycle,
not permanent one-shot-per-process.

### Why `std::once_flag` removal is safe

| Property | `std::once_flag` | Natural idempotency |
|---|---|---|
| Idempotent within lifecycle | Yes | Yes — `InterruptRPC()` checks `g_rpc_running`; `StopRPC()` body is idempotent |
| Thread-safe | Yes (built-in) | Yes — `g_rpc_running` is `std::atomic<bool>`; `StopRPC()` runs on shutdown thread after all RPC threads are joined |
| Resettable between lifecycles | **No** | Yes |
| Immune to #31289 race | No — once_flag consumed before StartRPC completes | Yes — checks `g_rpc_running` directly |
| New variables introduced | N/A | None — no `g_rpc_stopped` needed |

### Related Issues & PRs

| PR/Issue | Title | Relevance |
|---|---|---|
| [#31289](https://github.com/bitcoin/bitcoin/issues/31289) | `bitcoin-qt failed assertion on startup` | Race between `InterruptRPC()` and `StartRPC()` causes `assert(!g_rpc_running)` crash in `StopRPC()`. The `std::once_flag` in `InterruptRPC()` consumed its one chance before `g_rpc_running` was set to `true`. |
| [#18452](https://github.com/bitcoin/bitcoin/pull/18452) | `Fix GUI shutdown when waitfor* cmds are called from RPC console` | Added `InterruptRPC(); StopRPC();` to GUI shutdown path, increasing the likelihood of double-calls that motivated the `once_flag` pattern |
| [#24303](https://github.com/bitcoin/bitcoin/issues/24303) | `The libbitcoinkernel Project` | Library extraction — makes Bitcoin Core embeddable, where in-process restart becomes a real use case |
| [#27587](https://github.com/bitcoin/bitcoin/issues/27587) | `Bitcoin Kernel Library Project Tracking` | Ongoing kernel library work |

### Thread safety analysis

```
Shutdown sequence (single-threaded after thread joins):

  Interrupt(node)          ← calls InterruptRPC()  [g_rpc_running = false]
  Shutdown(node)           ← calls StopRPC()       [logs + DeleteAuthCookie]
                             calls ResetRPC()       [warmup flags reset]

Second lifecycle:

  AppInit(node)            ← calls StartRPC()      [g_rpc_running = true]
  ...normal operation...
  SetRPCWarmupFinished()   ←                        [fRPCInWarmup = false] ← assert passes
```

`InterruptRPC()` is called from signal handler context or the main thread.
`g_rpc_running` is `std::atomic<bool>`, so the early-return check is safe.
`StopRPC()` and `ResetRPC()` run sequentially on the shutdown thread after
all RPC worker threads have been joined.

*Issue states: see [patches/README.md](../README.md#cited-upstream-issues) (verified 2026-06-13).*
