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
(`Projects/AGENTS.md:89`); where recent network-directory data is already cached on
the device it takes **5–10 seconds**, down from about 40 seconds without it
(`Projects/Sources/Shared/TorViewModel.swift:400`). A
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

## Consequences

On a poor network, run after run may accomplish nothing but a message. That is the
correct outcome and the message says so, rather than the automation appearing to
work while quietly doing something else.

This holds for any future unattended path, including KernelApp's action and any
scheduled background work: a privacy setting is a floor, not a preference to be
weighed against throughput.
