---
adr: 0007
title: An unattended action watches its own clock rather than waiting to be told to stop
status: Accepted
date: 2026-09-04
supersedes: []
superseded_by: null
---

# 0007 — An unattended action watches its own clock rather than waiting to be told to stop

## Context

An action triggered by an automation gets roughly 30 seconds. The obvious design is
to let the system say when time is up and shut down in response, and a facility for
exactly that exists — but it requires iOS 27, while this app supports iOS 18
(`Projects/Project.swift:14-15`, matching the platform tier at
`Development/constitution.md:226`).

Reading the shutdown path shows the version gap is not the real obstacle. Stopping
the node waits on a continuation with no cancellation handling, backed by an
unbounded wait on a semaphore (`Sources/Bitcoin/Daemon.swift:46` and `:179`).

## Decision

An unattended action tracks its own deadline and begins shutting down before the
system's limit. Any stop signal that does arrive triggers the same shutdown earlier;
none is required for the design to work.

## Alternatives considered and rejected

Waiting to be told, using the purpose-built facility. Rejected on availability, but
it would not have worked regardless: a stop signal cannot rescue the action once it
is already blocked inside the shutdown wait, and cannot begin a shutdown that has not
started.

Raising the app's supported version to reach that facility. Rejected as a large cost
— every device below that release loses the app, and the platform tier in the charter
would need a formal amendment — bought for a mechanism that does not fit the code.

Treating a timed-out run like an unannounced kill and letting the node die
mid-write. Rejected because the whole point of a short window is that it ends
predictably, so the one ending we can control should be controlled.

## Consequences

The deadline must reserve time for shutdown rather than firing at the limit, because
the sequence sends a stop command and then waits for the daemon's main function to
return (`Sources/Bitcoin/Daemon.swift:178`).

Once shutdown has begun nothing can abandon it half-finished, which is the property
that makes this safe. An outright kill — force-quit, or memory reclaimed under
pressure — still stops the node mid-write and cannot be prevented by any mechanism.

This binds the second app's action when it is built.
