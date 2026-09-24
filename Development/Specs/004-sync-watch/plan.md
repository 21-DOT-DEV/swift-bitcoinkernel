---
feature: 004
title: The long-running action watches the node sync toward the tip
phase: null
status: Planned
updated: 2026-09-24
adrs: [0005, 0006, 0008, 0009]
---

# The long-running action watches the node sync toward the tip

## Summary

The iOS 27 "Keep Bitcoin Node Syncing" action spends its extended window
waiting for the node to answer its first question, then returns — its progress
bar describes only start-up. This feature adds a third stage to the shared run
routine: once the node has answered and is behind the known tip, the run stays
alive inside its budget and watches blocks arrive, driving the card with real
sync progress ("block 843,210 of 915,000") until it is caught up, out of time,
unable to advance, or stopped. Demo-app work, no roadmap phase.

Requirements and user-facing behavior: [spec.md](./spec.md). Ordered
implementation work: [tasks.md](./tasks.md). Evidence for the decisions —
upstream source verification, platform behavior, rejected alternatives:
[research.md](./research.md). Builds on the shared run from
[003](../003-node-automation-action/plan.md); every rule it set — one routine
both actions call, decisions as testable free functions, honest endings, the
node left running — still holds.

## Technical Context

**Language/Version**: Swift 6.3, strict concurrency · **Platform**: iOS 27 API
surface (`LongRunningIntent`, `ExecutionTargets`), runtime floor iOS 18 ·
**Testing**: Swift Testing on both demo-app platforms, `TestClock`-driven (swift-clocks
already a workspace dependency) · **Key APIs**: `Foundation.Progress`,
`AppEnum`/`@Property`, `getblockchaininfo` over the existing
`DashboardDataSource` seam · **Process**: `allowedExecutionTargets { .main }`
pins the long-running action to the app process — the daemon holds an
exclusive lock on the chain folder, and ADR 0005's "runs in the app"
requirement was until now enforced only by the absence of an extension target · **Constraints**:
self-bounded ≈21-minute worst case; a fresh progress write every ~5 s (the
system cancels silent runs at ~30 s — documented via
`IntentCancellationReason.timeout`); no protocol widening beyond the existing
seam.

## Constitution Check

- **Principle I** (Core alignment): `caughtUp` *is* Bitcoin Core's own verdict
  — the `initialblockdownload` flag it latches and clears itself
  (`UpdateIBDStatus`, `validation.cpp`), plus a closed header gap — not a
  copied test that could certify past a flag the node still reports. The
  peer-confirmation leg reads the *result* of a request Core itself sends
  every block-serving peer on a tip under a day old — no P2P logic
  reimplemented ([research §3](./research.md)).
- **Principle II** (interop & resource safety): no new Swift↔C++ boundary —
  all work is app-side Swift. The new loops hold the strict-concurrency
  practice the feature leans on: poll loops generic over `Clock`, cancellation
  checked separately from the node-stop flag each pass; the `@MainActor` wait
  hazard is exactly why the grace polls in `NodeRun`'s own loop rather than
  wrapping `waitUntilReady` ([research §4](./research.md)). One deviation is
  recorded rather than silently inherited: both intents' `perform()` is
  `@MainActor`, where Apple's execution-model guidance is non-isolated
  `perform()` with explicit `MainActor.run` hops — the watch's ~180 poll
  iterations run on the main actor, and the `waitUntilReady` hazard is
  downstream of that choice. De-isolating touches every `NodeSession` caller —
  deferred, not hidden.
- **Principle III** (lifecycle): no run ever stops the node; every ending
  leaves it running. Read-only RPCs during `Syncing` only.
- **Principle IV** (API surface): no public package API changes — all work is
  inside the demo app; the proof reads `initialblockdownload`, `blocks`, and
  `headers` off the same `getblockchaininfo` the watch already makes.
- **Principle V** (spec-first): `plan.md` remains the constitution-required
  artifact; `spec.md` carries the user scenarios and acceptance criteria in
  user-facing terms; decisions-as-pure-functions keeps the TDD seam.
- **Principle VI** (CI): unit tests on every decision function — and the
  meter's honesty invariants — run on both platforms: `Progress` is
  Foundation, so T019 drops `ProgressMeter`'s iOS-27 fence rather than
  leaving the bar-honesty tests compiled out on macOS; the device-only
  verification lives in one gated session.
- **Principle VII** (open source): not a package-API feature — the public
  artifacts are this Specs set and the ADR updates at T025, which land with
  the code.

No violations; nothing to justify in complexity tracking.

## Design

### 3.1 A third stage in the one routine

