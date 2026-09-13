# Delivery order for feature 003

The work that makes this feature real exists as one block of roughly 1,240 changed
lines. That is too large to review in a single pass, so this file cuts it into eleven
pull requests, each small enough to read properly and each able to build and pass its
checks on its own.

This file describes **how the work arrives**. [`plan.md`](plan.md) describes **what the
feature is** — its design, its decisions, and its verification list. When the two
appear to disagree, `plan.md` is right and this file is stale. It is deleted in slice
11, once `plan.md` has been corrected to describe what shipped.

Scope is what `plan.md` §1 (its goal and success criteria) calls the real feature: the
node starts, a run never falls back to a connection that exposes the person's home
network address, and the outcome is reported honestly. Three things named in
`plan.md` §7 (its follow-ups list) are deliberately **not** here — a quiet
notification of the outcome, a file marking a clean shutdown, and metadata that helps
the action appear in system search. They are meaningful only once a run has a real
outcome to report, and one of them has ready-made reference code (see below).

## How to read the table

**"Changed lines" means added plus deleted**, which is what a reviewer actually reads.

**Most of these are not stacked.** Slices 1, 2, 3, 4, 5 and 7 depend on nothing: each
can be opened straight against `main`, in any order, or all at once. Only 6 → 8 →
{9, 10} → 11 form a genuine chain, four deep. That matters because the received
guidance on chained pull requests is that three or four is the practical ceiling
before the cost of tracking dependencies outweighs the benefit of small reviews. This
sits inside that, and it means there is no eleven-deep rebase to manage.

**Each pull request should state what it depends on** in its own description, and link
back to this file, so a reviewer is never guessing where a slice sits.

**The tick boxes are edited here, in the same pull request as the slice they
describe** — so the box and the code it refers to cannot fall out of step. Note that a
tick box inside a table cell is not clickable on GitHub; it is edited in the file.

## Where the reference code lives

Two sources, with different standing.

