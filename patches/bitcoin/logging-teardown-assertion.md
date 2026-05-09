# Bitcoin Core Local Patch: Fix `DisconnectTestLogger` Assertion During Teardown

**Date**: 2026-05-08
**Status**: Applied (suitable for upstream)
**Repo**: https://github.com/bitcoin/bitcoin
**File**: `src/logging.cpp`

## Problem

During test teardown, `DisconnectTestLogger()` closes the log file and sets `m_fileout = nullptr`, but does not set `m_print_to_file = false`. When a background scheduler thread is still running and attempts to log after the logger is disconnected, `LogPrintStr()` hits:

```cpp
// logging.cpp line 498
if (m_print_to_file && !ratelimit) {
    assert(m_fileout != nullptr);  // ← SIGABRT
```

The sequence:
1. Test suite completes, teardown calls `DisconnectTestLogger()`
2. `m_fileout` is set to `nullptr`, file is closed
3. `m_print_to_file` remains `true`
4. A background thread (scheduler, etc.) logs a message
5. `assert(m_fileout != nullptr)` fires → process aborts with signal 6

All tests pass — the assertion happens during process exit after the test suite reports success. But it causes a non-zero exit code.

## Fix

```diff
 void BCLog::Logger::DisconnectTestLogger()
 {
     StdLockGuard scoped_lock(m_cs);
     m_buffering = true;
     if (m_fileout != nullptr) fclose(m_fileout);
     m_fileout = nullptr;
+    m_print_to_file = false;  // swift-bitcoin: prevent assertion during teardown
     m_print_callbacks.clear();
```

When `m_print_to_file` is `false`, the `if (m_print_to_file && !ratelimit)` guard in `LogPrintStr()` short-circuits before reaching the assertion. Background thread log messages are silently dropped during teardown — acceptable since the test output has already been captured.

## Why upstream

This is a defensive improvement: `DisconnectTestLogger()` should set all logging state to "disconnected." The full daemon never hits the assertion in normal operation (all background threads are joined before disconnect), but adding `m_print_to_file = false` makes the code more robust against edge cases. It's a one-line change with zero risk — if `m_fileout` is null, `m_print_to_file` should be false.