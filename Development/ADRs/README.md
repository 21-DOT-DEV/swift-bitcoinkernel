# Architecture Decision Records

One file per durable decision, named `NNNN-<slug>.md`. Records are append-only:
a decision that no longer holds is marked `Superseded` and points at the record
that replaced it, rather than being edited or deleted.

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
<!-- END GENERATED INDEX -->
