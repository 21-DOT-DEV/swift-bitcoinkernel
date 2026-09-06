---
feature: 003
title: Home automation action that runs the node unattended
phase: null
status: Planned
updated: 2026-09-03
adrs: [0005, 0006, 0007, 0008]
---

# Home automation action that runs the node unattended

An action NodeApp publishes to Shortcuts so a Home app automation can start the
Bitcoin node without anyone touching the phone, let it sync for as long as the
system allows, shut it down cleanly, and report how far it got. This is demo-app
work rather than a library roadmap phase; the [roadmap](../../Roadmap/README.md)
tracks the `Bitcoin` and `BitcoinKernel` libraries. The two decisions that outlive
this feature are recorded in
[ADR 0005](../../ADRs/0005-shortcuts-actions-run-in-the-app.md),
[ADR 0006](../../ADRs/0006-unattended-runs-never-bypass-tor.md) and
[ADR 0007](../../ADRs/0007-unattended-actions-own-their-deadline.md).

The equivalent action for KernelApp is a separate, later feature.

## 1. Goal & success criteria

- A Home app automation can trigger the action with the phone locked and the app
  not running, and the node starts.
- The action leaves the node's on-disk state clean whenever it is given the chance
  to shut down; after a kill it was never told about, the node recovers on the next
  start (§3.4 for which is which, §5 for the check).
- It reports the block height reached, or a plain reason it could not run.
- It never interrupts a node someone started themselves.
- It never connects without the privacy network when the person asked for it.

**The measurement this feature exists to produce:** how far a freshly started
daemon actually gets inside one window, on a real chain. That number decides
whether the longer visible-progress version in §7 is worth building.

## 2. Scope

**Platforms: phone and tablet only.** A home automation runs from a home hub — a
HomePod, Apple TV, or iPad — and never from a Mac, so the feature's purpose is
unreachable there. Shipping it on Mac would add only a button someone clicks by
hand, which starts a node for a few seconds and stops it, when leaving the app open
syncs far more. Gating uses availability annotations rather than compile-time
conditions, because the list that publishes actions to Shortcuts accepts only
platform-availability conditions. The same reasoning will apply to the second app's
action.

**In scope:** one action in the NodeApp target; a process-level owner for the node
so it can run without any screen present; ownership tracking so shutdown only
applies to a node the action started; a bounded wait for the privacy network when
enabled; unit tests for the decision logic.

**Out of scope (with owners):** the longer visible-progress version → §7 · KernelApp's action → its own later feature · moving chain
data into a shared container → §7 · any change to how the node syncs.

## 3. Design

### 3.1 A node owner that outlives the screen

`Projects/Sources/NodeApp/ContentView.swift:23` creates the node's view model with `@State`, so it exists
only while the interface does. When the system launches the app in the background
to service an action there is no interface, and therefore nothing owns the node.

A process-level owner replaces that: one instance per process, created on first
use, which both the interface and the action share. The interface's behaviour is
unchanged — it reads the same object it does today.

It stays inside this app for now. The second app will need the same thing when its
own action is built, but the two own different things — one runs a full Bitcoin
daemon, the other drives a validation engine — so the shared version is better
designed against two real cases than one. The privacy-network controller they
genuinely share already lives in `Projects/Sources/Shared/`.

The node and privacy-network objects are confined to the main thread, so the
action's work runs there too. That matches the sibling project this design was read
against — `circadian`, whose automation action marks its `perform()` function
`@MainActor` at `Projects/Sources/WorkIntents/ProcessSavedArticlesIntent.swift:24`
within that repository.

That citation is about **thread confinement only**. Where that project puts its
action is the opposite of the choice made here: its `WorkIntents` target is declared
`product: .extensionKitExtension` (`Projects/Project.swift:270`), a separate program
of exactly the kind ADR 0005 rejected for this app. The two projects agree on which
thread the work runs on and disagree on which process runs it, for the reasons that
record sets out.
No change to that confinement is needed or intended.

### 3.2 What the action does, in order

1. **If the node is not stopped**, report and return. Nothing is started and nothing
   is stopped — the ownership rule from ADR 0005, which is what stops an automation
   interrupting a session someone is watching. A node still starting has no height
   yet and one still stopping has an unreliable one, so the report names the state
   and carries the saved height with its age rather than pretending to a live
   figure.
2. **If the privacy network is switched on** (`tor_enabled`), start it and wait for
   it to be fully established. Establishing it from cold takes 30–60 seconds and
   cannot finish inside one window; from a warm cache it takes 5–10 seconds and
   leaves most of the window for syncing. A run that cannot finish establishing it
   still spends the window doing so, because that leaves the cache warm for the next
   run — the run's whole purpose becomes readiness rather than syncing, and it
   reports that. The node never starts on a direct connection (ADR 0006).
