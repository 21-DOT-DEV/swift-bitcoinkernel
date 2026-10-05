# Tasks — 004 · The long-running action watches the node sync toward the tip

Ordered work for [the plan](./plan.md); requirements cited as `FR-NNN` from
[spec.md](./spec.md); rationale in [research.md](./research.md).

Format: `- [ ] TNNN [P?] what lands (~changed lines) · files`. One checkbox is
one reviewable change — a single self-contained concern landed as one pull
request a reviewer can read in one sitting. A description that needs "and" to
say what it does is two tasks. The `(~N)` figures are added-plus-deleted
estimates: ~300 is the tripwire — split the task or justify why it cannot —
and ~400 is the ceiling. Tests ride in the same change as the code they cover,
written and seen failing first (the constitution's red → green rule). `[P]`
marks a task with no prerequisites — free to pick up early or in parallel;
`⟶ wait` gates what follows it on a device check — blocking, but not a pull
request; `needs TNNN` names a
prerequisite the ordering doesn't already imply; `provisional on TNNN` marks
a task that merges on CI but reopens if the named device check disagrees —
a flag, not a gate. Group headers are navigation,
not merge units — nothing ships "by phase"; each group still closes on a
checkpoint. `(FR-NNN)` cites the requirements a task serves — enabling work
cites nothing — and `verifies FR-NNN`/`SC-NNN` declares which of them its
tests exercise (a pure test task verifies without citing).
`ref LONG-PHASE-0` marks ground the reference branch already explored: consult
it for the fixes it discovered rather than re-deriving them. Tick the box in
the same change that lands the task.

## Prerequisite fixes — shipped bugs ahead of the feature

All of this ran once on `LONG-PHASE-0` (~1,800 changed lines in one branch).
It is re-implemented fresh at reviewable grain; the branch is the reference,
not a source of commits to replay.

- [x] T001 [P] Move the launch-time decisions into `NodeAutomation` as pure
  functions — privacy gating, argument build, the Tor-resurrection check —
  ahead of the snapshot changing how they're called; a refactor with no
  behavior change. Landed as: `DaemonConfig.Snapshot` (every key the builder
  consults) + `buildArguments(settings:torProxy:)`, with the live-read
  `buildArguments(torProxy:)` delegating through it; `requiresPrivateNetwork`,
  `privateNetworkTurnedOff`, and `StartRefusal.init(stillEnabled:)` staged
  tested-but-unwired — the Tor-resurrection check's *decisions* live here;
  the check itself (`NodeSession.startTorIfStillEnabled()` and its two call
  sites) lands with T002's wiring — the settings→args mapping stays in
  `DaemonConfig`, which the screens share (~270) ·
  `Sources/NodeApp/NodeAutomation.swift`, `DaemonConfig.swift`,
  `Sources/NodeAppTests/{DaemonConfigTests,NodeAutomationTests}.swift` ·
  ref `LONG-PHASE-0`
- [ ] T002 Capture the `DaemonConfig.Snapshot` T001 provides, once at
  `NodeRun.perform` entry, and launch from it alone — so the ~90 s grace
  can't widen a millisecond race into a 90-second one, and a mid-grace
  chain flip can't start a chain the run's launch decision never covered;
  write `requiresPrivateNetwork`'s combined answer back into the
  snapshot's `torEnabled` before building arguments (`buildArguments`
  gates `-proxy=` on that flag, so a live-on flip that skips the
  write-back launches direct); Tor checks fail closed via
  `NodeSession.startTorIfStillEnabled()` and a start failure no longer
  resurrects a just-disabled Tor (~200) · `Sources/NodeApp/NodeRun.swift`,
  `NodeSession.swift` · needs T001 · ref `LONG-PHASE-0`
- [ ] T003 [P] Stop tests writing the app's real `UserDefaults` — the test
  isolation fix the reference branch discovered mid-flight (~100) ·
  `Sources/NodeAppTests/` · ref `LONG-PHASE-0`
