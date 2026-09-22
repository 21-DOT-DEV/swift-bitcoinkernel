---
adr: 0005
title: Shortcuts actions run inside the app, in the background, with no shared container
status: Accepted
date: 2026-09-06
supersedes: []
superseded_by: null
---

# 0005 — Shortcuts actions run inside the app, in the background, with no shared container

## Context

The Shortcuts action for NodeApp can be published from the app target itself or from
a separate program bundled alongside it, and it can either open the app or run
without a screen. Two facts decide it. The Bitcoin daemon runs inside the calling
process, and the chain data lives in the app's own private folder on which the
daemon holds an exclusive lock, so a second process starting against that folder is
refused rather than admitted. And the established guidance for App Intents is to
leave the app in the background (`openAppWhenRun = false`) for work that does not
need a screen, since the system launches the app in the background to run the action
regardless. This record fixes those choices for the skeleton so the later work is a
swap, not a reversal.

## Decision

The action lives in the NodeApp target and runs in the background:
`openAppWhenRun` stays `false`. No shared container (an "App Group": a folder a
separate process could reach) is introduced, because the action runs in the app's
own process and reaches the chain folder directly.

## Alternatives considered and rejected

A separate bundled program, rejected because it runs in its own sandbox and could
not open the app's private chain folder without a shared container and a data
migration, and would then collide with the app on the folder's exclusive lock.
Bringing the app to the foreground per run, rejected because `openAppWhenRun` is
read by the system before the action runs and cannot be decided at run time, and
because foregrounding exercises the wrong path for an unattended automation, which
by definition has no screen.

## Consequences

No shared container and no data migration are needed while the action runs in the
app's process. The action must be written to run with no interface present. A shared
container returns as a requirement only if the action later moves into a separate
process — an App Intents extension or a widget — or must share chain data with the
sister KernelApp; both are follow-ups in
`../Specs/003-node-automation-action/plan.md` §7. Since this record was written the
mechanism arrived to enforce it rather than merely intend it: iOS 27's
`allowedExecutionTargets` (`ExecutionTargets.main`) pins the intents to the app
process, so an extension target appearing later cannot silently route a run — and a
second daemon against the folder's exclusive lock — into a sandbox that cannot hold
it. Two other details have drifted and are corrected here rather than left stale:
background execution is now `supportedModes = .background` on iOS 26+, with the
deprecated `openAppWhenRun` carried only for the iOS 18–25 runtimes (it goes when the
floor reaches iOS 26), and the iOS 27 long-running action holds the same floor. This
is the one decision the current skeleton embodies; the behaviour it will grow into
(the private-network gate, leaving the node running) is planned direction in that
same plan, to be recorded as its own ADR when its code lands. This binds KernelApp's
later action as well.
