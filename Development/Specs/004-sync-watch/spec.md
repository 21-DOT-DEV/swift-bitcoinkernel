# Spec — 004 · The long-running action watches the node sync toward the tip

Feature 004 · Status lives in [plan.md](./plan.md) · Design rationale in
[research.md](./research.md) · Ordered work in [tasks.md](./tasks.md)

## Summary

The iOS 27 "Keep Bitcoin Node Syncing" action currently spends its extended
execution window waiting for the node to answer its first question, then
returns — its progress bar describes only start-up. This feature gives the run
a third stage: once the node has answered and is behind the known tip, the run
stays alive inside a bounded window and watches blocks arrive, driving the
progress card with real sync progress ("block 843,210 of 915,000") until it is
caught up, out of time, unable to advance, or stopped.

## User journey

An automation (or the person, from Shortcuts) runs the long action on a locked
device. The run preflights, starts or observes the node, and — if the node
reports it is still syncing — keeps watching within its budget, reporting
honest block-count progress the whole time. When the run ends, it reports *how
syncing ended* as a branchable result, and the node is left running.

**Independent test:** run the action against a signet node known to be behind;
the card advances with real block gains and the run ends with a named sync
result — verifiable end-to-end on a locked device without any other feature.

### Acceptance scenarios

1. **Given** a node behind the tip, **when** the watch runs, **then** the bar
   climbs from where start-up left it with "Block X of Y" in the detail line,
   and the run ends `stillSyncing` if the budget expires — covers FR-001,
   FR-002, FR-003.
2. **Given** a node that can catch up inside the budget, **when** it does,
   **then** the run ends `caughtUp` and the bar fills — covers FR-005, FR-006.
3. **Given** a restarted synced node on a chain quiet past a day — Core latched
   the IBD flag set on its own rule — **when** no new block connects, **then**
   the run ends `noProgress` on the flat-window leash; and when the next block
   connects, `ConnectTip` re-runs the check and the flag proof ends `caughtUp`
   — covers FR-006, FR-007.
4. **Given** a fresh node whose peers connect but serve nothing, **when** its
   genesis-age tip keeps the flag set, **then** the run ends `noProgress` on
   the flat-window leash — never `caughtUp` — covers FR-007.
5. **Given** a node that stops answering entirely, **when** the unproductive
   leash trips (~2 min), **then** the run ends `noProgress` — not a generic
   system
   timeout — covers FR-007.
6. **Given** the person stops the node from the app mid-watch, **when** the
   next poll notices, **then** the run ends `nodeStopped` on the normal
   measured report — never a blanked `noAnswer` — covers FR-008.
7. **Given** the person cancels the run, **when** cancellation lands, **then**
   the existing cancel path runs unchanged and the node keeps running — covers
   FR-009.
8. **Given** a metered network or Low Data Mode appearing mid-watch, **when**
   the next poll reads conditions, **then** the run ends `conditionsChanged`
   naming the condition, and the node keeps running — covers FR-010.
9. **Given** Low Power Mode switched on mid-watch, or thermal reaching
   `.critical`, **when** the next poll reads conditions, **then** the run ends
   `conditionsChanged` naming the condition; `.serious` thermal mid-watch
   changes nothing (at entry it refuses, as today), and Low Power Mode already
   on at entry is accepted — covers FR-011.
10. **Given** the private network is not ready, **when** the run carries a
    grace, **then** it waits through Tor bootstrap inside the grace, re-decides
    on a live snapshot, and never starts on a direct connection — covers
    FR-013.
11. **Given** a regtest chain, **when** the watch would begin, **then** it
    declines entry — a self-defined chain is definitionally at its own tip —
    covers FR-015.
12. **Given** the short action on the same build, **when** it runs, **then**
    its behavior is unchanged in every case — covers FR-014.
13. **Given** an already-running node that skipped preflight, **when** the
    watch would commit, **then** a one-time conditions weigh-in runs first and
    a refusal ends `conditionsChanged` before the watch starts — covers FR-012.
14. **Given** a watched run that earned three blocks, **when** it ends,
    **then** the report carries `blocksGainedThisRun` = 3 alongside
    `blocksSinceLastCheck`, which keeps its pre-run-snapshot meaning — covers
    FR-016.
