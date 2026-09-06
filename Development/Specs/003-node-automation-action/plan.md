---
feature: 003
title: Home automation action that runs the node unattended
phase: null
status: Planned
updated: 2026-09-06
adrs: [0005, 0006, 0007, 0008, 0009]
---

# Home automation action that runs the node unattended

A Shortcuts automation triggers an action that starts the Bitcoin node while the phone
is locked and the app is not running. The node then keeps syncing on its own for several
minutes after the action returns, which is where nearly all the progress happens.

## 1. Goal & success criteria

- An automation triggers the action with the phone locked and the app not running, and
  the node starts.
- The node keeps running afterwards and is not stopped unless the person asked for it.
- Something reaches the person describing what happened — an unattended run has no
  screen, so the value the action hands back is never displayed.
- It never interrupts a node someone started themselves (ADR 0005).
- It never connects without the privacy network when the person asked for it (ADR 0006).
- After the system kills the node, the next start recovers by replaying rather than
  rebuilding.

## 2. Scope

**Platforms: phone and tablet only.** An automation runs from a phone, tablet or home
hub, never from a Mac, so the purpose is unreachable there. Gating is by compile-time
condition (`#if os(iOS)`), not an availability annotation — an annotation still compiles
the code into a Mac build and refuses it only at runtime.

**In scope:** one action in the NodeApp target; an owner for the node that outlives any
screen; ownership tracking so a node the action did not start is never stopped; a bounded
wait for the privacy network when enabled; a notification carrying the outcome; unit
tests for every decision the action makes.

**Out of scope:** the longer window (§7) · the second app's action · moving chain data
into a shared container (§7) · any change to how the node syncs.

## 3. Design

### 3.1 A node owner that outlives the screen

The node and privacy-network controllers belong to the process, not to a screen, so an
action can reach them when no interface exists. A single shared owner also stops two
runs triggered close together from both believing they own the node.

### 3.2 What the action does, in order

1. Raise a request that the system not suspend the app, released on every exit path.
2. If a node is already running, read it, report, and leave it alone (ADR 0005).
3. If the privacy setting is on and the network is not ready, refuse to start and say so
   (ADR 0006). Never start on a direct connection.
4. Otherwise start the node and wait only until it first answers.
5. Report, and return — without stopping the node (ADR 0009).

Stopping is a switch on the action, off by default. With it on, step 5 waits until the
deadline, stops the node, and then reports; ADR 0007 governs that path.

A node that never answered is never asked to stop, whatever the switch says. It is still
starting, cannot service the request, and the wait for it cannot be interrupted — asking
anyway hangs the run until the system kills it, which the person sees as a timeout.

### 3.3 What the action returns and reports

The value handed back always carries the outcome, chain, height, how far behind the
chain is, and progress since the last recorded height. How long it waited, how many
connections it had, and the age of a saved height appear **only when actually measured** —
absent means not measured, where zero would mean measured and nothing.

Progress is counted from the last height the app recorded, not from the start of this
run. The run itself gains almost nothing because it returns immediately; the node's real
progress happens afterwards, and only the next run can see it.

The four ways a run can end are written once and the Shortcuts-facing list is derived
from them, so adding a fifth will not compile until it is accounted for.

Reporting is a notification, because an unattended run has no screen to show the value
it returns. Its wording is unit-tested. Delivery failure can never fail a run.

### 3.4 Timing

Every figure comes from ADR 0008 and must be measured with the screen locked; attended
measurements are 3.5 to 9 times faster and unusable for this purpose. ADR 0009 covers why
the run does not wait.

## 4. Implementation steps

1. Process-level owner for the node and privacy-network controllers.
2. Decision logic as free functions, unit-tested, with no framework types.
3. The action, kept thin, calling those functions.
4. The outcome type and its wording, testable without a device.
5. The notification.
6. Device verification (§5).

## 5. Verification

- [x] The action appears in Shortcuts and runs from an automation.
- [x] Triggered with the phone locked and the app not running, the node starts.
- [x] A run reports through a notification with no permission prompt.
- [x] After a run the node is killed rather than shut down, and the next start recovers.
- [ ] Triggered while the app is open and syncing, the action reports and returns
      without stopping the node.
- [ ] With the privacy network on and reachable, the node starts through it.
- [ ] With the privacy network on and unreachable, the action refuses and the node never
      starts — verified by confirming no direct connections were made, not by reading the
      message.
