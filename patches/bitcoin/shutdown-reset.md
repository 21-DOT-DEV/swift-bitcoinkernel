# Bitcoin Core Upstream PR: Reset `g_shutdown` in `Shutdown()` for Restart Support

Prepared draft for contributing `g_shutdown.reset()` to Bitcoin Core's `src/init.cpp`.

## PR Title

```
init: reset g_shutdown in Shutdown() to support in-process restart
```

## PR Description

```markdown
Add `g_shutdown.reset()`, `gArgs.ClearArgs()`, and
`LogInstance().DisconnectTestLogger()` at the end of `Shutdown()` in
`src/init.cpp`, clearing global state so that `bitcoind_main()` can be called
again within the same process.

**Motivation:**

`Shutdown()` cleans up node-scoped state (chainstate, mempool, peers, indices,
scheduler, ECC context, kernel context) but does not reset two process-global
objects. Calling `bitcoind_main()` a second time hits fatal assertions:

1. `init.cpp:215: assert(!g_shutdown)` — `InitContext()` asserts `g_shutdown`
   is empty before emplacing the shutdown signal, but `Shutdown()` never resets it.
2. `args.cpp:603: assert(ret.second)` — `AddArg()` asserts each argument is
   inserted fresh, but `gArgs.m_available_args` still contains entries from the
   previous run. `ParseParameters()` only clears `command_line_options`, not the
   registered argument definitions.

This affects projects embedding Bitcoin Core as a library that need to
start/stop/restart the daemon without relaunching the host process — for
example, mobile apps (iOS/Android) and GUI applications that allow the user to
change configuration and restart the node.

`NodeContext` is stack-allocated fresh each `bitcoind_main()` invocation. The
two globals above are the only ones that block a clean restart.

**Change:**

```diff
     RemovePidFile(*node.args);

+    g_shutdown.reset();
+    gArgs.ClearArgs();
+    LogInstance().DisconnectTestLogger();
+
     LogInfo("Shutdown done");
 }
```

**Impact:**

- Zero behavior change for single-run invocations (the normal case)
- Enables `bitcoind_main()` to be called again after `Shutdown()` completes
- No test changes required for existing tests
- Does not affect consensus code
- `ClearArgs()` and `DisconnectTestLogger()` are existing public methods — no new API
- Follows the existing cleanup pattern in `Shutdown()` (all other node state
  is already reset/destructed before this point)
```

## Commit Message

```
init: reset global state in Shutdown() to support in-process restart

Add g_shutdown.reset() and gArgs.ClearArgs() at the end of Shutdown(),
clearing two process-global objects so that bitcoind_main() can be
re-invoked within the same process.

Shutdown() already cleans up all other node state (chainstate,
mempool, peers, indices, scheduler, ECC, kernel context) but leaves
three process-global objects stale:

- g_shutdown (std::optional<util::SignalInterrupt>) — emplaced in
  InitContext() which asserts it is empty on entry.
- gArgs.m_available_args — populated by SetupServerArgs(). AddArg()
  asserts each key is freshly inserted; ParseParameters() only clears
  command_line_options, not the registered arg definitions.
- LogInstance().m_buffering — set to false by StartLogging(), which
  asserts it is true on entry. The leaked singleton logger persists
  across restarts.

ClearArgs() and DisconnectTestLogger() are existing public methods.

This enables projects that embed Bitcoin Core as a library to restart
the daemon without relaunching the host process, which is important
for mobile apps and GUI applications that allow configuration changes
followed by a restart.

No behavior change for the normal single-run case.
```

## File Changed

**`src/init.cpp`** — 3 lines added (`g_shutdown.reset()`, `gArgs.ClearArgs()`, `LogInstance().DisconnectTestLogger()`)

### Diff (against current `master`)

```diff
diff --git a/src/init.cpp b/src/init.cpp
--- a/src/init.cpp
+++ b/src/init.cpp
@@ -414,6 +414,11 @@ void Shutdown(NodeContext& node)

     RemovePidFile(*node.args);

+    // Reset global state so that bitcoind_main() can be called again within
+    // the same process (e.g. an embedded app that restarts the daemon
+    // without relaunching).
+    g_shutdown.reset();
+    gArgs.ClearArgs();
+    LogInstance().DisconnectTestLogger();
+
     LogInfo("Shutdown done");
 }
```

> **Note:** Line numbers are approximate. The actual PR branch must be rebased
> onto `master` before opening. The `Shutdown()` function may have shifted due
> to upstream changes, but the insertion point (after `RemovePidFile`, before
> `LogInfo("Shutdown done")`) should be unambiguous.

