# Upstreaming plan — bitcoin/bitcoin

How we contribute the patches in [`bitcoin/`](bitcoin/) back to Bitcoin Core: what to work on first, what depends on what, and the rules every filing follows. Everything specific to a single patch — what its PR must say, which threads it cites — lives on that patch's card, at the top of the patch's own file.

House rule for this folder: every file must read cold. Plain words, short sentences, and a one-phrase explanation the first time any project term or issue number appears.

Issue states and every "still needed?" check were last verified **2026-07-02** against Bitcoin Core's development branch (`master`). All five `.patch` files were verified to apply cleanly to the vendored v31.0 tree (`Vendor/bitcoin`, per `subtree.yaml`) on **2026-07-17**. Re-verify all of this before filing anything.

## The pipeline

Five patches, one discussion thread, six filings. Three patches stand alone; the restart work is sequenced. Nothing in the first group blocks on anything.

**File anytime, in any order, one at a time — no thread needed:**

1. [Compile the network-interface file on iPhone-family SDKs](bitcoin/ios-netif-guard.md) — the same one-line `__has_include` change at two guard sites. Smallest first: it builds the track record.
2. [Stop the late-log crash during teardown](bitcoin/logging-teardown-assertion.md) — a one-line fix to a code path Bitcoin Core's own test framework runs on every teardown.
3. [Let the host app own `main()`](bitcoin/main-function-guard.md) — a two-line macro guard.

**The restart work — in this order:**

4. **Open the discussion thread** (pre-written text below). It states the problem — the node cannot restart inside one process — and asks maintainers to approve the approach before any code arrives.
5. [Make the RPC server restartable](bitcoin/rpc-server-reset.md) — a pull request that fixes a real, still-reproducing startup crash and can be judged on that alone; it links the thread only as context. Merging it also unlocks step 6, which needs `InterruptRPC()`/`StopRPC()` to be callable again in a second lifecycle. (The small `ResetRPC()` helper ships upstream with its caller in step 6, not here.)
6. [Reset four globals at shutdown](bitcoin/shutdown-reset.md) — the restart patch itself. Wait for approval on the thread (a "concept ACK": a maintainer thumbs-up on the idea), then open the pull request. It closes the thread.

**Optional, independent, low priority:**

- A short build-documentation PR recording the working iOS build command for the kernel library — the [CMake memo](bitcoin/cmake-ios-library-build.md) holds the command and the reasoning. File only if activity on #27587 (Bitcoin Core's kernel-library tracking issue) suggests appetite; the memo is a sufficient record otherwise.
- A CI job in this repo (not upstream) that runs Bitcoin Core's own kernel test binary against our build of the library, backing the "no behavior change" claim every filing makes.

## The discussion thread (pre-written)

Post as a new issue on `bitcoin/bitcoin`. Fill each ⟨placeholder⟩ when the thing it names exists. This text is the single home of the campaign's argument; the patch cards only add per-PR detail.

