---
description: Review UI code for design system compliance (Apple HIG, Material Design
  3, or Web standards)
---


<!-- Extension: forge -->
<!-- Config: .specify/extensions/forge/ -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may specify files to review, a target design system override (`"HIG"`, `"Material"`, `"Web"`), or areas to focus on.

## Goal

Review changed UI code for compliance with the project's design system. Auto-detect whether the project targets Apple HIG, Material Design 3, or Web standards, then evaluate against platform-specific guidelines across six dimensions.

This is a **single-purpose design system compliance reviewer** — it checks that code follows platform design conventions. For usability heuristics, use `review-ux`. For code quality, use `review-code`.

## Design System Detection

### Auto-detection

Determine the target design system from code signals:

| Signal | Design System | Reference |
|--------|--------------|-----------|
| `import SwiftUI`, `import UIKit`, `.swift` files with UI code | **Apple HIG** | developer.apple.com/design/human-interface-guidelines |
| `import androidx.compose.material3`, `@Composable`, XML layouts with `com.google.android.material` | **Material Design 3** | m3.material.io |
| `.html`, `.css`, `.tsx`/`.jsx` with React/Vue/Angular/Svelte, Tailwind classes | **Web** (WCAG 2.2 + HTML semantics) | w3.org/WAI/WCAG22 |

### Override

- **User argument**: `"HIG"`, `"Material"`, or `"Web"` in `$ARGUMENTS` overrides auto-detection.
- **`DESIGN.md`**: If a `DESIGN.md` exists at the repo root and declares a design system, use that.
- If detection is ambiguous (multiple frameworks), ask the user to clarify.

## Review Scope

### Determine what to review

Use the following priority order:

1. **User-specified scope**: If the user named specific files, directories, or scoping instructions, use those exactly.
2. **Git diff detection**: Otherwise, detect changed files:
   - **Feature branch**: Diff current branch against default branch (`main`/`master`) from merge-base, plus staged and unstaged changes.
   - **Default branch**: Staged and unstaged changes only.
3. **Fallback**: If no changes are detected, inform the user and ask what to review.

Filter to UI-relevant files only (view files, layout files, stylesheets, component files). Skip models, networking, tests, and backend logic unless they contain UI code.

### Load project context

Read these files if they exist (do not fail if absent):

- **Constitution** (`.specify/memory/constitution.md`): Project principles. Violations are CRITICAL.
- **Design guidelines** (`DESIGN.md` at repo root): Project-specific design rules structured as:
  - **Design System**: Declared target (Apple HIG, Material Design 3, Web)
  - **Always check**: Rules that must always be enforced
  - **Style**: Project conventions beyond the design system defaults
  - **Skip**: Files or patterns to exclude from review
