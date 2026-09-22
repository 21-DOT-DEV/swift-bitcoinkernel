---
feature: 004
title: The long-running action watches the node sync toward the tip
phase: null
status: Planned
updated: 2026-09-20
adrs: []
---

# The long-running action watches the node sync toward the tip

The iOS 27 "Keep Bitcoin Node Syncing" action currently spends its extended window
waiting for the node to answer its first question, then returns — its progress bar
describes only start-up. This feature gives the run a third stage: once the node has
answered and is behind the known tip, the run stays alive inside its budget and
watches blocks arrive, driving the card with real sync progress ("block 843,210 of
915,000") until it is caught up, out of time, stalled, or stopped. Demo-app work, no
roadmap phase. Builds on the shared run built in
[003](../003-node-automation-action/plan.md); every rule it set — one routine both
actions call, decisions as testable free functions, honest endings, the node left
running — still holds.

Two findings shape everything below. There is **no published ceiling** on the
extended window: the system ends runs that stop reporting progress or that hit
resource pressure, so a run must bound itself. And a block is not a unit of time:
`assumevalid` makes most of the chain nearly free while the recent tail carries
~90% of validation cost on constrained hardware, so the number of blocks that fit a
safe window cannot be fixed — it must be measured.

## 1. Goal & success criteria

- The card's bar advances with real blocks and its detail line carries the absolute
  position; nothing on the card claims progress the node did not make.
- Every run ends on its own terms — caught up, budget spent, conditions
  changed, stalled, or stopped — and the ending it reports is the one that
  happened, with `blocksGained` saying what the run itself earned.
- A following automation step can branch on how syncing ended
  (`caughtUp`/`stillSyncing`/`stalled`/`nodeStopped`/`conditionsChanged`)
  without any existing field changing meaning.
- A run that drifts onto a metered or data-restricted network — or into the heat
  or battery-saver states a start would have been refused for — ends early
  rather than spending what the person did not agree to; no run ever stops the
  node.
- The short action's behaviour is unchanged in every case.

## 2. Scope

**In scope:** the sync-watch stage inside `NodeRun` (orchestration only); the
bounded private-network wait on the same routine (§3.8); the
decisions it consults in `NodeAutomation` (the live-tip fraction, stall, ending
wording); the
new `syncResult` field and its `NodeSyncResult` enum on `NodeRunReport`; the card
wording for the new endings; the constants on `SyncNodeLongRunningIntent` (budget,
grace, both stall thresholds, the watch question budget, the meter scale); tests
for all of it.

**Out of scope:** any change to `SyncNodeIntent` (it passes no budget and sees none
of this) · stopping the node on any condition (§7) · AssumeUTXO or any faster
bootstrap (§7) · the sister KernelApp's action · a background-processing task for
idle-time sync (§7).

## 3. Design

### 3.1 A third stage in the one routine

`NodeRun.perform` gains two optional durations — `syncBudget` and
`privateNetworkGrace`, both default `nil`. Every existing path is unchanged but
one (§3.8): the watch begins only after a path lands on a live
reading — a just-started node that answered, a still-starting node that answered, or
an already-running node that was read — and only when a budget was passed *and* the
node says it is still syncing: its own `initialblockdownload` flag set, or a header
gap open — *and* the chain has a network to compare against: `chain ==
"regtest"` never enters, since a self-defined chain is definitionally at its
own tip and a peerless regtest node would otherwise burn the `flatWindow`
leash to `stalled` on every run. The flag is the gate rather than the gap alone because a node that has
not yet fetched fresh headers reports a gap of zero — on a first-ever start or a
resume against a stale chain, `blocks == headers` is true precisely when the node
has not yet learned how far behind it is, and the flag is the only honest
"not synced" signal. `LiveReading` gains the flag — `SyncSummary` already computes
it and the reading simply keeps it — along with everything the watch needs. A run
that declined, got no answer, or found the node finished (flag clear, no gap)
returns exactly as today. `SyncNodeIntent` passes nothing,
so its behaviour is byte-identical; the routine stays one.

### 3.2 The bound is time; the target is blocks

The run's watch ends on the first of:

- **Caught up** — two independent proofs, either suffices. The flag proof: the
  node's `initialblockdownload` flag clears *and* the gap is closed
  (`blocks == headers`, re-read each poll) — the flag is required here because
  height-equality alone is also true before fresh headers arrive, and a resumed
  node would otherwise declare itself caught up against a stale tip. The peer
  proof: a flat `blocks == headers` window where every established peer has
  no work outstanding for us (no `inflight`, no `presync`) *and* our tip is
  still recent — §3.5's rule — needed because the flag answers "should
  you trust this chain yet," not "is there work outstanding": it latches
  per-process on a 24-hour tip-age rule, so a synced node restarted while its
  tip is more than a day old reports IBD `true` with nothing left to fetch —
  an edge case (a *normal* restart latches the flag clear at init), but a
  real one on signet's longer miner stalls, which are the chain §5 verifies
  against. The evidence is deliberately not "what did peers announce" —
  a peer with nothing newer announces nothing (`pindexBestKnownBlock` only
  populates from real announcements, so `syncedHeaders` reads `-1` on exactly
  the healthy connections this proof exists for); it is Core's own leave-IBD
  test evaluated live — a recent tip plus connected peers with nothing in
  flight for us — rather than latched once at init.
- **Budget spent** — a wall-clock budget counted from the first answer. Fifteen
  minutes is the starting constant, re-measured with the screen locked before it is
  trusted (ADR 0008's rule). Total worst-case run is preflight + private-network
  grace + first-answer wait + budget ≈ 21 minutes.
- **Stalled** — §3.5; `unproductive` trips on nothing advancing while known
  work stands undone (~2 min), or `flatWindow` trips (~4 min flat and never
  once peer-certified — never peered, connectivity too broken for any peer to
  announce, or peers announcing heights beyond ours that never arrived).
- **Conditions drifted** — §3.6.
- **Stopped** — the existing `onCancel` path, unchanged.
- **Node stopped** — someone stops the node from the app while the watch runs.
  The poll loop checks `isStoppedOrStopping` at the top of each pass and again
  before accepting each answer — the same re-check every existing question
  makes, so a stop that lands mid-question discards the answer rather than
  feeding it to the watch — deliberately separate
  from `Task.isCancelled`, which keeps the existing cancel path — and it does
  *not* take the no-answer path: that path blanks every measured field and
  stamps `noAnswer`, which would discard an hour of real gains and write a
  sync-axis event over the outcome axis. The run ends on the normal measured
  report — the earned outcome, the last good reading — with `syncResult` =
  `nodeStopped` and wording that says the node was stopped, not left running.

### 3.3 The goal is the live tip itself

The bar needs a target, and the honest one is the thing the feature was asked
for: the current tip, re-read each poll. A rate-projected endpoint was
considered and rejected — the algebra degenerates. For the case the feature
exists for (a node that cannot catch up inside the budget, so the projection is
what binds), `goal = h₀ + rate·B` gives `fraction = (h − h₀)/(rate·B)` — and any
estimator that converges to the true rate makes that `rate·(t − t₀)/(rate·B) =
(t − t₀)/B`: a clock wearing a progress bar's clothes, *most* clock-like exactly
when the estimate is good. A trailing window only produces a lagged clock. So
there is no estimator:

```
fraction = (h − h₀) / max(liveHeaders − h₀, 1)
```

- A node that will catch up sweeps toward the working ceiling as `h` closes on
  `liveHeaders` — then the IBD-clear + equality check fires `caughtUp` and the
  ending fills the bar.
- A node that cannot catch up shows the truth: distance closed this run over
  the distance remaining when it began — small, real, never clock-like. The
  detail line carries the absolute position, so a single-digit bar beside
  "Block 845,350 of 916,800" reads as "far behind," not broken.
- The denominator is live: fresh headers arriving mid-run grow it, which can
  pull the true fraction down — the meter's never-retreat floor absorbs the dip
  while the detail line keeps reporting ground truth. A reorg below the run's
  baseline clamps the numerator at zero the same way.
- While the node knows no gap yet — `liveHeaders ≤ h₀`, the cold-IBD window
  before first headers — the bar holds at the band floor and the heartbeat
  keeps the run alive: nothing measurable is moving, and nothing claims it is.

`verificationprogress` was considered for the fraction and rejected: it is a
transaction-count estimate whose denominator is extrapolated from *wall-clock
time*, so it sits under 1.0 forever at the tip and can even drift downward on a
fully synced node (bitcoin/bitcoin#28847, #31127, #26433) — non-monotone, and
its growth-rate assumption is calibrated to mainnet, which makes it misleading
on the signet this feature is verified against. Height over the live tip is
both the honest fraction and the one the feature was asked for.

The watch asks `blockchainInfo` every ~5 seconds, and `peers()` only on flat
readings — the seam `DashboardDataSource` already exposes, so no protocol
widens. Each
question carries two bounds: `watchQuestionBudget` (~30 s — the watch's own
patience, deliberately not a match to any transport's: `HTTPTransport` rides
`URLSession.shared` at the 60 s system default and the direct bridge gives up
at 30, so whichever bound fires first ends the wait — and a question
unanswered this long is stale for a 5-second cadence anyway. The 10 s
`questionBudget` is shaped for the short action's ~30 s window, and a node
answering consistently in 11 s is slow, not dead), and the *remaining watch
budget* — `min(watchQuestionBudget, remaining)` — the clamp `awaitFirstAnswer`
already documents, inherited here so the sync budget is a real bound rather
than soft by a whole pass. The leashes' resolution is the pass cadence:
"120 seconds" resolves to 2–3 passes — stated so the constant is not
over-trusted.

The tip is a *display target*, never an ending condition: only `caughtUp`'s
two proofs — flag-clear + equality, or peer certification — end a run on it,
since a tip can still be stale, and missing it at budget's end is simply what
`stillSyncing` reports.

### 3.4 What the card shows

On entering the watch the headline becomes "Syncing the Bitcoin node" and the detail
line carries the absolute position — `Block 843,210 of 915,000` — refreshed with
each gain. The bar's honesty rules: never backwards; a tick keeps the count
fresh without ever posing as earned progress — under the dither it cannot lift
the bar at all — and only an earned finish fills.

The watch shares one bar with the stages before it, and the never-retreat rule
makes that load-bearing: a completed reading already writes `1.0` and the start-up
writes reach `0.9`, so a sync fraction starting near zero would be silently
discarded for the whole watch — the person would see a bar pinned near full while
the node grinds. A run carrying a `syncBudget` therefore maps its stages onto
bands — a `NodeAutomation` pure function — so every stage's writes land above
whatever came before: every pre-watch write — the fixed milestones and the smooth
first-answer ramp alike — compresses into the first ~10%, and the watch's distance
fraction sweeps from there up to the working ceiling (~95%). With no budget the
writes keep the full range — the short action has no card at all, and nothing it
emits changes.

Liveness likewise stops being a hope and becomes construction. The system grants
the extended window on one condition — progress keeps arriving; silence ends a
run at roughly thirty seconds — *documented*, not folklore:
`IntentCancellationReason.timeout` states it plainly, and only the total-run
ceiling stays unpublished (§6) — and the count is the signal every Apple
example demonstrates — and
a `tick()` only counts
when it can write a *new* value. Two reachable states exhaust the current meter:
the 50-notch heartbeat budget drains in ~4 minutes of accumulated silence —
ticks are skipped only when a real report just landed, so a Tor IBD path whose
gains arrive minutes apart spends the whole budget in a couple of gaps — and
once the bar sits at the
`scale − 1` ceiling — the "nearly caught up, then gone quiet" case — every tick
writes
the same value and the run dies ~30 seconds in as a generic timeout instead of its
designed ending. A monotonic tick into a reserve has a subtler third: once ticks
have ratcheted `reported` above `advance()`'s cap, no earned gain can ever show
again — and during a stall the bar visibly creeps toward full while nothing is
earned. So the meter's unit space grows (`scale` ≈ 10,000 — units are
arbitrary per Foundation's own guidance, and byte-scale counts are the canonical
case), `advance()` caps at `scale − 1 − reserve` (~95%), and `tick()` *dithers*
rather than ratchets: it writes whichever of the two absolute values `earned`
and `min(earned + 1, scale − 1)` is not currently standing — always distinct,
since `advance()`'s cap keeps `earned ≤ scale − 1 − reserve` — a fresh integer
on every call, never accumulating, never stranding earned progress beneath it.
The dither costs
the meter one split: its write floor moves from `reported` (which today forbids
any downward write) to `earned` — the monotone track of real progress — so a
tick can dip one sub-visible notch and recover, while no earned advance is ever
written backwards. The reserve stays ≈500 notches so the ratchet fallback needs
no re-layout — headroom, not a consumable: the dither never wanders more than a
notch from the frontier, so nothing drains it, and the `heartbeatUnits`
contribution cap goes with it. Its cost is stated plainly: a ~95% working
ceiling instead of ~99.99%, paid so the fallback stays a fallback rather than a
redesign. If device verification shows the system counts only
*increasing* writes as liveness, that fallback — a ratchet bounded inside the
reserve — is the shape this replaced, trading the two invariants back for
certainty.

The card's words need the same invariants the numbers have. Today the meter
writes `localizedDescription`/`localizedAdditionalDescription` only at
`finish()`, and `onProgress` carries a bare `Double`. The meter gains
headline/detail writes on the underlying `Progress`, and the run's progress
callback widens to a small value type — fraction, headline, detail — so the
watch can push "Block X of Y" wording, not just numbers. Two rules mirror the
numeric channel's: `finish()` makes *all* writes final — a flag gates text and
count alike, so a heartbeat landing after the ending cannot overwrite it — and
the detail is one composed sentence, not two competing for a line: the position
clause always ("Block 843,210 of 915,000"), with a staleness clause appended
once the run has been flat long enough to be worth saying ("…, last gain 3 min
ago") — an extra `Progress` property write for the system besides, though the
liveness guarantee stays the numeric channel's job.

### 3.5 Stall: when no new block is the answer

A watch that cannot gain is done — and a watch that can prove there is nothing
left to gain is done *successfully*, which is what `certified` exists to tell
apart. The state is three quantities, all *accumulators*, never a timestamp
difference: a first-ever start has never produced an advancing reading, so a
since-last-gain clock would already read minutes when its headers land and
would declare a stall exactly as real work begins.

Each pass feeds exactly one accumulator — `certified` taking the flat no-gap
passes it earns in place of `flatWindow` — chosen in order:

- An *advancing* reading — `blocks` or `headers` higher than the best yet seen —
  resets all three and feeds none. Advancing **headers** count as gain: during
  header fetch the blocks are legitimately frozen while the gap opens, and
  ignoring that movement is what would declare a healthy IBD stalled.
- No fresh reading at all feeds `unproductive` — **120 seconds** — whatever the
  last peer answer said: a node answering nothing is dead to the watch
  regardless of what it last claimed.
- A fresh reading with nothing advancing feeds `unproductive` only when the
  node has shown work it is not doing — `headers > blocks`, with peers known
  connected (≥ 1) *or unknown*. Everything else flat feeds `flatWindow` —
  **~240 seconds** (a flat no-gap pass with *full* peer evidence feeds
  `certified` instead — below) — because neither of its states can be expected
  to move:
  peers *known zero* — the ordinary cold-start connect, which over Tor can run
  well past two minutes — and an IBD-flagged node that has learned no gap yet
  (`headers ≤ blocks`), whose first `getheaders` over a cold circuit is work
  that cannot produce block movement. Pricing either at the `unproductive`
  trip would fail the run's most common first-ever path — the case this watch
  exists to survive.

Inside a flat, no-gap window the watch also accumulates `certified` — and the
evidence is Core's own leave-IBD test evaluated live, not anything a peer must
volunteer. A peer with nothing newer *announces nothing* — `pindexBestKnownBlock`
only ever populates from real announcements (non-empty headers, `inv`,
`cmpctblock`; an empty `getheaders` reply returns before the update site), and
peer state is per-connection, so every restarted synced node's `syncedHeaders`
read `-1` indefinitely. What the watch can actually see is work we initiated
and freshness we already hold. A flat no-gap pass earns `certified` seconds
when all of:

- at least one *established* peer (`connectionType` resolved with the same
  fallback the dashboard already uses — `peer.connectionType ?? (peer.inbound
  ? "inbound" : "outbound")` — then excluding `feeler`/`addr-fetch`, which
  are short-lived and never serve, so an unfiltered read would break the
  streak on every ~2-minute churn tick);
- no peer has block requests outstanding (`inflight` empty) — work in flight
  is work outstanding regardless of what heights say;
- no peer is mid low-work sync (`(presyncedHeaders ?? -1) == -1` — the field
  is `Int?`, and `nil` must read as "not presyncing," not fail the clause);
- the tip is still recent — `blockchainInfo.time` (already in `ChainSummary`)
  within a generous window, days rather than the flag's 24 h — because a tip
  older than the window cannot be told from "connected to peers that serve
  nothing": the one ambiguity recency cannot resolve, so a chain quiet past
  the window ends `stalled`, the safe direction. A fresh datadir fails here
  by construction — its tip is the genesis timestamp — which is the
  discrimination this clause exists to make.

`certified` is a consecutive streak ending `caughtUp` at **≥ 60 s *and* ≥ 6
qualifying passes** — the pass floor matters more here than on the leashes,
because this is the success verdict and a ~30 s pass budget makes "60 s"
reachable in two or three samples. A flat-window pass failing a clause —
no established peers, work in flight, presync running, stale tip — breaks
the streak to zero and feeds `flatWindow` instead. An *absent* peer answer
(the question timed out while the chain still answered) is no evidence either
way: it holds the streak *and* withholds the pass from `flatWindow`, so a
watch whose peer question goes permanently quiet runs to `stillSyncing`
rather than convicting a node it cannot see.

The leashes end `stalled`: `unproductive` at ~2 minutes, `flatWindow` at ~4 —
which now only ever means failure: a node that stayed unmovable without once
showing it is current. The fresh-datadir false positive dies on the *tip-age*
clause — a fresh node's tip is the genesis timestamp, which no recency window
admits — while the restarted-and-synced node has a tip the network built
recently enough to prove currency. The peer question is asked only on flat
passes — `getpeerinfo`
takes `cs_main` once per peer row, contending with the block connection the
watch exists to let proceed, and an advancing reading discards the answer
entirely — so during healthy sync the watch asks it never at all. And it
backs off when it cannot answer: an absent answer is already defined as no
evidence either way, so after ~3 consecutive peer-question timeouts the watch
stops asking it for the rest of the run — a question that has proven it will
not answer is pure cost, and dropping it restores the ~30 s pass ceiling in
the one degraded state that would otherwise pay ~60 s per pass and resolve
the `unproductive` leash on two samples instead of three. The 120 s figure sits
deliberately inside Bitcoin Core's own recovery gap — during deep download the
node drops a stalling peer in 2–64 s (`BLOCK_STALLING_TIMEOUT_DEFAULT`/`_MAX`),
and near the tip the fallback takes ~10 minutes per stalled block
(`BLOCK_DOWNLOAD_TIMEOUT_BASE` plus ~5 minutes per parallel peer) — so what peer
churn can fix resolves inside the leash, and what it cannot is dead peers, a
lost network, a wedged validation thread. One honest edge, kept deliberately:
a mid-watch reorg reads as flat and feeds `unproductive` even while the node
refills — no forward progress *is* happening; counting a changed
`bestblockhash` as activity is the optional refinement, not a requirement.

### 3.6 Conditions at entry and mid-watch

Two paths reach the watch having never weighed preflight —
`reportExistingNode` and `waitForStartingNode` — and a fifteen-minute watch is
not the quick read that exemption was written for. Before the watch commits,
the run weighs the full `refusal(for:)` once — power conditions included,
which needs the tested type to carry the granularity both policies use:
`DeviceConditions.overheating` is `.serious || .critical` collapsed to a
`Bool`, so it gains the `thermalState` itself; entry keeps refusing at
`.serious` while the drift check reads `.critical` from the same field — no
passing power conditions in as healthy, which would also have let a
`.critical`-at-entry device on `reportExistingNode` drift out on pass one
instead of being refused at the weigh-in. The gather stays narrow even here:
a running or starting node proves the chain folder exists, so
`prepareChainFolder()` is not re-run, `freeDiskBytes()` reads directly, and
the network answer comes from `NetworkCostMonitor.shared.current`. A refusal
ends the run `conditionsChanged` with the condition named — the disk floor
matters most: "filling the disk is far worse than skipping a run," and a node
writing blocks for fifteen more minutes is exactly what the floor protects.

Mid-watch, two kinds of condition get two rules. The money conditions —
metered, Low Data Mode — are absolute, checked every pass from the first: they
spend something continuously and are never consented to anywhere in the app,
so a watch that finds one ends the same pass. The power conditions differ
because of what they are. Low Power Mode already on at entry is a *standing
preference* — ending on it would silently remove the feature for everyone who
leaves it on, on every single run — so it ends the watch only if switched on
mid-watch. Thermal stays absolute but only at `.critical`: a thermal emergency
gets no fifteen-minute watch, while `.serious` — reached routinely by fifteen
minutes of validation on a locked phone — never ends it, or the headline
behavior would be "runs four minutes, then stops because the phone got warm."

The per-poll read is a narrow gather, deliberately not `readConditions()`:
that routine does two things a ~180-pass watch must not — `prepareChainFolder()`
is a filesystem write, and its network read waits on `NetworkCostMonitor.first()`
behind a two-second timeout, adding a suspension point to every poll. The watch
reads `NetworkCostMonitor.shared.current` — never waits; the monitor has long
since reported — plus `thermalState` and `isLowPowerModeEnabled`, and nothing
else.

On drift the run ends early with its own ending: `conditionsChanged`, a fifth
`NodeSyncResult` case, not `stillSyncing` — budget-spent means "run me again
now" and drifted-unsafe means "back off," and an automation can only branch on
what it can name. The wording is likewise the watch's own: `Refusal`'s
sentences all end "so the node did not start," which a mid-watch ending would
make a lie — the node did start, is running, and is left running. Ending the
run is not entirely consequence-free either way: `perform` returning lets the
app suspend, which freezes the in-process daemon — so a `.critical` abort does
relieve the device, indirectly. Stopping the node is deliberately not here —
it is a new act that needs its own ADR (§7). Files and disk stay preflight-only
past the entry weigh-in: they cannot drift the way the four can, and a
free-space re-check was explicitly deferred (§7).

### 3.7 The report's vocabulary grows on a second axis

`outcome` is untouched — it keeps meaning *what the run did to the node*
(`started`/`alreadyRunning`/…), the distinction ADR 0005 relies on. The sync ending
is a separate, orthogonal fact, so it is a separate, additive field:

```swift
@Property(title: "Sync result") var syncResult: NodeSyncResult?
```

`NodeSyncResult` is an `AppEnum` — `caughtUp`, `stillSyncing`, `stalled`,
`nodeStopped`, `conditionsChanged` — with explicit raw strings and a
completeness test, following the
slice-6 pattern: append only, pinned text, a test that every case has display
wording. `nodeStopped` names exactly what it means — the node was stopped
mid-watch (§3.2) — because the other reading, "the run was stopped," cannot
occur: a run-stop is a thrown `CancellationError` and produces no report to
carry a case. The field is `nil` whenever the run has no sync answer to give —
declined before the weigh-in, no answer before the watch, still coming up,
every short-action run — so the report's absent-means-not-measured discipline
holds; an entry-weigh-in refusal is the one pre-watch ending that does carry a
case (`conditionsChanged`), since the weigh-in is already the conditions
mechanism answering. A watched run also gains
`blocksGained` — heights earned while this run watched — because
`blocksSinceLastCheck` keeps its existing meaning (measured against the pre-run
`lastKnown` snapshot) and a fifteen-minute watch would otherwise leave that
field answering two questions at once. `lastKnown` itself keeps its
run-boundary discipline: written once at report time, never per-poll — a
killed run persists nothing, so the next run's delta spans the whole gap,
which is the honest answer since no report ever claimed those blocks; and a
*retried* run reads the same pre-run snapshot, so a system retry reports the
full delta rather than ≈0 against its own abandoned attempt's writes.
`blocksGained` is the field an automation reads for this run's answer. A run that watched
builds its report from the *final* poll's reading, not the first answer's —
otherwise the height and blocks-behind figures describe a moment a quarter-hour
old, and a `caughtUp` verdict would sit beside a stale five-thousand-block gap,
contradicting itself on its face. The bar-filling rule the end
card consults gains a second half: a run that never entered the watch — including
a node found already at the tip — has no goal, and the existing rule stands
(earned endings fill, so the caught-up node still gets a full bar); a run that
watched fills iff it ended `caughtUp` — the only watched ending where the goal
was actually reached, and under a live-tip goal there is no "met early": only
the ending check knows the tip was truly reached.

### 3.8 The long action can wait for the private network

When a run decides the private network is not ready, the shared routine starts
Tor and declines — a shape that starves on the most common automation topology:
Tor lives in the app process, bootstrap takes ~5–60 seconds, and a periodic run
on a device iOS reclaims between runs kicks Tor, declines, and dies mid-bootstrap
— forever. A run carrying `privateNetworkGrace` (the long action passes ~90
seconds, comfortably over a cold bootstrap) instead waits inside its window —
but *not* by wrapping `waitUntilReady` in `withHardTimeout`: that helper
abandons its work on timeout, and `waitUntilReady` is a `@MainActor` poll loop
whose `try?` sleep swallows the cancellation — the abandoned loop would spin on
the main actor for as long as Tor's retry machinery keeps the state `.starting`,
long past the run. The grace is instead a deadline-bounded poll written in
`NodeRun`'s own loop — the `awaitFirstAnswer` shape: `Task.isCancelled` and
`session.tor.isReady` checked each pass, a cancellable sleep between, an early
exit when Tor leaves `.starting`, and `onProgress` writes allowed throughout.
A Tor that readies does not jump to start — the run *re-decides*: node state,
device conditions, and the step itself are re-read, because ninety seconds is
long enough for the person to have started the node from the app, or the
network to have gone metered. A second `waitForPrivateNetwork` verdict declines
— the grace was spent. A Tor that never readies declines with the same
`privateNetworkNotReady` reason, so the report vocabulary is unchanged. Waiting
is also the more private posture: the run never starts on a direct connection
either way (ADR 0006's floor). On the card the wait is another pre-watch stage
inside the start-up band; the short action passes no grace and declines
instantly as today.

## 4. Implementation steps

0. **Prerequisite, shipped on its own commit ahead of the feature:** thread the
   entry-time `privacyEnabled` snapshot through `startArguments`'s build closure —
   today `DaemonConfig.buildArguments` re-reads `tor_enabled` live, so a mid-run
   toggle can start the node on a direct connection while the pref says Tor.
   That is a live ADR 0006 hole, not a wart, and it deserves a reviewable diff of
   its own rather than riding inside a progress feature. The same commit stops
   the start-failure path from resurrecting a Tor the user just switched off.
1. `NodeSyncResult` AppEnum (five cases), the `syncResult` field and
   `blocksGained` on `NodeRunReport`
   (+ string-pinning and wording-completeness tests). Compile-check the
   optional `AppEnum` `@Property` on day one — `EntityProperty<Value>`
   requires `Value: _IntentValue` and the report's existing optionals are
   `Int?`/`String?`, so it is plausible but not free; better learned here than
   in §5.
2. `NodeAutomation`: `LiveReading` gains `isInitialBlockDownload` and `headers` —
   everything it holds still comes from one answer — while the peer answer
   stays its own value passed beside it: it answers a different question under
   its own budget, and absent ≠ zero matters now that zero ends a run. A `SyncWatchState`
   value type holds the watch's pure state — baseline height, best-seen heights,
   both stall accumulators, the `certified` streak (consecutive qualifying
   flat seconds — §3.5's clauses: established peers, no `inflight`, no
   presync, recent tip; trips at ≥60 s *and* ≥6 passes), and the
   entry-time Low-Power snapshot the delta check compares — advanced by
   `(instant, reading?, peersAnswer)` where the peer answer carries the count
   *and* each peer's `inflight`/`presyncedHeaders`/`connectionType` (absent ≠
   zero still matters), emitting
   the ending decisions; the
   watch-entry decision on the IBD flag; the two `caughtUp` proofs (flag-clear
   + equality; the ~60 s `certified` settle); the live-tip fraction
   `(h − h₀)/max(liveHeaders − h₀, 1)`; the §3.6 decisions — the one-time
   `refusal(for:)` weigh-in on paths that skipped preflight (thermal carried
   honestly as `thermalState` in `DeviceConditions` — no healthy-passed
   power conditions) and the per-pass split: money absolute, thermal absolute at
   `.critical`, Low Power Mode delta — returning the *condition*, not a
   sentence, since `Refusal`'s messages all end "did not start," true only at
   entry. Plus the stage→band card-fraction map from §3.4 and the
   summary/ending sentences for the five endings — `caughtUp` carries two
   wordings, flag-cleared vs peer-certified (+ tests).
3. `NodeRun`: the §3.8 grace poll and post-grace re-decision on the
   private-network path, and the watch stage — poll loop asking the chain
   question every pass and `peers()` only when it comes back flat, each
   bounded at `min(watchQuestionBudget, remainingBudget)` (~30 s ceiling, per
   §3.3's inherited clamp — the budget stays a real bound), the peer question
   backing off entirely after ~3 consecutive timeouts (§3.5),
   `Task.isCancelled`
   and `isStoppedOrStopping` consulted *separately* each pass — the first takes
   the existing cancel path, the second builds the `nodeStopped` report from
   the last good reading. The `previous` snapshot for
   `blocksSinceLastCheck` is captured *before* the watch on the
   `reportExistingNode` path — today `measuredReport` reads
   `lastKnownReading()` at its call site, and the app's own sync poll can
   overwrite `lastKnown` during a fifteen-minute watch — reporting ~0 for a
   run that watched real gains; the start/wait paths already capture early
   for the same reason. And `measuredReport`'s closing `onProgress(1)` is
   suppressed on a budgeted run — it lands after the watch and would pin the
   bar full on every ending, exactly the dishonesty the band map exists to
   prevent; `finish(_:)` alone decides whether the bar fills. The split lives inside the *budgeted* path only:
   `measuredReport`'s closing `answerIsStillWanted` guard runs unchanged for an
   unbudgeted run, so the short action's a node-stopped-mid-question still
   returns `noAnswer` — byte-identical means byte-identical —
   `persistLastKnown` at report time only — never per-poll, so a retried run's
   `previous` is the true pre-run snapshot rather than an abandoned attempt's
   last write — the §3.6 machinery — the one-time weigh-in before the
   watch commits on the paths that skipped preflight, then the split per-pass
   check, all via the narrow gather (never `readConditions()`) — the §3.5
   accumulators via `SyncWatchState`, and the progress/detail writes — ending on
   a report built from the final poll's reading — with every pre-watch write,
   milestones and the first-answer ramp alike, routed through the band map.
   `WithHardTimeout`'s pile-up comment gets its bound re-derived: the
   stall/nodeStopped endings cap abandoned calls near the documented figure,
   because a node that stops answering ends the watch within ~2 minutes. Its
   premise
   note also gets a line: pre-bootstrap questions ride `HTTPTransport` and are
   genuinely cancellable — the uncancellable shape is the post-boot bridge.
   While in this file: give `report()` the same `isStoppedOrStopping` pre-check
   `awaitFirstAnswer` already makes. Both new loops are generic over
   `C: Clock<Duration>` — not `any Clock<Duration>`, on which `clock.now`
   erases to a non-`Comparable` `any InstantProtocol` and cannot compare
   deadlines; `withHardTimeout` documents exactly this and supplies the
   overload pattern for the `ContinuousClock` default — so their sleeps and
   deadlines are drivable under a `TestClock`, the same reason
   `TorViewModel(clock:)` takes one. The clock enters at `perform` as a
   defaulted parameter and threads through `runWithHeartbeat`'s work closure —
   `awaitFirstAnswer` reads `ContinuousClock.now` directly today, so it gains
   the parameter too rather than mixing two clocks inside one run.
4. `ProgressMeter`: gated on §5's first device experiment — text-only writes
   versus numeric-only, both — because the redesign's whole purpose is a
   guaranteed-fresh numeric write, and Apple's own `LongRunningIntent`
   example writes `localizedAdditionalDescription` on every chunk alongside
   the count. If a text write alone satisfies the system's liveness check,
   the dither/reserve machinery is unearned: the staleness clause the detail
   line already carries is fresh on every poll at zero honesty cost, and this
   step shrinks to the text surface. If it does not: the §3.4 construction —
   `scale` ≈ 10,000, `advance()` capped
   at `scale − 1 − reserve`, the write floor split into `earned` (monotone — the
   honesty invariant) and `reported` (last written — may dither ±1 around it),
   `tick()` alternating `{earned, earned + 1}` at the frontier, its skip gate
   keyed on `earned` having moved — not `reported`, which a flat `advance()`
   can re-settle after a dither and thereby halve the liveness margin to
   alternate heartbeats — and the now-purposeless `heartbeatUnits` cap
   retired — plus the
   text surface the card needs (headline/detail writes on the underlying
   `Progress`) and the widened
   `onProgress` payload (a small value type: fraction, headline, detail) so the
   run can push wording, not just numbers (+ invariant tests: a tick at the
   working ceiling still writes a new value; a tick never strands earned
   progress beneath it; the dither stays inside `{earned, earned + 1}`; after
   `finish()` no write lands — text or count). The widened
   payload is shared: `SyncNodeIntent` compiles through the same signature — it
   passes no headline or detail, and its progress sink stays the default no-op.
5. `SyncNodeLongRunningIntent`: pin `static var allowedExecutionTargets:
   ExecutionTargets { .main }` — iOS 27's execution-target declaration turns
   ADR 0005's "runs in the app process" from a fact about today's build graph
   (no extension target exists) into a constraint the system honors if a
   widget, control, or App Intents extension ever appears. The same
   `@available(iOS 27.0, *)` declaration lands on `SyncNodeIntent` — a second
   process against the daemon's exclusive folder lock is refused at any run
   length, and a 21-minute watch makes the silent version expensive. Then
   pass `syncBudget` (the 15-minute constant),
   `privateNetworkGrace` (~90 s), `stallThreshold`/`flatWindowLeash`/
   `certifiedSettle` (120 s / ~240 s / ~60 s), `watchQuestionBudget` (~30 s),
   the larger `scale`, and flip
   the headline on entering the watch. Prerequisite: the target has no
   `.xcstrings` catalog and every existing sentence is a bare literal — adding
   one is part of this step. Localization then has two sinks, named so the
   distinction survives implementation: `String(localized:)` for the card text
   (`Progress`'s `localized*` properties are plain `String`s, resolved in the
   app's locale), and — for the *dialog* — a `LocalizedStringResource` built
   from the same values, so `IntentDialog` resolves in the requester's locale.
   The report's `summary` property stays `String` — it is an existing
   `@Property` other fields share, and re-typing it would break automations §3.7
   says must not. The "Block X of Y" detail is the feature's first
   formatted substitution — where localization stops being optional either way.
   Caveat to verify while wiring it: `AppShortcut` phrases may localize through
   a dedicated `AppShortcuts.xcstrings` rather than the general catalog — if
   that holds, the phrase-localization follow-up (003 §7) needs its own file
   and does not come along free with this one.
6. Re-point `heartbeatCoverageExceedsWait`: the budget-longevity coupling it
   guarded dissolves with the cap — under the dither nothing is drained — so the
   test becomes the dither invariant itself: a tick at any reachable state
   writes a value different from the last, for the whole of a maximum-length
   run. (If device verification sends us to the ratchet fallback, the test
   returns to sizing the reserve against the whole-window tick count.)
7. Re-measure ADR 0008's locked-device timings and ADR 0009's post-return survival
   in the same device session §5 requires, so both records can move off `Proposed`.

## 5. Verification

All on a physical device, screen locked, per ADR 0008:

- [ ] Node behind on signet: the watch runs, the bar visibly climbs from where
      start-up left it (not pinned near full), the detail line reads "block X of
      Y", and the run ends `stillSyncing` at the budget.
- [ ] Node nearly caught up: the run ends `caughtUp`, the bar fills.
- [ ] Synced signet node restarted after a >24 h quiet stretch — IBD `true`,
      `blocks == headers`, peers connected, tip recent: the watch ends
      `caughtUp` on certification — ≥60 s *and* ≥6 qualifying passes — never
      `stalled`, and `feeler`/`addr-fetch` churn or one missed peer answer
      does not break the streak.
- [ ] Fresh datadir or resumed-stale node: the watch enters on the IBD flag even
      before headers arrive, survives the header-download stretch without a
      `stalled` verdict, keeps the bar at the band's floor rather than leaping to
      a believed tip, and never ends `caughtUp` while the flag is set — the
      genesis-age tip fails the recency clause by construction, so a node
      whose peers connect but serve nothing ends `stalled` on `flatWindow`,
      not `caughtUp`.
- [ ] A node whose peer question never answers while its chain readings keep
      arriving flat: nothing accumulates (absent answers are no evidence
      either way), the question backs off after ~3 consecutive timeouts so
      passes stay at ~30 s, and the run ends `stillSyncing` at the budget —
      not `stalled` on a node the watch cannot see.
- [ ] A regtest node: the watch declines entry at the gate (`chain ==
      "regtest"` never enters) — no leash burned, no `stalled` verdict on a
      self-defined chain.
- [ ] First experiment, before the meter redesign: does a text-only write
      (`localizedAdditionalDescription`) satisfy the system's liveness check?
      Test text-only, numeric-only, and both on a locked device — the step-4
      diff depends on the answer.
- [ ] `inflight`/`presyncedHeaders` populate as expected on a live node (the
      two `getpeerinfo` fields the certification rule actually reads), and a
      peer with requests in flight or mid-presync fails certification.
- [ ] Node stopped from the app's own UI mid-watch: the run ends on the normal
      measured report — earned outcome, last good reading, `syncResult` =
      `nodeStopped` — never a blanked `noAnswer` or a false `stalled`.
- [ ] Node comes up unable to reach a single peer (network collapsed after the
      start checks passed): the run ends `stalled` on the `flatWindow` leash
      (~four minutes) rather than burning the whole budget to `stillSyncing`.
- [ ] Tor enabled and cold on a locked device: the run waits through bootstrap
      inside the grace and proceeds to start — and a Tor that never readies
      declines with the unchanged `privateNetworkNotReady` reason, leaving no
      abandoned poll loop spinning on the main actor after the run returns.
- [ ] During the grace, conditions drift (network goes metered, or the person
      starts the node from the app): the post-grace re-decision declines or
      reports accordingly rather than starting on a stale snapshot.
- [ ] A node answering every question in ~11 s — slower than the short action's
      `questionBudget`, inside the watch's own — produces readings, resets the
      accumulators, and is never declared `stalled`.
- [ ] Network pulled mid-watch: ends `stalled` about two minutes after the last
      gain — reliably the designed ending, not a generic system timeout.
- [ ] Node already running on a metered link — or a device under the disk
      floor — when the long action fires: the `.reportExistingNode` path
      consults no preflight, so the entry weigh-in ends it `conditionsChanged`
      before the watch commits, node left running.
- [ ] Handoff to a metered link mid-watch: early `conditionsChanged` end, honest
      wording, node running.
- [ ] Device warms mid-watch: `.serious` changes nothing (routine on a
      validating phone), `.critical` ends `conditionsChanged` whenever seen;
      Low Power Mode already on at entry changes nothing — the watch runs —
      and switched on mid-watch ends it `conditionsChanged`; wording names the
      condition, node left running.
- [ ] A run ending `stillSyncing`/`stalled`/`conditionsChanged`: the card
      resolves as ended rather than hanging at ~95% — `Progress.isFinished`
      stays false by design on these endings, and if the card sticks, the
      honest-bar rule needs a different expression than leaving the count
      short.
- [ ] Stop button mid-watch: `CancellationError` thrown, node keeps running.
- [ ] The report's `syncResult` — the first optional `AppEnum` `@Property` on
      this report — renders and branches correctly in the Shortcuts UI.
- [ ] The short action on the same build behaves exactly as before.
- [ ] ADR 0008 timings and ADR 0009 survival re-measured and the records updated.

## 6. Risks and mitigations

- **The system's patience with a ~21-minute run is unpublished** — the ~30 s
  silence rule *is* documented (`IntentCancellationReason.timeout`); the total
  ceiling is not. Mitigated by
  construction: the run bounds itself, and a fresh progress write is guaranteed
  every 5 seconds for the whole window by §3.4's dither — a tick at any
  reachable state writes a value different from the last — rather than by luck;
  a system timeout already has an honest card ending. The ~21-minute
  figure is the one ceiling the three stage constants — grace, first-answer
  wait, watch budget — are reviewed against, not three independent numbers. The
  budget constant is the tunable. No API lever exists for it either:
  `LongRunningTaskOptions` — the `options:` parameter — is an OptionSet with
  no public members surfaced (Apple's only example is GPU resources), so
  `options: []` is the only spelling and the run's own bound is the bound.
- **A dithered tick may not count as liveness.** If the system only credits
  *increasing* counts, the run dies at ~30 s of silence despite fresh writes —
  caught by the first locked-device pass in §5, and the fallback (a ratchet
  bounded inside a ~500-notch reserve) is already specced in §3.4.
- **The tip outgrowing the bar.** Fresh headers arriving mid-watch grow the
  denominator, so the true fraction can fall; the meter's never-retreat floor
  holds the bar while the detail line keeps reporting ground truth — the person
  sees "Block X of Y" move honestly even when the bar cannot dip.
- **A mid-watch suspension lands as a giant delta.** A frozen process resumed
  later hands the accumulators and the budget one huge `Δt` — the run ends
  instantly on `stalled` or `stillSyncing`. Correct, not a bug: the in-process
  daemon froze for exactly as long. Noted so nobody "fixes" it.
- **A synced node whose IBD flag never clears.** The flag latches per-process
  on a 24-hour tip-age rule — a normal restart of a synced node latches *clear*
  at init, so the stuck case needs a tip older than a day: regtest always,
  signet when its miners stall that long. Worth covering, but an edge — which
  is why the peer question is asked only on flat passes rather than paying
  `getpeerinfo`'s per-peer `cs_main` acquisitions on every poll forever.
  Certification still keeps that edge cheap: the run settles in about a
  minute instead of burning the leash — and it is Core's own leave-IBD test
  evaluated live (recent tip + peers + nothing in flight), because the
  announce-based fields cannot answer: a peer with nothing newer says
  nothing, leaving `syncedHeaders` at `-1` on precisely the healthy
  connections this case is made of. What still ends `stalled` is the
  unprovable version — a node that cannot show currency, including a fresh
  datadir whose genesis-age tip fails the recency clause. One corollary worth
  noting: opening the app mid-watch adds two more `peers()` pollers
  (`DashboardViewModel.refresh`, `NodeViewModel`'s own poll) — the same
  `cs_main` cost argument for keeping the watch's asks flat-only.
- **`NodeRun` is shared.** The short action passes `nil` budget and takes the same
  code path as today; the regression surface is the new stage's entry condition,
  covered by tests on the decision functions.
- **A dead node could pile up abandoned questions for ~21 minutes.** It cannot: a
  node that stops answering produces no fresh readings, and §3.5's `unproductive`
  clock counts *then too* — so `stalled` (or `nodeStopped`, checked every pass)
  ends the watch within ~2 minutes. Abandoned calls stay at the documented scale: two
  30-second questions per pass across a ~2-minute window is on the order of a
  handful — under the figure `WithHardTimeout`'s comment already claims.

## 7. Out of scope (follow-ups)

- **AssumeUTXO bootstrap.** Every mobile full-node deployment that claims a usable
  node in hours does it via a UTXO snapshot or a trusted chainstate copy. It is the
  real answer to IBD-scale gaps on a phone — and a package-level feature, not an
  action feature.
- **Idle-time sync via `BGProcessingTask`.** Same prerequisite noted in 003 §7:
  the Background Modes capability and a task identifier.
- **Stopping a run-started node on metered drift.** The stronger protection —
  fire-and-forget `stop`, only ever for a node this run started — is a posture
  change that deserves its own ADR rather than shipping inside this feature.
- **Free-space re-check mid-watch.** Same mechanism as the network re-check;
  excluded only because the approved scope was the driftable conditions.
- **Lazy direct-bridge re-bootstrap.** `Daemon.bootstrap` is a one-shot ~30 s
  poll, and locked-device block-index loads are measured at 47–121 s — so on the
  run shape this feature serves, bootstrap can time out, `AutoTransport` falls
  back to `HTTPTransport`, and *nobody retries the bridge*: a node left running
  across many runs answers over HTTP for its whole life. A re-bootstrap attempt
  from the sync poll while `bitcoin_rpc_ready() == 0` would close it; package
  work, not action work.
- **Grace for the short action.** Deliberately declined: its ~30 s window cannot
  afford a cold bootstrap, so it keeps kicking-and-declining — the one shape
  §3.8 exists to outgrow on the long action.

## 8. Division of labor

Every decision — the fraction, stall, ending choice, wording — lives in
`NodeAutomation` as plain values, unit-tested on every platform in CI. `NodeRun`
orchestrates: it polls, it measures, it writes the card. Anything touching the
system's patience, the card, or suspension is verifiable only on a locked device,
which is what §5 exists for — the same session that re-measures ADRs 0008 and 0009.
