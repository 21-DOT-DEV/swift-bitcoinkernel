---
adr: 0006
title: An unattended run never falls back to a direct connection
status: Accepted
date: 2026-09-03
supersedes: []
superseded_by: null
---

# 0006 — An unattended run never falls back to a direct connection

## Context

NodeApp can route through Tor, the anonymity network that hides which computer is
talking to Bitcoin peers. It is off by default and, when on, must be **fully
established** before it is usable. Establishing it from cold takes **30–60 seconds**
(`Projects/AGENTS.md`, "Manual Tor integration testing"); where recent
network-directory data is already cached on the device it takes **5–10 seconds**,
down from about 40 seconds without it
(`TorViewModel.cacheDirectory`'s doc comment). A
background-triggered action gets roughly 30 seconds in total, so a cold start cannot
finish inside one window however the wait is written. An unattended run will
therefore sometimes find the privacy network unavailable within its window.

## Decision

An unattended run never starts the node on a direct connection when the privacy
setting is on. If the private connection is not established, the node does not start
— full stop. What the run does with the remainder of its window instead is a matter
for the feature plan, not for this record.

## Alternatives considered and rejected

Falling back to a direct connection when the private one is slow. Rejected
outright: it would send the person's home network address to Bitcoin peers after
they explicitly asked it not to, silently, on a schedule they set and then stopped
thinking about. Extra blocks synced is not a trade worth making against that.

Refusing to offer the action at all while the privacy setting is on. Rejected as
worse for the person than reporting the real reason, which they can act on.

## Correction, 2026-09-03

As first written this record blamed the retry schedule (5 seconds, then 30, then
120) for a first attempt exceeding the window. That was wrong: the first retry delay
is 5 seconds, not 30. The real constraint is cold start-up cost, now cited above.
The same edit narrowed the decision to the durable part — never connect without the
private network — and moved the question of what the run does with its remaining
time into the plan, where it belongs. The policy itself is unchanged.

## Correction, 2026-10-04

As implemented for feature 004, the launch-time check reads the preference a
second time and holds if **either** it or the run's entry snapshot says the
setting is on. The first draft read "when the privacy setting is on" as a
single point-in-time read; review found the asymmetric failure — a toggle
flipped *on* while a run was in flight would launch on a direct connection
moments after the person asked for privacy. Requiring privacy when either read
says on keeps the worst case a decline in both directions: on-then-off never
turns a private launch into a direct one either. The decline itself now says
which of the two happened ("being established" versus "turned off"), so a
decline is always a true sentence. The same review sharpened what "not
established" means at the boundary: a network on its way down still
reports its old endpoint until teardown finishes, and a node launched
onto a dead proxy can never connect — so the check reads the network's
readiness rather than the presence of an address, treating a stopping
network exactly like one that never started. A further review then found
one instant readiness alone cannot see: the preference write lands a step
before the network is told to stop, so a snapshot that required privacy
meeting a live read of off now declines outright — rather than launch
onto an endpoint whose teardown has already been ordered. The policy is
unchanged; its enforcement is fail-closed.

## Consequences

On a poor network, run after run may accomplish nothing but a message. That is the
correct outcome and the message says so, rather than the automation appearing to
work while quietly doing something else.

This holds for any future unattended path, including KernelApp's action and any
scheduled background work: a privacy setting is a floor, not a preference to be
weighed against throughput.