**The reference code** — the roughly 1,240 changed lines this plan slices up — is
published on branch
[`spec-003-stash-2026-09-10`](https://github.com/21-DOT-DEV/swift-bitcoinkernel/tree/spec-003-stash-2026-09-10),
where it arrives in a single commit, `14c12d1`. It was previously held in a local
saved-changes entry (a `git stash` entry), which is the wrong place for anything kept
overnight: such an entry is never pushed, so it is not backed up, and it is consumed
the moment it is applied. No pull request is open against this branch, so none of the
repository's automated checks run on it.

**It has never been compiled.** Treat it as a detailed sketch, not as working code.

Two practical notes. Link to the commit `14c12d1` rather than to the branch name when
a reference needs to stay valid, because a branch tip can move. And the branch should
be deleted once slices 1–11 have landed — at which point, if the code is still worth
keeping readable, tag it first: a tag cannot be moved by accident and does not show up
in branch listings or stale-branch reports.

The branch also carries slice 0's two commits and this file, so a reviewer comparing
it against `main` sees the whole feature at once rather than just the sketch.

**Pull request [#41](https://github.com/21-DOT-DEV/swift-bitcoinkernel/pull/41)** is an
earlier, different implementation of the same feature — 1,876 added lines across 27
files. It was closed rather than merged, so it stays readable indefinitely. Its
structure differs from this plan's (it put everything in one action type rather than
splitting the deciding from the orchestrating), so it is useful for comparison and for
the parts this plan does not rebuild, not as a template.

| Slice | In the reference branch | In pull request #41 |
|---|---|---|
| 1 | `Projects/Project.swift`, both `PrivacyInfo.xcprivacy` files | — |
| 2 | `DaemonConfig.swift`, `NodePreflight.swift`, `NodePreflightTests.swift` | — |
| 3 | `NodeAutomation.swift` (+139), `NodeAutomationTests.swift` (+181) | `NodeAutomation.swift` (+155), `NodeAutomationTests.swift` (+221) — an earlier take on the same decisions, worth reading against |
| 4 | — (new work) | — |
| 5 | `NetworkCost.swift` (+110), `NodeApp.swift` (+10) | — |
| 6 | `NodeRunReport.swift` (+127) | `NodeRunReport.swift` (+132) |
| 7 | — | The four decision records listed below |
| 8 | `NodeRun.swift` (+356), `NodeSession.swift` | `SyncNodeIntent.swift` (+361) and `RunLog.swift` (+54) — the same work, undivided |
| 9 | `SyncNodeIntent.swift` | as above |
| 10 | `SyncNodeLongRunningIntent.swift` (+141/−34) | — (this protocol did not exist when #41 was written) |

Out of scope here, but already written in #41 if it is picked up later:
`Shared/NotificationReporter.swift` (+74), `Shared/RunReporter.swift` (+56) and
`NodeAppTests/RunReporterTests.swift` (+91) for the quiet notification;
`NodeApp/BackgroundAssertion.swift` (+56) for the "do not suspend me" claim that
`plan.md` §7 decided not to rebuild.

## The eleven slices

| # | Landed | Pull request | Changed lines | Depends on |
|---|---|---|---|---|
| 0 | [x] | Open a pull request for the two commits already on the branch: a read-only connection for asking the node questions, and progress advanced from inside the long run | 85 | — |
| 1 | [x] | Declare the system calls Apple requires a stated reason for, in both apps, and bundle the declaration | 82 | — |
| 2 | [x] | Refuse to run when the chain folder cannot be set up; stop swallowing folder failures without a word | 73 | — |
| 3 | [x] | The plain decisions a run makes: blocks gained, the one sentence a person reads, what the progress display says at the end (+20 tests) | 324 | — |
| 4 | [x] | A "stop waiting after N seconds" helper, so one slow question to the node cannot consume a whole run (+ tests) | ~70 | — |
| 5 | [ ] | Watch whether the network is one a person would mind a multi-gigabyte download on | 120 | — |
| 6 | [ ] | The structured value a run hands back, with the text behind each outcome pinned, and a test that every outcome has display wording | ~165 | 3 |
| 7 | [ ] | Vet and land the recovered decision records — see the gate below | ≤262 | — |
| 8 | [ ] | The one routine both actions call: read the device, decline with a reason, or start the node; every question to it bounded | ~380 | 2, 3, 4, 5, 6, 7 |
| 9 | [ ] | Wire the short action, with the wait made conditional — see below | ~45 | 6, 8 |
| 10 | [ ] | Wire the iOS 27 action: honest progress display, keep-alive nudge, and removal of the temporary 30-second pause from slice 0 | 175 | 6, 8 |
| 11 | [ ] | Correct `plan.md` to describe what shipped, and delete this file | ~60 | 10 |

Roughly 1,545 changed lines across slices 1–11, averaging 140, largest 380.

### What slice 9 changes about the short action

"Sync Bitcoin Node" is the action that works on every system the app supports, inside
a window of roughly 27 seconds. It has **no progress display at all** — that exists
only on the iOS 27 protocol — so its only completion signal is returning.

Measured on device, loading the block index (the on-disk data a node must read before
it can answer anything) took 12, 14 and 14 seconds with the screen unlocked, and 121
and 47 seconds with it locked. The feature's whole purpose is the locked case. So a
cold start cannot be seen to finish inside this action's window by any arrangement of
that window.

Slice 9 therefore makes the wait conditional on what the run found:

- **A node was already running** → ask it one question, bounded by slice 4's helper,
  and report fully. This path genuinely succeeds, because nothing has to load the
  block index.
- **It just started one** → do not wait. Report that it is starting and return within
  a second or two. Apple's energy guidance is to stop background work the moment it is
  done rather than waiting to be suspended, and since the node has been observed to
  keep running after the action returns, holding the window open buys nothing but
  battery.

Slice 9 also corrects the action's own description, which currently promises to let
the node "sync for the short time a background action is allowed and report what
happened" — an outcome the measured device cannot deliver on a locked phone.

### The gate on slice 7

Four decision records were drafted in pull request #41 and never merged. **None is
restored on the strength of having been written.** Each lands only when its claims are
confirmed against the code as it stands today, or re-measured on this branch.

Numbers are kept as drafted. They were published in #41's own description, so reusing
one for a different decision would leave the same number meaning two things — which is
exactly what the convention against reusing numbers exists to prevent. A gap costs
nothing; a collision breaks every reference.

| Record | Lands as | Gate |
|---|---|---|
| `0006-unattended-runs-never-bypass-tor.md` | `Accepted` | **Cleared.** Its cited facts hold today: `Projects/AGENTS.md:89` still reads "30–60s cold (5–10s with cached consensus)", and `Projects/Sources/Shared/TorViewModel.swift` still records the drop from ~40s to ~5–10s |
| `0007-unattended-actions-own-their-deadline.md` | `Superseded`, pointing at `0009` | **Cleared.** Its load-bearing claim holds: `Sources/Bitcoin/Daemon.swift:46` is an unbounded semaphore and `:178` waits on it with no timeout and no cancellation, so a node shutdown cannot be abandoned once begun. Kept as the road not taken, so nobody re-proposes a self-managed shutdown deadline and rediscovers this the hard way. `Superseded` rather than `Rejected` because the checker at `Development/Tools/Sources/PlanIndex/Indexer.swift:17` permits only `Proposed`, `Accepted`, `Superseded` — and it is accurate: `0009` narrows `0007` rather than refuting it |
| `0008-unattended-timings-are-measured-on-a-locked-device.md` | `Accepted` | **Blocked.** Rests entirely on locked-versus-unlocked measurements. Re-measure on this branch first |
| `0009-unattended-runs-leave-the-node-running.md` | `Accepted` | **Blocked.** Rests on the node surviving past the action's return — 8 and 15 minutes observed, with 347 blocks in 90 seconds and 2,145 in 11 minutes. Re-measure on this branch first |

Slice 7 may therefore land in two parts: the two cleared records now, the two measured
ones after the device session below.

## Known problems in the reference code

These describe the reference branch, not anything on `main`. When each is fixed,
the lasting warning goes in a comment or a test name beside the fix; this section is
deleted with the file at slice 11.

- **The short action's wait cannot be enforced as written.** Its loop checks the clock
  between questions, but once a question is outstanding the loop is parked inside it
  and cannot notice the deadline pass — and none of the four ways to build the
  node-questioning client (`RPCClient` in the `Bitcoin` package) accepts a timeout, so
  the caller has no ceiling. On the fast path it is not even a network request but an
  in-process call that runs to completion, so it cannot be cancelled, only abandoned.
  One slow question consumes the whole window and the run reports nothing. Slices 4
  and 9 address this; the iOS 27 action's repeating nudge treats the symptom, not the
  cause.
- **The text behind each outcome value is not pinned.** The four outcome cases let
  Swift generate their stored text from the case names. That text is what a person's
  saved automation compares against, so renaming a case in source silently changes
  the meaning of a comparison someone already built. Slice 6 assigns the text
  explicitly and freezes it.
- **Nothing enforces that every outcome has display wording.** The case-to-wording
  dictionary is a plain dictionary with no completeness check, and a gap is a crash at
  the moment that outcome is shown, not a build failure. Slice 6 adds the test.
- **Three whole-number fields are optional, and optional fields on this kind of
  returned value have a history of trouble.** Absent and zero are genuinely different
  claims here — "measured, caught up" versus "nobody looked" — so they stay optional,
  but they need checking in the Shortcuts editor on a device before anything relies on
  them.

## Two checks no slice can cover

Both need a physical device with the screen locked, and both gate work above.

- [ ] Measure a cold start with the screen locked on this branch. `plan.md` §6 (its
      risks list) says every timing budget rests on this, and it has not been taken
      here. Gates slice 7's two blocked records, and confirms or corrects slice 9.
- [ ] Confirm the stop button on the iOS 27 progress display ends a run. Currently not
      reachable, because the placeholder finishes in milliseconds — which is why slice
      0 carries a temporary 30-second pause that slice 10 removes.