15. **Given** a watch that saw several readings after the first answer,
    **when** it ends, **then** the report describes the last good reading,
    not the first answer's — covers FR-017.
16. **Given** a run that ends before the watch — declined or unanswered —
    **when** it reports, **then** `syncResult` is `notMeasured`, except the
    weigh-in refusal which reports `conditionsChanged` — covers FR-005.
17. **Given** a silent stretch mid-watch, **when** heartbeat ticks write,
    **then** a fresh write lands every ~5 s and the bar never claims beyond
    the earned floor (+1 display band) — covers FR-004, FR-018.
18. **Given** a pass where the person stops the node as the network turns
    metered, **when** both endings hold at once, **then** the run reports
    `nodeStopped` — covers FR-019.
19. **Given** a node the run just started whose stored tip is hours old — the
    IBD flag already clear at load and headers not yet fetched, so flag and
    gap both read finished — **when** the first answer arrives, **then** the
    tip's age still enters the watch, and the run ends `caughtUp` once the gap
    the node then fetches closes — covers FR-001, FR-006.
20. **Given** a node the run started on a quiet signet — tip hours old, under
    a day — **when** headers never advance but at least two outbound
    block-serving peers report `synced_headers` equal to `headers`, **then**
    the run ends `caughtUp`; the same shape with no qualifying peers ends
    `noProgress` on the flat-window leash — covers FR-006, FR-007.

## Functional requirements

- **FR-001** Once a run carrying a sync budget lands on a live reading and the
  node reports still-syncing — its `initialblockdownload` flag set, *or* a
  header gap open, *or* a tip timestamp more than ~60 minutes old — the run
  enters a watch stage instead of returning. No one signal suffices: the flag
  covers the never-synced or day-stale node, but clears at chain-tip load for
  any tip under a day old; the gap reads zero whenever headers have not been
  fetched yet — and the node's startup order makes that the common case, since
  networking starts and RPC warmup ends within lines of each other, so the
  first answer lands before the first header fetch can finish. The tip's own
  timestamp covers the warm-restart window both others miss.
- **FR-002** The card's fraction is the distance this run closed toward the
  live tip, recomputed each poll — never rate-projected, never clock-derived,
  never `verificationprogress`.
- **FR-003** The headline flips to the syncing wording when the watch begins;
  the detail line carries the absolute position ("Block 843,210 of 915,000"),
  refreshed on each gain, and gains a "last gain N min ago" clause once no
  gain has landed for the unproductive leash's own duration (~120 s, FR-007)
  — silence is reported exactly when it starts costing the run.
- **FR-004** The earned progress position never retreats and no write claims
  unearned progress: heartbeat writes may dither ±1 around the earned floor
  but cannot raise it, and only an earned `caughtUp` finish fills the bar.
  Every pre-watch write compresses into a start-up band so a sync fraction
  starting near zero is not silently discarded.
- **FR-005** The report's `syncResult` is always set — one of the five
  branchable endings `caughtUp`, `stillSyncing`, `noProgress`, `nodeStopped`,
  `conditionsChanged` for a watched run, or `notMeasured` when the run has no
  sync answer to give: declined before the weigh-in, no answer before the
  watch, every short-action run — except the entry-weigh-in refusal, which
  reports `conditionsChanged`. A new field; no existing field changes
  meaning.
- **FR-006** `caughtUp` has one proof, and it is the node's own: the IBD flag
  cleared *and* `blocks == headers` (re-read each poll) *and* one of three
  ways to prove the run saw a real catch-up: headers advanced during the run,
  the tip is inside the ~60-minute freshness threshold, or — judged on any
  flat pass whose flag is clear, gap closed, and headers never advanced — at
  least two outbound block-serving peers report `synced_headers` equal to
  `headers`. The third leg is load-bearing, not ceremony: a run the tip-age
  gate admitted *started* at flag-clear and gap-closed, so only observed
  growth, a never-stale tip, or confirmed peers separates "watched a
  catch-up" from "arrived after one". The peer route is a completed exchange,
  not an inference — on a tip under a day old Core sends every block-serving
  peer a header request anchored one block back, so a current peer's answer
  is never empty. The answer proves the peer's best known is at our tip's
  *height* — a same-height fork would satisfy it too; what it confirms is
  that nothing higher exists, which is the question the leg asks. Inbound
  connections never count, and two must agree, so a run can only be fooled by
  peers as compromised as its own whole view already is. A chain quiet enough
  that nothing new exists *and* no peers can confirm ends `noProgress` on the
  flat-window leash — the honest outcome the quiet-chain edge already
  accepts.
  No copied leave-IBD test: Core runs that check itself at load, after each
  block-file import, and on every connect/disconnect, so a flag set with a
  recent tip exists only
  where the check was skipped mid-load — and certifying past a set flag would
  contradict the node's own report.