## Bitcoin Core PR Process Checklist

Per [CONTRIBUTING.md](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md):

- [ ] Fork `bitcoin/bitcoin` and create a branch from `master`
- [ ] Rebase the change onto current `master`
- [ ] Verify the diff applies cleanly to current `master`'s `init.cpp`
- [ ] Run the existing test suite: `ctest --test-dir build` (no new tests needed — no behavior change for single-run)
- [ ] Consider adding a functional test that calls `bitcoind_main()` twice (optional — strengthens the PR)
- [ ] PR title uses area prefix: `init:` (matches file location `src/init.cpp`)
- [ ] Commit message follows project conventions (imperative mood, no `@` mentions)
- [ ] No `@` mentions in PR description (use follow-up comments for pings)
- [ ] Consider pinging reviewers who last touched `Shutdown()` (use `git blame src/init.cpp`)

## Context & Prior Art

### How `g_shutdown` works today

- **Type**: `static std::optional<util::SignalInterrupt>` (file-scope in `init.cpp`)
- **Lifecycle**: emplaced in `InitContext()` (line ~216), used as the shutdown signal throughout the node's lifetime
- **Signal path**: `HandleSIGTERM()` → `(*g_shutdown)()` → `SignalInterrupt::operator()()` → wakes `bitcoind_main()`'s `wait()` call
- **Missing cleanup**: `Shutdown()` resets every other piece of global state (`node.chainman`, `node.mempool`, `node.kernel`, etc.) but never resets `g_shutdown`

### Why this is safe

| Concern | Status |
|---|---|
| Thread safety | `Shutdown()` is called after all threads are joined; no concurrent access to `g_shutdown` |
| Signal handlers | Signal handlers (`HandleSIGTERM`) are unregistered before `Shutdown()` runs |
| Destructor side effects | `util::SignalInterrupt` destructor is trivial (closes pipe fds) — safe to call here |
| `NodeContext` reuse | `NodeContext` is stack-allocated in `bitcoind_main()` — fresh each invocation |
| `gArgs` reuse | `ParseParameters()` calls `m_settings.command_line_options.clear()` — self-cleans |

### The `Shutdown()` cleanup sequence

```
Shutdown() cleanup order:
  1. Stop HTTP RPC, REST, RPC server, HTTP server
  2. Stop chain clients (wallets)
  3. Stop map port, peer manager, connection manager
  4. Stop Tor, background init, scheduler
  5. Reset peerman, connman, banman, addrman, netgroupman
  6. Dump mempool, flush fee estimator
  7. Flush chainstate to disk (twice)
  8. Stop and destroy all indexes
  9. Flush validation interface callbacks
  10. Reset chain clients, mempool, chainman, validation_signals, scheduler, ecc, kernel
  11. Remove PID file
  → g_shutdown.reset()  ← NEW (this PR)
  12. Log "Shutdown done"
```

### Related PRs & Issues

| PR/Issue | Title | Relevance |
|---|---|---|
| [#24303](https://github.com/bitcoin/bitcoin/issues/24303) | `The libbitcoinkernel Project` | Library extraction — makes Bitcoin Core embeddable |
| [#27711](https://github.com/bitcoin/bitcoin/pull/27711) | `Remove shutdown from kernel library` | Moved shutdown signaling out of kernel, uses `kernel::Notifications` instead |
| [#27587](https://github.com/bitcoin/bitcoin/issues/27587) | `Bitcoin Kernel Library Project Tracking` | Ongoing kernel library work |
| [#31382](https://github.com/bitcoin/bitcoin/pull/31382) | `kernel: Flush in ChainstateManager destructor` | RAII-ifying shutdown cleanup — same direction as this PR |

### Why a full restart works

`bitcoind_main()` (expanded from `MAIN_FUNCTION` in `bitcoind.cpp`) creates a
fresh `NodeContext` on the stack each invocation. The only globals that persist
across calls are:

| Global | Cleaned up? |
|---|---|
| `gArgs` (ArgsManager) | **No** — `ParseParameters()` only clears `command_line_options`, not `m_available_args`. This PR adds `ClearArgs()` |
| `LogInstance()` (BCLog::Logger) | **No** — `m_buffering` set to `false` by `StartLogging()`, leaked singleton persists. This PR adds `DisconnectTestLogger()` |
| `tableRPC` (CRPCTable) | Accumulates — safe (commands are additive, not conflicting) |
| `g_shutdown` | **No** — this PR fixes it |
| `LogInstance()` | Singleton, reused — safe |

## Labels to Request

- `Refactoring` — cleanup of shutdown path
- `Utils/log/libs` — affects init/shutdown lifecycle
