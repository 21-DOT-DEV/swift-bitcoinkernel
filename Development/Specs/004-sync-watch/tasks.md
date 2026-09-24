# Tasks — 004 · The long-running action watches the node sync toward the tip

Ordered work for [the plan](./plan.md); requirements cited as `FR-NNN` from
[spec.md](./spec.md); rationale in [research.md](./research.md).

Format: `- [ ] TNNN [P?] description · file`. `[P]` marks a task independent of
its wave-mates (different files, no incomplete dependency). `⟶ wait` lines are
dependency joins. Each phase closes on a verifiable checkpoint. Task order is
dependency order, not schedule — a `[P]` test task is written and seen failing
before the wave-mates it covers (the constitution's red → green rule); each
checkpoint asserts that. A trailing `(FR-NNN)` cites the requirements a task
serves — enabling work cites nothing — and a test task declares which of them
its tests exercise as `verifies FR-NNN`; the index's coverage map counts only
those. One checkbox, one completable unit: work landing in different pull
requests is different tasks.

## Phase 0 — Prerequisite (own commit, ahead of the feature)

- [ ] T001 Snapshot the settings the run reasons about, once, at entry —
  every key `buildArguments` consults (`bitcoin_network`, `node_type`,
  `tor_enabled`, `private_broadcast_enabled`, `listen_enabled`, `rpc_auth`,
  the resource figures), not `privacyEnabled` alone: the ~90 s grace widens a
  millisecond race into a 90-second one across all of them, and a mid-grace
  chain flip starts a network the run never weighed — live ADR 0006 hole,
  reviewable on its own (`rpc_auth` is the weakest of the set — the session's
  questions authenticate by `.cookie`, never the `-rpcauth` creds, so its
  consequence is a launched config nobody reasoned about, not a failed
  question); the same commit stops the start-failure path resurrecting a
  just-disabled Tor ·
  `Sources/NodeApp/DaemonConfig.swift`, `NodeRun.swift`, `NodeSession.swift`
- [ ] T027 `IntentDialog` built from a `LocalizedStringResource` template
  interpolating the report's values — `IntentDialog(stringLiteral:
  report.summary)` ships a runtime `String` with no extractable key in both
  intents; the same commit rips out the hand-rolled `block\(s)` ternary in
  the summary builder — plural variants belong to the catalog, not a suffix —
  a bug fix on the already-shipped short action, reviewable on its
  own, and the decision that fixes the shape T009's summary sentences are
  written in · `Sources/NodeApp/SyncNodeIntent.swift`,
  `SyncNodeLongRunningIntent.swift`, `NodeAutomation.swift`
- [ ] T028 `persistLastKnown` moves out of `measuredReport` — today the write
  runs *before* the last `answerIsStillWanted` guard, so a run cancelled or
  node-stopped in that window advances the baseline while reporting nothing,
  and the .timeout discard would drop a watched run's whole span of gains;
  the report carries the last-known height+chain and each intent persists it
  only on the path that returns `.result(value:)` — a shipped bug on the
  short action, not just a 004 shape ·
  `Sources/NodeApp/NodeRun.swift`, `SyncNodeIntent.swift`,
  `SyncNodeLongRunningIntent.swift`

**Checkpoint:** a settings toggle landing mid-run cannot re-scope what this
run launches; the shipped dialog's text is extractable; each diff ships
standalone.

## Phase 1 — Report surface

- [ ] T002 `NodeSyncResult` `AppEnum` — the FR-005 case set including
  `notMeasured`, explicit raw strings · `Sources/NodeApp/NodeRunReport.swift`
- [ ] T003 `syncResult` + `blocksGainedThisRun` `@Property`s on `NodeRunReport`
  — non-optional `AppEnum`, no conformance gamble; the same commit renames
  the existing `NodeAutomation.blocksGained(from:to:)` helper to
  `blocksSince(previous:to:)` — `measuredReport` stores its result in
  `blocksSinceLastCheck`, so the file must not hold two names meaning
  different baselines, and the property name is the shipped contract where
  the collision costs the most (FR-005, FR-016) ·
  `Sources/NodeApp/NodeRunReport.swift`, `NodeAutomation.swift`
- [ ] T004 [P] String-pinning and wording-completeness tests — every case has
  display wording; the `notMeasured` rules and `blocksGainedThisRun` presence
  — plus a test asserting the two baselines differ (`blocksSinceLastCheck`
  spans the pre-run gap, `blocksGainedThisRun` only what this run watched;
  titles disambiguate in the Shortcuts UI) (verifies FR-005, FR-016) ·
  `Sources/NodeAppTests/NodeRunReportTests.swift`

**Checkpoint:** report carries the second axis (`syncResult`) and
`blocksGainedThisRun`; the new tests were seen failing before the code they
cover.

## Phase 2 — Decision functions (`NodeAutomation`, pure and tested)

All independent of each other inside the file — one wave:

- [ ] T005 `LiveReading` gains `isInitialBlockDownload`, `headers`, and
  `tipTime` — `blocksBehind` already carries the gap, and `info.time` is
  already modeled; the peer answer rides beside it as its own value — a
  `PeerEvidence` per peer carrying `syncedHeaders` and the resolved
  `connectionType` (the field, falling back to the `inbound` boolean —
  unresolved outbound fails closed), not folded into the reading ·
  `Sources/NodeApp/NodeAutomation.swift`
- [ ] T006 `SyncWatchState` value type — baseline, best-seen heights, the
  headers-advanced latch, both accumulators, entry Low-Power snapshot —
  advanced by `(instant, reading?)`, emitting ending decisions ·
  `Sources/NodeApp/NodeAutomation.swift`
- [ ] T007 Decisions: watch-entry gate — IBD flag, open gap, or tip older than
  `tipFreshnessThreshold` (~60 min) against an injected wall-clock `now`;
  regtest never enters (FR-001, FR-015) — the `caughtUp` proof — flag cleared
  *and* `blocks == headers` *and* (headers advanced this run, tip inside the
  threshold, or — on a flat pass whose flag is clear, gap closed, and headers
  never advanced — at least `peerConfirmationsRequired` (2)
  `outbound-full-relay`/`block-relay-only` peers reporting
  `synced_headers == headers`), the node's own verdict (FR-006) — leashes
  (FR-007), live-tip fraction (FR-002)
- [ ] T008 Conditions decisions: one-time `refusal(for:)` weigh-in on
  preflight-skipped paths (`DeviceConditions` gains honest `thermalState`),
  per-pass split — money absolute, thermal `.critical`, Low-Power delta —
  returning the *condition* not a sentence; the weigh-in's network read is
  `first()` bounded ~2 s — `current` fails open on a cold launch — while the
  per-pass drift read uses `current` (FR-010, FR-011, FR-012) ·
  `Sources/NodeApp/NodeAutomation.swift`, `NodePreflight.swift`
- [ ] T009 Stage→band card-fraction map + summary/ending sentences for the five
  endings — every count-bearing sentence authored plural-aware (templates
  shaped for String Catalog variants or automatic grammar agreement, never a
  hand-suffixed `s`), and durations via `Duration.formatted` /
  `RelativeDateTimeFormatter`, never a hand-built "min ago" — T022's catalog
  lands after these sentences exist · `Sources/NodeApp/NodeAutomation.swift`
- [ ] T010 [P] Unit tests for every decision function — flat/advancing/absent
  readings, the `caughtUp` proof's three legs, leashes, drift
  matrix, the ending-precedence order, the warm-restart gate — an aged tip
  enters with flag clear and no gap, a fresh one does not; and the
  peer-confirmation leg — a qualifying flat pass (flag clear, gap closed,
  headers never advanced) with two outbound confirmations ends `caughtUp`,
  while one, inbound-only, an unresolved type, or a timed-out answer leaves
  the pass to the leashes and ends `noProgress`, with the peer answer never
  resetting a leash (verifies FR-001, FR-002, FR-006,
  FR-007, FR-010, FR-011, FR-012, FR-015, FR-019) ·
  `Sources/NodeAppTests/NodeAutomationTests.swift`

**Checkpoint:** every watch decision is a tested pure function — tests seen
failing before the functions they cover; no `NodeRun` code touched yet.

## Phase 3 — Orchestration (`NodeRun`)

- [ ] T011 Private-network grace: deadline-bounded poll in `NodeRun`'s own loop
  shape (never `withHardTimeout` around `waitUntilReady`), post-grace
  re-decision of node state + conditions + step (FR-013) ·
  `Sources/NodeApp/NodeRun.swift`
- [ ] T012 Watch stage: chain question every ~5 s bounded at
  `min(watchQuestionBudget, remaining)` — and the same bound covers
  `awaitFirstAnswer` on budgeted runs (the short action keeps
  `questionBudget`, or a slow-but-alive ~11 s node never reaches the watch);
  on every qualifying flat pass a `getpeerinfo` rides the same bound for the
  confirmation count — an absent answer is no evidence and the pass falls
  through to the leashes; each question's serving transport logged — read per pass from a
  `bridgeReady` flag `NodeViewModel` records at its bootstrap's resolution
  (`bitcoin_rpc_ready()` is package-internal C; the flag can flip once,
  early, on a fast start — a `noProgress` verdict attributes to a 30 s or a
  60 s ceiling); the watch judges on answers, never on `.running` — that flag
  itself waits on the bridge bootstrap's ~30 s poll;
  `Task.isCancelled` and `isStoppedOrStopping` consulted separately each
  pass; every ending leaves the node running, and every watched run reports
  exactly one sync result (FR-005, FR-008, FR-009) ·
  `Sources/NodeApp/NodeRun.swift`
- [ ] T013 `previous` snapshot captured at attach on `reportExistingNode` —
  before the weigh-in, not merely before the watch: the app's own sync poll
  can overwrite `lastKnown` in those seconds too; the report carries the
  last-known height+chain for the intent's success-path persist (T028);
  report built from the last good reading (FR-017) ·
  `Sources/NodeApp/NodeRun.swift`
- [ ] T014 Suppress `measuredReport`'s closing `onProgress(1)` on budgeted runs
  only — the unbudgeted `answerIsStillWanted` guard stays byte-identical
  (FR-014) · `Sources/NodeApp/NodeRun.swift`
- [ ] T015 Both new loops generic over `C: Clock<Duration>` (not
  `any Clock` — erased `InstantProtocol` can't compare deadlines); clock enters
  at `perform`, threads through `runWithHeartbeat` and `awaitFirstAnswer`; the
  sleep policy lands here — cadence and heartbeat sleeps carry ~1 s tolerance
  so the system can coalesce them, while only `withHardTimeout`'s deadline
  race keeps `tolerance: nil` · `Sources/NodeApp/NodeRun.swift`
- [ ] T016 `report()` gains the `isStoppedOrStopping` pre-check;
  `WithHardTimeout`'s pile-up comment re-derived — the loop is sequential, so
  nothing overlaps unless abandoned; an abandoned call's residual is (channel
  give-up − question budget): ≈0 on the direct bridge where the ~30 s budget
  matches the give-up, and cancelled outright over HTTP, where
  `work.cancel()` is the one signal `URLSession` observes — both halves
  recorded, and the premise noted (pre-bootstrap HTTP cancellable; post-boot
  bridge not) ·
  `Sources/NodeApp/NodeRun.swift`, `Sources/Shared/WithHardTimeout.swift`
- [ ] T026 End-to-end `TestClock` run in a new `NodeRunTests.swift`, written
  red-first — a budgeted run through grace → start → watch → named ending on
  the last good reading, the node left running and `blocksGainedThisRun`
  counting the earned heights; a `nodeStopped` variant ends the watch when
  the node
  stops mid-poll; a warm-restart run — flag clear, no gap, tip past
  `tipFreshnessThreshold` — reaches the watch on the age leg alone, in both
  quiet-chain shapes: ≥2 confirming outbound peers end it `caughtUp`, and zero
  qualifying peers end it `noProgress`; and the unbudgeted path emits
  byte-identical report fields
  and progress writes — the SC-005 assertion (verifies FR-005, FR-008,
  FR-009, FR-013, FR-014, FR-016, FR-017, SC-005) ·
  `Sources/NodeAppTests/NodeRunTests.swift`

**Checkpoint:** a budgeted run exercises grace → start → watch → named ending
end-to-end under a `TestClock`; the unbudgeted path is unchanged.

## Phase 4 — Progress meter (gated on the device experiment)

⟶ **wait** — the Phase 6 liveness experiment (text-only vs numeric writes)
decides this phase's size *before* it is written; T017 can run any time.

- [ ] T017 Text surface regardless of outcome: headline/detail writes on the
  underlying `Progress` — the detail line carries "Block X of Y" (FR-003) —
  a fresh write lands every pass even if the numeric path stays as-is
  (FR-004, FR-018); `onProgress` payload widened to a value type
  (fraction, headline, detail — `SyncNodeIntent` compiles through the same
  signature with defaults), `finish()` gates text and count alike ·
  `Sources/NodeApp/ProgressMeter.swift`, `NodeRun.swift`
- [ ] T018 If numeric writes are required: `scale` ≈ 10,000, `advance()` capped
  at `scale − 1 − reserve`, write floor split `earned` (monotone) / `reported`
  (may dither ±1), `tick()` alternating `{earned, earned+1}`, skip gate keyed
  on `earned`, `heartbeatUnits` cap retired — fallback if the system credits
  only *increasing* writes: a ratchet bounded inside the reserve (FR-004,
  FR-018) · `Sources/NodeApp/ProgressMeter.swift`
- [ ] T019 [P] Invariant tests: tick at the working ceiling writes a new value;
  tick never strands earned progress; dither inside `{earned, earned+1}`;
  nothing lands after `finish()`; re-point `heartbeatCoverageExceedsWait` at
  the banded model — simulate the compressed pre-watch ramp (~10 notches over
  the wait, not ~90) before counting coverage, and assert it spans
  `waitForFirstAnswer + syncBudget`: red on the pre-004 layout today, and
  measuring the real meter whichever way the experiment lands — the intent's
  own comment predicted the `questionBudget` growth `watchQuestionBudget` is.
  Drop the `#if os(iOS)`/`@available` fences on
  `ProgressMeter` and its tests — `Progress` and `Ending` are platform-free —
  so the invariants run on both platforms (verifies FR-004, FR-018) ·
  `Sources/NodeApp/ProgressMeter.swift`,
  `Sources/NodeAppTests/ProgressMeterTests.swift`,
  `SyncNodeLongRunningIntentTests.swift`

