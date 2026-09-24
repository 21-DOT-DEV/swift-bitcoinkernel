<!--
Delete this comment before committing.

The WHAT in user-facing terms — add this file when behavior needs separating
from mechanism (e.g. branchable results or externally visible contracts).
Rules:

  * No frontmatter, no `status` field — plan.md alone carries those. The header
    is a title plus links to the siblings.
  * Number requirements FR-001… and outcomes SC-001… so tasks.md can cite them.
    The bold `**FR-001**`/`**SC-001**` form is the definition the checker
    counts — a plain-text mention elsewhere (e.g. pointing at another
    feature's FR) is treated as a reference, not a definition.
  * Every requirement must be testable by somebody who has never read plan.md.
    A standing constraint on the design space — an ADR's enforcement, a
    platform limit — is not a functional requirement: record it under
    Assumptions and dependencies instead.
  * Scenarios are Given/When/Then in outcome language — what the person or the
    automation observes, not which component produced it. Tag each with the
    requirement(s) it exercises ("— covers FR-001") so the checker's coverage
    map can see which requirements lack a scenario.
  * An unresolved question is marked openly (e.g. "Unresolved: …") so it cannot
    be mistaken for a decision.
-->

# Spec — NNN · <title>

Feature NNN · Status lives in [plan.md](./plan.md) · Design rationale in
[research.md](./research.md) · Ordered work in [tasks.md](./tasks.md)

## Summary

<2–4 sentences: what changes for the person using this, in outcome language.>

## User journey

<The happy path end-to-end.>

**Independent test:** <how this feature alone is verified end-to-end.>

### Acceptance scenarios

1. **Given** <state>, **when** <event>, **then** <observable result> — covers
   FR-001.

## Functional requirements

- **FR-001** <one sentence, testable>.

## Measurable outcomes

- **SC-001** <something a reviewer can observe or measure — a number where one
  exists>.

## Edge cases

- **<name>** — <what happens, and why that answer is acceptable>.

## Assumptions and dependencies

- <what this feature relies on but does not build>.
