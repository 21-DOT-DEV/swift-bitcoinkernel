# Make the RPC server restartable

`InterruptRPC()` and `StopRPC()` — the two functions that wind down Bitcoin Core's JSON-RPC server — each guard themselves with `std::once_flag`, a C++ one-shot lock that can never re-arm. One shot per process means a second node start inside the same process trips fatal assertions. The locks are also stronger than needed: both function bodies are already safe to call twice. Removing them fixes a separately reported startup crash as well, and a new three-line helper, `ResetRPC()`, restores the server's "warming up" state for the next lifecycle.

| | |
|---|---|
| **Status** | Applied here; not yet filed upstream. Still needed on master: the locks remain at `src/rpc/server.cpp:281,292` (checked 2026-07-02). |
| **Touches** | `src/rpc/server.cpp`, `src/rpc/server.h` |
| **Depends on** | Nothing. |
| **Unlocks** | [Reset four globals at shutdown](shutdown-reset.md) — it needs `InterruptRPC()`/`StopRPC()` to be restartable first. Locally this patch also carries the `ResetRPC()` helper; upstream that helper ships with the shutdown PR (see the must-not list below). |
| **File as** | Direct pull request, step 5 of [the pipeline](../UPSTREAMING.md#the-pipeline). Link the discussion thread for context; the crash fix justifies the PR on its own. |
| **PR title** | `rpc: remove once_flag from InterruptRPC/StopRPC` |
| **Cite** | [#31289](https://github.com/bitcoin/bitcoin/issues/31289) — the startup crash this removes (closed 2024 with no fix; still reproduces). [#19111](https://github.com/bitcoin/bitcoin/pull/19111) — precedent: the same locks were already narrowed once, on the same reasoning. |

## The change

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

The diff matches the vendored v31.0 tree and applies cleanly to it (checked 2026-07-17); rebase onto current `master` before opening the PR.

## Writing the PR

Must say:

- Lead with the crash. Preserved wording: "The `once_flag` in `InterruptRPC()` can be consumed before `StartRPC()` sets `g_rpc_running`, so `StopRPC()`'s `assert(!g_rpc_running)` can fire" — the race reported in #31289, still reproducible on master.
- Both bodies are naturally idempotent (safe to call twice): `InterruptRPC()` sets an atomic flag that is already false the second time; `StopRPC()` deletes a cookie file that is already gone.
- The one observable change. Preserved wording: "`InterruptRPC()` before `StartRPC()` now early-returns silently instead of logging and burning the flag."
- Include a regression test driving `InterruptRPC(); StartRPC(); InterruptRPC(); StopRPC();`.

Must not:

- Do not include `ResetRPC()` in the upstream PR. Upstream it has no caller until the shutdown patch lands, and "new API with zero callers" is a standard rejection — it ships with [its caller](shutdown-reset.md) instead. Our local `.patch` does include it, because our shutdown patch is its caller here. This is the one place the local patch and the upstream PR deliberately differ.
- Do not write "Fixes #31289" — that issue is closed; cite it as the historical report.

## Notes

Why removing the locks is safe:

| Property | With `std::once_flag` | Without |
|---|---|---|
| Safe to call twice in one lifecycle | Yes | Yes — `InterruptRPC()` checks the atomic flag; `StopRPC()`'s body is idempotent |
| Thread-safe | Yes | Yes — the flag is `std::atomic<bool>`; `StopRPC()` runs on the shutdown thread after RPC workers are joined |
| Can re-arm for a second lifecycle | **No** | Yes |
| Exposed to the #31289 race | Yes | No — the flag is checked directly |

Shutdown runs `InterruptRPC()` then `StopRPC()` then (locally) `ResetRPC()` in sequence on one thread; the next start's `SetRPCWarmupFinished()` then finds the warmup flag it asserts on.