3. **Start the node** using the same argument builder the interface uses, but only
   after a check that belongs to the action alone: if the privacy setting is on and
   no proxy address exists, the action stops instead of building anything. The
   builder itself is not modified and the interface's path is untouched.

   That check is the point. The builder adds the proxy only when an address is
   present — `if torEnabled, let proxy = torProxy` at
   `Projects/Sources/NodeApp/DaemonConfig.swift:70-72` — so a missing address means
   the argument is simply left out, which the surrounding comment explains as "Tor
   not yet bootstrapped" (`Projects/Sources/NodeApp/DaemonConfig.swift:22-25`). The
   reasoning is written down separately: the daemon "should start *without* a stale
   proxy and reconnect later" (`Projects/AGENTS.md:75`). That is defensible with
   someone watching the screen. It
   is not defensible unattended: it would start the node on a direct connection and
   expose the person's home network address to peers, which ADR 0006 forbids. Relying
   on step 2's wait being correct is not enough — a wait that exits for any reason
   would fall straight through into an unprotected start.
4. **Hold** until a deadline set safely below the system's limit for a
   background-triggered action.
5. **Shut down cleanly** through the daemon's normal path and wait for it to
   finish, then report.

### 3.3 What the action returns

Every path returns two things: a structured value another automation step can act
on, and a plain sentence for the person reading it. That is what the platform
expects, and it is what lets someone build their own automation that reacts to the
result rather than merely reading it.

The value is a custom type with four named fields, each of which appears as its own
variable someone can use in the next step of their automation: **what happened**
(started and synced, already running, waiting on the private network, or could not
start), the **block height**, how many **blocks remain behind** the headers the node
knows about when it is live, and the **age of the height** when it came from the
saved value rather than a live reading.

Four fields is a commitment: renaming or removing one later silently breaks
automations people have built. They are named together here for that reason.

Height alone is misleading: a node tracks both the height it has fully validated and
the headers it knows about, and during catch-up the second runs far ahead of the
first. Reporting the remaining-blocks figure alongside the height is what stops a
number reading as "caught up" when it is not. The percentage-complete figure is
deliberately not reported: it is measured against a moving target and can fall over
time even on a fully synced node.

### 3.4 The deadline

The published limit for a background-triggered action is about 30 seconds, and
starting the daemon consumes part of it before any syncing happens. The deadline
is therefore a named constant, set below that, with the first release recording
what it actually achieved rather than assuming.

**The action does not wait to be told when to stop.** It watches its own clock and
begins shutting down before the system's limit, for a reason visible in the existing
code: shutdown waits on a continuation with no cancellation handling, backed by an
unbounded wait on a semaphore (`Sources/Bitcoin/Daemon.swift:46` and `:179`). That
cuts both ways. Once shutdown has begun, nothing can abandon it half-finished, which
is what we want. But it also means a stop signal cannot rescue the action once it is
already inside that wait, and cannot begin a shutdown that has not started.

A purpose-built facility for being told about cancellation exists, but it requires
iOS 27 and this app supports iOS 18 (`Projects/Project.swift:14-15`, matching the
platform tier at `Development/constitution.md:226`). The design does not depend on
it. If ordinary task cancellation does reach the action, it simply triggers the same
shutdown earlier; if it never arrives, the action's own deadline already covered it.

So two ways a run can end early:

- **The action's own deadline fires**, or a stop signal arrives first. Either way the
  shutdown sequence runs to completion.
- **The process is killed outright** — force-quit from the app switcher, or the
  system reclaiming memory under pressure. No warning is given and no cleanup code
  runs. This cannot be prevented.

Shutting down is not instant: the sequence sends a stop command and then waits for
the daemon's main function to return (`Sources/Bitcoin/Daemon.swift:178`). The
deadline therefore reserves time for it rather than starting it at the limit.

## 4. Implementation steps

1. Extract the process-level node owner; point `ContentView` at it. No behaviour
   change to the interface.
2. Add the action and the declaration that publishes it to Shortcuts, gated to phone
   and tablet by availability annotation, returning the four-field type from §3.3.
3. Implement the five steps in §3.2, with ownership and privacy-network decisions
   as pure functions that can be tested without a node.
4. Add the action-only check from §3.2 step 3, so an unattended start cannot omit
   the proxy while the privacy setting is on. Then edit `Projects/AGENTS.md:75` to
   say that its "start without a stale proxy and reconnect later" guidance describes
   the **interface** path only, and that an unattended run refuses to start instead,
   per ADR 0006. The two are not in conflict — they cover different situations — but
   as written that line reads as a rule for the builder generally, which is how an
   implementer would end up applying it in the wrong place. The interface's
   behaviour is unchanged; see §7.
