# Upstreaming campaign — bitcoin/bitcoin

The plan for *how and in what order* to file the patches in `patches/bitcoin/`. The per-patch `.md` files hold the diffs and per-PR detail; this doc is the authority on sequencing and framing, and **supersedes the "strategy / PR 1 of 2" sections in the individual `.md` drafts where they conflict** (those predate the verification below).

Issue states and the master-source novelty checks were verified **2026-06-14** (see `README.md` § "Cited upstream issues" for the register).

## Situation

All four PR-shaped patches are still needed on current `bitcoin/bitcoin` master (verified by reading master):

| Patch | Still novel on master? | Evidence |
|-------|------------------------|----------|
| netif iOS guard | Yes | `src/common/netif.cpp` still uses bare `#elif defined(__APPLE__)` around `<net/route.h>`/`<sys/sysctl.h>`; no `TARGET_OS_OSX`. |
| MAIN_FUNCTION guard | Yes | `src/compat/compat.h` still `#define`s `MAIN_FUNCTION` with no `#ifndef` guard. |
| rpc once_flag removal | Yes | `src/rpc/server.cpp` still has `std::once_flag`/`call_once` in `InterruptRPC`/`StopRPC` (4 occurrences). |
| shutdown resets | Yes | `src/init.cpp` still leaks the four process-globals across a second `bitcoind_main()`. |

**The two issues the original drafts leaned on are closed — the framing must change:**
- **#11720** ("iOS Deployment Target for RPC") closed (completed) 2023-04-27. Do **not** frame anything as "completing" or "closing" it. Anchor on the still-open kernel tracker **#27587** instead.
- **#31289** (the `StopRPC()` startup-assert race) closed (completed) 2024-11-20 with **no fixing commit** — the race still reproduces on master. Do **not** write "Fixes #31289"; file the rpc fix fresh and reference #31289 as the historical report.

**Citations that hold (merged):** **#35141** (node-context reset pattern for fuzz — upstream's own in-process-reinit need) and **#18702** (introduced `MAIN_FUNCTION`). Closed-unmerged PRs **#27711 / #31382 / #12557** may be cited only as "same direction," never as precedent.

**Local evidence the restart path works:** `Tests/BitcoinTests/DaemonSoakTests.swift` runs 5 in-process `start → bootstrap → stop → waitUntilStopped` cycles cleanly (passes in ~1.8s with rpc-server-reset + shutdown-reset applied). This is the concrete demonstration UP-3 needs.

## Filing order