- [ ] T004 [P] `IntentDialog` built from `LocalizedStringResource` templates
  interpolating the report's values — `IntentDialog(stringLiteral:
  report.summary)` ships a runtime `String` with no extractable key; the same
  change removes the hand-rolled `block\(s)` ternary — plural variants belong
  to the catalog, and the catalog joins the NodeApp `resources:` list in
  `Projects/Project.swift` — the target enumerates resources by name, not by
  glob, so without the entry the file never compiles into the app
  (re-run `tuist generate` after the edit) (~220, mostly generated catalog
  rows) ·
  `Sources/NodeApp/SyncNodeIntent.swift`,
  `SyncNodeLongRunningIntent.swift`, `NodeAutomation.swift`,
  `Resources/NodeApp/`, `Projects/Project.swift` · ref `LONG-PHASE-0`
- [ ] T005 [P] `persistLastKnown` moves out of `measuredReport` — today the
  write runs before the last `answerIsStillWanted` guard, so a run cancelled
  or node-stopped in that window advances a baseline it never reported; the
  report carries the last-known height+chain and each intent persists it only
  on the path that returns `.result(value:)` (~80) ·
  `Sources/NodeApp/NodeRun.swift`, `SyncNodeIntent.swift`,
  `SyncNodeLongRunningIntent.swift` · ref `LONG-PHASE-0`

**Checkpoint:** a settings toggle landing mid-run cannot re-scope what this
run launches; dialog text is extractable; baselines advance only on reported
results. Every task lands standalone.

## Report vocabulary

- [ ] T006 [P] Rename `NodeAutomation.blocksGained(from:to:)` to
  `blocksSince(previous:to:)` — `measuredReport` stores its result in
  `blocksSinceLastCheck`, and the file must not hold two names meaning
  different baselines before T007 adds the second (~40) ·
  `Sources/NodeApp/NodeAutomation.swift` and its callers
- [ ] T007 `NodeSyncResult` `AppEnum` — the FR-005 case set including
  `notMeasured`, explicit raw strings — plus the `syncResult` and
  `blocksGainedThisRun` `@Property`s on `NodeRunReport`, non-optional. Tests
  pin every case's display wording, the `notMeasured` rules, and that the two
  baselines differ (`blocksSinceLastCheck` spans the pre-run gap,
  `blocksGainedThisRun` only what this run watched) (FR-005, FR-016;
  verifies FR-005, FR-016) (~200) · `Sources/NodeApp/NodeRunReport.swift`,
  `Sources/NodeAppTests/NodeRunReportTests.swift` · needs T006

**Checkpoint:** the report carries the second axis (`syncResult`) and
`blocksGainedThisRun`; the tests were seen failing before the code they cover.

## What the watch reads

- [ ] T008 `LiveReading` gains `isInitialBlockDownload`, `headers`, and
  `tipTime` — `blocksBehind` already carries the gap and `info.time` is
  already modeled — plus `PeerEvidence`, a per-peer value carrying
  `syncedHeaders` and the resolved `connectionType` (the field, falling back
  to the `inbound` boolean — unresolved outbound fails closed), riding beside
  the reading rather than folded into it (~110) ·
  `Sources/NodeApp/NodeAutomation.swift`, `Dashboard.swift`
- [ ] T009 [P] `DeviceConditions` gains the `thermalState` itself — today's
  `overheating` collapses `.serious || .critical` to a `Bool`; entry keeps
  refusing `.serious` while the drift check reads `.critical` from the same
  field (~120) · `Sources/NodeApp/NodePreflight.swift`,
  `Sources/NodeApp/NodeRun.swift`, `Sources/NodeAppTests/NodePreflightTests.swift`

**Checkpoint:** every signal the decisions below need exists as plain data.

## Watch decisions — pure functions in `NodeAutomation`, each tested in-diff

- [ ] T010 `SyncWatchState` — the watch's memory as a value type: baseline
  heights, best-seen, the headers-advanced latch, both stall accumulators,
  the entry Low-Power snapshot. `advance(instant:reading:)` feeds exactly one
  accumulator per pass — an advancing reading resets both; an absent reading
  feeds `unproductive` (~120 s); a flat reading feeds `unproductive` only
  while undone work shows (`headers > blocks`), everything else flat feeds
  `flatWindow` (~240 s) (FR-007; verifies FR-007) (~220) ·
  `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T008 ·
  provisional on T039
