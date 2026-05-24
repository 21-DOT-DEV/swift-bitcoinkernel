# `btck_chainstate_manager_get_best_entry` can return null after `setWipeDBs(true, true)`, leading to undocumented SEGV in accessor functions

**Component**: `libbitcoinkernel` C API
**Files**: `src/kernel/bitcoinkernel.cpp`, `include/bitcoinkernel.h`
**Symptom severity**: SIGSEGV (signal 11) of the host process
**Observed**: 2026-05-03, while building `KernelApp` Phase B2
**Bitcoin Core version observed against**: vendored at `Vendor/bitcoin/`
**Stack trace captured**: yes — see [Stack trace](#stack-trace) below
**Reproducer (regression coverage)**: [`Tests/BitcoinKernelTests/UpstreamConcernsTests.swift::captureSegfaultForUpstream`](../../Tests/BitcoinKernelTests/UpstreamConcernsTests.swift) (`.disabled` by default)

---

## TL;DR

After opening a chainstate manager with `setWipeDBs(blockTreeDB: true, chainstateDB: true)` against a previously-used data directory, **`btck_chainstate_manager_get_best_entry` returns `nullptr`** because `chainman.m_best_header` is null at that point. The accompanying doc comment in `bitcoinkernel.h` does not mention this possibility, and the downstream accessors (`btck_block_tree_entry_get_height`, `_get_block_hash`, `_get_block_header`, `_equals`) dereference the entry pointer without null-guarding. Any caller following the documented usage pattern segfaults.

The C API surface needs one of:

- **Option A** — guarantee `m_best_header` is non-null whenever the manager is observable to callers (e.g., re-bootstrap genesis at the end of construction when wipe flags were set).
- **Option B** — document that `get_best_entry` may return null on a freshly-wiped manager, and add null guards to the entry accessors so the failure mode is "no-op / sentinel" rather than SEGV.

## Root cause (read directly from current source)

The function returns whatever `chainman.m_best_header` happens to be:

```cpp
// src/kernel/bitcoinkernel.cpp:1047-1051
const btck_BlockTreeEntry* btck_chainstate_manager_get_best_entry(
    const btck_ChainstateManager* chainstate_manager)
{
    auto& chainman = *btck_ChainstateManager::get(chainstate_manager).m_chainman;
    return btck_BlockTreeEntry::ref(
        WITH_LOCK(chainman.GetMutex(), return chainman.m_best_header));
    //                                       ^^^^^^^^^^^^^^^^^^^^^^^
    //          nullptr after a (true, true) wipe and before any block
    //          has been re-loaded by the caller
}
```

`Handle::ref` is a plain `reinterpret_cast` (no null check):

```cpp
// src/kernel/bitcoinkernel.cpp:99-127
template <typename C, typename CPP>
struct Handle {
    static const C* ref(const CPP* cpp_type) {
        return reinterpret_cast<const C*>(cpp_type);   // null in → null out
    }
    static const CPP& get(const C* ptr) {
        return *reinterpret_cast<const CPP*>(ptr);     // ← UB if ptr is null
    }
};
```

The downstream accessors all reach `Handle::get(entry)` without a null guard. Example:

```cpp
// src/kernel/bitcoinkernel.cpp:1165-1168
int32_t btck_block_tree_entry_get_height(const btck_BlockTreeEntry* entry)
{
    return btck_BlockTreeEntry::get(entry).nHeight;   // SEGV here if entry is null
}
```

The `bitcoinkernel.h` doc comment for `btck_chainstate_manager_get_best_entry` says:

```c
/* include/bitcoinkernel.h:1109-1113 */
 * @param[in] chainstate_manager Non-null.
 * @return                       The btck_BlockTreeEntry.
 */
```

— silent about the post-wipe null case.

## Stack trace

Captured 2026-05-03 from Xcode (Swift Testing under LLDB) on the reproducer below:

```
#0  btck_block_tree_entry_get_height(const btck_BlockTreeEntry *)
       at Sources/libbitcoinkernel/src/kernel/bitcoinkernel.cpp:1167
#1  BlockTreeEntry.height.getter
       at Sources/BitcoinKernel/Block/BlockTreeEntry.swift:29
#2  openOnce(wipeAll:) in captureSegfaultForUpstream()
       at Tests/BitcoinKernelTests/UpstreamConcernsTests.swift:189
#3  captureSegfaultForUpstream()
       at Tests/BitcoinKernelTests/UpstreamConcernsTests.swift:194
```

Frame `#0` is `*reinterpret_cast<const CBlockIndex*>(nullptr)` — the null-deref of `nHeight`.

## Empirical matrix (persistent storage)

| Sequence                                                            | Result      |
|---------------------------------------------------------------------|-------------|
| Fresh dir → `(true, true)` open + `bestEntry.height`                | works       |
| Prior open (no `bestEntry` access) → `(true, true)` + access        | works       |
| Prior open + access → reopen `(false, false)` + access              | works       |
| Prior open + access → reopen `(false, true)` + access               | works       |
| Prior open + access → reopen `(true, false)` + access               | works       |
| **Prior open + access → reopen `(true, true)` + access**            | **SIGSEGV** |

The first row matters: a *fresh* dir + `(true, true)` works, because the manager's startup path still loads genesis. The bug is specifically a wipe that throws away the on-disk block tree without re-loading genesis, leaving `m_best_header == nullptr`.

Captured via `swift test` running each row in isolation (5/5 SIGSEGVs on the crashing row). The `bestEntry` access bisection — identical sequences with and without that single line — gave 3/3 pass and 3/3 SIGSEGV respectively.

## Suggested upstream fix

**Option A — keep `m_best_header` non-null** (recommended):

> Inside `btck_chainstate_manager_create` (or the wipe-handling code path), when both wipe flags are set, re-bootstrap the genesis block before returning the manager. After this fix, `m_best_header` is guaranteed non-null whenever a constructed manager is observable to callers, matching the implicit contract of the doc comment.

**Option B — document and null-guard**:

> Update `bitcoinkernel.h` doc comment to mention "may return null on a freshly-wiped manager that has not yet processed any blocks." Add explicit null guards to:
>
> - `btck_block_tree_entry_get_height`
> - `btck_block_tree_entry_get_block_hash`
> - `btck_block_tree_entry_get_block_header`
> - `btck_block_tree_entry_get_previous` (already null-checks `pprev` but not the entry itself)
> - `btck_block_tree_entry_equals`
>
> Each guard could `LogError` and return a sentinel (`0` for height, `nullptr` for object returns) — matching the existing pattern in e.g. `btck_block_read`.

Either fix unblocks the embedder use case. Option A preserves API ergonomics; Option B is more local but pushes complexity to every binding generator.

## Why this matters for embedders

Mobile and embeddable contexts (`KernelApp`, `py-bitcoinkernel`, etc.) cannot recover from a SIGSEGV. The current behavior forces every caller to know "if you used `(true, true)` wipe, do not call `bestEntry` until you have processed at least one block" — a precondition that is not documented in the C header. Worse, language bindings that infer nullability from the doc comment (Swift's `.apinotes`, ObjC `nonnull`, Rust `Option<>` choices) will all generate non-failable signatures and hit the same SEGV.

## Reproduction (Swift, 25 lines)

```swift
import BitcoinKernel
import Foundation

let params = ChainParameters(.regtest)
let opts = ContextOptions()
opts.setChainParams(params)

let tmpDir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).path
try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

// First open: persistent, no wipe. Materializes block-index on disk.
do {
    let ctx = try Context(options: opts)
    let mopts = try ChainstateManagerOptions(context: ctx, dataDirectory: tmpDir)
    let mgr = try ChainstateManager(options: mopts)
    _ = mgr.bestEntry.height  // CRITICAL: forces chainstate state-write
}

// Second open: same dir, both wipe flags set.
let ctx2 = try Context(options: opts)
let mopts2 = try ChainstateManagerOptions(context: ctx2, dataDirectory: tmpDir)
_ = mopts2.setWipeDBs(blockTreeDB: true, chainstateDB: true)
let mgr2 = try ChainstateManager(options: mopts2)  // succeeds (silent null m_best_header)
_ = mgr2.bestEntry.height                          // SIGSEGV (signal 11)
```

## Reproduction (C, 35 lines)

```c
#include <bitcoinkernel/bitcoinkernel.h>
#include <stdio.h>
#include <sys/stat.h>

int main(void) {
    const char* dir = "/tmp/bk-getbestentry-segfault";
    mkdir(dir, 0700);

    /* First open — must call get_best_entry on the result to materialize state. */
    btck_Context* ctx1 = btck_context_create(NULL);
    btck_ChainstateManagerOptions* opts1 =
        btck_chainstate_manager_options_create(ctx1, dir);
    btck_ChainstateManager* mgr1 = btck_chainstate_manager_create(ctx1, opts1);
    const btck_BlockTreeEntry* tip1 = btck_chainstate_manager_get_best_entry(mgr1);
    int32_t h1 = btck_block_tree_entry_get_height(tip1);
    printf("first open height=%d\n", h1);
    btck_chainstate_manager_destroy(mgr1);
    btck_chainstate_manager_options_destroy(opts1);
    btck_context_destroy(ctx1);

    /* Second open with full wipe. */
    btck_Context* ctx2 = btck_context_create(NULL);
    btck_ChainstateManagerOptions* opts2 =
        btck_chainstate_manager_options_create(ctx2, dir);
    btck_chainstate_manager_options_set_wipe_dbs(opts2, true, true);
    btck_ChainstateManager* mgr2 = btck_chainstate_manager_create(ctx2, opts2);
    /* mgr2 is non-null. */
    const btck_BlockTreeEntry* tip2 = btck_chainstate_manager_get_best_entry(mgr2);
    /* tip2 is null (undocumented). */
    int32_t h2 = btck_block_tree_entry_get_height(tip2);   /* SIGSEGV */
    printf("UNREACHABLE: %d\n", h2);
    return 0;
}
```

## Related Bitcoin Core work

| Reference | Status | Relevance |
|---|---|---|
| [PR #31439](https://github.com/bitcoin/bitcoin/pull/31439) "validation: In case of a continued reindex, only activate chain in the end" (mzumsande, merged Feb 2025) | Merged | **Direct precedent.** Bitcoin Core's `bitcoind -reindex` flow has explicit logic to *"connect the genesis block during the original -reindex"* via `ActivateBestChainState()` (gated on `ActiveHeight() == -1`). This logic lives in `node::AppInitMain` / validation, **not in `btck_chainstate_manager_create`** — which is exactly what leaves the kernel C API surface exposed. |
| [PR #24630](https://github.com/bitcoin/bitcoin/pull/24630) "index: reset indexes when running reindex-chainstate" (mzumsande, merged) | Merged | Adjacent area. Description explicitly notes the same null pattern: *"set the best block index to nullptr because we have no chain (FindForkInGlobalIndex() returns nullptr)"*. Confirms upstream is aware that `m_best_header == nullptr` is reachable post-reindex; just hasn't been addressed at the kernel API. |
| [PR #30132](https://github.com/bitcoin/bitcoin/pull/30132) "indexes: Don't wipe indexes again when continuing a prior reindex" (sedited, merged 2024) | Merged | Reverts `kernel: De-globalize fReindex`. Touches the reindex flag handling on the kernel side. |
| [Issue #24303](https://github.com/bitcoin/bitcoin/issues/24303) "The libbitcoinkernel Project" | Open tracking | Umbrella issue. Cross-reference when filing. |
| [Issue #27587](https://github.com/bitcoin/bitcoin/issues/27587) "Bitcoin Kernel Library Project Tracking" | Open tracking | Active tracking. Cross-reference when filing. |
| [Issue #33128](https://github.com/bitcoin/bitcoin/issues/33128) "*BSD, OmniOS: -reindex is broken" (hebasto, Aug 2025) | Open | Different shape (platform-specific) but signals the reindex code paths are actively buggy and under attention. |

## Proposed minimal upstream fix (low controversy, ready to PR)

The fix below is **Option B** — relax the implicit non-null contract and add null guards to the entry accessors. It is intentionally minimal:

- Pure refactor of error handling — no semantic change to the happy path.
- Matches an existing pattern in the same file (`btck_block_read` returns `nullptr` + `LogError`).
- One follow-up doc-comment update to make nullability explicit.
- Easy to add a regression test (call `get_best_entry` on a wiped manager and assert `nullptr`).

**Option A** (re-bootstrap genesis at the end of `btck_chainstate_manager_create` when wipe flags were set) is also viable and slightly nicer ergonomically, but it would have to be threaded through `node::ChainstateLoadOptions` / `LoadChainstate` and the existing reindex-aware genesis-bootstrap logic in PR #31439 — much higher review surface. Option B is the "ship today" version; Option A could follow.

### Diff against `src/kernel/bitcoinkernel.cpp`

```diff
@@ -1162,21 +1162,40 @@ btck_BlockHeader* btck_block_tree_entry_get_block_header(const btck_BlockTreeEnt
 {
+    if (!entry) {
+        LogError("btck_block_tree_entry_get_block_header called with null entry");
+        return nullptr;
+    }
     return btck_BlockHeader::create(btck_BlockTreeEntry::get(entry).GetBlockHeader());
 }

 int32_t btck_block_tree_entry_get_height(const btck_BlockTreeEntry* entry)
 {
+    if (!entry) {
+        LogError("btck_block_tree_entry_get_height called with null entry");
+        return -1;
+    }
     return btck_BlockTreeEntry::get(entry).nHeight;
 }

 const btck_BlockHash* btck_block_tree_entry_get_block_hash(const btck_BlockTreeEntry* entry)
 {
+    if (!entry) {
+        LogError("btck_block_tree_entry_get_block_hash called with null entry");
+        return nullptr;
+    }
     return btck_BlockHash::ref(btck_BlockTreeEntry::get(entry).phashBlock);
 }

 int btck_block_tree_entry_equals(const btck_BlockTreeEntry* entry1, const btck_BlockTreeEntry* entry2)
 {
+    if (!entry1 || !entry2) {
+        LogError("btck_block_tree_entry_equals called with null entry");
+        return 0;
+    }
     return &btck_BlockTreeEntry::get(entry1) == &btck_BlockTreeEntry::get(entry2);
 }
```

`btck_block_tree_entry_get_previous` already null-checks the input via `btck_BlockTreeEntry::get(entry).pprev`, but should be hardened identically:

```diff
 const btck_BlockTreeEntry* btck_block_tree_entry_get_previous(const btck_BlockTreeEntry* entry)
 {
+    if (!entry) {
+        LogError("btck_block_tree_entry_get_previous called with null entry");
+        return nullptr;
+    }
     if (!btck_BlockTreeEntry::get(entry).pprev) {
         LogInfo("Genesis block has no previous.");
         return nullptr;
     }
     return btck_BlockTreeEntry::ref(btck_BlockTreeEntry::get(entry).pprev);
 }
```

### Diff against `src/kernel/include/bitcoinkernel.h`

```diff
@@ -1105,9 +1105,13 @@
 /**
  * @brief Get the btck_BlockTreeEntry whose associated btck_BlockHeader has the most
  * known cumulative proof of work.
  *
  * @param[in] chainstate_manager Non-null.
- * @return                       The btck_BlockTreeEntry.
+ * @return                       The btck_BlockTreeEntry, or null if the
+ *                               chainstate manager has no best header
+ *                               (e.g., immediately after construction
+ *                               with both wipe flags set, before any
+ *                               block has been processed).
  */
```

The accessor doc comments (`btck_block_tree_entry_get_height` etc.) should similarly note that they accept null and return `-1` / `nullptr` in that case.

### Suggested regression test

In `src/test/kernel_tests.cpp` (or wherever the kernel C-API tests live):

```cpp
BOOST_AUTO_TEST_CASE(get_best_entry_returns_null_after_full_wipe)
{
    /* Open, populate, close. */
    /* Reopen with set_wipe_dbs(true, true). */
    /* Assert btck_chainstate_manager_get_best_entry returns nullptr. */
    /* Assert each accessor returns its sentinel without crashing. */
}
```

## Adjacent investigation (rejected hypotheses)

While triaging this, two follow-on hypotheses were tested and **rejected**:

| Hypothesis | Reproducer | Result |
|---|---|---|
| libbitcoinkernel has bitcoind-style process-global state breaking repeated lifecycle cycles | `Tests/BitcoinKernelTests/UpstreamConcernsTests.swift::repeatedKernelLifecycle` | **PASSES** — no global-state bug |
| `ChainstateManager.deinit` aborts when the data directory has been removed while the manager is alive | `Tests/BitcoinKernelTests/UpstreamConcernsTests.swift::managerDeinitAfterDirRemoved` | **PASSES** — kernel deinit is graceful |

## Local fix in swift-bitcoinkernel (applied — independent of upstream)

`Sources/libbitcoinkernel/include/libbitcoinkernel.apinotes` (a swift-bitcoinkernel-local
file, not part of upstream Bitcoin Core) **previously** annotated the function as
`_Nonnull`, which let the Swift importer generate a non-failable Swift signature
for a function that could return null.

**Applied 2026-05-03:**

1. Annotation flipped to `_Nullable` in `Sources/libbitcoinkernel/include/libbitcoinkernel.apinotes:432`.
2. `ChainstateManager.bestEntry` in `Sources/BitcoinKernel/Chainstate/ChainstateManager.swift:44-67` now `guard let`-unwraps the C result and calls `preconditionFailure` with a diagnostic message (pointing here) when the upstream null path is hit. This converts the SIGSEGV into a Swift fatal error that shows up properly in crash reports and points the next reader at this file.

Forward compatibility:

- If upstream ships **Option A** (re-bootstrap genesis on construction), the trap is unreachable from any well-formed call sequence and the local fix is simply dormant.
- If upstream ships **Option B** (relax contract + null-guard accessors), we may later upgrade `bestEntry` to a true `Optional<BlockTreeEntry>` and surface the nil case as a typed result. The annotation flip is already correct for that path.

`KernelAppViewModel.requestReindex(.full)` remains gated by a stub-throwing factory in unit tests so the trap is not exercised in CI. Production callers that hit `.full` reindex will trap with the diagnostic message above; Phase B3 will add a UI confirmation gate to make `.full` reindex an explicit, dangerous user action.

## Bitcoin Core PR Process Checklist

Per [CONTRIBUTING.md](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md):

- [ ] Reproduce against current `bitcoin/bitcoin@master` (we observed against the vendored copy)
- [ ] Search existing issues for `get_best_entry null`, `chainstate wipe`, `m_best_header nullptr kernel`
- [ ] Cross-reference [#24303](https://github.com/bitcoin/bitcoin/issues/24303) (libbitcoinkernel project) and [#27587](https://github.com/bitcoin/bitcoin/issues/27587) (kernel tracking)
- [ ] File as **issue first** since the fix shape needs Bitcoin Core's choice between Option A and Option B above
- [ ] Include the C reproducer, the matrix table, and the stack trace
- [ ] Mention discovery context (Swift wrapper, embedded mobile use case)
- [ ] No `@` mentions in the issue body

## Labels to Request

- `Bug`
- `Crash`
- `Kernel`
