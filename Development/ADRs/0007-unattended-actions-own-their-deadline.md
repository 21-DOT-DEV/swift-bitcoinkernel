---
adr: 0007
title: An unattended action watches its own clock rather than waiting to be told to stop
status: Superseded
date: 2026-09-04
supersedes: []
superseded_by: "0009"
---

# 0007 — An unattended action watches its own clock rather than waiting to be told to stop

> Superseded by ADR 0009, which narrows when this applies. An unattended run now
> leaves the node running by default, so there is usually nothing to stop and no
> time to reserve. Everything below still governs the case where stopping was
> explicitly asked for.

## Context

An action triggered by an automation gets roughly 30 seconds. The obvious design is
to let the system say when time is up and shut down in response, and a facility for
exactly that exists — but it requires iOS 27, while this app supports iOS 18
(`Projects/Project.swift:14-15`, matching the platform tier at
`Development/constitution.md:226`).

Reading the shutdown path shows the version gap is not the real obstacle. Stopping
the node waits on a continuation with no cancellation handling, backed by an
unbounded wait on a semaphore (`Sources/Bitcoin/Daemon.swift:46` and `:178`).

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

## Correction, 2026-09-05

"Roughly 30 seconds" above is measured to be wrong, and the error mattered. On device,
the system's out-of-time warning arrived 27.4 s and 27.9 s after the run began, and
both runs finished about a third of a second after it — late, because they were
budgeting against 30. Clean shutdown was separately measured between 0.36 s and 4.8 s.

The window was therefore treated as **27 seconds with 6 held back for shutdown**, so
work stopped at 21 and even the slowest observed shutdown finished before the
warning. The constants encoding that treatment (`budget` and `shutdownReserve`)
belonged to the implementation this record describes and never shipped: the current
design reserves no shutdown window — ADR 0009 leaves the node running — and instead
bounds each wait with a deadline its caller passes and each single question with
`Projects/Sources/Shared/WithHardTimeout.swift`.

This did not change the decision — the action still watched its own clock — only the
number it watched for. That implementation also began raising a "do not suspend me"
assertion for the length of a run, which the log had shown was absent; its expiry
callback was a backstop, not where shutdown began, since it was given less time than
a shutdown could take. The current design raises no such assertion.