- [ ] T011 Watch-entry gate — enter only when the IBD flag is set, a header
  gap is open, or the tip is older than `tipFreshnessThreshold` (~60 min)
  against an injected wall-clock `now`; `regtest` never enters (FR-001,
  FR-015; verifies FR-001, FR-015) (~150) ·
  `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T008
- [ ] T012 The `caughtUp` proof — flag cleared *and* `blocks == headers`
  *and* one of: headers advanced this run, the tip is inside the freshness
  threshold, or — on a qualifying flat pass (flag clear, gap closed, headers
  never advanced) — at least `peerConfirmationsRequired` (2)
  `outbound-full-relay`/`block-relay-only` peers report `synced_headers ==
  headers` (FR-006; verifies FR-006) (~200) ·
  `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T008, T010
- [ ] T013 Ending precedence — `nodeStopped`, then `caughtUp`, then
  `conditionsChanged`, then `noProgress`, then `stillSyncing`; cancellation
  stays outside the list entirely (FR-019; verifies FR-019) (~100) ·
  `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T010
- [ ] T014 Live-tip fraction and the stage→band map — `(h − h₀) /
  max(liveHeaders − h₀, 1)` against a live denominator, clamped at zero on a
  reorg below baseline; every pre-watch write compresses into the ~10%
  start-up band, the watch's distance fraction sweeps to the ~95% working
  ceiling, and the no-budget path keeps the full range (FR-002, FR-004;
  verifies FR-002) (~150) · `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T008
- [ ] T015 Ending sentences and card wording — the five endings, the
  position clause always, the staleness clause once flat past the leash;
  every count-bearing sentence plural-aware (catalog variants or grammar
  agreement, never a hand-suffixed `s`), durations via `Duration.formatted` /
  `RelativeDateTimeFormatter` (FR-003; verifies FR-003) (~150) ·
  `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T004
- [ ] T016 Entry weigh-in `refusal(for:)` — the one-time full conditions
  check on paths that skipped preflight (`reportExistingNode`,
  `waitForStartingNode`); `filesReadable`/`chainFolderExists` inferred from
  the answering node, `prepareChainFolder()` skipped, actor-free (no
  `UIApplication.isProtectedDataAvailable`), `freeDiskBytes()` read
  directly, network via `NetworkCostMonitor.first()` bounded ~2 s — `current`
  fails open on a cold launch; refusal ends `conditionsChanged` naming the
  condition (FR-010, FR-011, FR-012; verifies FR-012) (~150) ·
  `Sources/NodeApp/NodeAutomation.swift`, `NodePreflight.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T009
- [ ] T017 Per-pass drift — reads `NetworkCostMonitor.shared.current` (never
  waits), `thermalState`, `isLowPowerModeEnabled`, nothing else; metered and
  Low Data Mode are absolute, thermal only `.critical`, Low Power Mode only
  as a delta from the entry snapshot; returns the condition, not a sentence
  (FR-010, FR-011; verifies FR-010, FR-011) (~120) ·
  `Sources/NodeApp/NodeAutomation.swift`,
  `Sources/NodeAppTests/NodeAutomationTests.swift` · needs T009

**Checkpoint:** every watch decision is a tested pure function — each test
was seen failing before the function it covers; the run routine gains no
watch orchestration until the next group.

## The run routine — `NodeRun` orchestrates

