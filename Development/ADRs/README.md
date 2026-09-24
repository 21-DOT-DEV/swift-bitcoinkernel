# Architecture Decision Records

One file per durable decision, named `NNNN-<slug>.md`. A decision that no
longer holds is marked `Superseded` and points at the record that replaced it,
rather than being edited or deleted. Two kinds of fix are allowed and they are
not the same: cosmetic edits — typos, formatting, a stale pointer — go in
place; a factual correction — the record said something that was wrong — is
appended as a dated `## Correction` section naming what was wrong (see 0006),
so the record shows when the drift was noticed rather than reading as if it
had always known. The decision text itself is never edited.

Cite source by symbol name or document section, not `file:line` — line numbers
churn under edits; a symbol survives them.

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
| 0005 | [Shortcuts actions run inside the app, in the background, with no shared container](0005-shortcuts-actions-run-in-the-app.md) | Accepted | 2026-09-06 |
| 0006 | [An unattended run never falls back to a direct connection](0006-unattended-runs-never-bypass-tor.md) | Accepted | 2026-09-03 |
| 0007 | [An unattended action watches its own clock rather than waiting to be told to stop](0007-unattended-actions-own-their-deadline.md) | Superseded | 2026-09-04 |
| 0008 | [Unattended timings are measured on a locked device, never an unlocked one](0008-unattended-timings-are-measured-on-a-locked-device.md) | Proposed | 2026-09-06 |
| 0009 | [An unattended run leaves the node running unless asked to stop it](0009-unattended-runs-leave-the-node-running.md) | Proposed | 2026-09-06 |
<!-- END GENERATED INDEX -->