1. **netif guard** (UP-1) — smallest, behavior-preserving, no issue needed. Builds the track record.
2. **MAIN_FUNCTION guard** (UP-4) — 2-line guard; file after the umbrella issue exists to point at.
3. **Umbrella issue** (off #27587, draft below) — frames the embedding need; anchors UP-4/UP-6.
4. **rpc once_flag removal** (UP-2) — fresh `rpc:` PR fixing the race.
5. **shutdown resets** (UP-3) — issue-first (concept ACK before a PR); cite #35141 + the soak evidence.

Follow the org playbook in `README.md` § "Upstreaming playbook" (repro branch on `21-DOT-DEV/bitcoin`, smallest viable PR, `Assisted-by:` disclosure, no `@`-mentions, DrahtBot self-labels).

## Umbrella issue (draft — anchor on #27587, not #11720)

> **Title:** `build: residual source gaps for building bitcoind/libbitcoinkernel on Apple non-macOS platforms`
>
> **Summary.** The kernel-library direction (#24303, tracked in #27587) makes "Bitcoin Core components inside an external app" a supported use, with working proofs of concept on iPhone: `Sjors/kernel-i-node` (signet blocks from an HTTP source validated by libbitcoinkernel) and a pure-SwiftPM build of `bitcoind` + `libbitcoinkernel` running on iOS/macOS. A small, bounded set of source changes is all that still stands between master and those builds. Each is a separate, behavior-preserving PR:
>
> 1. **`src/common/netif.cpp`** — `<net/route.h>`/`<sys/sysctl.h>` are absent from the iOS SDK; narrow the `__APPLE__` guards to `__APPLE__ && TARGET_OS_OSX` (PR: ⟨UP-1 link⟩). Falls through to the existing unsupported-platform `std::nullopt` path.
> 2. **`src/compat/compat.h`** — the host app owns `main()`; an `#ifndef` guard around `MAIN_FUNCTION` lets a build system rename the entry point (PR: ⟨UP-4 link⟩).
> 3. **Build-config introspection for iOS** — `HAVE_SYSTEM` off and the randomness probes `TARGET_OS_OSX`-aware when targeting non-macOS Apple platforms (⟨UP-6⟩).
> 4. **Process-global re-initialization** — on mobile, stop → reconfigure → start within one host process is the normal lifecycle; four globals currently assert on the second `bitcoind_main()` (tracked separately with a repro branch: ⟨UP-3 issue link⟩; also benefits in-process fuzz re-init, cf. #35141).
>
> **Explicitly not requested:** iOS CI, an Apple app in this repo, App Store anything, or packaging changes — downstream projects own all of that and provide continuous external build coverage for these paths.
>
> *(This does not ask to reopen or close #11720; it scopes the residual build-system work the kernel direction implies. Disclose AI assistance per the #35304 precedent if applicable.)*

## Per-PR notes

**UP-1 netif — direct PR.** Title `net: guard macOS-only route headers for iOS build compatibility`. Rebase the `.patch` onto master (hunk line numbers differ; the change is the two `__APPLE__ → __APPLE__ && TARGET_OS_OSX` narrowings plus the `<TargetConditionals.h>` include). Drop advocacy ("increasingly relevant as mobile apps mature"); state the bare facts. Pre-empt "no iOS CI": no upstream CI change is requested, the guard is inert everywhere upstream builds, and downstream `apple-builds.yml` exercises the iOS path continuously.

**UP-4 MAIN_FUNCTION — small PR.** Title `compat: allow overriding MAIN_FUNCTION via the build system`. Keep it to the 2-line `#ifndef` guard. Tie to the umbrella issue (one link), not #11720. Let maintainers decide whether a first-class CMake switch is wanted — raise that in the umbrella issue, not this PR.

**UP-2 rpc once_flag — fresh PR (not "Fixes #31289").** Title `rpc: remove std::once_flag from InterruptRPC/StopRPC`. Lead with the bug: the once_flag in `InterruptRPC()` can be consumed before `StartRPC()` sets `g_rpc_running`, so `StopRPC()`'s `assert(!g_rpc_running)` can fire — the race reported (and still unfixed) in #31289, which still reproduces on master. Both functions are naturally idempotent without the flag; add a regression test driving `InterruptRPC(); StartRPC(); InterruptRPC(); StopRPC();`. **Do not** include `ResetRPC()` here — it has no in-tree caller until UP-3, and "new API, zero callers" is a standard NACK; it lands with its caller in UP-3. Document the one observable change: `InterruptRPC()` before `StartRPC()` now early-returns silently instead of logging and burning the flag.

**UP-3 shutdown resets — issue first.** Cite **#35141** prominently (upstream's own node-context-reset-for-fuzz need) and link the soak repro branch. Open questions for maintainers: reset at the end of `Shutdown()` vs. lazily at the next `InitContext()` (the latter provably can't affect single-run behavior); and the logger reset should be a properly-named `BCLog::Logger` method, not `DisconnectTestLogger()` called from production. The applied source resets **four** globals (`g_shutdown`, `gArgs`, `ResetRPC`, logger) — `shutdown-reset.md` is already corrected to say four. Evidence: `DaemonSoakTests` (5 clean in-process restart cycles) shows the end state once these land.

## Complementary CI (optional, PKG-4)

A CI job that builds and runs upstream `test_kernel` against the SPM-built `libbitcoinkernel` (with the same defines the targets use) would back the "no behavior change" claim each PR makes and catch subtree/flag drift. Not required to file, but strengthens every UP narrative; start macOS-only.

## Filing checklist (per PR)

- [ ] Repro/regression branch on `21-DOT-DEV/bitcoin` (per the #35293 → #35304 playbook).
- [ ] Rebase the `.patch` onto current master; `git apply --check` clean.
- [ ] PR title uses the area prefix; commit message imperative, no `@`-mentions.
- [ ] `Assisted-by:` trailer if AI-assisted (per the #35304 precedent).
- [ ] On merge: delete the local `.patch` + `.md` and move the Status row in `README.md` to "dropped".