- [ ] T018 Make the run drivable — thread `C: Clock<Duration>` (not `any
  Clock` — erased `InstantProtocol` can't compare deadlines) through
  `perform`, `runWithHeartbeat`, and `awaitFirstAnswer`, with the wall-clock
  `now` the tip-age leg reads injectable beside it. Give `perform` a session
  seam too: `session` is today a concrete `NodeSession` singleton whose
  node, Tor, and reader are fixed instances, so a test cannot conjure a
  never-ready Tor or a mid-watch-stopping node — a narrow protocol (or an
  internal-init session) exposing Tor readiness, node state, and the
  `DashboardDataSource` reader lets the harness fake all three. Land
  `NodeRunTests.swift` with the minimal `TestClock` harness the run tasks
  below build on; the sleep policy lands here too — cadence and heartbeat
  sleeps carry ~1 s tolerance so the system can coalesce them, only
  `withHardTimeout`'s deadline race keeps `tolerance: nil` (~200) ·
  `Sources/NodeApp/NodeRun.swift`, `Sources/NodeApp/NodeSession.swift`,
  `Sources/NodeApp/SyncNodeLongRunningIntent.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift`
- [ ] T019 [P] `bridgeReady` flag — `NodeViewModel` records the direct
  bridge's bootstrap outcome (`bitcoin_rpc_ready()` is package-internal C
  the app can't call), and the run logs the serving transport per question,
  so a `noProgress` verdict attributes timings to a 30 s or a 60 s ceiling
  (~80) · `Sources/NodeApp/NodeViewModel.swift`,
  `Sources/NodeApp/NodeRun.swift`
- [ ] T020 [P] Widen the `onProgress` payload to a value type — fraction,
  headline, detail — `SyncNodeIntent` compiling through the same signature
  with defaults (~80) · `Sources/NodeApp/NodeRun.swift`,
  `ProgressMeter.swift`
- [ ] T021 Private-network grace — a deadline-bounded poll in `NodeRun`'s own
  loop shape (never `withHardTimeout` around `waitUntilReady`, which abandons
  a `@MainActor` loop whose `try?` sleep swallows cancellation);
  `Task.isCancelled` and `session.tor.isReady` checked each pass, early exit
  when Tor leaves `.starting`, `onProgress` throughout; after the grace the
  run re-decides — node state, device conditions, and the step — settings
  stay the T002 snapshot; a Tor that never readies declines with the
  unchanged `privateNetworkNotReady`; the `TestClock` test drives a
  never-readying Tor to the decline and a readying one into the re-decision
  (FR-013; verifies FR-013) (~250) ·
  `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T018, T020
- [ ] T022 The watch stage — poll `blockchainInfo` every ~5 s bounded at
  `min(watchQuestionBudget, remaining)`, the same bound covering
  `awaitFirstAnswer` on budgeted runs (the short action keeps
  `questionBudget`, or a slow-but-alive ~11 s node never reaches the watch);
  the entry gate consulted once, `SyncWatchState` advanced per pass, the
  emitted ending applied by precedence — a spent budget ends `stillSyncing`;
  a fresh progress write lands every pass; `Task.isCancelled` and
  `isStoppedOrStopping` consulted separately; the watch judges on answers,
  never the `.running` flag; the `TestClock` test asserts the question
  bound, the precedence application, and a fresh write every pass (~380 —
  over the tripwire because poll, feed, apply, and their driving test are
  one mechanism; splitting mid-loop leaves a half-wired stage)
  (FR-001, FR-005, FR-009, FR-018, FR-019; verifies FR-009, FR-018, FR-019) ·
  `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift`
  · needs T008, T010, T011, T013, T014, T018, T019, T020
- [ ] T023 Weigh-in call site — the preflight-skipped paths
  (`reportExistingNode`, `waitForStartingNode`) run T016's `refusal(for:)`
  once before the watch commits; a refusal ends `conditionsChanged` naming
  the condition, its test asserting the weigh-in ran once and the watch
  never committed (FR-012; verifies FR-012) (~110) ·
  `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T016, T022
- [ ] T024 Drift call site — each pass runs T017's narrow gather; a found
  condition ends the run `conditionsChanged` mid-watch, its test injecting a
  metered answer mid-watch (FR-010, FR-011; verifies FR-010, FR-011)
  (~110) · `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T017, T022
- [ ] T025 `getpeerinfo` ride-along — on each qualifying flat pass (flag
  clear, gap closed, headers never advanced) one `getpeerinfo`, bounded like
  every question, feeds T012's confirmation count; an absent or timed-out
  answer is no evidence — the pass falls through to the leashes, and a peer
  answer never resets one; the test watches a qualifying flat pass ask once
  and a non-qualifying pass never ask (FR-006; verifies FR-006) (~160) ·
  `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift`
  · needs T012, T022 · provisional on T039
- [ ] T026 `nodeStopped` ending — `isStoppedOrStopping` checked at the top of
  each pass, again before accepting each answer, and as `report()`'s
  pre-check, deliberately separate
  from `Task.isCancelled`; the run ends on the normal measured report —
  earned outcome, last good reading — never a blanked `noAnswer` or a false
  `noProgress`; the test stops the node mid-watch and reads the measured
  report's ending (FR-008, FR-009; verifies FR-008, FR-009) (~180) ·
  `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T022
- [ ] T027 `previous` snapshot captured at attach on `reportExistingNode` —
  before the weigh-in, not merely before the watch: the app's own sync poll
  can overwrite `lastKnown` in those seconds too; a watched run's report is
  built from the last good reading, not the first answer's — the test
  overwrites `lastKnown` between attach and weigh-in and reads the surviving
  baseline (FR-017; verifies FR-017) (~140) ·
  `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T022
- [ ] T028 Suppress `measuredReport`'s closing `onProgress(1)` on budgeted
  runs only — the unbudgeted `answerIsStillWanted` guard stays
  byte-identical; the test records the write sequence on both paths
  (FR-014; verifies FR-014) (~70) · `Sources/NodeApp/NodeRun.swift`,
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T022
- [ ] T029 `WithHardTimeout`'s pile-up comment is re-derived — the loop is
  sequential, so nothing overlaps unless abandoned; an abandoned call's
  residual is (channel give-up − question budget): ≈0 on the direct bridge,
  cancelled outright over HTTP, where `work.cancel()` is the one signal
  `URLSession` observes — both figures from ADR 0008 (~40) ·
  `Sources/Shared/WithHardTimeout.swift` · needs T022 · provisional on T040

**Checkpoint:** every stage the run needs is wired — grace, start, watch,
endings — each pinned by an in-diff `TestClock` test, the unbudgeted path
unchanged; the assembled run's proof is the end-to-end group.

## The card — `ProgressMeter`

- [ ] T030 Headline and detail writes on the underlying `Progress` — the
  detail line carries "Block X of Y", the staleness clause appended once flat
  past the leash's own duration; `finish()` gates text and count alike; one
  composed sentence, not two competing for a line (FR-003; verifies FR-003)
  (~170) · `Sources/NodeApp/ProgressMeter.swift`,
  `Sources/NodeAppTests/ProgressMeterTests.swift` · needs T020
- [ ] T031 [P] Drop the `#if os(iOS)`/`@available` fences on `ProgressMeter`
  and its tests — `Progress` and `Ending` are platform-free — so the meter's
  invariants run on both platforms (~60) ·
  `Sources/NodeApp/ProgressMeter.swift`,
  `Sources/NodeAppTests/ProgressMeterTests.swift`

⟶ **wait** — T038's liveness experiment sizes the next task. It runs on the
current build; nothing else blocks it, so run it early.

- [ ] T032 Meter honesty, sized by the experiment — if numeric writes are
  required: `scale` ≈ 10,000, `advance()` capped at `scale − 1 − reserve`,
  the write floor split `earned` (monotone) / `reported` (may dither ±1),
  `tick()` alternating `{earned, earned + 1}` with its skip gate keyed on
  `earned`, `heartbeatUnits` retired; fallback if only *increasing* writes
  count: a ratchet bounded inside the ~500-notch reserve. If text alone
  satisfies liveness: the redesign shrinks to nothing and only the re-pointed
  guard lands. Either way: invariant tests — tick at the working ceiling
  writes a new value, dither stays inside `{earned, earned+1}`, nothing lands
  after `finish()` — and `heartbeatCoverageExceedsWait` re-pointed at the
  banded model, simulating the compressed ramp (~10 notches over the wait)
  and asserting coverage across `waitForFirstAnswer + syncBudget` (FR-004,
  FR-018; verifies FR-004, FR-018) (~60–250) ·
  `Sources/NodeApp/ProgressMeter.swift`,
  `Sources/NodeAppTests/ProgressMeterTests.swift`,
  `SyncNodeLongRunningIntentTests.swift` · needs T030, T031

**Checkpoint:** the bar can hold a guaranteed-fresh write every ~5 s for the
whole window without ever claiming unearned progress — whichever way the
experiment landed.

## Wiring the action

- [ ] T033 [P] `allowedExecutionTargets { .main }` on
  `SyncNodeLongRunningIntent` — ADR 0005's process pin turned into a
  system-honored constraint; the short action stays unpinned, its ~30 s
  budget can't afford the launch latency (ADR 0005) (~20) ·
  `Sources/NodeApp/SyncNodeLongRunningIntent.swift`
- [ ] T034 Wire the constants — `syncBudget` 15 min, `privateNetworkGrace`
  ~90 s, `unproductiveLeash`/`flatWindowLeash` 120/~240 s,
  `tipFreshnessThreshold` ~60 min, `watchQuestionBudget` ~30 s,
  `peerConfirmationsRequired` 2, meter `scale`; the headline flips to the
  syncing wording on watch entry; constants and the execution-target
  declaration pinned in `SyncNodeLongRunningIntentTests` (FR-003, FR-006,
  FR-007, FR-013; verifies FR-006, FR-007, FR-013) (~150) ·
  `Sources/NodeApp/SyncNodeLongRunningIntent.swift`,
  `Sources/NodeAppTests/SyncNodeLongRunningIntentTests.swift` ·
  needs T021, T022, T030 · provisional on T039 and T040
- [ ] T035 The card's strings into the catalog T004 adds — card text via
  `String(localized:)`; `summary` stays `String`; count-bearing keys take
  String Catalog plural variants (or automatic grammar agreement); verify
  whether `AppShortcut` phrases need a dedicated `AppShortcuts.xcstrings` —
  if so that follow-up is its own file (FR-003) (~200) ·
  `Sources/NodeApp/`, `Resources/NodeApp/` · needs T004, T015, T030

**Checkpoint:** the action is wired end to end — constants, card text,
dialog, and a branchable `syncResult` in the Shortcuts UI; the on-device
proof is T039's.

## End-to-end proof

- [ ] T036 `TestClock` run end-to-end — a budgeted run through grace → start
  → watch → named ending on the last good reading, the node left running,
  `blocksGainedThisRun` counting the earned heights; the unbudgeted path
  emits its pre-existing report fields and progress writes byte-identical
  (the two new fields read `notMeasured` and 0) — the SC-005
  assertion (verifies FR-005, FR-009, FR-013, FR-014, FR-016, FR-017,
  SC-005) (~160) · `Sources/NodeAppTests/NodeRunTests.swift` ·
  needs T021–T029, T034
- [ ] T037 `TestClock` ending coverage — a `nodeStopped` variant ends the
  watch when the node stops mid-poll; the warm-restart run — flag clear, no
  gap, tip past `tipFreshnessThreshold` — reaches the watch on the age leg
  alone in both quiet-chain shapes: ≥2 confirming outbound peers end
  `caughtUp`, zero qualifying end `noProgress` (verifies FR-006, FR-008)
  (~140) ·
  `Sources/NodeAppTests/NodeRunTests.swift` · needs T036

**Checkpoint:** the whole pipeline — grace, start, watch, every ending —
runs green under a `TestClock` with the node left running.

## Device checks and records — not pull requests

- [ ] T038 Liveness experiment — text-only write vs numeric-only vs both,
  on a locked device; the question is `BGContinuedProcessingTask`'s
  expiration behavior, and the answer sizes T032. Runs on the current build —
  nothing blocks it; run it early.
- [ ] T039 Every item in the plan's Verification checklist except T038's
  experiment, on a locked
  physical device — one pass, every box; the warm-restart box needs hours of
  idle time between runs for the tip to age past `tipFreshnessThreshold`, so
  it is its own session. One measurement rides that session: time from the
  first answer to the second confirming peer, over Tor and locked. Near or
  over the ~240 s `flatWindowLeash`, the quiet-chain leg never fires before
  the leash — the contingent fix is plan §3.5's: on runs the tip-age leg let
  in, start `flatWindow` only once the peer question has seen at least one
  outbound peer (the run budget still bounds the wait).
- [ ] T040 Re-measure ADR 0008 locked-device timings and ADR 0009
  post-return survival in the same session; move both records off
  `Proposed`; correct `plan.md` to describe what shipped — a docs pull
  request, the only one in this group.

**Checkpoint:** every checkbox in the plan's Verification section closed on
hardware, both ADRs updated, the plan describing what exists.

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