`NodeRun.perform` gains two optional durations — `syncBudget` and
`privateNetworkGrace`, both default `nil`. Every existing path is unchanged but
one (§3.8): the watch begins only after a path lands on a live reading — a
just-started node that answered, a still-starting node that answered, or an
already-running node that was read — and only when a budget was passed *and*
the node says it is still syncing: its `initialblockdownload` flag set, a
header gap open, *or* a tip timestamp more than ~60 minutes old — *and* the
chain has a network to compare against: `chain == "regtest"` never enters,
since a self-defined chain is definitionally at its own tip and a peerless
regtest node would otherwise burn the `flatWindow` leash to `noProgress` on
every run. No one signal can carry the gate: a node that has not yet fetched
fresh headers reports a gap of zero, and the flag clears at chain-tip load for
any tip under a day old — while networking starts and RPC warmup ends within
lines of each other at init, so the first answer lands before the first header
fetch can finish. Flag-clear *and* gap-zero is exactly what a warm restart
reports while hours of blocks wait — the periodic automation's common case —
and the tip's own `time` field is the signal that covers it ([research
§2](./research.md)). `LiveReading` gains the flag — `SyncSummary` already
computes it — along with `headers` and `tipTime`; the age is judged against a
wall-clock `now` the run supplies, injectable beside the duration clock. A run
that declined, got no answer, or found the node finished — flag clear, no gap,
tip fresh — returns exactly as today.
`SyncNodeIntent` passes nothing, so its behaviour is byte-identical; the
routine stays one.

### 3.2 The bound is time; the target is blocks

The watch ends on the first of:

- **Caught up** — one proof, and it is the node's own: `initialblockdownload`
  cleared *and* the gap closed (`blocks == headers`, re-read each poll) *and*
  either headers advanced during the run, the tip is inside the ~60-minute
  freshness threshold, or — on a flat pass whose flag is clear, gap closed,
  and headers never advanced — at least two outbound block-serving peers
  report `synced_headers == headers`, the completed exchange Core itself
  asked them for (§3.5) — the flag is required because height-equality alone is
  also true before fresh headers arrive, and on a warm restart it is already
  clear at the first answer (§3.1), so the third leg separates "watched a
  catch-up" from "arrived after one". There is no second proof — there almost
  was: a live
  copy of Core's leave-IBD test (`chainwork` ≥ the network minimum, tip inside
  `max_tip_age`) was this bullet's other half until the call sites were
  counted — Core runs that check at `LoadChainTip`, after each block-file
  import, and on every `ConnectTip`/`DisconnectTip`, so a flag still set with a
  recent tip
  exists only where the check was skipped mid-load (a reindex or import the
  app cannot produce), and certifying past a set flag would contradict the
  node's own report ([research §3](./research.md)).