**Checkpoint:** the bar can keep a guaranteed-fresh write every ~5 s for the
whole window without ever claiming unearned progress — the invariant tests
were seen failing before the meter changed.

## Phase 5 — Intent wiring and localization

- [ ] T020 `allowedExecutionTargets: ExecutionTargets { .main }` on
  `SyncNodeLongRunningIntent` — turns ADR 0005's process pin into a
  system-honored constraint where the budget can afford the launch latency;
  the short action stays unpinned — `.main`'s cost inside a ~30 s budget is a
  real change, and FR-014 promises none (ADR 0005; platform enforcement, not
  feature behavior) · `Sources/NodeApp/SyncNodeLongRunningIntent.swift`
- [ ] T021 Pass the constants: `syncBudget` 15 min, `privateNetworkGrace` ~90 s,
  `unproductiveLeash`/`flatWindowLeash` 120/~240 s, `tipFreshnessThreshold`
  ~60 min, `watchQuestionBudget` ~30 s, `peerConfirmationsRequired` 2, meter
  `scale`;
  flip the headline on entering the watch — constants and the long action's
  execution-target declaration pinned in `SyncNodeLongRunningIntentTests`
  (FR-003, ADR 0005; verifies FR-006, FR-007, FR-013) ·
  `Sources/NodeApp/SyncNodeLongRunningIntent.swift`
