# Architecture Decision Records

One file per durable decision, named `NNNN-<slug>.md`. Records are append-only:
a decision that no longer holds is marked `Superseded` and points at the record
that replaced it, rather than being edited or deleted.

**Correcting a record whose decision still stands.** A factual error that does not
change what was decided is fixed in place, with a dated `## Correction` section
saying what was wrong and what replaced it. Anything that changes what was decided
is a new record instead. The dated note is not ceremony: an unmarked fix to a
document that claims to be immutable invites the next reviewer to report the same
error again.

A choice belongs here when it stays true after the feature that prompted it has
shipped and the surrounding code has moved on. Feature-local choices that die
with their feature stay in that feature's plan under `../Specs/`.

Each record opens with YAML frontmatter:

```yaml
---
adr: 0001
title: Use Icon Composer .icon bundles for demo app icons
status: Accepted          # Proposed | Accepted | Superseded
date: 2026-07-16
supersedes: []
superseded_by: null
---
```

Then: **Context** (what forced the decision), **Decision**, **Alternatives
considered and rejected**, **Consequences**. Keep each to a paragraph.

The table below is generated from those frontmatter blocks. Do not hand-edit it.

<!-- BEGIN GENERATED INDEX -->
| # | Decision | Status | Date |
|---|---|---|---|
| 0001 | [Wallet support is RPC-only, with no separate Swift wallet library](0001-wallet-support-is-rpc-only.md) | Accepted | 2026-05-07 |
| 0002 | [Peer-to-peer networking replaces the remote-node HTTP client model](0002-p2p-replaces-remote-node-client.md) | Accepted | 2026-05-07 |
| 0003 | [Use Icon Composer .icon bundles for the demo app icons](0003-icon-composer-bundles-for-demo-app-icons.md) | Accepted | 2026-07-16 |
| 0004 | [Keep the screen awake through high-level Foundation and UIKit APIs](0004-foundation-apis-for-keeping-the-screen-awake.md) | Accepted | 2026-07-20 |
| 0005 | [Shortcuts actions run inside the app, and only stop a node they started](0005-shortcuts-actions-run-in-the-app.md) | Accepted | 2026-09-03 |
| 0006 | [An unattended run never falls back to a direct connection](0006-unattended-runs-never-bypass-tor.md) | Accepted | 2026-09-03 |
| 0007 | [An unattended action watches its own clock rather than waiting to be told to stop](0007-unattended-actions-own-their-deadline.md) | Accepted | 2026-09-04 |
<!-- END GENERATED INDEX -->
