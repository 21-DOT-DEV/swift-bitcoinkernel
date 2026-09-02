---
adr: 0004
title: Keep the screen awake through high-level Foundation and UIKit APIs
status: Accepted
date: 2026-07-20
supersedes: []
superseded_by: null
---

# 0004 — Keep the screen awake through high-level Foundation and UIKit APIs

## Context

Both demo apps can run a blockchain sync for a long time. On iPhone and iPad a
locked device suspends the app and stalls the sync; on Mac the sync continues
regardless, but the dashboard becomes invisible when the display sleeps.

## Decision

Use the platform's high-level APIs. On iPhone and iPad, set
`UIApplication.shared.isIdleTimerDisabled`. On Mac, call
`ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled,
reason:)` and hold the returned token. The hold is active only while the app is
frontmost and is released otherwise.

## Alternatives considered and rejected

IOKit power assertions, rejected as a lower-level API for something Foundation
already covers. Holding the screen awake from the background, rejected because a
backgrounded iPhone or iPad app cannot do it at all, and on Mac the sync runs
whether or not the display sleeps, so the hold would spend energy for nothing.

## Consequences

No entitlements or new permissions are needed. Detecting whether the app is
frontmost differs by platform and this is the part that surprises: iPhone and
iPad read `scenePhase == .active`, but Mac must read
`@Environment(\.appearsActive)`, because `scenePhase` does not report focus loss
on Mac. The Mac activity token must be begun and ended exactly once, so the
controller guards on a stored token rather than calling `beginActivity` again.
Any future work that gates behaviour on "is this window frontmost" inherits the
same platform split.