- **Agent instructions** (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`): Additional project conventions.

If a `DESIGN.md` exists, its rules take precedence over general heuristics for the areas it covers.

## Review Dimensions

Evaluate changed UI code across these six dimensions. Skip dimensions irrelevant to the files under review. Apply platform-specific checks based on the detected design system.

### 1. Foundations

- **Color**: Semantic colors used instead of hardcoded values
  - HIG: Named colors from asset catalog, `Color.accentColor`, system colors
  - Material: `MaterialTheme.colorScheme` tokens, not hardcoded hex
  - Web: CSS custom properties / design tokens, not inline hex values
- **Typography**: Scalable text styles used
  - HIG: Dynamic Type via `.font(.body)`, `.font(.title)`, etc.
  - Material: `MaterialTheme.typography` text styles
  - Web: Relative units (`rem`, `em`), responsive font sizing
- **Spacing**: Design tokens or system spacing over magic numbers
- **Theming**: Dark mode / light mode supported
  - HIG: System appearance respected, no forced color scheme
  - Material: Dynamic color / Material You supported
  - Web: `prefers-color-scheme` media query handled

### 2. Layout & Navigation

- Navigation patterns match platform conventions
  - HIG: `NavigationStack`, `TabView`, no deprecated `NavigationView`
  - Material: `NavHost`, `NavigationBar`, `NavigationRail`
  - Web: Semantic `<nav>`, landmark regions, breadcrumbs
- Responsive / adaptive layout for different screen sizes
- Safe areas and insets respected (HIG, Material)
- Orientation and multitasking support where applicable

### 3. Components

- Platform-native components used correctly (not reinventing standard controls)
- Interactive controls have proper states: default, disabled, loading, error, selected
- Form elements have associated labels
- Buttons have clear visual hierarchy (primary, secondary, destructive)

### 4. Accessibility

- **Touch/tap targets**: Minimum sizes met
  - HIG: 44×44 pt
  - Material: 48×48 dp
  - Web: 44×44 px (WCAG 2.5.8)
- **Screen reader labels**: All interactive and meaningful visual elements labeled
  - HIG: `.accessibilityLabel()`, `.accessibilityHint()`
  - Material: `contentDescription`, `semantics { }`
  - Web: `aria-label`, `alt` text, semantic HTML
- **Color contrast**: Not relying on color alone to convey meaning
- **Motion**: Respecting reduced motion preferences
  - HIG: `accessibilityReduceMotion`
  - Material: `ReducedMotion`
  - Web: `prefers-reduced-motion`
- **Focus management**: Logical focus order, visible focus indicators
- **Heading hierarchy**: Correct heading levels for navigation

### 5. Content Display

- Images have accessibility descriptions
- Lists and collections use platform-appropriate patterns
- Loading states present for asynchronous content
- Empty states provide guidance (not blank screens)
- Error states displayed with recovery options

### 6. Platform Conventions

Platform-specific idioms that users expect:

- **HIG**: Back button in navigation bar, swipe-to-go-back, sheet presentation styles, pull-to-dismiss, respecting safe area for home indicator
- **Material**: FAB placement, bottom sheet behavior, snackbar positioning, edge-to-edge content, predictive back gesture
- **Web**: Skip-to-content link, `<main>` landmark, responsive breakpoints, progressive enhancement, print styles

## Confidence Scoring

Rate each finding from 0–100:

| Range | Meaning |
|-------|---------|
| 0–25 | Likely false positive or pre-existing issue |
| 26–50 | Minor style preference not in guidelines |
| 51–75 | Valid but low-impact |
| 76–89 | Important — violates design system guidelines |
| 90–100 | Critical — accessibility violation, constitution violation, or platform anti-pattern |

**Only report findings with confidence ≥ 76.**

Constitution violations are automatically CRITICAL (confidence 90+).

## Execution Steps

1. **Detect design system** — Auto-detect or use override from user / `DESIGN.md`.
2. **Determine scope** — Identify UI files to review.
3. **Load context** — Read constitution, `DESIGN.md`, and agent instructions.
4. **Review each file** — Evaluate against applicable dimensions with platform-specific checks.
5. **Filter** — Discard findings below confidence 76.
6. **Classify** — Group by severity (Critical ≥ 90, Important 76–89).
7. **Run self-assessment** — Verify report quality.
8. **Output report**.

## Output Format

### Summary header

```text
DESIGN REVIEW — <Design System>
Design system: <Auto-detected | User-specified> (<framework>)
Files reviewed: <count>
Findings: <critical count> critical, <important count> important
```

### Per-file findings

For each file with findings (omit files with 0 findings):

```text
<FileName>
Findings: <critical count> critical, <important count> important
```

### Critical Issues (confidence ≥ 90)

For each:
- **Tag and location**: `[Dimension Lnn]` (e.g., `[A11Y L42]`, `[Foundations L18]`)
- **Description** and confidence score
- **Fix**: Concrete suggestion
- **Ref**: Design system guideline URL

### Important Issues (confidence 76–89)

Same format as Critical.

### Strengths

Briefly note what the UI code does well (3–5 items max). Examples: consistent use of design tokens, strong accessibility labeling, proper navigation patterns.

## Self-Assessment Checklist

Before finalizing, verify:

- **Design system identified**: Detected or declared, not assumed.
- **Scope completeness**: All changed UI files reviewed (or `DESIGN.md` skip rules noted).
- **Confidence integrity**: No findings below 76 included.
- **Constitution check**: Constitution loaded and checked (or "no constitution found" noted).
- **Platform accuracy**: Findings reference the correct design system (not mixing HIG advice for a Material project).
- **Evidence quality**: Every finding includes file path, line number, and concrete fix.

If any check fails, fix the gap before outputting.

## Behavioral Notes

- Be precise and factual. Every finding must reference a specific file and line.
- Do not invent issues. If the UI code is clean, say so.
- Do not comment on code logic, performance, or test coverage — those belong to `review-code`.
- Respect `DESIGN.md` skip rules.
- When suggesting fixes, use platform-idiomatic code.
- Accessibility findings should always include the specific guideline reference (HIG, Material, WCAG).