- [ ] T022 Add the target's first `.xcstrings`; card text via
  `String(localized:)`; `summary` stays `String`. Count-bearing keys take
  String Catalog plural variants (or automatic grammar agreement) — the
  ternary-suffix pattern T027 removes never re-enters; duration strings come
  from `Duration.formatted`/`RelativeDateTimeFormatter`. Verify whether
  `AppShortcut` phrases need a dedicated `AppShortcuts.xcstrings` — if so,
  that follow-up is its own file ·
  `Sources/NodeApp/`, `Resources/NodeApp/`

**Checkpoint:** the action runs the full watch on-device with correct card
text, dialog, and a branchable `syncResult` in the Shortcuts UI.

## Phase 6 — Device verification (gated)

Entry: a build with Phases 1–5 merged, a physical device, the ability to lock
the screen and leave it. Every item from the plan's Verification section,
locked-screen per ADR 0008:

- [ ] T023 Liveness experiment first — text-only write vs numeric-only vs
  both; the question is `BGContinuedProcessingTask`'s expiration behavior,
  and the answer sizes Phase 4's T018
- [ ] T024 Every item in the plan's Verification checklist, on a locked
  physical device — one pass, every box; the warm-restart box needs hours of
  idle time between runs for the tip to age past `tipFreshnessThreshold`, so
  it is its own session, not a rerun. One measurement rides that session:
  time from the first answer to the second confirming peer, over Tor and
  locked — connect, handshake, and the anchored `getheaders` reply for two
  peers against a possibly-stale address book, unmeasured today. If it lands
  near or over the ~240 s `flatWindowLeash`, the quiet-chain leg never fires
  before the leash — the contingent fix is small: on runs the tip-age leg let
  in, start `flatWindow` only once the peer question has seen at least one
  outbound peer (the run budget still bounds the wait). Design unchanged
  until the number exists
