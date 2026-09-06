---
adr: 0008
title: Unattended timings are measured on a locked device, never an unlocked one
status: Accepted
date: 2026-09-06
supersedes: []
superseded_by: null
---

# 0008 — Unattended timings are measured on a locked device, never an unlocked one

## Context

Every number this feature was built on — a 27-second window, an 11-second block-index
load, a 21-second work deadline, a 6-second shutdown reserve — was measured on device
with someone watching the screen. That is the one condition an unattended automation
never has.

The first genuinely screen-locked runs, on 2026-09-05, separated cleanly from the
attended ones:

| Screen | Time to load the block index |
| --- | --- |
| Unlocked | 14 s, 14 s, 12 s |
| Locked | 121 s, 47 s |

No overlap, 3.5× to 9× slower, on the same device minutes apart with the file cache
still warm. iOS deliberately throttles work in a background-launched process, and the
block index load is the most disk-heavy thing a run does.

The consequence was not a slow run but a broken one. The node could not answer inside
the 21-second deadline, the run correctly reported that it had not come up, then asked
it to stop — and a node still inside its own start-up cannot service a stop, so the
uninterruptible wait (ADR 0007) blocked until the system killed the run. The person
saw "Sync Bitcoin Node timeout" and the node died mid-write.

## Decision

A timing that describes unattended behaviour is measured with the screen locked and
the app not running. An attended measurement may be recorded for comparison, but it
never sets a budget, a deadline or a reserve.

Any run that waits on the node bounds that wait, and treats not finishing as an
expected outcome rather than an error.

## Consequences

The existing budget is known to be measured wrongly. It is not corrected here, because
two locked samples cannot set a number — they only establish that the attended figures
are unusable for this purpose.

The gap is large enough that no budget may fix it. A 121-second start-up cannot be
accommodated inside a 27-second window by any arrangement of that window, so this
records a limit on the short unattended action rather than a tuning problem.

This binds the second app's action when it is built, and it applies to any future
measurement of the longer window, which must also be taken with the screen locked.