5. Unit-test those decisions: already-running returns without stopping; privacy
   network enabled but not ready returns without starting; privacy network
   disabled proceeds; ownership recorded correctly; and the guard refuses to build
   arguments with the setting on and no proxy address.
6. Verify by hand on a device, per §5.

## 5. Verification

- [ ] The action appears in Shortcuts and can be added to a Home automation.
- [ ] Triggered with the app not running and the phone locked, the node starts and
      the action reports a height.
- [ ] Triggered while the app is open and syncing, the action reports and returns
      without stopping the node.
- [ ] With the privacy network on and reachable, the node starts through it.
- [ ] With the privacy network on and unreachable, the action reports that and the
      node never starts — checked by confirming no direct connections were made,
      not only by reading the message.
- [ ] After a normal run, restarting the app finds the chain state intact.
- [ ] After a run ended by force-quitting from the app switcher mid-sync, the app
      starts again and recovers without asking for a full rebuild.
- [x] Record the height gained per run — the measurement in §1.

### What five device runs actually measured, 2026-09-05

Recorded as a range, not an average: the average of a run that gained nothing and a
run that gained 45 blocks describes neither, and there were too few runs to call the
spread noise.

| What was measured | Range across runs |
| --- | --- |
| Blocks gained in a run | 0, 6, 23, 45 |
| Time before the node answered at all | ~12 s |
| Total window before the system's out-of-time warning | 27.4 s and 27.9 s |
| Time to shut the node down cleanly | 0.36 s to 4.8 s |

Three things follow, and they drove the changes now in the code:

1. **The window is 27 seconds, not 30**, so runs were landing late. Recorded as a
   dated correction on ADR 0007 (the record that says an unattended action watches its
   own clock), since the number binds the second app's action too.