- **FR-007** A node that produces no fresh reading ends `noProgress` on the
  ~120 s unproductive leash. Flat readings with provable undone work
  (`headers > blocks`) feed the same leash; everything else flat — an IBD
  node that has learned no gap yet, a flat no-gap window, a chain quiet past
  Core's own recency rule — feeds the ~240 s flat-window leash. A
  `getpeerinfo` answer is evidence for `caughtUp` only — it is not a chain
  reading and never resets either leash.
- **FR-008** A node stopped from the app mid-watch ends the run `nodeStopped`
  on the normal measured report — the earned outcome and last good reading —
  never a blanked `noAnswer` or a false `noProgress`.
- **FR-009** No run ever stops the node; every ending leaves it running.
- **FR-010** A metered network or Low Data Mode found at the entry weigh-in or
  on any pass ends the run `conditionsChanged` immediately.
- **FR-011** Thermal `.serious` or hotter refuses at entry, as the preflight
  gate does today; once the watch commits, only `.critical` ends the run —
  mid-watch `.serious` never does. Low Power Mode already on at entry is
  accepted; switched on mid-watch ends `conditionsChanged`.
- **FR-012** Paths that skipped preflight (already-running node, still-starting
  node) take a one-time full conditions weigh-in before the watch commits — a
  refusal ends `conditionsChanged` with the condition named.
- **FR-013** When the private network is not ready, a run carrying a grace
  waits for Tor inside it (~90 s), then re-decides on a live snapshot; a Tor
  that never readies declines with the unchanged reason; the run never starts
  on a direct connection.
- **FR-014** The short action's behavior is unchanged — it passes no budget and
  takes the same code path as today.
- **FR-015** A `regtest` chain never enters the watch.
- **FR-016** A watched run's report carries `blocksGainedThisRun` — heights earned
  while this run watched — alongside `blocksSinceLastCheck`, which keeps its
  pre-run-snapshot meaning.
- **FR-017** A watched run's report is built from the last good reading, not
  the first answer's — on endings whose final poll produced nothing
  (`noProgress`, `nodeStopped`), that is the last reading that returned data.
- **FR-018** A fresh progress write lands every ~5 s for the whole window —
  liveness by construction, since the system cancels silent runs (~30 s, the
  documented figure).
- **FR-019** When more than one ending holds on a single pass, the result
  resolves by precedence — `nodeStopped`, then `caughtUp`, then
  `conditionsChanged`, then `noProgress`, then `stillSyncing`. A deliberate
  stop ends measurement itself; a completed proof is terminal truth —
  conditions that drifted are advisory for the next run, not a verdict on one
  that finished; unconsented conditions outrank a tripwire; any verdict
  outranks a spent budget.

## Measurable outcomes

Behavioral endings live in the acceptance scenarios above; this list holds only
what a number can falsify. The plan's Verification checklist cites each one.

- **SC-001** During a watch, every earned block gain raises the earned
  progress position, and no heartbeat write raises the earned floor —
  measurable on earned writes, not raw `completedUnitCount`.
- **SC-002** A synced node restarted on a chain quiet past a day ends
  `noProgress` on the flat-window leash (~4 min) — indistinguishable from a
  dead network, the honest direction — and reports `caughtUp` within a pass
  of the next connected block clearing the flag.
- **SC-003** A node that can never gain — and has no peers able to confirm a
  current tip — ends `noProgress` in ~2–4 minutes — the ~120 s unproductive
  leash or the ~240 s flat-window leash — rather than burning the whole
  budget.
