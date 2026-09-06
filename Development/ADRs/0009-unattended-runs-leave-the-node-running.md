---
adr: 0009
title: An unattended run leaves the node running unless asked to stop it
status: Accepted
date: 2026-09-06
supersedes: []
superseded_by: null
---

# 0009 — An unattended run leaves the node running unless asked to stop it

> Amends ADR 0007, which is still accepted. That record governs how the action decides
> when to stop; this one governs whether it stops at all.

## Context

An action triggered by an automation gets roughly 27 seconds (ADR 0008). The design
assumed that was also the node's working life, so the action waited most of the window
and then shut the node down before returning.

Device measurement showed the assumption was wrong. A node started by an action **keeps
running after the action returns** — 8 minutes in one measured case, 15 in another, on a
locked phone with no background capability declared. Blocks arrive almost entirely in
that period, not during the action:

| | Blocks gained |
| --- | --- |
| A run that waited and then stopped the node | 0 to 32 |
| A run that started the node and left it | 347 in 90 seconds, 2,145 in 11 minutes |

Stopping the node at the end of the action was therefore discarding nearly all of the
work. One run stopped a healthy node after 6 seconds of running, having made no peer
connections at all.

Waiting is no better. The protection the app holds against being suspended is released
when the action returns either way, so waiting does not extend the node's life — it only
pushes the action toward the cut-off, which has already produced a visible timeout error.

## Decision

An unattended run starts the node and returns as soon as the node answers. It does not
wait, and it does not stop the node.

Stopping is available as a switch on the action, off by default. When it is on, the run
waits and then stops, and ADR 0007's reasoning about owning the deadline and reserving
time applies unchanged.

A node that never answered is never asked to stop, regardless of the switch: it is still
inside its own start-up, where the request cannot be serviced and the wait cannot be
interrupted.

## Consequences

The node is normally killed by the system rather than shut down cleanly. That is
acceptable on evidence rather than in principle: it has happened repeatedly across
device testing and the node has recovered every time by replaying, never once requiring
a rebuild.

The node runs for minutes rather than seconds after each trigger, which costs battery.
That is the trade for the feature working at all.

**The survival is observed, not promised.** The system releases its hold on the app when
the action returns; that the app is not frozen immediately afterwards is the system's
choice, not a guarantee, and it may change with an OS release, under memory pressure, or
on another device. Nothing should be built that depends on a particular duration.

Because the run returns before any blocks arrive, it cannot report what it achieved.
Progress is reported by comparing against the last height the app recorded, which spans
the minutes after the previous run returned.

This binds the second app's action when it is built.
