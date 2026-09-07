---
feature: 003
title: Action that runs the node unattended from a Shortcuts automation
phase: null
status: In Progress
updated: 2026-09-06
adrs: [0005]
---

# Action that runs the node unattended from a Shortcuts automation

A Shortcuts action, added to an automation in the Shortcuts app (the Automations tab,
triggered by time or event — not the Home app's HomeKit automations), starts the
Bitcoin node while the phone is locked and the app is not running. This is a from-scratch rewrite; it lands
first as a skeleton that only proves the execution path, then grows the real
behaviour in later commits. Demo-app work, no roadmap phase. The one decision the
skeleton already embodies — run in-app, in the background, no shared container — is
recorded in ADR [0005](../../ADRs/0005-shortcuts-actions-run-in-the-app.md). The two
decisions that shape the real run but are not yet built or measured here — never
bypass the private network, and leave the node running — are planned direction in
§7, each to be ratified as its own ADR when its code lands.

**Outstanding at this stage:** everything past the skeleton. The current build does
no node work — it logs that it ran and returns a line of text. The real run is §7.

## 1. Goal & success criteria

The skeleton (this stage):

- The action appears in the Shortcuts app once the app is installed.
- Running it by hand returns a line of text into the Shortcuts app, and writes a
  start and finish line to the system log (`os.log`, subsystem `dev.21.NodeApp`,
  category `Shortcut`).
- Triggered with no screen present, the app is launched in the background and the
  action runs without opening the app.

The feature it grows into (later commits, §7):

- An automation triggers the action with the phone locked and the app not running,
  and the node starts.
- The node keeps running afterwards and is not stopped unless asked (planned; §7).
- It never interrupts a node someone started themselves (ADR 0005).
- It never connects without the private network when that is asked for (planned; §7).

## 2. Scope

**Platforms: phone and tablet only.** A Shortcuts automation runs on a phone or
tablet, never on a Mac, so the purpose is unreachable there. NodeApp still builds
for Mac, so the action is gated by a compile-time condition (`#if os(iOS)`), not an
availability annotation — an annotation still compiles the code into the Mac build
and refuses it only at runtime.

**In scope (this stage):** one action in the NodeApp target (`SyncNodeIntent`) that
logs and returns text; its registration so it appears in Shortcuts
(`NodeAppShortcuts`). Background execution with no screen. The action stays a thin
adapter that returns quickly, so the real work is a swap rather than a rewrite.

**Out of scope (with owners):** starting the node and every behaviour that depends on
it (§7) · the sister KernelApp's action (§7) · a shared data container (§7) · the
longer execution window (§7). All are follow-ups, not part of the skeleton.

## 3. Design

### 3.1 A thin action

`SyncNodeIntent` is an `AppIntent` in the NodeApp target. Its `perform()` runs in the
background (`openAppWhenRun = false`), records a start and finish line, and hands back
a value — currently a fixed line of text via `ReturnsValue<String>` and a matching
dialog. Keeping the return a simple value rather than a structured entity is the
lighter idiomatic choice, and revisited only if a later Shortcut step needs to branch
on individual fields (§7). Keeping `perform()` thin is what lets the longer execution
window be adopted later without reshaping the action (§7).

### 3.2 Why in-app and in the background

The daemon runs inside the calling process and the chain data lives in the app's own
locked folder, so the action must run in the app's process to reach it; the system
launches the app in the background for exactly this. `openAppWhenRun` stays `false`
because an unattended automation has no screen and that is the path worth proving, and
because the flag is read before the action runs and cannot be decided per run. Full
reasoning in ADR 0005.

### 3.3 What it will grow into

The real run — start the node, gate on the private network, report through a silent
notification, leave the node running — is deliberately not in the skeleton. Those
decisions are planned direction in §7, each to become its own ADR when its code
lands and its behaviour is measured on this branch rather than inherited.

## 4. Implementation steps

1. The action and its registration, background-only, logging and returning text.
   **(this stage)**
2. A process-owned owner for the node and private-network controllers, reachable with
   no screen present. (§7)
3. Decision logic as free functions with no framework types, unit-tested. (§7)
4. Start the node behind the private-network gate; report through a silent
   notification. (§7)
5. Device verification with the screen locked (§5).

## 5. Verification

- [x] The action appears in the Shortcuts app after install.
- [ ] Run by hand, it returns text into the Shortcuts app and logs a start and finish
      line.
- [ ] Triggered with no screen present, the app launches in the background and the
      action runs without opening the app.
- [ ] (Later) Triggered with the phone locked and the app not running, the node
      starts.
- [ ] (Later) With the private network on and unreachable, the action refuses and the
      node never starts — confirmed by no direct connections being made, not by
      reading the message.

## 6. Risks and mitigations

- **A locked-screen start can take minutes, far longer than the ~30-second window.**
  Observed on the prior implementation (the APPLE-SHORTCUT branch), not yet measured
  here; it must be re-measured on this branch before any budget or deadline rests on
  it. → The real run will report honestly and return rather than hang; nothing in the
  skeleton is exposed to this yet.
- **The node's survival after the action returns is an observation to reproduce, not a
  promise.** The prior implementation saw it; this branch has not. → Nothing will be
  built that depends on a particular duration; the feature degrades to a status report
  if survival does not hold.
- **Timings measured on an unlocked device mislead** — an attended device is
  throttled far less than a locked one. → Any timing that sets a budget or deadline is
  measured with the screen locked; recorded here so it binds the later work.

## 7. Out of scope (follow-ups)

Ordered roughly by when each is needed. Each note says why it is deferred, on the
best practice that an App Intent's `perform()` stays thin and fast and that
process-crossing plumbing is added only when a second process actually exists.

- **Start the node and report the result.** The core behaviour: reach the
  process-owned node with no screen present, start it, wait only until it first
  answers, and return. The first real-work commit. It carries two decisions we have
  agreed but not yet built or measured here, each to be ratified as its own ADR in the
  commit that implements it:
    - **Never bypass the private network.** When the privacy setting is on and the
      private connection is not established, the node does not start — it never falls
      back to a direct connection, which would expose the person's home network
      address after they asked it not to. To become an ADR when the gate is coded.
    - **Leave the node running by default.** The run returns as soon as the node
      answers and does not stop it; stopping is an explicit, off-by-default switch.
      This is why the self-managed shutdown deadline and the "don't-suspend-me"
      assertion from the prior implementation are not being rebuilt. To become an ADR
      when the start path is coded and the node's post-return lifetime is measured on
      this branch.
- **A silent notification for the outcome.** An unattended run has no screen, so the
  value the action returns is never displayed; a quiet local notification
  (provisional authorisation, so no permission prompt) is the only evidence the run
  happened. Deferred because it is only meaningful once there is a real outcome to
  report.
- **A shared data container (App Group).** Not needed while the action runs in the
  app's own process (ADR 0005). Required only if the action later moves into a
  separate process — an App Intents extension or a widget — or must share chain data
  with KernelApp, because separate processes have separate sandboxes and reach shared
  state only through a group container. Added at that split, not before.
- **The sister KernelApp's action.** ADR 0005 is written to bind it, and the two
  planned decisions above are meant to as well, but the shared abstraction is better
  designed once two real cases exist rather than guessed from one.
- **The longer execution window (`LongRunningIntent`, iOS 27).** Extends execution
  past the ~30-second limit and renders a progress card without card code. The app's
  floor is iOS 18, and raising it drops every device below iOS 27, so this waits.
  Whether an unattended trigger even qualifies for the longer window is unknown and
  needs a probe before anything is built on it. The action is kept a thin, quick
  adapter so adopting it is a conformance change, not a rewrite.
- **A structured return entity.** The action returns a simple text value today.
  Upgrade to a multi-field entity only if a later Shortcut step needs to branch on
  individual figures (height, chain, blocks behind); until then the simple value is
  the lighter idiomatic choice.
- **Localized invocation phrases and description.** The action's `title` is already a
  localizable resource, but the spoken phrases and the `IntentDescription` are English
  only. Localizing means adding an `AppShortcuts` string catalog
  (`AppShortcuts.xcstrings`) and making the description a localized resource; the
  catalog must also be added to NodeApp's `resources:` in `Projects/Project.swift`,
  since resources there are listed explicitly rather than globbed. Deferred: a demo-app
  skeleton has no localization target yet, and Apple's phrase rules (short, app name
  included) are already met in English.
- **Discoverability metadata.** `IntentDescription` can carry a `categoryName` and
  `searchKeywords`, and the action can name its returned value, all of which help the
  action surface in Spotlight and the Shortcuts app. Deferred: optional polish, best
  added once the action does real work worth surfacing.

## 8. Division of labor

Decision logic will live in free functions with no framework types, so it is testable
on every platform in CI; the action orchestrates and does no deciding. Anything
touching Shortcuts, notifications, background launch or the system's suspension rules
can only be verified by hand on a device, which is why §5 exists and why the skeleton
ships first — to prove that path before real work depends on it.
