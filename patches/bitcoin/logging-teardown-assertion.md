# Stop the late-log crash during teardown

`DisconnectTestLogger()` — the logger's between-lifecycles reset — closes the log file and nulls the file handle, but leaves the "write to file" switch on. A background thread that logs one line after that hits `assert(m_fileout != nullptr)` and aborts the process. Every test can pass and the process still exits non-zero. The fix is one line: turn the switch off too. Late messages are then dropped silently, which is fine — the output that matters was already captured.

The crash sequence:

1. Teardown calls `DisconnectTestLogger()`.
2. The log file is closed and the handle set to null.
3. The "write to file" switch (`m_print_to_file`) stays on.
4. A background thread (the scheduler, for example) logs a message.
5. `LogPrintStr()` sees the switch on, asserts the handle is non-null, and aborts.

| | |
|---|---|
| **Status** | Applied here; not yet filed upstream. Still needed on master: `DisconnectTestLogger()` still leaves `m_print_to_file` true (checked 2026-07-02). |
| **Touches** | `src/logging.cpp` |
| **Depends on** | Nothing. |
| **File as** | Direct pull request, anytime — step 2 of [the pipeline](../UPSTREAMING.md#the-pipeline). Optional report-then-fix variant (the #35293 → #35304 pattern that worked before): open a small issue with the crash sequence first, but only if it ships with an upstream-shaped repro branch — without the repro, the direct PR is stronger. |
| **PR title** | `logging: clear m_print_to_file on teardown` |
| **Cite** | [#29018](https://github.com/bitcoin/bitcoin/issues/29018) — their open fuzz-stability tracker; an abort during teardown is that problem class. |

## The change

```diff
 void BCLog::Logger::DisconnectTestLogger()
 {
     StdLockGuard scoped_lock(m_cs);
     m_buffering = true;
     if (m_fileout != nullptr) fclose(m_fileout);
     m_fileout = nullptr;
+    m_print_to_file = false;  // swift-bitcoinkernel: prevent assertion during teardown
     m_print_callbacks.clear();
```

## Writing the PR

Must say:

- The five-step sequence above; it is a one-line defensive fix — if the file handle is null, the write-to-file switch should be off.
- The path is not test-only in practice: every `BasicTestingSetup` teardown runs it, including fuzz targets that build a full setup per input (`utxo_total_supply`), so a teardown abort is a stability liability of the #29018 kind.
- Frame it as teardown robustness. No restart story needed.
- Answer the test question either way: the crash needs a background thread racing teardown, so if a deterministic test is impractical, say so in the PR and explain why.