- [ ] With the stop switch on, the node is stopped and the run stays inside its window.
- [ ] A run that returns in a couple of seconds still leaves the node syncing. **Never
      tested** — every observed survival followed a run that waited about 21 seconds.
- [ ] Whether raising the node thread's scheduling band shortens a locked start-up.
      Measured from the node's own log: the gap between `Loading block index` and
      `Loaded best chain`, across several locked runs, against the 47–424 second range
      recorded before the change. A null result rules out this lever only; it would not
      distinguish throttling from the app being repeatedly suspended (§7).

## 6. Risks and mitigations

- **The node surviving after the action returns is observed, not promised.** The system
  releases its hold when the action returns; that the app is not frozen immediately is
  its choice. → Recorded in ADR 0009; nothing depends on a particular duration, and the
  feature degrades to a status report if it stops.
- **The node is normally killed mid-write.** → It has recovered by replaying every time
  across device testing, never requiring a rebuild. Verified in §5, not assumed.
- **A locked-screen start can take minutes.** → The action reports honestly and returns
  rather than hanging; the node finishes starting on its own.
- **Runs are not guaranteed to happen on time or at all.** → Each run reports for itself;
  nothing depends on a schedule being kept.
- **The privacy network's cached directory data goes stale after a few hours**, so an
  infrequent automation spends its window re-establishing the connection. → Documented in
  the action's description.

## 7. Out of scope (follow-ups)

> **What this can and cannot do.** It keeps a node current and, given enough triggers,
> can make real progress on catching one up — a single trigger has gained over 2,000
> blocks. It is not a substitute for leaving the app open.

- **A longer window via `LongRunningIntent`** (iOS 27, released 2026-09-14). Extends
  execution past the 30-second limit and renders a progress card without any card code.
  The most promising follow-up. Unknown whether an unattended trigger qualifies — that
  needs a probe before anything is built on it.
- **Bitcoin Core's start-up message notifier gains a subscriber on every node start and
  never drops one**, so after four starts in one app process every start-up line is
  written four times. Same class as the reset already worked around at
  `Sources/Bitcoin/Daemon.swift:66-73`. Harmless today; worth reporting upstream.
- **Why a locked start-up is 4 to 35 times slower is not established.** Two
  explanations fit the evidence equally well: the system throttles disk reads for
  low-priority work, or it suspends and resumes the app repeatedly, which from outside
  looks the same. Loading the block index emits almost no log lines, so there is no way
  to tell them apart from what we have. This matters because start-up now directly
  reduces how much the node syncs — its life after the action returns is finite, and
  loading consumes most of it.

  One cheap lever has been tried: the node's thread now asks for the `.utility`
  scheduling band rather than the default (`Sources/Bitcoin/Daemon.swift`). That would
  help under the first explanation and do nothing under the second. Confidence is low —
  the evidence that a thread's own setting survives a limit applied to the whole
  backgrounded app is weak, and what exists suggests it may not. **A null result rules
  out this lever, not the throttling explanation.**

- **Peer connection is slow and unreliable** — two runs in three have gained nothing
  because no peer connected in time. Naming a few known-good peers would help, at a
  decentralisation and privacy cost.
- **Moving chain data to a shared container**, needed only when a second app or an
  extension must reach it.

### Considered and rejected

Kept so they are not proposed again.

- **A Live Activity card.** A card grants no extra running time — it is a display, and
  the run is still bounded. Its receipt is also removed four hours after ending, so an
  overnight run's card is gone before anyone wakes.
- **Push-driven card updates.** The only way to update a card after the process dies, and
  it means a server learning when this device syncs. Closed off by ADR 0006's reasoning.
- **`BGContinuedProcessingTask`** (iOS 26). Must be submitted from the foreground in
  response to an explicit tap, so it can never serve an unattended automation.
- **Reading the node's start-up replies to drive the display.** Built and deleted:
  removing one line that recorded a false failure achieved the same result, and the
  existing screen already shows the node's own description of what it is doing.
- **Faster node start-up settings.** Worth about a second against a ten-second cost, and
  naming the verification setting explicitly makes the node refuse to start when memory
  is short rather than skipping the check.
- **Waiting longer before returning.** The hold does not protect the node — the system's
  hold is released when the action returns either way — so waiting only pushes the run
  toward the cut-off.

## 8. Division of labor

Decision logic lives in free functions with no framework types, so it is testable on
every platform in CI. The action orchestrates and does no deciding. Anything touching
Shortcuts, notifications or the system's suspension rules can only be verified by hand on
a device, which is why §5 exists.
