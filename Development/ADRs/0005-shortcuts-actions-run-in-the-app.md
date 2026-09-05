---
adr: 0005
title: Shortcuts actions run inside the app, and only stop a node they started
status: Accepted
date: 2026-09-03
supersedes: []
superseded_by: null
---

# 0005 — Shortcuts actions run inside the app, and only stop a node they started

## Context

An action published to Shortcuts can live inside the app or inside a small
separate program bundled alongside it. A sibling project uses the separate-program
approach. This app is different in two ways that decide the answer: the Bitcoin
daemon starts inside the calling process, and the chain data lives in the app's own
private folder, marked so device and iCloud backups skip it.

## Decision

Actions live in the app target. The system launches the app in the background to
run them, so the daemon starts in the process that already owns the chain data.

Separately, an action shuts down only a node it started itself. Finding the node
already running means reporting its height and returning, untouched.

## Alternatives considered and rejected

A separate bundled program, rejected because it cannot open the app's private
chain folder without adding a shared container and relocating existing data while
preserving the backup-exclusion flag — and because Bitcoin Core takes an exclusive
lock on its data folder. A second process starting against the same folder does not
corrupt anything; it refuses to start, reporting "Cannot obtain a lock on directory
… is probably already running" (`Vendor/bitcoin/src/init.cpp:1165`, via
`util::LockDirectory` at `init.cpp:1161`). The databases underneath were never
designed for two programs at once.

Unconditional shutdown at the end of a run, rejected because an automation firing
while someone watches the node sync would stop it, which reads as the app dying.

## Correction, 2026-09-03

As first written this record blamed commit `d4296f1` for the two-process risk. That
commit fixes a race **inside one process** — one part of the other app waiting for
its own sync producer to release the data folder before reopening it — so it never
supported the claim. The real reason is the exclusive folder lock cited above,
which is verified in this repository's own vendored source rather than inferred.
The decision is unchanged.

## Consequences

No shared container and no data migration are needed. Relocating chain data later
remains possible and would not break these actions, because that is only a path
change. What *would* break them is embedding a separate program, which shadows the
app's own actions — so that route is closed unless the actions move with it.

An automation triggered during an active session accomplishes nothing beyond a
status report. That is the intended trade.

This applies to KernelApp's later action as well.
