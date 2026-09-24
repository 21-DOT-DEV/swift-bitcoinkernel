---
feature: NNN
title: <one line, no trailing period>
phase: null                 # e.g. "3 · RPC Client"; null for tooling or demo-app work
status: Planned             # Planned | In Progress | Implemented
updated: YYYY-MM-DD
adrs: []                    # decision records this feature produced, materially
                            # revised, or depends on, e.g. [0003, 0007] — the
                            # checker warns when the documents cite a record
                            # this list does not name
---

<!--
Delete this comment before committing.

Copy this folder to `NNN-slug/` and fill it in. Rules that the checker enforces:

  * `status` is one of the three values above and lives ONLY here. The table in
    ../README.md is generated from it.
  * No section named "Status log", "Review resolutions", "Review rounds", or
    "Changelog". If review changes the design, EDIT the affected section so this
    plan describes what shipped. Do not append a note saying it is now wrong.
  * A decision that outlives this feature becomes a record in ../../ADRs/ and is
    listed in `adrs:` above. Feature-local choices stay inline, in one sentence.
  * Record what this feature ADDED (for example "+7 tests"), never a running
    total of the whole suite. Totals go stale; deltas do not.

Only this file is indexed — it is the one required artifact — but the checker
also validates the siblings: they must carry no frontmatter, every `FR-NNN` a
spec defines must be cited in tasks.md (or this file when there is none),
every `SC-NNN` must be cited in this file's Verification, and no file may cite
an ID spec.md never defines. A feature adds siblings by role, each with a
minimal header (title + sibling links):

  * `spec.md` — the WHAT in user-facing terms: scenarios, acceptance criteria,
    numbered requirements (FR-NNN) and measurable outcomes (SC-NNN), edge
    cases, assumptions. Add when behavior needs separating from mechanism —
    e.g. branchable results or externally visible contracts. Measurable
    outcomes carry only what a number can falsify; behavioral endings belong
    in the scenarios. Mark anything genuinely undecided with `Unresolved:` so
    it cannot be mistaken for a settled decision.
  * `tasks.md` — the ordered work: TNNN tasks with file paths, grouped by
    implementation layer with dependency markers and per-phase checkpoints.
    Add when the work has real ordering — dependency waves, phase gates — that
    a flat list would hide. Every task cites the `FR-NNN`s it satisfies; with
    no tasks.md, the citations belong in this file instead — the checker holds
    every defined FR to a citation in one file or the other. A requirement from
    another feature is cited qualified — `003/FR-004` — so it is not read as a
    dangling cite to an ID this spec never defined. A test task marks the FRs
    its tests exercise with `verifies FR-NNN`; a requirement with neither a
    verifies cite nor an acceptance scenario errors, and scenario-only
    verification warns.
  * `research.md` — the evidence layer: upstream source verification, platform
    behavior, rejected alternatives. Add when decisions rest on evidence from
    outside this repository. Cite upstream by symbol name, not file:line —
    line numbers churn under patches and version bumps.

When siblings exist, plan.md keeps the frontmatter and index role and takes
the lighter skeleton — Summary, Technical Context, Constitution Check against
../../constitution.md, Design, Verification, Risks, Deferred work, Division of
labor, Complexity Tracking — and MUST NOT restate a sibling's content: one
fact, one home. See ../004-sync-watch/ for a worked example. A small feature
keeps this file alone.

Everything else that happened during review belongs in the commit message.
-->

# <Title>

<Summary — one short paragraph: what this is, who it is for, and whether it is
a roadmap phase or tooling/demo-app work. Link the ADRs it produced.>

## Technical Context

## Constitution Check

<One line per principle in ../../constitution.md — satisfied how, or "not
applicable" with a one-line reason. A justified deviation lands in Complexity
Tracking below.>

## Design

## Verification

- [ ] <a verifiable check> — when spec.md exists, cite the `SC-NNN` each check
     verifies (SC-001)

## Risks

## Deferred work

## Division of labor

## Complexity Tracking

<Empty by default — delete the section if unused. Fill ONLY when the
Constitution Check reports a justified deviation from ../../constitution.md:
which principle, why the deviation is warranted, what it costs. Governance
requires deviations to be explicitly justified; this is where that lives.>