2. **Roughly twelve of those seconds are start-up, and none of it is recoverable.**
   Asking the node directly every 250 ms instead of waiting for the app's own flag
   changed nothing, so the cost is inside the node. Its log breaks the twelve down the
   same way on every start:

   | Start-up phase | Time |
   | --- | --- |
   | Wallet check, peer addresses, ban list | under 1 s |
   | **Loading the block index** | **10–11 s** |
   | Verifying the last 6 blocks | ~1 s |
   | Starting network threads, done | under 1 s |

   Loading the block index dominates and no setting shortens it — it is reading the
   index off disk, and every run is a fresh start. The verification pass is the only
   part any setting touches, worth about a second, and naming that setting explicitly
   makes the node **shut down during start-up** rather than skip the check when memory
   is short ([bitcoin/bitcoin#25574](https://github.com/bitcoin/bitcoin/pull/25574)) —
   the worst failure available to an unattended run, for a one-second saving. Decision:
   change nothing about start-up.
3. **The reported gain is a floor, not a count.** The node keeps downloading while it
   shuts down and the height is read before that begins, so up to 11 blocks per run go
   uncounted. Runs report "at least +N" rather than a bare number.

4. **Shutting down is getting slower** — 0.34, 2.07, 3.81, 5.10 s across four runs
   against a 6 s reserve. The likeliest cause is the amount of freshly-synced state to
   write out. Four samples cannot say whether it levels off, so the reserve stays at 6
   and each run now reports its own overrun instead of the number being guessed at.

### The measurements above are attended, and that turns out to matter

Everything in the table above was measured with someone watching the screen. The first
screen-locked runs were 3.5× to 9× slower at loading the block index — 121 s and 47 s
against 12–14 s — which is more than the whole window. ADR 0008 records the rule that
came out of it: an unattended timing is measured with the screen locked.

Two consequences are already in the code. A run never asks a node that has not answered
to stop, and every wait on the node is bounded, because the uninterruptible stop (ADR
0007) applied to a node still starting up is what turned a slow run into a visible
timeout and an ungraceful kill.

### How a run reports, and why it is not a dialog

The action returns a dialog, and on an unattended run that dialog reaches nobody:
there is no Siri session and no interface to display it in. ADR 0006 assumes the
person receives the refusal message, so something has to deliver it.

Runs report through `RunReporter` (`Projects/Sources/Shared/RunReporter.swift`), a
two-method protocol carrying no ActivityKit, UserNotifications or App Intents types.
That keeps the wording under test on the macOS leg of CI, which is the only leg that
can test any of this — a background-launched action cannot be exercised in CI at all.

Three properties are deliberate:

- **Neither method throws.** Reporting is a side effect of a run and must never be
  able to fail one. An implementation that cannot deliver stays silent.
- **The refusal is reported before the private-network gate**, so a run that never
  starts the node still produces a message.
- **The completed case is reported before the shutdown wait**, which cannot be
  interrupted and has been measured at up to 5.1 s. A run killed inside that wait
  would otherwise report nothing. The height cannot be re-read after shutdown anyway,
  so reporting early costs nothing.

The implementation is a local notification with a fixed identifier, so each run
replaces the last rather than accumulating, and with provisional authorisation, which
is granted without a prompt and delivers quietly. A run must never be the thing that
asks for permission — it has no interface in which to ask.

## 6. Risks and mitigations

- The window may be too short to gain any blocks, making the feature a status
  report rather than a sync. → Measured (§5): it gains something on most runs but not
  all. That is enough for the narrower purpose stated in §7 and not enough for the
  broader one, which is why the longer version stays a follow-up.
- A kill with no warning stops the node mid-write, leaving its databases unclean. →
  Unrecoverable data loss is not the usual outcome: the node replays blocks on next
  start, which is far quicker than a full rebuild, and only asks for a rebuild if it
  actually detects damage. The mitigation is therefore to verify recovery rather
  than to promise prevention (§5), and to reserve time for the shutdown sequence so
  the handled paths do not become unhandled ones.
- Background-triggered runs are not guaranteed to happen on time or at all. → The
  action reports per-run; nothing depends on a schedule being honoured.
- The privacy network's cached directory data goes stale after a few hours, so an
  automation that fires once a day may find every run cold and never benefit from
  the previous run's warming. → The action's description states that it needs to run
  more often than the cache decays; how often it fires is set in the Home app and
  cannot be enforced from here. §5 records what a daily cadence actually achieves.

## 7. Out of scope (follow-ups)

> **What the short version is actually for, and what it cannot do.** At roughly 25
> blocks a run against the network's roughly 144 a day, this keeps an already
> nearly-current node current — about six triggers a day covers the daily rate.
>
> It cannot catch a node up, and the gap is not close. The device this was measured on
> was 26% synced (height 554,310, downloading blocks dated December 2018), roughly
> 346,000 behind. At 25 blocks a run and eight runs a day that is about **4.7 years**.
> Anyone not already near the tip needs the initial-block-download work below, and the
> action must not be presented as a way to get there.

- **The longer visible version, and the extraction that goes with it.** An action
  triggered through Shortcuts is granted permission to start a live progress card
  even with the app in the background, which is the exception that makes an
  unattended long run possible at all. That version is the second caller of this
  feature's logic, so **its first step is extracting the shared core**: a budget that
  can end early, progress reporting for whatever is watching, and a stop that runs
  once and cannot be half-done. Only the trigger and the reporting surface differ
  between the two.

- **A Live Activity card instead of the notification.** Deferred, not rejected. The
  card's advantage is updating in place rather than stacking up, which needs a stack
  to be worth having — at one run a day there is no stack. And its receipt is removed
  four hours after the run ends, so an overnight run's card is gone before anyone
  wakes, while a notification waits until it is read. If the cadence ever becomes
  hourly, both of those reverse and the card earns its place; it drops in behind
  `RunReporter` with no change to the run itself. Note that a card grants **no extra
  running time** — it is a display, and the run is still bounded by the same window.

- **Bitcoin Core's init-message notifier gains a subscriber on every node start and
  never drops one.** Confirmed in the node's log: after four starts in one app
  process, every `init message:` line is written four times, while every other line is
  written once. This is the same class of problem as the SOCKS flag already worked
  around at `Sources/Bitcoin/Daemon.swift:66-73` — a global upstream never resets
  because a normal process exits after shutdown, whereas ours restarts the node inside
  a living process. The effect today is about ten duplicated log lines per run, so it
  is not urgent, but it is unreleased state accumulating across restarts and the fix
  belongs with the other reset shims. Worth filing upstream.

- **Initial block download started from inside the app**, using the iOS 26
  continued-processing task. That mechanism **must be submitted while the app is on
  screen** and needs steady progress or the system ends it, so it can never serve an
  unattended automation — it is the right tool for someone tapping sync and then
  leaving the app, and the wrong tool for the daily refresh above. Recording this
  because the two are easy to confuse.
- Relocating chain data into a shared container, which would unlock a Home Screen
  panel or a Control Centre button. Cheaper now than after chains grow.
- The equivalent action for KernelApp, which drives its own sync loop and so can
  report real progress rather than polling.
- Whether the **interface** should also refuse to start without the proxy when the
  privacy setting is on. Today it starts and reconnects, which is visible to someone
  watching but still means a period of direct connections they did not ask for. That
  is a question about existing behaviour, not about this feature, and changing it
  would alter the foreground flow.

## 8. Division of labor

- **Agent:** all code, unit tests, and the build check.
- **You:** the device checks in §5 — a Home automation on a real phone with the
  screen locked cannot be exercised from a build machine.