- **SC-004** The worst-case run self-bounds at ≈21 minutes, and a fresh
  progress write lands every ~5 s throughout — the system never needs to kill
  the run for silence.
- **SC-005** An unbudgeted run (the short action) emits report fields and
  progress writes identical to the pre-feature behavior — verifiable as a
  test assertion on the unbudgeted path, not a judgement call.

## Edge cases

- **Cold-IBD window** — the node knows no gap yet (its header height has not
  passed the height at watch entry): the bar holds at the band floor and the
  heartbeat keeps the run alive; nothing claims movement that did not happen.
- **Warm restart inside the recency window** — a node whose stored tip is
  hours old but under a day: the flag is already clear at the first answer and
  no gap has been fetched yet, so flag-and-gap alone would read finished — the
  tip-age leg is what still enters the watch. A chain that genuinely produced
  nothing in the gap never advances headers; if at least two outbound
  block-serving peers confirm our tip — `synced_headers == headers`, a
  completed exchange Core itself asked for — the run ends `caughtUp`, and only
  with no qualifying confirmation does it end `noProgress` on the flat-window
  leash — the same honest word a dead network earns.
- **Quiet chain past the recency window** — indistinguishable from a dead
  network; ends `noProgress` (the safe direction). Stated, not hidden.
- **Mid-watch reorg** — reads as flat and feeds the unproductive leash even
  while the node refills; no forward progress *is* happening. Counting a
  changed `bestblockhash` is an optional refinement, not a requirement.
- **Mid-watch suspension** — a frozen process resumed later hands the
  accumulators and budget one giant `Δt`; the run ends `noProgress` or
  `stillSyncing` instantly. Correct: the in-process daemon froze for exactly
  as long.
- **Tip outgrowing the bar** — fresh headers mid-watch grow the denominator;
  the never-retreat floor holds the bar while the detail line keeps reporting
  ground truth.
- **Slow-but-alive node** — a node answering every question in ~11 s is slower
  than the short action's patience but inside the watch's own; its answers
  keep showing new heights — the only kind that resets the leashes, since
  answering alone does not — and it is never `noProgress`.
- **System `timeout` mid-watch** — if the system ends the run anyway (a clock
  misestimate, a stretch the meter could not cover), `onCancel` records
  `.timeout`, the card writes the honest cut-short ending, and the thrown
  `CancellationError` discards the measured report — `syncResult`,
  `blocksGainedThisRun`, and the last good reading never reach the automation. Rare
  by construction; stated so the loss is known, not surprising.
- **A retried run re-watches from the top** — `restartPerform` runs `perform`
  again: preflight, grace, first answer, and a fresh watch — up to ~21 minutes
  per attempt, the node left running between attempts. Nothing bounds how many
  attempts one Shortcuts invocation triggers; a guard that detects a
  just-finished attempt from the pre-run snapshot is deferred work.
- **Settings changed mid-run** — the run reasons about the snapshot taken at
  entry throughout: a toggle landing during the ~90 s grace applies to the
  next run, never silently re-scopes this one — `bitcoin_network` included,
  which otherwise could start a chain the regtest gate never weighed.

## Assumptions and dependencies

- The system's patience with silent runs (~30 s) is documented; the total
  execution ceiling is not — the run bounds itself.
- Builds on the shared run routine from feature 003; every rule it set (one
  routine both actions call, decisions as testable free functions, honest
  endings, the node left running) still holds.
- Both actions run only in the app process — an ADR 0005 constraint the
  design enforces (a second process could never start against the locked
  chain folder). It is platform enforcement of a standing decision, not
  feature behavior, so it is recorded here rather than as a requirement.
- The Tor-toggle start-hole fix (T001) is a separate bugfix landing ahead of
  this feature — the watch widens its exposure but does not create it; it
  carries no requirement here because it is not feature behavior.
- Verification happens on signet — the chain whose miner stalls exercise the
  latched-IBD edge.
- Out of scope here (tracked as deferred work in the plan): stopping the node
  on any condition, AssumeUTXO bootstrap, an idle-time background-processing
  task (`BGProcessingTask` — not the `BGContinuedProcessingTask` this feature
  rides), the sister app's action.
