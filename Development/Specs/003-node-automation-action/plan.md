---
feature: 003
title: Action that runs the node unattended from a Shortcuts automation
phase: null
status: In Progress
updated: 2026-09-19
adrs: [0005, 0006, 0007, 0008, 0009]
---

# Action that runs the node unattended from a Shortcuts automation

A Shortcuts action, added to an automation in the Shortcuts app (the Automations tab,
triggered by time or event — not the Home app's HomeKit automations), starts the
Bitcoin node while the phone is locked and the app is not running. Demo-app work, no
roadmap phase. A from-scratch rewrite: both actions call one shared run routine
(`NodeRun.perform`) that does the real node work — start behind the private-network
gate, wait for the first answer, report honestly — so the two cannot drift apart.

The decisions the shipped run embodies — run in-app, in the background, no shared
container — is ADR [0005](../../ADRs/0005-shortcuts-actions-run-in-the-app.md).
Four recovered records carry the run's remaining durable rules:
[0006](../../ADRs/0006-unattended-runs-never-bypass-tor.md) (accepted — never fall
back to a direct connection),
[0007](../../ADRs/0007-unattended-actions-own-their-deadline.md) (superseded by 0009 —
the self-managed shutdown deadline, kept as the road not taken), and
[0008](../../ADRs/0008-unattended-timings-are-measured-on-a-locked-device.md) +
[0009](../../ADRs/0009-unattended-runs-leave-the-node-running.md) (both proposed
until their figures are re-measured with the screen locked on this branch).

**Outstanding at this stage:** the locked-device verification in §5 — the real run
has landed but its timings and the iOS 27 stop button have not been confirmed on a
physical device with the screen locked, which is what ADRs 0008 and 0009 wait on.

## 1. Goal & success criteria

- An automation triggers the action with the phone locked and the app not running, and
  the node starts.
- The node keeps running afterwards and is not stopped unless asked.
- It never interrupts a node someone started themselves (ADR 0005).
- It never connects without the private network when that is asked for.
- The outcome is honest and typed: an automation can branch on what actually happened
  (started, already running, declined, still coming up, no answer).
- On iOS 27, the longer-running action shows a progress card the person can stop.

## 2. Scope

**Platforms: phone and tablet only.** A Shortcuts automation runs on a phone or
tablet, never on a Mac, so the purpose is unreachable there. NodeApp still builds for
Mac, so the action is gated by a compile-time condition (`#if os(iOS)`), not an
availability annotation — an annotation still compiles the code into the Mac build and
refuses it only at runtime.

**In scope:** two actions in the NodeApp target — the baseline `SyncNodeIntent` and
the iOS 27 `SyncNodeLongRunningIntent` — sharing one run routine (`NodeRun`); their
registration (`NodeAppShortcuts`); the process-owned `NodeSession`; the decisions a
run makes as testable free functions (`NodeAutomation`, `NodePreflight`); the typed
report (`NodeRunReport`); and the progress card's honesty policy (`ProgressMeter`).

**Out of scope:** the sister KernelApp's action · a shared data container · a silent
notification for the outcome · localization · anything else in §7.

## 3. Design

### 3.1 A thin action

`SyncNodeIntent` is an `AppIntent` in the NodeApp target. Its `perform()` calls the
shared run routine and returns a `NodeRunReport` — a structured entity with named
fields (outcome, chain, heights, connections) a later Shortcut step can branch on —
plus a dialog built from the report's summary sentence. A structured entity rather
than a simple value: unattended outcomes are exactly where a following step wants
fields, and "started" versus "already running" cannot be told apart in one line of
text. Keeping `perform()` thin — it orchestrates, never decides — is also what let
the longer execution window be adopted without reshaping the action.

### 3.2 Why in-app and in the background

The daemon runs inside the calling process and the chain data lives in the app's own
locked folder, so the action must run in the app's process to reach it; the system
launches the app in the background for exactly this. Running in the background is
declared two ways for full coverage — `supportedModes` on iOS 26+, the older
`openAppWhenRun` on iOS 18–25 (§7 retires the latter). Full reasoning in ADR 0005.

### 3.3 What it grew into

The real run — start the node, gate on the private network, return an honest typed
report, leave the node running — is `NodeRun.perform`, the one routine both actions
call. The decisions it embodies are recorded under `../../ADRs/`: 0006 is accepted
(its refusal ships as `NodeAutomation.startArguments` — a run that cannot honour the
private-network setting declines rather than falling back); 0008 and 0009 are
proposed until their behaviour is measured on this branch rather than inherited. A
silent notification for the outcome was considered and deferred (§7) — the typed
report and its dialog are the evidence a run happened.

### 3.4 Reaching the process-owned state across the thread boundary

`NodeSession` (the holder owning the node and address-hiding-network controllers for
the whole process) is isolated to the main actor — the thread that owns
user-interface state — because it holds main-actor view-models. An action's
`perform()` runs off that thread by default, and under Swift 6 (this project's
language mode) an un-isolated `perform()` cannot touch `NodeSession` without a compile
error, so the start step could not build without crossing that line.

**Decision:** mark `perform()` itself `@MainActor` — it mostly orchestrates main-actor
state, while the node's heavy work runs on its own thread and every wait is an `await`
that frees the main actor. Rejected: per-access hops, which suit a mostly-background
method; and un-isolating the holder, which would let two threads race on the same
view-models. **The rule this carries:** any future heavy or synchronous step inside
`perform()` must be pushed off the main actor explicitly (noted beside the code).
Applied throughout the run so it is compiler-enforced. A standard idiom, so recorded
here rather than as an ADR; it binds the later KernelApp action the same way.

### 3.5 The longer-running variant (iOS 27)

`LongRunningIntent` (a 2026 type letting a Shortcut action run past the ~30-second
limit while the system shows a progress card) exists only in the iOS 27 set of Apple
APIs. A type's capabilities are fixed when built, so one type cannot be the
long-running kind only on newer systems: the longer-running form is a **separate**
type, `SyncNodeLongRunningIntent`, beside the baseline `SyncNodeIntent`.

Three things let it coexist with an app supporting iOS 18:

- **Toolchain requirement, not a compile fence** — the demo apps require the iOS 27
  SDK toolchain (Xcode 27+) to build. A runtime `@available` check cannot rescue a
  symbol the compiled-against SDK lacks, so the choice is binary: fence the file out
  on older toolchains, or require the newer one. An earlier `#if compiler(>=6.4)`
  fence covered the Xcode 26→27 transition; it was removed once Xcode 27 became the
  declared minimum, because a silently feature-less build is worse than a loud
  compile failure. The iOS 18–26 *runtime* gate remains — it is the
  `if #available` in `NodeAppShortcuts`, not a compile fence.
- **Two actions, not one that switches type.** The extended runtime goes only to the
  type the system launches, so the long-running type must itself be registered —
  delegation from the baseline would not get the window. Registering *one* action whose
  backing type changes with the system version is impossible: it needs an `if/else`, and
  the list of published actions is read from source text as compile-time constants, which
  accepts a bare `if #available(…)` but rejects general branching ("closure containing
  control flow statement cannot be used with result builder"). Helper properties are
  rejected too. So `NodeAppShortcuts` registers the baseline unconditionally and adds
  the iOS 27 variant alongside. On iOS 18–26 a person sees one action; on iOS 27, two.
  Each shape was tested against Xcode 26.4 and 27; the rules are recorded beside the
  code. A further wall found by testing: **only one type in the app may publish the
  actions list** ("Only 1 `AppShortcutsProvider` conformance is allowed"), so a second
  provider is not an escape route — and the sister KernelApp cannot add its own to this
  app either.

**Naming, so the two are not confusable.** They are named as two different actions
rather than a base and a variant: **Sync Bitcoin Node** (short run) and **Keep Bitcoin
Node Syncing** (runs past the usual limit, with a progress display that can be
stopped), each with its own spoken phrases and icon. Both were previously called "Sync
Bitcoin Node", which left two indistinguishable entries side by side when building an
automation. The second name is also written to read well on its own, because it is the
one that survives the other's retirement; a name like "… (Extended)" would end up
referring to a sibling that no longer exists.

**What is safe to rename later, and what is not.** A saved automation refers to an
action by its **code-level type name** (here `SyncNodeLongRunningIntent`), not by the
name a person reads. So:

| Changing… | Breaks a saved automation? |
|---|---|
| The displayed name or the description | No — label only |
| The code-level type name, or a setting's variable name or type | **Yes** — that is the stored reference |
| A spoken phrase | No, but it breaks the words someone learned to say, and how they find the action |

That makes the *type* names the durable commitment, so they are worth settling before
release; displayed names stay adjustable, and spoken phrases should not be rewritten
casually even though nothing breaks. If a type name ever must change, keep the old type
as a deprecated stand-in that forwards to the new one rather than deleting it — which is
also the mechanism for retiring the short-run action (§7).
- **Stop hook** — also conforms to `CancellableIntent`, so a stop (by the person, or
  by the system on timeout) reaches `onCancel` with its reason. No shutdown runs
  there — the node is deliberately left running (ADR 0009), and a node still inside
  its own start-up could not service a stop anyway. What the hook does is record the
  reason, which is how the run tells the person's dismissal from the system's
  patience ending: the first leaves the card alone, the second writes an honest
  "run cut short" ending — while the node keeps running either way.

Unlike the baseline, this action wraps the shared run in `performBackgroundTask` and
drives the system progress card throughout — the heartbeat the extended window
demands. The card's honesty policy lives in `ProgressMeter`: the bar never retreats,
the heartbeat's total contribution is capped at half the bar and is spent only
during real silence, and nothing but an earned finish fills it.

### 3.6 Declining a run the device cannot serve

Starting the node runs for minutes and writes continuously, so a run first checks six
device conditions and declines with a reason rather than starting and quietly
achieving nothing (`NodePreflight` — plain values, no framework types, so it is
unit-testable in CI without a device):

| Condition | Why it stops a run |
|---|---|
| The app's files are not readable | Only between a restart and the first unlock; a run then cannot read the chain at all |
| Less than 1 GB free | The node writes continuously; filling the disk is far worse than skipping a run |
| The network is metered (cellular, or a link shared from another phone) | Catching up a chain moves gigabytes; the one condition that costs money rather than battery |
| Low Data Mode is on for this network | A stated preference to use as little data as possible. Separate from metered: Low Data Mode on home wireless is restricted but not metered, and either alone should stop a multi-gigabyte sync |
| The device is already too hot | Adding minutes of sustained work makes it worse |
| Battery saver is on | The person asked the device to conserve; a multi-minute run contradicts that |

The reported reason is the most fundamental one when several apply, in that order —
both network conditions ahead of heat and battery saver, since spending someone's data
allowance unasked is the only outcome that costs money. Unknown free space is **not**
treated as too little, or a device that cannot report it would never run.

**File readability was checked, not assumed:** the app declares no stricter file
protection, so its files take the platform default — readable from the first unlock
after a restart, and still readable when merely locked. A locked-phone run reads the
chain fine; only the pre-first-unlock window is closed, which the first check covers.
This also rules file protection out as a cause of the slow locked-screen start-ups
in §6.

The decision lives in `NodePreflight`; the code that *reads* the conditions is
framework-dependent, cannot be exercised in CI, and ships with its caller
(`NodeRun.readConditions`).

## 4. Implementation steps

1. The actions and their registration, background-only (`SyncNodeIntent`,
   `NodeAppShortcuts`).
2. A process-owned owner (`NodeSession`) for the node and address-hiding-network
   controllers, reachable with no screen present; the main screen reads it instead of
   creating its own.
3. The decisions a run makes as free functions with no framework types
   (`NodeAutomation`: which step to take, and the refuse-to-start-without-a-proxy
   guard), unit-tested.
4. The iOS 27 longer-running variant (`SyncNodeLongRunningIntent`) — iOS-27-only at
   runtime, Xcode-27-only at build time — sharing the same run routine, its stop
   hook recording the cancellation reason (§3.5).
5. Whether device conditions allow a run at all (`NodePreflight`), unit-tested (§3.6),
   read live by the run (`NodeRun.readConditions`).
6. The shared run (`NodeRun.perform`): start the node behind the private-network
   gate, every question bounded by `withHardTimeout`, an honest typed report
   (`NodeRunReport`), and the progress card's honesty policy (`ProgressMeter`).
7. Device verification with the screen locked (§5).

## 5. Verification

- [x] The action appears in the Shortcuts app after install.
- [ ] Run by hand, it returns a report into the Shortcuts app and logs a start and
      finish line.
- [ ] Triggered with no screen present, the app launches in the background and the
      action runs without opening the app.
- [x] On iOS 18–26, only the short-run action appears and the app does not crash at
      launch. This was the one unverified risk in registering an action that only exists
      on newer systems; it does not occur, so no fallback is needed.
- [x] On iOS 27, "Keep Bitcoin Node Syncing" shows a progress display, confirming the
      extended time window engages.
- [ ] On iOS 27, that display's stop button ends the run and logs
      `run: cancelled (userCancelled)`. Now exercisable — real node work holds the
      run open long enough to reach the button — but not yet confirmed on device.
- [ ] Triggered with the phone locked and the app not running, the node starts.
- [ ] With the private network on and unreachable, the action refuses and the
      node never starts — confirmed by no direct connections being made, not by reading
      the message.

## 6. Risks and mitigations

- **A background-launched action gets only about 30 seconds, and once it returns the
  system may pause or shut down the app — which stops the node, because the node runs
  inside the app's own process.** The defining constraint of the feature. → The action
  never depends on more than that window: it returns as soon as the node first answers.
  How long the node keeps running afterwards is not guaranteed; §7 covers the ways one
  might extend it and why none is reliable today.
- **When the system ends a paused app it sends no warning of any kind.** The
  "app will terminate" callback fires only while an app is still running, and a
  memory-reclaiming kill gives no notice, so no code can run then to shut the node down
  cleanly. → Nothing is designed around a final-warning callback. The only genuine
  "about to be stopped" signal is the iOS 27 stop hook (§3.5), which records the
  cancellation reason so the run can tell a dismissal from a timeout — the node
  itself is deliberately left running (ADR 0009). State is written as the run goes
  and the node replays its own on-disk state next start.
- **A run that stops reporting progress can be cut short by the system.** On the iOS 27
  action, advancing progress is what keeps the extended time window open — not
  decoration. A first version set the total before the run and the completed count
  after it, so the display sat at 0% throughout (seen on device) and a real run would
  have risked being killed by the very mechanism meant to keep it alive. → Progress is
  advanced from inside the run, repeatedly; the real node work must keep doing so.
- **A locked-screen start can take minutes.** Observed on the prior implementation, not
  yet measured here. → Must be re-measured on this branch before any budget rests on
  it; the real run reports honestly and returns rather than hangs.
- **The node's survival after the action returns is an observation to reproduce, not a
  promise.** → Nothing will depend on a particular duration; the feature degrades to a
  status report if survival does not hold.
- **Timings measured on an unlocked device mislead** — an attended device is throttled
  far less. → Any timing that sets a budget or deadline is measured with the screen
  locked.

## 7. Out of scope (follow-ups)

Ordered roughly by when each is needed.

- **Mark clean shutdowns.** Write a file when the node stops cleanly and remove it, so
  its presence at next launch means the previous run was ended without warning — the
  standard way to detect an unannounced end, and it would turn "the node recovered
  every time" (§6) into something the logs show. Needs a real node stop to mark.
  Related: consider reading whether the device is plugged in alongside the §3.6
  conditions; a multi-minute run is far more appropriate while charging, which may
  justify relaxing the heat and battery-saver checks.
- **A silent notification for the outcome.** An unattended run has no screen, so the
  returned value is never displayed; a quiet local notification (provisional
  authorisation, so no permission prompt) is the only evidence the run happened.
  Meaningful only once there is a real outcome.
- **A shared data container (App Group).** Not needed while the action runs in the app's
  own process (ADR 0005). Required only if the action moves to a separate process — an
  App Intents extension or a widget — or must share chain data with KernelApp, since
  separate processes have separate sandboxes.
- **The sister KernelApp's action.** ADR 0005 and the two decisions above are written to
  bind it, but the shared abstraction is better designed once two real cases exist.
- **Keeping the node running after the action returns — the open problem.** No
  third-party app gets a guaranteed always-on background process, so the node runs only
  until the system pauses the app. Options, none reliable today:
    - **The longer execution window (`LongRunningIntent`, iOS 27)** — shipped (§3.5):
      the action wraps the shared run in `performBackgroundTask` and drives the
      progress card. No shutdown runs inside `onCancel` by design (ADR 0009).
      Remaining: whether an unattended trigger qualifies for the extended window at
      all, and the ADR 0009 re-measurement — both need a physical iOS 27 device.
    - **A background maintenance job (`BGProcessingTask`)** — runs minutes, but only
      while the device is idle, and ends when the person touches it. Might
      *opportunistically* extend runtime; **worth measuring** once node-start exists.
      **Prerequisite, absent today:** the Background Modes capability with its
      "background processing" option, plus the task identifier in the app's settings
      file — so this cannot be attempted without a project-configuration change.
    - **A user-tap background task (`BGContinuedProcessingTask`, iOS 26)** — rejected:
      needs an explicit tap, so it cannot serve an unattended automation.
    - **An always-on background mode** (audio, location, voice calling, external
      accessories, Bluetooth accessory) — rejected as a group: none describes a Bitcoin
      node, and claiming one to buy running time invites app-store rejection.
    - **Accept that the system pauses the node — the current posture.** Start, report,
      let it run until suspended; degrade to a status report if it does not survive.
- **Retire the older background-run flag.** The action declares both `supportedModes`
  (iOS 26+) and `openAppWhenRun` (iOS 18–25) for the same behaviour. When the
  oldest-supported OS reaches iOS 26, drop the old flag.
- **Retire the short-run action, once only the iOS 27 one is wanted.** Do not delete it:
  anyone who built it into a larger shortcut would silently lose that step. Mark it
  deprecated with `replacedBy` pointing at `SyncNodeLongRunningIntent`, so people are
  guided to the survivor and existing automations keep working. Blocked until the app's
  oldest-supported OS reaches iOS 27.
- **Localized phrases and description.** The `title` is already localizable; the spoken
  phrases and description are English only. Localizing needs an `AppShortcuts` string
  catalog, which must also be added to NodeApp's `resources:` in
  `Projects/Project.swift`, since resources there are listed explicitly rather than
  globbed. Deferred: no localization target yet, and Apple's phrase rules are already
  met in English.
- **Discoverability metadata** — a category, search keywords, and a name for the
  returned value, which help the action surface in Spotlight. Optional polish, best
  added once the action does real work.

## 8. Division of labor

Decision logic lives in free functions with no framework types, so it is testable on
every platform in CI; the action orchestrates and does no deciding. Anything touching
Shortcuts, notifications, background launch or the system's suspension rules can only
be verified by hand on a device, which is why §5 exists — the execution path has been
proven, and what remains is locked-device verification of the real run.
