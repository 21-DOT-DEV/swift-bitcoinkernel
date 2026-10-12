# Specs

One numbered folder per feature (`NNN-slug/`). `plan.md` is the required,
indexed artifact — it alone feeds the generated table below. A feature adds
siblings beside the plan by role, not size: `spec.md` for the user-facing WHAT
(scenarios, `FR-NNN` requirements, `SC-NNN` outcomes), `tasks.md` when the work
has real ordering, `research.md` when decisions rest on evidence from outside
this repository. Siblings carry no frontmatter — status lives in `plan.md`
alone — and the checker enforces the citation contract both ways: every
`FR-NNN` the spec defines must be cited in `tasks.md` (or `plan.md` when there
is no tasks file), every `SC-NNN` in `plan.md`, and no file may cite an ID the
spec never defines — cite another feature's requirement qualified
(`003/FR-004`) so the rule knows it is foreign. The same run prints a coverage
map per spec-bearing feature — each requirement → its citing tasks → the test
tasks → the scenarios that exercise it — so a requirement named only where it
is never tested is visible rather than silent. The
[`_template/plan.md`](_template/plan.md) comment describes when each earns its
place; [`004-sync-watch/`](004-sync-watch/) is a worked example of the full
split. The number is a stable global counter, independent of roadmap
re-phasing; a plan's roadmap phase lives in its frontmatter, not its path.
Features that are tooling or demo-app work carry no phase.

Start from [`_template/plan.md`](_template/plan.md).

## What a plan is, and is not

A plan describes one feature and is **corrected as it changes**. When review
changes the design, edit the affected section so the plan describes what shipped.
Never append a note saying an earlier section is now wrong: that is how a plan
ends up contradicting itself, and how it grows without bound.

**A rule lives once.** A requirement, pairing rule, or scope boundary is
stated fully in exactly one place — the `FR-NNN` or edge-case bullet in
`spec.md` — and siblings cite the ID instead of restating the rule's terms
(a one-line gloss beside the cite is fine; re-specification is how two
copies of one rule drift into contradiction). Inside `spec.md`, keep one
claim per statement: a bullet carrying three semi-independent clauses
invites a restatement that contradicts one clause while echoing the rest.
After editing a claim-bearing sentence, grep its subject across the
siblings — a second normative statement of the same rule is drift, not
coverage.

**A fix is new content.** Review-driven edits are themselves claims, and
they get one delta sweep per round over the cumulative changes since the
last clean pass — never per-fix (a sweep's own fixes ride into the next
round's delta). A round is done when a pass yields zero *blocking*
findings. Blocking means: a contradiction between documents, a requirement
that cannot be observed, a wrong mechanism/path/command claim, a broken
task or PR dependency, or a token/secrets exposure. Thinner findings are
recorded in the round's commit message (the "everything else" row of the
material table below), not fixed — a thin fix is fresh regression
surface, and the drain/churn classification below is how an all-thin
round gets noticed.

The sweep opens with a **claims inventory**: every assertable line in the
delta extracted to a flat list — one fact each, anchored to file and
section, covering the whole delta, because a claim the fix did not mean
to make is the usual shape of a fix-introduced bug. Then the recurrence
list runs as sequential search passes, then one open pass for whatever
the list does not name. The list earns entries: a bug class gets a line
only after producing a finding twice — today it reads scope-boundary
claims, duplicated-rule drift, unverified mechanism claims,
self-reference gaps, convention-conformance, unobservable guards.
Classify every finding **drain** (predates this round's fixes) or
**churn** (introduced by them): churn flat while drain thins is a
treadmill — raise the fix bar, not the sweep rate.

This discipline applies to every document this file governs —
spec-bearing folders, `_template/`, and this file. Executable surfaces
(workflows, actions) carry their own gates; if a sweep on a code-side
delta catches what those gates miss, the rule earns a code-side home.

Plans therefore carry **no status log, review log, or round-by-round history**.
That material has three homes instead:

| Material | Goes to |
|---|---|
| A decision that outlives the feature, or a review finding the evidence refuted | [`../ADRs/`](../ADRs/README.md), listed in the plan's `adrs:` field |
| A trap that will bite whoever next touches the code | A comment or test name beside that code |
| Everything else that happened during review | The commit message |

**Test counts: deltas, not totals.** Record what a feature *added* (`+7 tests`),
never a running total for the whole suite. A total is a snapshot of one moment
and is wrong by the next commit; a delta stays true.

## Status

A feature's state lives in exactly one place: the `status` field in its plan's
frontmatter. `Planned` means not started; `In Progress` means code complete on a
branch; `Implemented` means **merged**, which is a fact about the repository rather
than a claim that every check passed. Verification that is still outstanding at
merge stays as an unticked box in the plan's own list and is named near the top, so
a reader does not have to reach §5 to find it. The table below
is generated from those fields by
[`../Tools`](../Tools/README.md) (`swift run --package-path Development/Tools
plans`), so the index and the plans cannot
disagree. Do not hand-edit it.

<!-- BEGIN GENERATED INDEX -->
| # | Feature | Phase | Status | Plan |
|---|---|---|---|---|
| 001 | App icons for the demo apps | — | In Progress | [plan.md](001-app-icons/plan.md) |
| 002 | Keep Screen Awake toggle in both demo apps | — | Implemented | [plan.md](002-keep-screen-awake/plan.md) |
| 003 | Action that runs the node unattended from a Shortcuts automation | — | In Progress | [plan.md](003-node-automation-action/plan.md) |
| 004 | The long-running action watches the node sync toward the tip | — | Planned | [plan.md](004-sync-watch/plan.md) |
| 005 | Authenticate github.com clones and retry fetch flakes in CI | — | Planned | [plan.md](005-reliable-clones/plan.md) |
<!-- END GENERATED INDEX -->
