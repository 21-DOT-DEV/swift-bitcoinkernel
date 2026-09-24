# Research — 004 · The long-running action watches the node sync toward the tip

Evidence and rejected alternatives for [the plan](./plan.md). Spec in
[spec.md](./spec.md); ordered work in [tasks.md](./tasks.md). Everything here is
source-verified against the vendored `Vendor/bitcoin/` tree or Apple platform
documentation; anything unverifiable is flagged as a device question.

## 1. Why the progress target is the live tip, not an estimate

**Rate projection was considered and rejected — the algebra degenerates.** For
the case the feature exists for (a node that cannot catch up inside the budget,
so the projection is what binds), `goal = h₀ + rate·B` gives
`fraction = (h − h₀)/(rate·B)`. Any estimator that converges to the true rate
collapses that to `rate·(t − t₀)/(rate·B) = (t − t₀)/B` — a clock wearing a
progress bar's clothes, *most* clock-like exactly when the estimate is good. A
trailing window only produces a lagged clock. So there is no estimator — the
surviving fraction is the live-tip formula plan §3.3 fixes.

**`verificationprogress` was considered and rejected.** It is a
transaction-count estimate whose denominator is extrapolated from *wall-clock
time*, so it sits under 1.0 forever at the tip and can drift downward on a fully
synced node (bitcoin/bitcoin issues #28847, #31127, #26433). It is non-monotone,
and its growth-rate assumption is calibrated to mainnet — misleading on the
signet this feature verifies against.

**Blocks are not units of time.** `assumevalid` makes most of the chain nearly
free while the recent tail carries ~90% of validation cost on constrained
hardware. The number of blocks that fit a safe window cannot be fixed — the
bound is time (a wall-clock budget), the target is blocks.

## 2. Bitcoin Core's initial-block-download flag

`getblockchaininfo`'s `initialblockdownload` is the honest "still syncing"
signal — but with a shape that matters:

- **It latches per-process on a 24-hour tip-age rule, and nothing re-opens it
  on a timer.** A synced node restarted while its tip is more than a day old
  reports IBD `true` with nothing left to fetch — and stays that way until the
  next block connects, because Core re-runs the check only at `LoadChainTip`,
  after each block-file import, and on every `ConnectTip`/`DisconnectTip`. On
  a quiet signet
  that is a real stall of the *flag*, not the node — the watch reports it
  honestly as `noProgress`, and the flag clears the moment a block lands.
- **A node that has not yet fetched fresh headers reports a gap of zero.** On a
  first-ever start or a resume against a stale chain, `blocks == headers` is
  true precisely when the node has not yet learned how far behind it is.
- **Neither flag nor gap covers the warm restart — and the startup order makes
  the hole permanent.** `m_cached_is_ibd` starts `true`
  (`Vendor/bitcoin/src/validation.h:1049`) and `LoadChainTip` clears it for
  any tip under a day old — before networking. Networking itself starts at
  `init.cpp`'s `connman->Start`, and `SetRPCWarmupFinished` follows ~ten lines
  later on the same thread with no wait for peers, so the first
  `getblockchaininfo` answer lands before the first `getheaders` reply can —
  reporting flag clear and `headers == blocks` for a node hours behind. Every
  periodic automation lands in this window; the tip's own timestamp — `time`
  on the same chain question — is the signal that survives it. (Peer-side
  signals stay ruled out for entry too: `getpeerinfo`'s `startingheight` now
  returns only under `-deprecatedrpc=startingheight` — `rpc/net.cpp` — and is
  the peer's unverified claim besides.)

So three signals gate entry — flag, gap, and tip age, each covering a window
the others miss — and the flag still answers "should you trust this chain
yet." Flag cleared *plus* gap closed *plus* proof the run saw a catch-up —
headers advanced during the run, the tip was never stale, or two outbound
peers confirmed our tip — is the whole `caughtUp` proof; no copied recency
test belongs beside it (§3 records why).

The ~60-minute freshness threshold is a heuristic, not a Core rule — a few
block intervals. Its false positive is mainnet-rare: a genuine >60-minute
lull between blocks happens at roughly e⁻⁶ ≈ 0.25% of attach instants on
mainnet — and is routine on a single-signer chain like signet, where the
signer idles, which is why the flat case that can't otherwise prove a
catch-up earns a peer confirmation (§3) rather than paying the `noProgress`
cost every lull. Its
known bound: `time` is miner-set and consensus-tolerant to ~2 h in the
future, so a skewed stamp can hide up to ~3 h of real staleness — the ~1–3 h
band is the blind spot, and anything staler still enters on tip age itself;
the flag (a >24 h rule) is not the backstop.

## 3. Peer evidence — what was tried and why each form failed

Certification went through four designs. Each failure is recorded so it is not
re-attempted:

1. **Elapsed silence.** Treating minutes of flat readings with connected peers
   as proof of currency fails both ways: a fresh node at height zero can hold
   connected peers serving nothing usable, and a restarted synced node can hold
   the latched IBD flag with no work left. Silence cannot distinguish them.
2. **`syncedHeaders` as a peer-says-current signal — misread, then reinstated
   for one job.** The first inspection stopped halfway: `nSyncHeight`
   populates only from `pindexBestKnownBlock`, and an empty `getheaders`
   reply returns before the update site — so it read `-1` on every restarted
   synced node, exactly the healthy connections the proof exists for. What
   that missed is Core's anchoring (`net_processing.cpp:5797-5812`): when the
   best header is under 24 h old, Core sends `getheaders` to *every*
   block-serving peer starting one block *before* the tip — an up-to-date
   peer's reply is never empty, `UpdateBlockAvailability` records its best
   block, and `synced_headers` reads our own `headers` within a round trip.
   The `-1`-forever observation is the *unhealthy* case, not the healthy one.
   Rejected as a *progress* signal — a peer that announces nothing when
   nothing is newer still cannot show movement — but kept as a *confirmation*
   signal: `synced_headers == headers` is a completed exchange, not an
   absence. Guards: only `outbound-full-relay` and `block-relay-only`
   connections count (inbound is attacker-selected; manual, feeler and
   addr-fetch are excluded), at least two must agree, and the request fires
   once per connection at connect time, only while the tip is under 24 h — a
   tip crossing the boundary mid-session keeps the confirmations earlier-
   connecting peers already recorded, while a chain stale the whole time
   gathers none.
3. **`max(syncedHeaders) <= headers` as a comparison.** Not even the
   comparison it needs: `pindexBestKnownBlock` points into the local block
   index, but `headers` reports the most-work header rather than the highest —
   a peer announcing a higher-height, lower-work branch whose headers we hold
   can read above it. The comparison fails as a *progress* signal regardless —
   a field that can only echo our own height at best cannot show movement.
4. **Binary "peers connected throughout" streak.** Too strict in the other
   direction — a healthy node stalls if the first peer answer lags or
   connectivity briefly wobbles.

**The surviving design asks peers only what Core already asked them — because
Core's own verdict never needed them.** `ChainstateManager::UpdateIBDStatus`
(`Vendor/bitcoin/src/validation.cpp`) latches IBD false on exactly two
conditions, evaluated against the node's own chain: tip chain work ≥
`nMinimumChainWork`, and the tip timestamp inside `max_tip_age`
(`CChain::IsTipRecent`, `Vendor/bitcoin/src/chain.h`; the default is 24 h —
`DEFAULT_MAX_TIP_AGE` in `kernel/chainstatemanager_opts.h`). No peer count, no
in-flight bookkeeping, no presync state. Attempts 1, 3 and 4 stay failed —
each tried to infer "nothing left to fetch" from what peers volunteer, the
wrong substrate for a progress signal, since peers announce nothing when
there is nothing newer. Item 2 survives in one narrow role that is not
volunteered inference at all: the result of a request Core itself sent,
counted only over self-initiated outbound block-serving connections, and
requiring two — the standard eclipse-aware floor. A run whose entire outbound
view is attacker-owned can still be fooled into `caughtUp`; that residual is
the same exposure the node already carries, and nothing narrower exists.

**The copied live test was then deleted too — it was almost unreachable.**
`UpdateIBDStatus` runs at five call sites only: `Chainstate::LoadChainTip`
(startup), after each block-file import (`init.cpp`'s post-init refresh and
`btck_chainstate_manager_import_blocks` in `kernel/bitcoinkernel.cpp`), and
on every `ConnectTip` / `DisconnectTip`. A flag still set while the tip is recent can therefore exist
only where the check early-returned on `LoadingBlocks()` — a reindex or
import running at init, which the app cannot produce — and in every other
state the flag's own verdict already covers it: tip recent with enough work
clears at init; tip past 24 h fails the check's recency half on any copy as
well; a new block's `ConnectTip` clears it. Reporting `caughtUp` while
`initialblockdownload` is still set would contradict the node's own verdict,
so the flag, a closed gap, and observed header growth (a never-stale tip, or
two confirmed outbound peers) are the whole proof. A chain quiet past the
window — where the peer mechanism cannot gather two answers — is
indistinguishable from a dead network and ends `noProgress` — the safe
direction. The per-network `nMinimumChainWork`
constants (`kernel/chainparams.cpp`) are recorded here only so nobody
re-derives them for a resurrected copy.

The watch asks `blockchainInfo` — `initialblockdownload`, `blocks`, `headers`,
`time` — and, on the flat passes that can't otherwise prove a catch-up (flag
clear, gap closed, headers never advanced), `getpeerinfo` for the
confirmation count. The lock accounting runs honest in both directions:
`getpeerinfo` takes `cs_main` once per peer row (`GetNodeStateStats`,
`net_processing.cpp`), but `getblockchaininfo` takes the same lock once per
call for `m_best_header` (`rpc/blockchain.cpp`) — so the watch's own ~5 s
chain question is the far busier `cs_main` user (~180 acquisitions a run,
plus a `getpeerinfo` per flat pass — itself one acquisition per peer row —
and the two pollers the app adds) — unchanged on either transport,
since the lock is taken inside Core per call; the HTTP path adds an
authenticated loopback round trip on top of the same acquisition. All are
short field reads under the lock rather than scans — cheap either way — but
the cadence, not the deleted call, is the number to revisit if the lock ever
contends.

**Core's own stall-recovery constants bound the leashes.** During deep download
the node drops a stalling peer in 2–64 s (`BLOCK_STALLING_TIMEOUT_DEFAULT`/`_MAX`);
near the tip the fallback takes ~10 minutes per stalled block
(`BLOCK_DOWNLOAD_TIMEOUT_BASE` plus ~5 minutes per parallel peer). What peer
churn can fix resolves inside the ~120 s `unproductive` leash; what it cannot
is dead peers, a lost network, a wedged validation thread.

## 4. iOS execution-window and progress-liveness evidence

- **Silence ends a run — documented, not folklore.** The run's window is a
  `BGContinuedProcessingTask` — `performBackgroundTask(options:operation:)`
  hands the work to it — and `IntentCancellationReason.timeout` states plainly
  that a run that stops reporting progress is cancelled at roughly thirty
  seconds. That expiration behavior is the T023 experiment's concrete target.
  The *total* run ceiling is unpublished — the run must bound itself
  (~21 minutes worst case: preflight + private-network grace + first-answer
  wait + watch budget).
- **`LongRunningTaskOptions` has one public member, and it earns this feature
  nothing.** `.requiresGPU` is public API at iOS 27.0; block validation is
  CPU-bound, so `options: []` remains the only correct spelling here. What
  does not exist is a lever for a longer window — recorded so nobody re-opens
  it.
- **Every sleep carries a tolerance decision.** `withHardTimeout`'s deadline
  race keeps `tolerance: nil` — "late answers are timeouts" is load-bearing.
  The cadence and heartbeat sleeps take ~1 s: a watch schedules ~540 timed
  wakeups, and forbidding the OS from coalescing them spends battery and feeds
  the thermal `.critical` the watch itself ends on (§5).
- **Apple's own `LongRunningIntent` example writes
  `localizedAdditionalDescription` on every chunk alongside the count** — which
  is why the meter redesign is *gated on a device experiment*: if a text-only
  write satisfies the liveness check, the dither machinery is unearned (the
  staleness clause the detail line already carries is fresh on every poll at
  zero honesty cost). If the system counts only *increasing* numeric writes,
  the specced fallback is a ratchet bounded inside the ~500-notch reserve.
- **`allowedExecutionTargets`/`.main` exists in iOS 27** and pins the intent to
  the app process. ADR 0005's correctness requirement — the daemon holds an
  exclusive lock on the chain folder, so a second process is refused — is
  currently enforced only by the absence of an extension target (a build-graph
  fact, not a constraint). The pin converts it into a system-honored rule ahead
  of any widget, control, or App Intents extension.
- **`withHardTimeout` abandons its work on timeout.** `waitUntilReady` is a
  `@MainActor` poll loop whose `try?` sleep swallows cancellation — wrapping it
  would leave an abandoned loop spinning on the main actor past the run. The
  private-network grace is therefore a deadline-bounded poll in `NodeRun`'s own
  loop shape. Corollary for the pile-up comment: pre-bootstrap questions ride
  `HTTPTransport` and are genuinely cancellable; the uncancellable shape is the
  post-boot direct bridge.
- **The transport is chosen per call — and on a locked device it is probably
  HTTP.** `AutoTransport.send` routes direct when `bitcoin_rpc_ready() == 1`,
  HTTP otherwise. The bridge's bootstrap is a fire-and-forget `Task` inside
  `NodeViewModel.start` — shared by the action path — so early questions
  flow over `CookieTransport` while its one-shot ~30 s poll loses to the
  47–121 s locked-device block-index loads ADR 0008 measured; nothing
  retries, and all ~180 watch questions ride `URLSession` — though on a
  fast-starting node the flag can flip mid-watch. Orphan lifetime and
  cancellability are inversely coupled per path: direct gives up at ~30 s
  (residual ≈0 while the budgets match, but uncancellable); HTTP's ceiling
  is 60 s — a 30 s orphan per timeout, except `work.cancel()` genuinely
  terminates it (the one transport that observes cancellation). The `cs_main`
  count is unchanged either way — the lock is per call inside Core — and the
  HTTP path adds a `.cookie` file read plus an authenticated loopback round
  trip on top. `bitcoin_rpc_ready()` is package-internal C the app cannot
  call — logging the serving transport means plumbing a `bridgeReady` flag
  `NodeViewModel` sets when its bootstrap resolves, not a per-poll C call.
  Corollary: the session's questions authenticate by `.cookie`, so `rpc_auth`
  never reaches the client — a mid-grace change there yields a launched
  config nobody reasoned about, not a 401.
- **The heartbeat guard must model the banded layout.** Under band compression
  the first-answer ramp writes ~10 distinct notches over the 240 s wait rather
  than ~90, so ticks fire ~38 times during it — ~38 of the meter's 50 units
  gone before the watch begins, ~60 s of numeric coverage for a 900 s watch.
  `heartbeatCoverageExceedsWait` ticks a fresh meter dry — it models the
  pre-band layout and passes either way, so the re-point (T019) simulates the
  compressed ramp and asserts across `waitForFirstAnswer + syncBudget`, red on
  the old model today. The intent's own comment predicted the `questionBudget`
  growth `watchQuestionBudget` is; the re-derived guard names it.
- **The silent-omit is already guarded — do not re-investigate.** On the
  unattended path `NodeAutomation.startArguments` throws
  `privateNetworkNotReady` before `buildArguments` runs, so `tor_enabled`
  true with a nil proxy never reaches the silent omit the builder's doc
  describes. ADR 0006's floor is enforced; T001's snapshot widens the same
  guarantee from the Tor flag to every settings key.

## 5. Conditions-policy evidence

- **Metered network and Low Data Mode are absolute.** They spend money/data
  continuously and are never consented to anywhere in the app — a watch that
  finds one ends the same pass, entry included.
- **Low Power Mode: entry-state vs. delta.** Already on at entry is a standing
  preference — ending on it would silently remove the feature for everyone who
  leaves it on, on every run. Switched on mid-watch is a drift and ends the
  watch.
- **Thermal: `.critical` only.** `.serious` is reached routinely by fifteen
  minutes of validation on a locked phone — aborting there would make the
  headline behavior "runs four minutes, then stops because the phone got warm."
  `DeviceConditions.overheating` collapsed `.serious || .critical` to a `Bool`,
  so the tested type gains the `thermalState` itself; entry keeps refusing at
  `.serious` while the drift check reads `.critical` from the same field.
- **Two network reads, two different mechanisms — an earlier draft swapped
  them.** The once-per-run weigh-in waits on `NetworkCostMonitor.first()`
  bounded at ~2 s, exactly as `readConditions()` does — `current` fails open
  (`.unknown` reads as "not costly"), and on a background launch the run
  reaches the weigh-in within milliseconds of the watcher's start, when
  "not yet reported" is the normal state: reading `current` there would skip
  the metered refusal on the exact topology the feature exists for. The
  ~180-per-run drift check is the one that reads `current` (never waits) —
  `readConditions()` itself is still too heavy for it: `prepareChainFolder()`
  is a filesystem write, and a two-second suspension per poll is forbidden —
  plus `thermalState` and `isLowPowerModeEnabled`.
- **Ending the run is not consequence-free.** `perform` returning lets the app
  suspend, which freezes the in-process daemon — a `.critical` abort does
  relieve the device, indirectly. Stopping the node is deliberately not here;
  it is a new act needing its own ADR.

## 6. Baseline and reporting semantics

- **`blocksSinceLastCheck` keeps run-boundary discipline.** `lastKnown` is
  written once at report time, never per-poll — and only on the path that
  actually returns `.result(value:)`. T028 moves the write out of
  `measuredReport`: today it precedes the last `answerIsStillWanted` guard,
  so a run cancelled or node-stopped in that window advances the baseline
  while reporting nothing — and the `.timeout` discard would silently drop a
  watched run's whole span of gains. After the fix a killed run persists
  nothing, so the next run's delta spans the whole gap — honest, since no
  report ever claimed those blocks. A retried run reads the same pre-run snapshot, so a
  system retry reports the full delta rather than ≈0 against its own abandoned
  attempt's writes. What is not bounded is the retry itself — `restartPerform`
  re-runs `perform` from the top, up to ~21 minutes per attempt, with the node
  left running between attempts (spec edge cases). The `previous` snapshot is
  captured *before* the watch on
  the `reportExistingNode` path — the app's own sync poll can overwrite
  `lastKnown` during a fifteen-minute watch, reporting ~0 for a run that
  watched real gains.
- **Localization has two sinks, and the shipped one is a bug.** `Progress`'s
  `localized*` properties are plain `String`s resolved in the app's locale —
  card text uses `String(localized:)`. The dialog is worse off: both intents
  today build it as `IntentDialog(stringLiteral: report.summary)` — a runtime
  `String` yields no extractable key, so the sentence cannot be translated at
  all; it must be built from a `LocalizedStringResource` template
  interpolating the report's values. That is a bug fix on the already-shipped
  short action (T027), and it fixes the shape T009's summary sentences are
  written in — which is why it lands ahead of them. The report's `summary`
  stays `String` — an existing `@Property` other fields share; re-typing would
  break automations. Open item: `AppShortcut` phrases may require a dedicated
  `AppShortcuts.xcstrings` rather than the general catalog — verify while
  wiring (T022); if so the phrase-localization follow-up (003) needs its own
  file.
- **`syncResult` is non-optional with an explicit `notMeasured` case.** The
  open question was whether `Optional<some AppEnum>` satisfies
  `EntityProperty<Value>` — sidestepped rather than answered: a non-optional
  enum is the standard shape, gives automations a branchable value rather
  than a `nil` to test for, and stays append-safe (AppEnum raw values persist
  by string — appending cases is safe, renaming or renumbering is not). The
  nil-rules requirement collapses into FR-005.
