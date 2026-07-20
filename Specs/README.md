# Specs

Feature specs, **spec-kit-aligned but lightweight**: one numbered folder per feature
(`NNN-slug/`) with a canonical `plan.md` inside. The `.specify/` scaffolding and
`speckit.*` workflows already exist in this repo; we keep spec-kit's *folder
convention* but author only the files we actually use (a `plan.md` per feature),
not its full template/script machinery. Each plan's roadmap **phase / feature
mapping lives in its header**, not the path — the spec number is a stable global
counter, independent of roadmap re-phasing. Features that are demo-app or tooling
polish (not a library roadmap phase) say so in the header and leave the phase blank.

> **Casing note:** this directory is intentionally `Specs/` (capitalized, matching
> the repo's other top-level directories `Projects/`, `Sources/`, `Vendor/`).
> spec-kit's scripts default to lowercase `specs/`, so wiring that tooling to these
> files later would need the path adjusted.

Each `plan.md` opens with a metadata table — **Feature / Status / Decisions /
Assumptions** — then numbered sections (Goal, Scope, Design, Steps, Verification,
Risks). Keep the **Status** row current: `Planned` → `In Progress` (code complete on a branch) → `Implemented` at merge.

| # | Feature | Phase | Status | Plan |
|---|---|---|---|---|
| 001 | App icons for the demo apps (NodeApp, KernelApp) — Icon Composer `.icon` / Liquid Glass | — · app polish | Planned | [plan.md](001-app-icons/plan.md) |
| 002 | "Keep Screen Awake" toggle in both demo apps — prevent auto-lock (iOS) / display sleep (macOS) while running | — · app polish | In Progress | [plan.md](002-keep-screen-awake/plan.md) |
