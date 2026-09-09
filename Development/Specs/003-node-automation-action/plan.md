---
feature: 003
title: Action that runs the node unattended from a Shortcuts automation
phase: null
status: In Progress
updated: 2026-09-08
adrs: [0005]
---

# Action that runs the node unattended from a Shortcuts automation

A Shortcuts action, added to an automation in the Shortcuts app (the Automations tab,
triggered by time or event — not the Home app's HomeKit automations), starts the
Bitcoin node while the phone is locked and the app is not running. Demo-app work, no
roadmap phase. A from-scratch rewrite: it lands first as a skeleton that only proves
the execution path, then grows the real behaviour.

The one decision the skeleton already embodies — run in-app, in the background, no
shared container — is ADR [0005](../../ADRs/0005-shortcuts-actions-run-in-the-app.md).
Two decisions that shape the real run are planned direction in §7, each to become its
own ADR when its code lands: never bypass the private network, and leave the node
running.

**Outstanding at this stage:** everything past the skeleton. The current build does no
node work — it logs that it ran and returns a line of text. The real run is §7.

## 1. Goal & success criteria

The skeleton (this stage):

- The action appears in the Shortcuts app once the app is installed.
- Running it by hand returns a line of text into the Shortcuts app, and writes a start
  and finish line to the system log (`os.log`, subsystem `dev.21.NodeApp`, category
  `Shortcut`).
- Triggered with no screen present, the app launches in the background and the action
  runs without opening the app.

The feature it grows into (§7):

- An automation triggers the action with the phone locked and the app not running, and
  the node starts.
- The node keeps running afterwards and is not stopped unless asked.
- It never interrupts a node someone started themselves (ADR 0005).
- It never connects without the private network when that is asked for.

## 2. Scope

**Platforms: phone and tablet only.** A Shortcuts automation runs on a phone or
tablet, never on a Mac, so the purpose is unreachable there. NodeApp still builds for
Mac, so the action is gated by a compile-time condition (`#if os(iOS)`), not an
availability annotation — an annotation still compiles the code into the Mac build and
refuses it only at runtime.

**In scope (this stage):** one action in the NodeApp target (`SyncNodeIntent`) that
logs and returns text; its registration so it appears in Shortcuts
(`NodeAppShortcuts`); the iOS 27 variant as a skeleton (§3.5); the device-condition
decision (§3.6). The action stays a thin adapter that returns quickly, so the real
work is a swap rather than a rewrite.

**Out of scope:** starting the node and every behaviour that depends on it · the
sister KernelApp's action · a shared data container · the longer execution window in
earnest. All in §7.

## 3. Design

### 3.1 A thin action

`SyncNodeIntent` is an `AppIntent` in the NodeApp target. Its `perform()` runs in the
background, records a start and finish line, and returns a fixed line of text as a
simple value plus a matching dialog. A simple value rather than a structured entity is
the lighter idiomatic choice, revisited only if a later Shortcut step needs to branch
on individual fields (§7). Keeping `perform()` thin is what lets the longer execution
window be adopted later without reshaping the action.

### 3.2 Why in-app and in the background

The daemon runs inside the calling process and the chain data lives in the app's own
locked folder, so the action must run in the app's process to reach it; the system
launches the app in the background for exactly this. Running in the background is
declared two ways for full coverage — `supportedModes` on iOS 26+, the older
`openAppWhenRun` on iOS 18–25 (§7 retires the latter). Full reasoning in ADR 0005.

### 3.3 What it will grow into

The real run — start the node, gate on the private network, report through a silent
notification, leave the node running — is deliberately not in the skeleton. Those
decisions are planned direction in §7, each to become its own ADR when its code lands
and its behaviour is measured on this branch rather than inherited.

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
Applied to the skeleton now so it is compiler-enforced. A standard idiom, so recorded
here rather than as an ADR; it binds the later KernelApp action the same way.

### 3.5 The longer-running variant (iOS 27)

`LongRunningIntent` (a 2026 type letting a Shortcut action run past the ~30-second
limit while the system shows a progress card) exists only in the iOS 27 set of Apple
APIs. A type's capabilities are fixed when built, so one type cannot be the
long-running kind only on newer systems: the longer-running form is a **separate**
type, `SyncNodeLongRunningIntent`, beside the baseline `SyncNodeIntent`.

Three things let it coexist with an app supporting iOS 18 and built day-to-day with an
older Xcode:

- **Compile fence** — `#if compiler(>=6.4)`, so the everyday toolchain skips the file.
  Necessary because a runtime `@available` check cannot rescue a symbol the
  compiled-against SDK lacks; the compiler version stands in for "iOS 27 SDK present",
  reliable because each Xcode ships a fixed compiler+SDK pair.
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
- **Clean-stop hook** — also conforms to `CancellableIntent`, so a stop (by the person,
  or by the system on timeout) can run a graceful shutdown. Logs only in the skeleton.

Like the baseline this is a **skeleton**: it logs, ticks one unit of progress (the
mandatory heartbeat that keeps the extended run alive), and returns.

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

Only the decision lands here; the code that *reads* these conditions is
framework-dependent, cannot be exercised in CI, and lands with its caller (§7).

## 4. Implementation steps

1. The action and its registration, background-only, logging and returning text.
2. A process-owned owner (`NodeSession`) for the node and address-hiding-network
   controllers, reachable with no screen present; the main screen reads it instead of
   creating its own.
3. The decisions a run makes as free functions with no framework types
   (`NodeAutomation`: which step to take, and the refuse-to-start-without-a-proxy
   guard), unit-tested.
4. The iOS 27 longer-running variant (`SyncNodeLongRunningIntent`) as a skeleton behind
   a compile fence, one visible action per system version, clean-stop hook wired but
   empty (§3.5).
5. Whether device conditions allow a run at all (`NodePreflight`), unit-tested (§3.6).
6. Start the node behind the private-network gate; report through a silent
   notification.
7. Device verification with the screen locked (§5).

## 5. Verification

- [x] The action appears in the Shortcuts app after install.
- [ ] Run by hand, it returns text into the Shortcuts app and logs a start and finish
      line.
- [ ] Triggered with no screen present, the app launches in the background and the
      action runs without opening the app.
- [x] On iOS 18–26, only the short-run action appears and the app does not crash at
      launch. This was the one unverified risk in registering an action that only exists
      on newer systems; it does not occur, so no fallback is needed.
- [x] On iOS 27, "Keep Bitcoin Node Syncing" shows a progress display, confirming the
      extended time window engages.
- [ ] On iOS 27, that display's stop button ends the run and logs
      `run: cancelled (userCancelled)`. Not yet exercisable: the first attempt showed
      the display appear at 0% and vanish before it could be tapped, because the
      skeleton finishes in milliseconds. A temporary paced loop now holds a run open for
      about 30 seconds so the button can be reached; it is removed when real node work
      replaces it.
- [ ] (Later) Triggered with the phone locked and the app not running, the node starts.
- [ ] (Later) With the private network on and unreachable, the action refuses and the
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
  "about to be stopped" signal is the iOS 27 stop hook (§3.5), which is where a graceful
  shutdown belongs; otherwise state is written as the run goes and the node replays its
  own on-disk state next start.
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

- **Start the node and report the result.** Reach the process-owned node with no screen
  present, start it, wait only until it first answers, and return. The first real-work
  commit. It carries two agreed but unbuilt decisions, each to be ratified as its own
  ADR in the commit that implements it:
    - **Never bypass the private network.** With the privacy setting on and the private
      connection not established, the node does not start — never a fallback to a direct
      connection, which would expose the person's home network address after they asked
      it not to.
    - **Leave the node running by default.** The run returns as soon as the node answers
      and does not stop it; stopping is an explicit, off-by-default switch. This is why
      the prior implementation's self-managed shutdown deadline and "don't-suspend-me"
      assertion are not being rebuilt.
- **Read the device conditions, and mark clean shutdowns.** Both pair with node-start:
    - **Reading the six conditions** §3.6 consumes. Deferred because the code is
      framework-dependent and cannot be exercised in automated checks. Notes for
      whoever writes it: read free space as the figure the system reports for
      *important* usage, not raw free bytes, and treat it as a courtesy check — it counts
      space the system may not reclaim in time, so a write failure must still be handled.
      Also consider reading whether the device is plugged in; a multi-minute run is far
      more appropriate while charging, which may justify relaxing the heat and
      battery-saver checks.
    - **A clean-shutdown marker.** Write a file when the node stops cleanly and remove
      it, so its presence at next launch means the previous run was ended without
      warning — the standard way to detect an unannounced end, and it would turn "the
      node recovered every time" (§6) into something the logs show. Needs a real node
      stop to mark.
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
    - **The longer execution window (`LongRunningIntent`, iOS 27)** — most promising;
      skeleton exists (§3.5). Remaining: real start/report inside
      `performBackgroundTask`, real shutdown inside `onCancel`, and whether an
      unattended trigger even qualifies — needs a physical iOS 27 device.
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
- **A structured return entity.** Upgrade from the simple text value only if a later
  Shortcut step needs to branch on individual figures (height, chain, blocks behind).
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
be verified by hand on a device, which is why §5 exists and why the skeleton ships
first — to prove that path before real work depends on it.
