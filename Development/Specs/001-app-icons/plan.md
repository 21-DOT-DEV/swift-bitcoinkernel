---
feature: 001
title: App icons for the demo apps
phase: null
status: In Progress
updated: 2026-08-31
adrs: [0003]
---

# App icons for the demo apps

New icons for `NodeApp` and `KernelApp`, built from three supplied SVGs using
Apple's Icon Composer `.icon` format, so they show the layered look on iOS and
macOS 26 and a compiler-flattened version down to the apps' floor of iOS 18 and
macOS 15. This is demo-app polish rather than a library roadmap phase; the
[roadmap](../../Roadmap/README.md) tracks the `Bitcoin` and `BitcoinKernel`
libraries. The format choice and its consequences are recorded in
[ADR 0003](../../ADRs/0003-icon-composer-bundles-for-demo-app-icons.md).

**Still open:** the Icon Composer polish pass (§4, Phase 5) has not been done.
Both `icon.json` files still carry the hand-authored first-pass values, including
the placeholder layer scale.
## 1. Goal & success criteria

- Both example apps ship a real icon (not the current blank placeholder), built from the supplied SVGs.
- Liquid Glass layered rendering on iOS/macOS 26; an acceptable auto-flattened icon at the iOS 18 / macOS 15 floor.
- One `.icon` per app covers iPhone, iPad, and Mac.
- Legible at Home-Screen (~60pt) and Spotlight (~29pt) sizes, including the node line-art.
- `tuist generate` + `xcodebuild` succeed on both platforms (matches CI).

## 2. Scope

**In scope:** two self-contained `AppIcon.icon` bundles (each holds its own drawing under `Assets/` — the single source of truth for that shipped icon); the `resources` wiring in `Projects/Project.swift`; removal of the two empty placeholder appiconsets. `Projects/Design/AppIcons/` holds only artwork not yet wired into a bundle (currently just `node_app_pruned.svg`), so no drawing is duplicated in the repo.

**Out of scope (explicit owners):** mode-driven icon switching → §8 follow-up (a 2nd `.icon`, an Info.plist alternate-icons entry, iOS-only Swift); any redraw of the artwork beyond the Phase 5 polish; deployment-target changes.

## 3. Design

### 3.1 Source → app mapping

- `kernel_app.svg`      → KernelApp icon (full-color mascot); lives only in `KernelApp/AppIcon.icon/Assets/`.
- `node_app_full.svg`   → NodeApp icon (rust line-art, archival mode); lives only in `NodeApp/AppIcon.icon/Assets/`.
- `node_app_pruned.svg` → single copy in `Projects/Design/AppIcons/`, held for the future switching follow-up. Not shipped now.

### 3.2 `icon.json` schema (real format)

Top level: `fill`, `groups`, `supported-platforms`. Background is `fill` (solid color or `linear-gradient`); foreground art lives in `groups[].layers[]`. Colors are `srgb:`/`display-p3:` decimal-RGBA strings, **not** hex. Keep artwork layers flat — glass, shadow, and translucency are group/layer settings applied in Icon Composer (Phase 5), not baked into the SVG.

```json
{
  "fill": {
    "linear-gradient": [
      "srgb:0.99608,0.98431,0.94118,1.00000",
      "srgb:0.94902,0.88235,0.78039,1.00000"
    ],
    "orientation": { "start": { "x": 0, "y": 0 }, "stop": { "x": 1, "y": 1 } }
  },
  "groups": [
    { "layers": [ { "image-name": "node_app_full.svg", "name": "node" } ] }
  ],
  "supported-platforms": { "squares": "shared" }
}
```

The two gradient stops are the cream (`#FEFBF0`) and sand (`#F2E1C7`) values from the kernel palette, converted to `srgb:` decimals. Final colors + display-p3 variants are tuned in Phase 5.

## 4. Implementation steps

**Phase 0 — Confirm the `.icon` bundle format.** The schema above is known from sample `.icon` bundles. Before authoring, cross-check it against one freshly generated `.icon` (a throwaway from Icon Composer, or a current sample) so the key set matches this Xcode version. If hand-authoring fights the schema, fall back to building each `.icon` in Icon Composer from the prepped SVGs.

**Phase 1 — Prepare artwork.** Each shipped drawing lives in its `.icon` bundle's `Assets/`; `Projects/Design/AppIcons/` retains only the not-yet-bundled `node_app_pruned.svg`, so no drawing is duplicated. The QuiverAI generator comment was stripped from each SVG. No text-to-outline step (verified: `<text>`/`<tspan>` counts are 0). Note for polish: `kernel_app.svg` has a baked ground-shadow ellipse; flat art is preferred, so it is a candidate for removal in Phase 5.