- [ ] T025 Re-measure ADR 0008 locked-device timings and ADR 0009 post-return
  survival in the same session; move both records off `Proposed`

**Checkpoint:** every checkbox in the plan's Verification section closed on
hardware, both ADRs updated.

## Pull-request slicing

The phases above order the *work*; this table cuts it into *reviewable pull
requests* — each builds and passes checks on its own. "Changed lines" is
added-plus-deleted estimate from the plan, since no implementation exists to
measure.

- **Most slices are independent** — "Depends on" chains run no more than four
  links deep (13→11→8→7→6 and 13→11→8→4→2, five slices each), and slices 0, 1,
  2, 3, 6, 9, 15, 16 can open against `main` in any order.
  Slices under the ~150-line band are enabling diffs rather than review
  units — they exist so later slices open against a landed base; the band is
  a guide, not a floor.
- **A dependency can be a device check, not just a slice** — such a slice still
  merges on CI, but its design stays provisional: if the named check fails on a
  locked phone, the slice reopens.
- **Row E is not code.** It is the plan's Verification liveness experiment, runs on the
  current build, nothing blocks it — run it early because it sizes slice 10.

| # | Landed | Pull request | Tasks | Changed lines | Depends on |
|---|---|---|---|---|---|
| E | [ ] | Device check, not a PR: does a text-only write count as the liveness the system requires? | T023 | — | — |
| 0 | [ ] | Snapshot the run's settings at entry — a mid-run toggle cannot re-scope what this run launches, chain included (ADR 0006 hole; ships ahead of the feature) | T001 | ~150 | — |
| 1 | [ ] | Report gains the sync-result word (five branchable values) + `blocksGainedThisRun`; display text pinned by tests | T002–T004 | ~250 | — |
| 2 | [ ] | `LiveReading` gains the still-syncing flag, known header height, and tip timestamp; the peer answer rides beside it | T005 | ~110 | — |
| 3 | [ ] | `DeviceConditions` gains real thermal detail: entry still refuses at `.serious`, drift ends only at `.critical` | T008 (type half) | ~200 | — |
| 4 | [ ] | The watch's memory: `SyncWatchState` — best-seen heights, headers-advanced latch, both stall accumulators, the peer-confirmation clause (+ tests) | T006 + T007 (state half) + T010 (state tests) | ~390 | 2 |
| 5 | [ ] | Card math and wording: distance-to-tip fraction, the band map, the five ending sentences (+ tests) | T007 (fraction) + T009 + T010 (fraction/wording tests) | ~250 | 1, 2, 15 |
| 6 | [ ] | Thread `C: Clock<Duration>` through the run routine so every sleep and deadline is drivable in tests | T015 | ~80 | — |
| 7 | [ ] | Private-network grace: deadline-bounded Tor wait, then full re-decision before starting | T011 | ~200 | 3, 6 |
| 8 | [ ] | The watch stage: poll loop, entry gate, flat-pass `getpeerinfo` for the confirmation count, `nodeStopped` ending, report built from the last good reading, stopped-node pre-check | T012–T014 + T016 | ~430 | 1, 2, 4, 5, 6, 7, 9 |
| 9 | [ ] | Progress plumbing: the progress callback widens to carry headline and detail, not just a fraction | T017 (payload half) | ~120 | — |
| 10 | [ ] | Keep-alive mechanics — the text surface alone, or the dither-and-reserve redesign; size set by row E | T017 (text half) + T018–T019 | ~60–350 | E, 9 |
| 11 | [ ] | Conditions during the watch: the one-time weigh-in on skipped-preflight paths, then per-pass drift checks (+ drift-matrix tests) | T008 (drift half) + T010 (drift tests) + NodeRun wiring | ~200 | 3, 8 |
| 12 | [ ] | Wire the long-running action: execution-target pin, budget/grace/leash constants, syncing headline, first `.xcstrings` | T020–T022 | ~300 | 8, 10 |
| 13 | [ ] | Correct `plan.md` to describe what shipped; record re-measured locked-device timings in ADRs 0008/0009 | T024–T025 | ~100 | 11, 12 |
| 14 | [ ] | End-to-end `TestClock` run — grace → start → watch → named ending, plus the unbudgeted-path byte-identical assertion | T026 | ~140 | 8 |
| 15 | [ ] | Fix the shipped dialog's unextractable string — `IntentDialog` built from a localized template, hand-rolled plural suffixes removed (both intents) | T027 | ~100 | — |
| 16 | [ ] | Persist `lastKnown` only on the success path — a cancelled or stopped run no longer advances a baseline it never reported | T028 | ~60 | — |

Roughly 3,130–3,430 changed lines across slices 0–16; largest ~430. Tick boxes
are edited in the same pull request as the slice.

## Deferred

Shipped-with-reasons, from the plan's follow-up list — none block this feature:
AssumeUTXO bootstrap (package feature), `BGProcessingTask` idle sync (a
different API — opportunistic idle-time work, not the
`BGContinuedProcessingTask` this feature's runs ride; needs the Background
Modes capability), stopping a run-started node on metered drift (own ADR),
mid-watch free-space re-check, the measured report on a system `.timeout`
(needs a channel that survives the throw), non-isolated `perform()` with
explicit `MainActor.run` hops (bigger than this feature — touches every
`NodeSession` caller), a guard for retried runs (the pre-run snapshot detects
a just-finished attempt), lazy direct-bridge re-bootstrap (004 makes it
load-bearing: HTTP-for-life is the expected locked-device case; the watch's
first successful reading is the trigger bootstrap polled for, and the
explicit retry is action work — `Daemon.bootstrap` is already public), grace
for the short action (declined — its ~30 s window cannot afford a cold
bootstrap).
