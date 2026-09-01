---
adr: 0003
title: Use Icon Composer .icon bundles for the demo app icons
status: Accepted
date: 2026-07-16
supersedes: []
superseded_by: null
---

# 0003 — Use Icon Composer .icon bundles for the demo app icons

## Context

Both demo apps shipped an empty placeholder icon. Artwork arrived as SVGs, and
the icons had to render on iOS and macOS 26, where the system draws layered
icons with its own lighting, while still producing something acceptable at the
apps' floor of iOS 18 and macOS 15.

## Decision

One Icon Composer `.icon` bundle per app, wired into the app target as a
directory resource. The asset compiler generates every size and the older-system
fallback from that single bundle. Both apps sit on the same cream-to-sand
gradient background with flat artwork on top, so they read as a family and the
system supplies the gloss rather than the artwork baking it in.

## Alternatives considered and rejected

Asset catalogs with hand-generated sizes. Rejected because it requires an SVG
rasterizer on every machine that builds the icons, and it is no longer the format
Apple is developing. Also rejected: shipping a separate hand-tuned icon for older
systems, which Apple does not support alongside a `.icon` bundle.

## Consequences

Building the icons requires an Xcode 26 toolchain, which local machines and CI
already use. The deployment floor is unchanged. Older systems receive the
automatically flattened version of the same bundle, and there is no developer
control over how that flattening looks: the choice is to accept it or to abandon
`.icon` entirely. Verify at the floor rather than assuming.
