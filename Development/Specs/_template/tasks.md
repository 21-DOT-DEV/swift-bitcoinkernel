<!--
Delete this comment before committing.

The ordered work — add this file when the work has real ordering (dependency
waves, phase gates) that a flat list in plan.md would hide. Rules:

  * No frontmatter, no `status` field — plan.md alone carries those.
  * Tasks are TNNN (e.g. T001) in dependency order, grouped into phases that
    each close on a verifiable checkpoint: `- [ ] T001 <what> · <files>`.
  * `[P]` marks a task independent of its wave-mates (different files, no
    incomplete dependency). `⟶ wait` marks a join on something outside the
    phase — another phase, or a check that needs a device.
  * Cite FR-NNN where a task serves a requirement; enabling work cites nothing.
    The checker requires every FR defined in spec.md to be cited at least once
    — here, or in plan.md when the feature has no tasks file. A test task
    declares which of its cites its tests exercise as `(verifies FR-NNN)`; the
    coverage map counts only those toward test verification, so a requirement
    with neither a verifies cite nor an acceptance scenario errors, and
    scenario-only verification warns.
  * One checkbox is one completable unit — work landing in different pull
    requests is different tasks, not halves of one.
  * A phase's test task precedes the implementation it covers: the constitution
    requires red → green, and each checkpoint states the new tests were seen
    failing before the implementing change ran.
  * The slicing table is recommended for large features — it cuts phases into
    reviewable pull requests (roughly 150–400 changed lines each, dependency
    chains no deeper than four). "Depends on" may name a device check: such a
    slice merges on CI but stays provisional until the check passes.
-->

# Tasks — NNN · <title>

Ordered work for [the plan](./plan.md); requirements cited as `FR-NNN` from
[spec.md](./spec.md); rationale in [research.md](./research.md).

## Phase 0 — <name>

- [ ] T001 <what> (FR-001) · `path/to/file.swift`
- [ ] T002 [P] Tests for it — written and seen failing first (verifies FR-001) ·
  `path/to/ThingTests.swift`

**Checkpoint:** <what is verifiably true when this phase closes>.

## Pull-request slicing

| # | Landed | Pull request | Tasks | Changed lines | Depends on |
|---|---|---|---|---|---|
| 0 | [ ] | <one plain sentence a stranger could parse> | T001 | ~N | — |

## Deferred

<out-of-scope items, each with its reason — none block this feature>.