- **Budget spent** — a wall-clock budget counted from the first answer. Fifteen
  minutes is the starting constant, re-measured locked before it is trusted
  (ADR 0008's rule). Total worst case ≈ 21 minutes including preflight, grace,
  and first-answer wait.
- **No progress** — §3.5; `unproductive` trips on nothing advancing while
  known work stands undone (~2 min), `flatWindow` on ~4 min flat.
- **Conditions drifted** — §3.6.
- **Stopped** — the existing `onCancel` path, unchanged.
- **Node stopped** — someone stops the node from the app while the watch runs.
  The poll loop checks `isStoppedOrStopping` at the top of each pass and again
  before accepting each answer, deliberately separate from `Task.isCancelled`;
  it does *not* take the no-answer path — that would blank every measured field
  and discard a quarter-hour of real gains. The run ends on the normal measured
  report — earned outcome, last good reading — with `syncResult` =
  `nodeStopped`.

The list above is presentation order, not precedence. When several endings
hold on the same pass — the node stopped as the network turns metered, a stall
tripwire tripping as the catch-up proof lands — exactly one is reported, by
precedence (FR-019): `nodeStopped`, then `caughtUp`, then `conditionsChanged`,
then `noProgress`, then `stillSyncing`. A deliberate stop ends measurement
itself; a completed proof is terminal truth — drifted conditions are advisory
for the next run, not a verdict on one that finished; unconsented conditions
outrank a tripwire; any verdict outranks a spent budget. The poll loop checks
in that order, and cancellation stays outside the list entirely — it is the
existing `onCancel` path, not a sync result.

### 3.3 The goal is the live tip itself

The bar's target is the current tip, re-read each poll — the distance this
run closed over the distance that remained at watch entry (the FR-002
contract; the algebra lives here):

```
fraction = (h − h₀) / max(liveHeaders − h₀, 1)
```

- A node that will catch up sweeps toward the working ceiling as `h` closes on
  `liveHeaders` — then a `caughtUp` proof fires and the ending fills the bar.
- A node that cannot catch up shows the truth: distance closed this run over
  the distance remaining when it began — small, real, never clock-like. The
  detail line carries the absolute position, so a single-digit bar beside
  "Block 845,350 of 916,800" reads as "far behind," not broken.
- The denominator is live: fresh headers arriving mid-run grow it, which can
  pull the true fraction down — the meter's never-retreat floor absorbs the dip
  while the detail line keeps reporting ground truth. A reorg below the run's
  baseline clamps the numerator at zero the same way.
- While the node knows no gap yet (`liveHeaders ≤ h₀` — the cold-IBD window
  before first headers) the bar holds at the band floor and the heartbeat keeps
  the run alive: nothing measurable is moving, and nothing claims it is.

The rate-projected alternative degenerates to a clock and
`verificationprogress` is non-monotone — both rejected, with the algebra and
upstream issues in [research §1](./research.md).

The watch asks `blockchainInfo` every ~5 s — the seam `DashboardDataSource`
already exposes, so no protocol widens; `getpeerinfo` joins only on the flat
passes that can't prove a catch-up any other way — flag clear, gap closed,
headers never advanced — for the peer-confirmation count (§3.5). A
budgeted run
bounds *every* question at `watchQuestionBudget` (~30 s — the watch's own
patience; a question unanswered this long is stale for a 5-second cadence
anyway), the first-answer wait included: the 10 s
`questionBudget` is shaped for the short action's ~30 s window, where an 11 s
answer is slow, not dead — a run carrying a fifteen-minute budget can afford
the wider bound everywhere or the slow-but-alive node never reaches the watch
at all.

Which transport carries a question is decided *per call* — `AutoTransport`
routes direct when `bitcoin_rpc_ready() == 1`, HTTP otherwise — and on a
locked device the expected case is HTTP for the node's whole life. The
bridge's bootstrap is a fire-and-forget `Task` inside `NodeViewModel.start`
— the same `start` the run shares — so early questions already flow over
HTTP while its one-shot ~30 s poll loses to the 47–121 s block-index loads
ADR 0008 measured, and nothing retries (the deferred re-bootstrap is what
closes it — 004 makes it load-bearing rather than anecdotal,
[research §4](./research.md)). The selection is real, not hypothetical: on a
fast-starting node the bridge can flip mid-watch, so poll 3 and poll 40 may
ride different transports. A corollary worth stating before anyone "fixes"
it: the watch — like `awaitFirstAnswer` — trusts *answers*, never the
`.running` flag; the flag itself waits on that same bootstrap poll, so a
state-gated wait would stall on a node already answering. The ~30 s figure
stays honest on both paths, for
opposite reasons: on the direct bridge it equals the transport's own
give-up, so an abandoned call parks ≈0 s; over HTTP the `CookieTransport`
ceiling sits at 60 s, and the 30 s orphan is *cancelled* —
`withHardTimeout`'s `work.cancel()` is the one signal `URLSession`
observes. Orphan lifetime and cancellability are inversely coupled, selected
per call by a C function — which is why T012 logs the serving transport per
poll: `bitcoin_rpc_ready()` itself is package-internal, so the run reads a
`bridgeReady` flag `NodeViewModel` records from its bootstrap outcome, and a
`noProgress` verdict on device cannot attribute its timings without it (an ~11 s
answer means different things under a 30 s and a 60 s ceiling).

The second bound is the *remaining watch budget* —
`min(watchQuestionBudget, remaining)`, the clamp `awaitFirstAnswer` already
documents, so the sync budget is a real bound rather than soft by a whole
pass. The leashes' resolution is the pass cadence: "120 seconds" resolves to
~24 passes — a floor, tripped on the first boundary at or after the deadline —
stated so the constant is not over-trusted. Sleeps carry a
policy, set while T015 threads the clock through the loops: of the ~540 timed
wakeups a watch schedules, only `withHardTimeout`'s ~180 deadline races keep
`tolerance: nil` — "late answers are timeouts" is load-bearing — while the
cadence and heartbeat sleeps take ~1 s, letting the system coalesce them with
its other wakeups on a locked phone ([research §4](./research.md)).

The tip is a *display target*, never an ending condition: only `caughtUp`'s
single proof ends a run on it; missing it at budget's end is simply what
`stillSyncing` reports.

### 3.4 What the card shows

On entering the watch the headline becomes "Syncing the Bitcoin node" and the
detail line carries the absolute position — `Block 843,210 of 915,000` —
refreshed with each gain. The bar's honesty rules: never backwards; a tick
keeps the count fresh without posing as earned progress; only an earned finish
fills.

The watch shares one bar with the stages before it, and the never-retreat rule
makes that load-bearing: a completed reading already writes the
completion-equivalent value and start-up writes reach ~0.9, so a sync fraction
starting near zero would be silently discarded for the whole watch — a bar
pinned near full while the node grinds. A budgeted run therefore maps its
stages onto bands — a `NodeAutomation` pure function — every pre-watch write
(the fixed milestones and the smooth first-answer ramp alike) compresses into
the first ~10%, and the watch's distance fraction sweeps from there to the
working ceiling (~95%). With no budget the writes keep the full range.

Liveness is construction, not hope: the system cancels silent runs at ~30 s
(documented — [research §4](./research.md)), so a fresh numeric write must land
every pass. Two reachable states exhaust the current meter — the 50-notch
heartbeat budget drains in ~4 minutes of accumulated silence, and at the
`scale − 1` ceiling every tick writes the same value — and a monotonic tick has
a subtler third failure: once ticks ratchet `reported` above `advance()`'s cap,
no earned gain can ever show again. So, *if the device experiment requires
numeric writes* ([research §4](./research.md) — Apple's own example writes text
on every chunk, and text alone may satisfy the check at zero honesty cost):

- `scale` grows to ≈10,000 (units are arbitrary per Foundation's guidance).
- `advance()` caps at `scale − 1 − reserve` (~95%).
- The write floor splits: `earned` (monotone — the honesty invariant) and
  `reported` (last written — may dither ±1 around it).
- `tick()` *dithers*: writes whichever of `{earned, earned + 1}` is not
  currently standing — always distinct, never accumulating, never stranding
  earned progress beneath it. Its skip gate keys on `earned` having moved, not
  `reported` (a flat `advance()` can re-settle `reported` after a dither and
  halve the liveness margin).
- The reserve stays ≈500 notches so the ratchet fallback needs no re-layout —
  headroom, not a consumable; the `heartbeatUnits` cap retires. The cost is
  stated plainly: a ~95% working ceiling instead of ~99.99%, paid so the
  fallback stays a fallback.

One interaction the experiment does not size — it breaks a guard: under
compression the first-answer ramp writes ~10 distinct notches across the wait
rather than ~90, so ~38 of the meter's 50 heartbeat units are spent before the
watch begins — ~60 s of numeric coverage against a 900 s watch — while
`heartbeatCoverageExceedsWait`, which ticks a fresh meter dry, keeps passing.
The re-pointed guard (T019) simulates the compressed ramp and asserts coverage
across `waitForFirstAnswer + syncBudget`, written to fail on the pre-004
layout — the phase's red-first — whichever branch the experiment takes
([research §4](./research.md)).

The card's words need the same invariants the numbers have. The meter gains
headline/detail writes on the underlying `Progress`, and the run's progress
callback widens to a small value type — fraction, headline, detail — so the
watch pushes wording, not just numbers. `finish()` makes *all* writes final — a
flag gates text and count alike — and the detail is one composed sentence, not
two competing for a line: the position clause always, a staleness clause
appended once the run has been flat long enough ("…, last gain 3 min ago").

### 3.5 Stall: when no new block is the answer

A watch that cannot gain is done — on one of two leashes, never a timestamp
difference: a first-ever start has never produced an advancing reading, so a
since-last-gain clock would declare a stall exactly as real work begins.

Each pass feeds exactly one accumulator, chosen in order:

- An *advancing* reading — `blocks` or `headers` higher than the best yet seen —
  resets both and feeds none. Advancing **headers** count as gain: during
  header fetch the blocks are legitimately frozen while the gap opens.
- No fresh reading at all feeds `unproductive` — **120 s**: a node answering
  nothing is dead to the watch. The 120 s figure sits inside Core's own
  stall-recovery gaps ([research §3](./research.md)).
- A fresh reading with nothing advancing feeds `unproductive` only when the
  node has shown work it is not doing (`headers > blocks`). Everything else
  flat feeds `flatWindow` — **~240 s** — because its state cannot be expected
  to move on a leash's timescale: an IBD-flagged node that has learned no gap
  yet (`headers ≤ blocks`), whose first `getheaders` over a cold circuit is
  work that cannot produce block movement; and — the honest edge — a chain
  quiet past the 24 h recency window, whose flag stays set on Core's own rule
  until the next block connects.

Beside the accumulators the state keeps one latch — `headersAdvanced`, set
when best-seen `headers` passes the entry reading's: the leg `caughtUp` needs
on runs the tip-age gate admitted, where flag-clear and gap-closed described
the *starting* state and only observed growth or a fresh tip proves the
catch-up happened.

Every flat pass that can't otherwise prove a catch-up has one more way out,
because Core gives it one: on a tip under a day old, Core's connect path
sends every block-serving peer a `getheaders` anchored one block back — so a
current peer's reply is never empty and its best-known block records within a
round trip (`net_processing.cpp`; [research §3](./research.md)). A pass
qualifies to ask when the flag is clear, the gap is closed, and
`headersAdvanced` is still false — a fresh tip would already have ended the
run on the freshness leg, so staleness is implied, and a run whose passes
advance never asks at all. On each such pass the watch asks `getpeerinfo`
once, bounded like every question at `min(watchQuestionBudget, remaining)`,
and counts peers whose `connectionType` resolves to `outbound-full-relay` or
`block-relay-only` — the field itself, falling back to the `inbound` boolean
when absent, so an unresolved outbound peer fails closed — reporting
`synced_headers == headers`. Two or more means the reachable network holds
nothing higher than our tip: `caughtUp`. The answer proves height, not block
identity — a same-height fork satisfies it too, which is the right question
to ask. Fewer, none, or a timed-out answer is no evidence — the pass falls
through to the leashes exactly as it does today, and the peer answer is
evidence only: it is not a chain reading and never resets a leash. The
guards match the risk: inbound and manual connections never count (inbound is
attacker-selected), and the ≥2 floor means a run is fooled only by peers as
compromised as its own whole view already is — the residual an all-outbound
eclipse already gives every node. The send fires once per connection at
connect time, so a tip crossing 24 h mid-session keeps the confirmations
earlier-connecting peers already recorded, while a chain stale the whole
time gathers none — the flag-admitted quiet chain keeps its `noProgress`.
The leash assumes two confirmations complete well inside ~240 s — unmeasured
over Tor on a locked device with a stale address book; T024 times it and
carries the contingent fix.

A live copy of Core's leave-IBD test (`chainwork` ≥ the network minimum, tip
inside `max_tip_age`) was once this section's second proof. It was deleted,
not weakened: Core runs the same check at `LoadChainTip`, after each
block-file import, and on every `ConnectTip`/`DisconnectTip`
([research §3](./research.md)), so a
flag still set while the tip is recent exists only where the check was
skipped mid-load — a reindex or import the app cannot produce — and
reporting `caughtUp` while `initialblockdownload` is still set would
contradict the node's own verdict. The flag stays the proof's spine. A chain
quiet past the recency window — where the peer mechanism cannot gather two
answers — is indistinguishable from a dead network and ends `noProgress` — the
safe direction, stated honestly.

One honest edge, kept deliberately: a mid-watch reorg reads as flat and feeds
`unproductive` even while the node refills — no forward progress *is*
happening; counting a changed `bestblockhash` is an optional refinement.

### 3.6 Conditions at entry and mid-watch

Two paths reach the watch having never weighed preflight —
`reportExistingNode` and `waitForStartingNode` — and a fifteen-minute watch is
not the quick read that exemption was written for. Before the watch commits,
the run weighs the full `refusal(for:)` once — power conditions included, which
needs the tested type to carry the granularity both policies use:
`DeviceConditions` gains the `thermalState` itself (today's `overheating`
collapses `.serious || .critical` to a `Bool` — [research §5](./research.md));
entry keeps refusing at `.serious` while the drift check reads `.critical`
from the same field — no passing power conditions in as healthy. The gather
narrows further than narrow: by the time the weigh-in runs, the node is
answering RPCs, which has already proven it read the chain — `filesReadable`
and `chainFolderExists` are inferred from the running node rather than
re-read, `prepareChainFolder()`'s write is skipped either way, and the weigh-in
never touches `UIApplication.isProtectedDataAvailable`, a main-actor read —
leaving it actor-free, which is what the deferred non-isolated `perform()`
needs. `freeDiskBytes()` reads directly, and the network answer waits on
`NetworkCostMonitor.first()` bounded at ~2 s — the weigh-in runs once per run,
so it can afford the wait `readConditions()` pays, and it cannot afford
`current`: `.unknown` reads as "not costly," and a background launch reaching
the weigh-in before the first report lands is the exact cold-launch case
`first()` exists for. A refusal ends the run
`conditionsChanged` with the condition named — the disk floor matters most:
"filling the disk is far worse than skipping a run."

Mid-watch, two kinds of condition get two rules (rationale in [research
§5](./research.md)):

- **Money conditions** — metered, Low Data Mode — absolute, checked every pass:
  they spend something continuously and are never consented to anywhere.
- **Power conditions** — Low Power Mode already on at entry is a standing
  preference (ends the watch only if switched on mid-watch); thermal is
  absolute only at `.critical` (`.serious` is routine on a validating phone).

The per-poll read is a narrow gather, deliberately not `readConditions()` —
that routine writes the filesystem and waits on a network read behind a
two-second timeout, both forbidden in a ~180-pass watch ([research
§5](./research.md)). The watch reads `NetworkCostMonitor.shared.current`
(never waits) plus `thermalState` and `isLowPowerModeEnabled`, and nothing
else.

On drift the run ends `conditionsChanged` — a fifth `NodeSyncResult` case, not
`stillSyncing`: budget-spent means "run me again now," drifted-unsafe means
"back off," and an automation can only branch on what it can name. The wording
is the watch's own: `Refusal`'s sentences all end "so the node did not start,"
which a mid-watch ending would make a lie — the node did start, is running, is
left running. Ending the run lets the app suspend, which freezes the in-process
daemon — a `.critical` abort does relieve the device, indirectly. Stopping the
node is deliberately not here (Deferred work). Files and disk stay
preflight-only past the entry weigh-in; the free-space re-check was explicitly
deferred (Deferred work).

### 3.7 The report's vocabulary grows on a second axis

`outcome` is untouched — it keeps meaning *what the run did to the node*, the
distinction ADR 0005 relies on. The sync ending is orthogonal, so it is a
separate, additive field:

```swift
@Property(title: "Sync result") var syncResult: NodeSyncResult
```

`NodeSyncResult` is an `AppEnum` over the FR-005 case set — explicit raw
strings, a completeness test,
append-only per the slice-6 pattern. `nodeStopped` names exactly what it means;
"the run was stopped" cannot occur (a run-stop throws `CancellationError` and
produces no report). A sixth case, `notMeasured`, is what the field reads when
the run has no sync answer — declined before the weigh-in, no answer before
the watch, every short-action run — except the entry-weigh-in refusal, which
reports `conditionsChanged` since the weigh-in is already the conditions
mechanism answering. Non-optional deliberately: whether `Optional<some
AppEnum>` satisfies `EntityProperty<Value>` is unverified ([research
§6](./research.md)), a non-optional enum is the standard shape, and a
branchable value beats a `nil` automations must test for.

A watched run also gains `blocksGainedThisRun` — heights earned while this run
watched — because `blocksSinceLastCheck` keeps its existing meaning (measured
against the pre-run `lastKnown` snapshot) and a fifteen-minute watch would
otherwise leave it answering two questions at once. `lastKnown` keeps
run-boundary discipline — written once at report time, never per-poll
([research §6](./research.md)). A watched run builds its report from the last
good reading — the last poll that returned data, which on a `noProgress` or
`nodeStopped` ending is earlier than the last pass — otherwise a `caughtUp`
verdict would sit beside a stale five-thousand-block gap. The bar-filling rule gains a second half: a run
that never entered the watch (including a node found already at the tip) keeps
the existing rule — earned endings fill — while a run that watched fills iff it
ended `caughtUp`: the only watched ending where the goal was actually reached,
and under a live-tip goal there is no "met early."

### 3.8 The long action can wait for the private network

When a run decides the private network is not ready, the shared routine starts
Tor and declines — a shape that starves on the most common automation topology:
a periodic run on a device iOS reclaims between runs kicks Tor, declines, and
dies mid-bootstrap — forever. A run carrying `privateNetworkGrace` (~90 s,
comfortably over a cold bootstrap) instead waits inside its window — *not* by
wrapping `waitUntilReady` in `withHardTimeout`: that helper abandons its work,
and `waitUntilReady` is a `@MainActor` poll loop whose `try?` sleep swallows
cancellation — the abandoned loop would spin on the main actor past the run
([research §4](./research.md)). The grace is a deadline-bounded poll in
`NodeRun`'s own loop shape: `Task.isCancelled` and `session.tor.isReady`
checked each pass, a cancellable sleep between, early exit when Tor leaves
`.starting`, `onProgress` writes throughout.

A Tor that readies does not jump to start — the run *re-decides*: node state,
device conditions, and the step itself are re-read, because ninety seconds is
long enough for the person to have started the node or the network to have gone
metered. Settings are deliberately *not* in that list — they were snapshotted
once at entry (T001, widened from `tor_enabled` alone to every key
`buildArguments` consults), so a mid-grace change applies to the next run
rather than re-scoping this one mid-flight — `bitcoin_network` included, whose
flip would otherwise start a chain the regtest gate never weighed and leave
`blocksSinceLastCheck` diffing against a snapshot of the old chain. A second
`waitForPrivateNetwork` verdict declines — the grace was spent. A Tor that never readies declines with the same `privateNetworkNotReady`
reason — the report vocabulary is unchanged. Waiting is also the more private
posture: the run never starts on a direct connection either way (ADR 0006's
floor). On the card the wait is another pre-watch stage inside the start-up
band; the short action passes no grace and declines instantly as today.

### 3.9 The long action pins its process

ADR 0005's correctness requirement — the daemon holds an exclusive lock on the
chain folder, so a second process starting against it is refused — is today
enforced only by the absence of an extension target: a build-graph fact, not a
constraint. iOS 27's `allowedExecutionTargets` makes it one the system honors,
and `SyncNodeLongRunningIntent` declares `.main` — ahead of any widget,
control, or App Intents extension; at a ~21-minute watch the silent version of
that failure is expensive. Only the long action takes the pin: Apple reserves
`.main` for code that genuinely needs the process, since forcing it defeats
extension-based execution and adds launch latency — and the short action's
whole budget is ~30 s, where that latency is a real change to a path FR-014
says is unchanged.

## Verification

All on a physical device, screen locked, per ADR 0008 — executed as the gated
Phase 6 in [tasks.md](./tasks.md):

- [ ] Node behind on signet: the watch runs, the bar visibly climbs from where
     start-up left it (not pinned near full), the detail line reads "block X of
     Y", and the run ends `stillSyncing` at the budget. (SC-001, SC-004)
- [ ] Node nearly caught up: the run ends `caughtUp`, the bar fills.
- [ ] Synced signet node restarted after a >24 h quiet stretch — IBD `true`,
     `blocks == headers`, tip past Core's own recency rule: the flat-window
     leash ends it `noProgress` in ~4 min — and when the next block connects,
     `ConnectTip` clears the flag and the run ends `caughtUp`. (SC-002)
- [ ] Fresh datadir or resumed-stale node: the watch enters on the IBD flag
     even before headers arrive, survives the header-download stretch without
     `noProgress`, keeps the bar at the band floor, and never ends `caughtUp`
     while the flag is set — the genesis-age tip keeps the flag set on Core's
     own rule, so a node that cannot fetch ends `noProgress` on `flatWindow`.
- [ ] A regtest node: the watch declines entry at the gate — no leash burned,
     no `noProgress` on a self-defined chain.
- [ ] First experiment, before the meter redesign: does a text-only write
     (`localizedAdditionalDescription`) satisfy the system's liveness check —
     `BGContinuedProcessingTask`'s expiration? Text-only, numeric-only, and
     both on a locked device — Phase 4's size depends on the answer.
- [ ] Node stopped from the app's own UI mid-watch: the run ends on the normal
     measured report — earned outcome, last good reading, `syncResult` =
     `nodeStopped` — never a blanked `noAnswer` or a false `noProgress`.
- [ ] Node comes up unable to reach a single peer: the run ends `noProgress` on
     `flatWindow` (~4 min) rather than burning the whole budget. (SC-003)
- [ ] Tor enabled and cold on a locked device: the run waits through bootstrap
     inside the grace and proceeds — and a Tor that never readies declines with
     the unchanged `privateNetworkNotReady` reason, leaving no abandoned poll
     loop spinning on the main actor.
- [ ] During the grace, conditions drift (network goes metered, or the person
     starts the node from the app): the post-grace re-decision declines or
     reports accordingly rather than starting on a stale snapshot.
- [ ] A node answering every question in ~11 s produces advancing readings —
     the only kind that resets the leashes — and is never `noProgress`.
- [ ] A node the run started whose stored tip is hours old but under a day —
     the warm restart: the first answer shows flag clear and no gap, yet the
     tip-age leg still enters the watch, and when the fetched gap closes the
     run ends `caughtUp` rather than an early `notMeasured` return. The device
     pass needs the phone left idle for hours beforehand — its own T024 item.
- [ ] The warm restart on a quiet signet — headers never advance because
     nothing new exists: at least two outbound block-serving peers report
     `synced_headers == headers` and the run ends `caughtUp`, not
     `noProgress` — on signet's small network, check the daemon's outbound
     set is actually populated before reading the result. (SC-002's
     quiet-past-a-day sibling keeps `noProgress` — past 24 h Core asks only
     one peer, so two can never confirm.)
- [ ] The same quiet-signet shape with no qualifying peers — none connected,
     none answering, or only inbound ones — ends `noProgress` on `flatWindow`:
     no confirmation is no evidence.
- [ ] Network pulled mid-watch: ends `noProgress` ~2 minutes after the last gain —
     the designed ending, not a generic system timeout. (SC-003)
- [ ] Node already running on a metered link — or a device under the disk
     floor — when the long action fires: the `reportExistingNode` path consults
     no preflight, so the entry weigh-in ends it `conditionsChanged` before the
     watch commits, node left running.
- [ ] Handoff to a metered link mid-watch: early `conditionsChanged` end,
     honest wording, node running.
- [ ] Device warms mid-watch: `.serious` changes nothing, `.critical` ends
     `conditionsChanged`; Low Power Mode already on at entry changes nothing,
     switched on mid-watch ends it `conditionsChanged`; wording names the
     condition, node left running.
- [ ] A run ending `stillSyncing`/`noProgress`/`conditionsChanged`: the card
     resolves as ended rather than hanging at ~95% — `Progress.isFinished`
     stays false by design on these endings, and if the card sticks, the
     honest-bar rule needs a different expression.
- [ ] Stop button mid-watch: `CancellationError` thrown, node keeps running.
- [ ] `syncResult` — the report's new `AppEnum` `@Property`, `notMeasured`
     included — renders and branches correctly in the Shortcuts UI.
- [ ] The short action on the same build behaves exactly as before. (SC-005)
- [ ] The watch's detached-task cost measured, not assumed: ~360 `Task.detached`
     spawns per run — a work task and a timer task per bounded question — none
     inheriting the background task's QoS; observe memory and energy on a
     locked run.
- [ ] The serving transport is logged per poll — a `noProgress` or slow verdict
     attributes to a 30 s or a 60 s ceiling; the timings feeding T025's ADR
     0008 re-measure are meaningless without it.
- [ ] ADR 0008 timings and ADR 0009 survival re-measured and the records
     updated.

## Risks

- **The system's patience with a ~21-minute run is unpublished** — the ~30 s
  silence rule is `BGContinuedProcessingTask`'s documented expiration
  behavior; the total ceiling is not. Mitigated by construction: the run
  bounds itself and a fresh progress write is guaranteed every ~5 s for the
  whole window by §3.4's mechanism. The ~21-minute figure is the one ceiling
  the three stage constants are reviewed against. No API lever for a longer
  window exists — recorded in [research §4](./research.md) so nobody re-opens
  it.
- **A dithered tick may not count as liveness.** If the system only credits
  *increasing* counts, the run dies at ~30 s of silence despite fresh writes —
  caught by the first locked-device experiment, with the ratchet fallback
  already specced in §3.4.
- **The tip outgrowing the bar.** Fresh headers grow the denominator mid-watch;
  the never-retreat floor holds the bar while the detail line reports ground
  truth.
- **A mid-watch suspension lands as a giant delta.** A frozen process resumed
  later ends instantly on `noProgress` or `stillSyncing`. Correct, not a bug — the
  in-process daemon froze for exactly as long. Noted so nobody "fixes" it.
- **A synced node whose IBD flag never clears.** Reported honestly, not
  certified around: the flag is Core's own verdict, and the only state where
  it stays set with a recent tip is a `LoadingBlocks` skip (a reindex or
  import the app cannot produce — [research §3](./research.md)). A quiet
  chain whose flag never clears still ends `noProgress` — peer confirmation
  cannot certify past a set flag; the flag clears on the next connected
  block. A
  fresh datadir still ends `noProgress` on the genesis-age tip.
- **`NodeRun` is shared.** The short action passes `nil` budget and takes the
  same code path as today; the regression surface is the new stage's entry
  condition, covered by tests on the decision functions.
- **The feature certifies the foundations it stands on.** The leash and
  budget constants rest on ADRs 0008 and 0009, both still `Proposed` — and
  T025's locked-device re-measure is what moves them to `Accepted`. A
  measurement that disagrees reopens the constants, not just the records;
  the slicing table marks the dependent slices provisional for exactly this
  reason.
- **A dead node could pile up abandoned questions.** It cannot — for a reason
  that splits cleanly per transport. The poll loop is sequential (ask, answer
  or timeout, sleep to the next tick), so nothing overlaps unless a call is
  abandoned; on the direct bridge the ~30 s budget equals the give-up, so an
  orphan parks ≈0 s; over HTTP — the expected locked-device path — the 30 s
  orphan is *cancelled*, `URLSession` being the one transport
  `withHardTimeout`'s `work.cancel()` reaches. Neither path accumulates;
  T016's re-derived comment records both halves.

## Deferred work

- **AssumeUTXO bootstrap** — the real answer to IBD-scale gaps on a phone; a
  package-level feature, not an action feature.
- **Idle-time sync via `BGProcessingTask`** — a different API from the
  `BGContinuedProcessingTask` this feature's runs ride: opportunistic,
  idle-time work versus user-initiated continued processing. Same prerequisite
  noted in 003: the Background Modes capability and a task identifier.
- **Surfacing the measured report when the system ends a run on `.timeout`** —
  `CancellableIntent`'s throw discards it (`syncResult`, `blocksGainedThisRun`, the
  last good reading); recovering it needs a report channel that survives the
  throw.