**Phase 2 — Author the `.icon` bundles.** Write each `icon.json` per §3.2 (cream→sand gradient `fill`, the SVG as a flat layer in `groups[].layers[]`). Drop each app's working SVG copy into that bundle's `Assets/`.

**Phase 3 — Wire into Tuist.** Add the `.icon` bundle to each app target's `resources` as a directory path (`"Resources/KernelApp/AppIcon.icon"`, `"Resources/NodeApp/AppIcon.icon"`), **not** a `/**` glob, so Tuist keeps it as one compiled bundle (Tuist 4.195.11 supports this; issue #7923, fixed in 4.57). Do **not** add `ASSETCATALOG_COMPILER_APPICON_NAME` — already set in each `Shared.xcconfig`. Remove the two empty `AppIcon.appiconset` directories. Regenerate and confirm no error.

**Phase 4 — Build and verify (agent).** Build both apps for an iOS 26 simulator and macOS; confirm the icon appears (not blank) in light and dark. Build against the iOS 18 / macOS 15 floor and confirm Xcode's auto-flattened fallback renders acceptably — this is take-it-or-leave-it (D5); there is no hand-populated fallback. Check legibility at ~60pt and ~29pt, especially the node line-art.

**Phase 5 — Human polish and sign-off (you, in Icon Composer).** Requires macOS 26.4+ (local is 26.5.1). Do this for each of the two `.icon` bundles:

1. **Open it.** Double-click the `.icon` (or Icon Composer → File → Open). If the gradient background and the drawing both appear on the canvas, the hand-authored file is valid (the "validate" half of authoring path C). If it opens blank or errors, flag it for a rebuild-from-SVG fallback.
2. **Get oriented.** Left sidebar = layers; center = live preview; right panel (inspector) = fill / glass / shadow controls; bar under the canvas = platform + appearance modes (Default / Dark / Clear / Tinted).
3. **Fix size/position first.** The layer `scale` is a first-pass guess (~5). Adjust scale and centering in the inspector's Composition/Layout controls so the art fills the tile with a comfortable margin.
4. **Add the glossy finish.** Select the group; in Liquid Glass, turn on Specular, nudge Translucency and Shadow. Keep it subtle — the system supplies most of the lighting.
5. **Tune the appearance modes.** Step through Dark, Clear, Tinted (single-color). Those derive brightness from the default colors, so the rust line-art can come out too dark; if so, use the "vary" control next to Fill to set a lighter fill just for that mode.
6. **Check small sizes.** Preview near ~60pt and ~29pt; thicken/simplify the node line-art if it thins or muddies.
7. **Save.** File → Save (⌘S) writes back in place; the next build picks it up. Then the work can be committed.

Note: `kernel_app.svg` has a baked-in ground-shadow ellipse; consider hiding/removing it so the system lighting isn't fighting a pre-baked shadow.

## 5. Verification checklist

- [ ] Both apps build clean with the new icons (iOS + macOS).
- [ ] Icon renders in light and dark on iOS 26.
- [ ] Icon renders on macOS (Dock + Finder).
- [ ] Auto-flattened fallback renders acceptably at the iOS 18 / macOS 15 floor.
- [ ] Legible at 60pt and 29pt; node line-art still reads.
- [ ] `tuist generate` + `xcodebuild` both succeed (matches CI).

## 6. Risks and mitigations

- `icon.json` is a newish format; exact keys can shift between Xcode versions. → Cross-check the schema against a freshly generated `.icon` in Phase 0; fall back to Icon Composer authoring.
- Detailed node line-art can wash out at small sizes and in tinted/clear variants. → Small-size check in Phase 4; thicken/simplify in Phase 5.
- The older-OS fallback is Xcode's auto-flattened `.icon`, with no developer control and some documented rough edges on specific releases. → Verify at the actual floor. If unacceptable, the decision is binary (accept it, or defer `.icon` and keep asset catalogs), not a hand-tuned fallback.

## 7. Out of scope (follow-ups)

- **Mode-driven node icon switching** (archival vs pruned): a second `.icon`, an Info.plist alternate-icons entry, and iOS-only switching code. Clean addition later; nothing here blocks it. iOS/iPadOS only (macOS has no runtime icon-swap API), and iOS shows a system alert on each swap.
- Any redraw of the supplied artwork beyond the Phase 5 polish tweaks.

## 8. Division of labor

- **Agent:** Phases 0–4 (schema confirm, art prep, `.icon` authoring, Tuist wiring, build and verification).
- **You:** Phase 5 (Icon Composer polish and final sign-off).