> **Title:** `process: bitcoind cannot restart within one process (four globals assert on a second bitcoind_main())`
>
> **Summary.** The kernel-library direction (#24303, tracked in #27587) makes "Bitcoin Core components inside an external app" a supported use, with working proofs on Apple platforms: Sjors/kernel-i-node (libbitcoinkernel validating signet blocks inside an iOS/macOS app, announced on #27587) and a pure-SwiftPM embedding of `bitcoind` + `libbitcoinkernel` in iOS/macOS apps with continuous external build coverage. This continues what #11720 explored before its "Superceded by kernel" close. For an embedded daemon the host app owns the process lifecycle: stop → reconfigure → start without relaunching is the normal cycle. Today four process-globals survive `Shutdown()` and assert on a second `bitcoind_main()` call: `g_shutdown`, `gArgs`, `LogInstance().m_buffering`, `fRPCInWarmup`.
>
> In-process resettability is also a property the fuzz suite already enforces per iteration: `CheckGlobals` aborts targets that leak PRNG or time state (#31486, #31549); stale cross-iteration node-context state produced real coverage bugs, fixed by per-iteration reset-and-reinstall (#34302, #35141); stability/determinism is tracked in #29018. The test framework likewise resets the logger and args between in-process lifecycles (`setup_common.cpp`), so production `Shutdown()` is the one lifecycle path without resets.
>
> The fix is two bounded, behavior-preserving PRs:
>
> 1. **`src/rpc/server.cpp`** — remove the permanently one-shot `std::once_flag`s from `InterruptRPC()`/`StopRPC()` (both bodies are naturally idempotent; also removes the still-reproducible #31289 race). Continues #19111's direction for these flags. (PR: ⟨link to the RPC pull request⟩)
> 2. **`src/init.cpp`** — reset the four process-globals at the end of `Shutdown()`, mirroring what `BasicTestingSetup` teardown already does. Repro branch with 5 clean in-process restart cycles: ⟨link to the repro branch⟩. (PR follows concept ACK here: ⟨link to the shutdown pull request⟩)
>
> **Open question:** reset at the end of `Shutdown()` (symmetric with the rest of its cleanup) or lazily at the next `InitContext()` (provably no effect on single-run behavior)? Either resolves the asserts; happy to implement whichever reviewers prefer. Relatedly, the logger reset deserves a properly named `BCLog::Logger` method rather than production code calling `DisconnectTestLogger()`.
>
> Two adjacent build-compat guards (the `MAIN_FUNCTION` override, ⟨link to that pull request⟩; the `net/route.h` guard for non-macOS Apple SDKs, ⟨link to that pull request⟩) round out the embedded-daemon path but stand alone and are not part of this issue.
>
> Process separation (#28722) does not reach this use case: `bitcoin-node` hosts the same process-globals, and the embedding platforms above cannot spawn helper processes, so in-process restart is their only lifecycle.
>
> **Explicitly not requested:** iOS CI, an Apple app in this repo, App Store anything, packaging changes, or new fuzz targets — whether a lifecycle-cycling fuzz target is worth having is a separate question these changes merely make possible. Downstream projects own packaging and provide continuous external build coverage for these paths. (For context, the kernel library itself already builds for iOS from stock CMake with no source changes — demonstrated against master by Sjors/kernel-i-node and reproduced on v31 — so nothing iOS-specific is requested in this issue at all; the `net/route.h` guard is a standalone PR.)
>
> *(This does not ask to reopen or close #11720; it scopes the in-process work the kernel direction implies. Disclose AI assistance per the #35304 precedent if applicable.)*

## Platform reach

The three restart patches and the `main()` guard are OS-agnostic: they matter wherever bitcoind is embedded inside a host process, on any OS Bitcoin Core supports. Only the netif guard is Apple-specific, and its virtue upstream is being inert everywhere else.

| Platform | Restart trio | `main()` guard | netif guard | Tested? |
|---|---|---|---|---|
| Linux | Benefits | Benefits | Inert (netlink branch) | Partly — the default suite (one in-process daemon lifecycle per run) runs in the Linux container CI (`docker-builds.yml`); the restart soak test is opt-in (`RUN_SOAK_TESTS=1`) and not run in CI anywhere yet. |
| Android | Benefits (a JNI-embedded node has the same lifecycle) | Benefits | Inert (netlink) | Not set up. Stock CMake supports `-DCMAKE_SYSTEM_NAME=Android` with an NDK — the same recipe as the [iOS CMake memo](bitcoin/cmake-ios-library-build.md). |
| Windows | Benefits | Benefits — the macro originated as a Windows fix (#18702) | Inert (iphlpapi branch) | Not from this repo. |
| FreeBSD / OpenBSD | Benefits | Benefits | Inert | Not tested; low priority. |
| macOS / iOS | Tested | Tested | Tested | CI on every commit. |
| tvOS / visionOS | Compile-proven only | Compile-proven | Compile-proven ([receipts](bitcoin/ios-netif-guard.md)) | tvOS end-to-end is blocked ([memo](bitcoin/tvos-execvp-feasibility.md)); the visionOS simulator is the nearest untried Apple target. |

Two upgrades worth making before the thread opens: run the opt-in soak test in the Linux container so the restart story has a non-Apple existence proof (a scheduled or secondary CI lane, mirroring the repo's existing `RUN_EXIT_TESTS` opt-in pattern, would keep that claim continuously true — soak tests belong out of the per-commit path); and an Android compile proof (an afternoon with the NDK, mirroring the iOS memo) to widen the demand story to the other mobile platform.

## Cited threads

One row per Bitcoin Core issue or pull request our cards and the thread draft cite. States last verified 2026-07-02; re-check before filing anything that references them.

| Thread | State | What it is, and why we cite it |
|--------|-------|--------------------------------|
| [#31289](https://github.com/bitcoin/bitcoin/issues/31289) | Closed 2024-11-20, no fix landed | The startup crash the RPC patch removes. Still reproduces on master; cite as the historical report, never as "Fixes". |
| [#19111](https://github.com/bitcoin/bitcoin/pull/19111) | Merged 2020-06-02 | Narrowed the same one-shot locks once before; precedent for the RPC patch. |
| [#18452](https://github.com/bitcoin/bitcoin/pull/18452) | Merged 2020-05-29 | Added the double-call path those locks guard against; background for the RPC patch. |
| [#34302](https://github.com/bitcoin/bitcoin/pull/34302) | Merged 2026-01-20 | Their fuzz targets now reset node state between in-process iterations; precedent for the shutdown patch. |
| [#35141](https://github.com/bitcoin/bitcoin/pull/35141) | Merged 2026-05-23 | Extends #34302's reset pattern; shows it is the accepted idiom. |
| [#31486](https://github.com/bitcoin/bitcoin/pull/31486) | Merged 2024-12-17 | Fuzz harness aborts on leaked random-number state; the enforced no-leftover-globals rule. |
| [#31549](https://github.com/bitcoin/bitcoin/pull/31549) | Merged 2025-01-10 | Same rule for leaked system-time use. |
| [#29018](https://github.com/bitcoin/bitcoin/issues/29018) | Open | Their tracker for fuzz stability and leftover global state; the problem class two of our patches live in. |
| [#30537](https://github.com/bitcoin/bitcoin/pull/30537) | Merged 2024-07-31 | Kernel already tolerates repeated contexts in one process; supports the restart story. |
| [#18702](https://github.com/bitcoin/bitcoin/pull/18702) | Merged 2020-04-22 | Origin of the `MAIN_FUNCTION` macro (a Windows security fix); lineage for the entry-point patch. |
| [#25251](https://github.com/bitcoin/bitcoin/pull/25251) | Merged 2022-06-13 | Consolidated that macro into `compat.h`; second half of the lineage. |
| [#24303](https://github.com/bitcoin/bitcoin/issues/24303) | Closed 2023-05-10 | The original kernel-library project issue; background for "embedding is a supported direction". |
| [#27587](https://github.com/bitcoin/bitcoin/issues/27587) | Open | The living kernel-library tracker; the thread draft anchors here. |
| [#11720](https://github.com/bitcoin/bitcoin/issues/11720) | Closed 2023-04-27 | The historical iOS thread, closed "Superceded by kernel"; cite as lineage only. |
| [#21208](https://github.com/bitcoin/bitcoin/issues/21208) | Closed 2021-02-17 | A second "iOS build support" ask, closed as a duplicate of #11720; cited as evidence that platform-support framing gets closed on sight. |
| [#29450](https://github.com/bitcoin/bitcoin/pull/29450) | Merged 2025-10-24 | Replaced the custom `MAC_OSX` macro with the standard `__APPLE__`; precedent for choosing the standard mechanism, and the source of the "didn't we just remove the macOS distinction?" objection the netif card answers. |
| [#29834](https://github.com/bitcoin/bitcoin/pull/29834) | Merged 2025-05-11 | First step of the `MAC_OSX` removal (crypto directory); also the one-sentence-description example for compat PRs. |
| [#35659](https://github.com/bitcoin/bitcoin/pull/35659) | Merged 2026-07-13 | Dropped outdated *BSD workarounds in `netif.cpp`; moved the netif guard sites on master to lines 21/220, so the netif patch rebases with context drift. |
| [#30043](https://github.com/bitcoin/bitcoin/pull/30043) | Merged 2024-09-30 | Created `netif.cpp` with an availability gate inside its FreeBSD branch and the dummy-implementation fallback — the file's founding design precedent for the netif patch. |
| [#32405](https://github.com/bitcoin/bitcoin/pull/32405) | Merged 2025-05-05 | Replaced configure header probes with `__has_include` in `randomenv.cpp` and `threadnames.cpp`; mechanism precedent (a different transformation — concede that if raised). |
| [#9921](https://github.com/bitcoin/bitcoin/pull/9921) | Merged 2017-03-16 | Probed `MSG_DONTWAIT` "in the same way as `MSG_NOSIGNAL`"; part of the platform-facility-availability family the netif compound guard belongs to. |
| [#35658](https://github.com/bitcoin/bitcoin/pull/35658) | Merged 2026-07-06 | Maintainer include-hygiene PR in `netif.cpp`; the description style model (mechanical claims, no failure narrative, unsupported platform as reference only) and evidence the file is actively groomed. |
| [#34995](https://github.com/bitcoin/bitcoin/pull/34995) | Open | Include-what-you-use enforcement for `src/common/`; filing watchpoint — if it merges first, re-run the apply-check and rebase. |
| [#33435](https://github.com/bitcoin/bitcoin/pull/33435) | Merged 2025-09-22 | Merged PR whose prose uses "unsupported platforms" verbatim; vocabulary precedent for the netif description. |
| [#12557](https://github.com/bitcoin/bitcoin/pull/12557) | Closed unmerged 2020-04-23 | The old cross-compile-for-iOS attempt; same direction, never precedent. |
| [#27711](https://github.com/bitcoin/bitcoin/pull/27711) | Closed unmerged 2023-07-08 | Tried removing shutdown globals from the kernel; same direction, never precedent. |
| [#31382](https://github.com/bitcoin/bitcoin/pull/31382) | Closed unmerged 2026-02-20 | Tried automatic flush-on-destroy cleanup; same direction, never precedent. |
| [#28722](https://github.com/bitcoin/bitcoin/issues/28722) | Open | Multiprocess tracking issue. Process separation is additive — monolithic binaries remain the default — and cannot replace in-process restart on platforms that cannot spawn processes. |

## Rules for every filing

Distilled from Bitcoin Core's [CONTRIBUTING.md](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md), its [AI policy](https://github.com/bitcoin/bitcoin/blob/master/doc/AI_POLICY.md), and community practice ([Atack's guide](https://jonatack.github.io/articles/how-to-contribute-pull-requests-to-bitcoin-core)). The AI policy is binding, not advisory.

**Before opening anything:**

1. Follow the AI policy. These files are research and drafting aids — the PR body and every reviewer reply must be written by the human filer, in their own words, and the filer must be able to explain every change unaided. Doubt about author understanding is grounds for immediate closure, and PRs must not be opened or driven by autonomous agents. Quoting an AI interaction requires disclosure plus your own commentary. Our merged #35304 also carried an `Assisted-by:` commit trailer; keep doing that when it applies.
2. Give review before asking for it, and keep giving it while waiting. The common rule of thumb is 5–15 reviews of other people's PRs per PR you open, and CONTRIBUTING's own advice for a stalled PR is "give review to others".
3. Check the release schedule (pinned in the repo's issues). Filings during feature freeze — the pre-release window when only critical fixes land — wait until after the release.
4. Build a reproducible branch on `21-DOT-DEV/bitcoin` (our public fork) demonstrating the bug or capability first. This is the path that worked for our one accepted fix (#35293, the report → #35304, the merged fix).
5. Two trees matter, so check both. The local `.patch` must apply cleanly to the pristine vendored tree — `git apply --check --directory=Vendor/bitcoin patches/bitcoin/<name>.patch` (v31.0, per `subtree.yaml`) — and any line numbers quoted in a patch's write-up refer to that tree unless labeled otherwise. The upstream PR targets `master`: re-verify the patch is still needed there, rebase, and run CI on the fork before opening.

**Writing the commits and the PR:**

6. Smallest possible PR; the fix before any refactor. A PR merges when its improvement outweighs the review effort it asks for — say so where it is plainly true (the three standalone guards are one-minute reviews).
7. Every commit compiles and passes tests on its own. Subject line at most 50 characters, starting with the area prefix (`rpc:`, `init:`, `net:`, `logging:`, `compat:`); then a blank line and a body that explains why, written in the imperative mood. Each card's PR title doubles as the commit subject, so it obeys the same cap.
8. A bug-fix PR carries a test that demonstrates the bug and proves the fix whenever possible, and the description says how to test the change. If a test is impractical, say so and explain why.
9. No `@`-mentions anywhere — they get copied into git history and spam notifications; ping people in follow-up comments instead. The project bot (DrahtBot) assigns labels; do not request them.

**While a PR is open:**

10. Squash fixup commits proactively. After any rebase or force-push, post the `git range-diff` output so reviewers can re-confirm their earlier review cheaply. Every push and comment notifies everyone subscribed, so batch them.
11. Waiting is normal; spend it reviewing others' PRs. Do not open the next filing while the current one is active — land it, or let it clearly stall, first.

**After a merge:**

12. Delete the patch's `.md` and `.patch` here and update its entry in [`README.md`](README.md).