- **Non-isolated `perform()` with explicit `MainActor.run` hops** — Apple's
  recommended intent shape; it would take the watch's ~180 poll iterations
  off the main actor and remove the grace-loop hazard at its root rather than
  working around it. Touches every `NodeSession` caller — bigger than this
  feature.
- **A guard for retried runs** — `restartPerform` re-runs the whole ~21-minute
  pipeline per attempt and nothing bounds the count; the pre-run snapshot
  already timestamps the last attempt, which is enough to detect (and decide
  on) a just-finished run.
- **Stopping a run-started node on metered drift** — a posture change that
  deserves its own ADR.
- **Free-space re-check mid-watch** — same mechanism as the network re-check;
  deferred because the approved scope was the driftable conditions.
- **Lazy direct-bridge re-bootstrap** — `Daemon.bootstrap` is a one-shot ~30 s
  poll fired once (fire-and-forget) inside `NodeViewModel.start`, and
  locked-device block-index loads measure 47–121 s, so it can time out and
  leave the node answering over HTTP for its whole life. Two closes of
  different sizes: the transparent version — the bridge quietly retrying
  while `bitcoin_rpc_ready() == 0` — is package work; the explicit version —
  a guarded second `Daemon.bootstrap` call — is action work (`Daemon.bootstrap`
  is public; the app already calls it). 004 is the first feature for which
  "HTTP for life" is the expected case, so this item now determines the
  watch's entire cost model, and the watch hands it a trigger it never had:
  the first successful reading proves the RPC server is up — exactly the
  condition bootstrap polled for. One guarded attempt there converts the
  remaining ~179 loopback round trips into in-process calls for a single
  `_bridge_init`. Until it lands, §3.3 designs for HTTP, not the bridge.
- **Grace for the short action** — declined: its ~30 s window cannot afford a
  cold bootstrap.

## Division of labor

Every decision — the fraction, stall, ending choice, wording — lives in
`NodeAutomation` as plain values, unit-tested on every platform in CI.
`NodeRun` orchestrates: it polls, it measures, it writes the card. Anything
touching the system's patience, the card, or suspension is verifiable only on a
locked device — the gated Phase 6 session, which also re-measures ADRs 0008 and
0009.
