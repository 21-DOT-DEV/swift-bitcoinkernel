# Reset four globals at shutdown

`Shutdown()` tears down everything the node built — chain state, mempool, peers, indexes — but leaves four process-wide globals holding state from the finished run, and each one greets a second `bitcoind_main()` call with a fatal assertion. This patch resets all four at the very end of `Shutdown()`, which is exactly what Bitcoin Core's own test framework already does between in-process test runs. The result is a clean stop → reconfigure → start cycle for apps that embed the node.

The four globals, and the assertion each one trips on restart:

1. `g_shutdown` — the shutdown signal; the next init asserts it is empty (`src/init.cpp:215`).
2. `gArgs` — the registry of command-line options; re-registering asserts every option is new (`src/common/args.cpp:603`).
3. `LogInstance().m_buffering` — the logger's startup mode; `StartLogging()` asserts it is on.
4. `fRPCInWarmup` — the RPC "warming up" flag; `SetRPCWarmupFinished()` asserts it is set.

| | |
|---|---|
| **Status** | Applied here; not yet filed upstream. Still needed on master: `src/init.cpp` performs none of these resets (checked 2026-07-02). |
| **Touches** | `src/init.cpp` — and, in the upstream PR only, `src/rpc/server.{cpp,h}`, which receive the `ResetRPC()` helper (locally that helper lives in the RPC patch). |
| **Depends on** | [Make the RPC server restartable](rpc-server-reset.md) — its once-flag removal must merge upstream first so `InterruptRPC()`/`StopRPC()` can run again in a second lifecycle. It does not supply `ResetRPC()`: upstream, that helper ships here, with its caller. |
| **File as** | Pull request only after the discussion thread (step 4 of [the pipeline](../UPSTREAMING.md#the-pipeline)) gets a maintainer thumbs-up on the approach. This PR closes the thread. |
| **PR title** | `init: reset process globals in Shutdown()` |
| **Cite** | The discussion thread ⟨link once open⟩. [#34302](https://github.com/bitcoin/bitcoin/pull/34302) / [#35141](https://github.com/bitcoin/bitcoin/pull/35141) — their fuzz targets already reset node state between in-process iterations. [#29018](https://github.com/bitcoin/bitcoin/issues/29018) — their open tracker for exactly this leftover-global-state problem class. [#30537](https://github.com/bitcoin/bitcoin/pull/30537) — the kernel side already tolerates repeated contexts per process. |
| **Evidence** | `Tests/BitcoinTests/DaemonSoakTests.swift` — five clean stop/start cycles in one process with this patch applied (~1.8 s). Opt-in, not run in CI: `RUN_SOAK_TESTS=1 swift test --filter 'BitcoinTests.DaemonSoakTests'` (it runs alone because it owns the one daemon). |

## The change

```diff
diff --git a/src/init.cpp b/src/init.cpp
--- a/src/init.cpp
+++ b/src/init.cpp
@@ -414,6 +414,12 @@ void Shutdown(NodeContext& node)

     RemovePidFile(*node.args);

+    // Reset global state so that bitcoind_main() can be called again within
+    // the same process (e.g. an embedded app that restarts the daemon
+    // without relaunching).
+    g_shutdown.reset();
+    gArgs.ClearArgs();
+    ResetRPC();
+    LogInstance().DisconnectTestLogger();
+
     LogInfo("Shutdown done");
 }
```

The diff matches the vendored v31.0 tree and applies cleanly to it (checked 2026-07-17; the insertion point sits at `src/init.cpp:414-416` there). On master the function may have shifted, but the insertion point — after `RemovePidFile`, before the final "Shutdown done" log line — is unambiguous. Rebase onto current `master` before opening the PR.

## Writing the PR

Must say:

- The four globals and their assertions, exactly as listed above, with file and line.
- It mirrors the test framework: `~BasicTestingSetup` already calls `LogInstance().DisconnectTestLogger()` and `gArgs.ClearArgs()` between in-process lifecycles (`src/test/util/setup_common.cpp:227,237`). This brings production shutdown to parity.
- Zero behavior change for the normal single-run case; two of the four calls are existing public methods, and all other node state is already reset earlier in `Shutdown()`.
- Implement whichever shape the thread approved. The open design question posed there: reset at the end of `Shutdown()`, or lazily at the next `InitContext()` (which provably cannot affect a single run)?
- The evidence: five clean in-process restart cycles, with a link to the repro branch.
- Offer an in-tree test in the PR itself — a test driving a second init/shutdown cycle — because bug-fix PRs are expected to carry the test that proves the fix. The external soak evidence supports the claim; it does not replace the test.

Must not:

- Never claim the patch fixes their fuzzing. Preserved wording: "No upstream fuzz target drives a full `bitcoind_main()` init/shutdown cycle today, so this is alignment with an enforced direction, not the removal of an existing blocker."
- Never claim it makes iOS work — the kernel library builds for iOS with no patches at all (see the [CMake memo](cmake-ios-library-build.md)).

## Notes

- Safety: `Shutdown()` runs after every thread is joined and signal handlers are unregistered, so nothing races the resets; they sit after every other teardown step and before only the final log line.
- `NodeContext` (the per-run bundle of node state) is stack-allocated fresh on each `bitcoind_main()` call. These four globals are the only cross-run blockers; the RPC command table also persists, but harmlessly (registration is additive).
- The logger reset borrows a test-framework method, `DisconnectTestLogger()`. The thread floats giving it a production-appropriate name; adopt whatever reviewers prefer.
