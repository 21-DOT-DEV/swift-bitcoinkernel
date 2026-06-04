---
description: Manage design tokens (colors, spacing, typography)
handoffs:
- label: Update Design System
  agent: speckit.forge.design-system
  prompt: Update the design system's Visual Foundation to reference these tokens
- label: Spec a Component
  agent: speckit.forge.component
  prompt: Spec a component using these tokens
- label: Create Feature Spec
  agent: speckit.specify
  prompt: Create a feature spec (tokens are available as context)
---


<!-- Extension: forge -->
<!-- Config: .specify/extensions/forge/ -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may describe tokens to create or update (e.g., `"Add dark mode palette"`, `"Initialize tokens for our Swift library"`, `"Update spacing scale to 8px base"`).

## Goal

Create or update a design tokens specification at `.specify/memory/design-tokens.md`. Tokens are organized in a 3-tier hierarchy (primitive → semantic → component) with platform-specific code blocks for direct use in code.

This command is **independent but composable** — it works standalone, but references the design system spec when it exists and is referenced by component specs.

## Execution Flow

### 1. Parse user input

- Determine whether to create a new token file or update specific categories.
- Extract any platform targets, color values, or brand requirements mentioned.

### 2. Load project context

Read these files if they exist (do not fail if absent):

- **Design system** (`.specify/memory/design-system.md`): Visual foundation decisions (colors, typography, spacing).
- **Existing tokens** (`.specify/memory/design-tokens.md`): Current token definitions (for updates).
- **Existing components** (`.specify/memory/components/*.md`): Components that reference tokens.
- **Constitution** (`.specify/memory/constitution.md`): Project principles.
- **Design guidelines** (`DESIGN.md`): Project-specific design rules.
- **Agent instructions** (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`).

### 3. Extract Figma context (optional)

If the user provides a Figma file URL in `$ARGUMENTS`:

- Check if Figma MCP tools are available (e.g., `get_file`, `get_node`).
- If available, extract token data from Figma:
  - **Figma Variables** → primitive and semantic tokens (color, spacing, typography)
  - **Figma Styles** → legacy tokens (gradients, shadows, text styles)
  - **Variable modes** → theming (light/dark, brand variants, high-contrast)
  - **Variable collections** → map to token hierarchy tiers
- Use extracted Figma data as the starting point — do not ask the user to re-specify values already in Figma.
- If Figma MCP is not available or no URL is provided, skip and proceed with manual input.

### 4. Check if tokens file exists

- If exists: update mode — identify categories to add or modify. Propose a version bump.
- If not: create from scratch.

### 5. Auto-detect platform

Use this priority:
1. User-specified platform in `$ARGUMENTS`.
2. Platforms declared in `.specify/memory/design-system.md`.
3. Auto-detect from code:
   - `import SwiftUI` / `import UIKit` / `.swift` UI files → **iOS**
   - `import androidx.compose.material3` / `@Composable` → **Android**
   - `.html` / `.css` / `.tsx` / `.jsx` / Tailwind → **Web**
4. Ask if ambiguous.

Generate code blocks only for detected/specified platforms.

### 6. Generate token spec

Write the following sections to `.specify/memory/design-tokens.md`:

**Header**:
- Token file name, version, creation/update date
- Platform targets
- Base unit (e.g., 4px, 8px)

**Token Hierarchy**:

The 3-tier structure:

- **Primitive tokens**: Raw, context-free values. The palette.
  - Named by what they are: `blue-500`, `gray-100`, `font-inter`, `size-16`
- **Semantic tokens**: Intent-based aliases referencing primitives.
  - Named by what they mean: `color-primary`, `color-error`, `font-body`, `spacing-md`
- **Component tokens** (optional): Component-specific aliases referencing semantic tokens.
  - Named by where they're used: `button-bg-primary`, `card-border-radius`, `input-text-color`

Each tier references the one above via alias syntax: `{primitive-name}`.

**Token Categories** (from W3C DTCG taxonomy — include categories relevant to the project):

**Color**:
- Primitive: Full color palette with hex values (e.g., `blue-50` through `blue-900`)
- Semantic: `color-primary`, `color-secondary`, `color-accent`, `color-background`, `color-surface`, `color-text-primary`, `color-text-secondary`, `color-border`, `color-success`, `color-warning`, `color-error`, `color-info`

**Typography**:
- Font families (primary, monospace, optional display)
- Font weights (regular, medium, semibold, bold)
- Font sizes (type scale: xs, sm, base, lg, xl, 2xl, 3xl)
- Line heights (tight, normal, relaxed)
- Letter spacing (tight, normal, wide)

**Spacing**:
- Base unit and scale (e.g., 4px base: `spacing-1` = 4px, `spacing-2` = 8px, ..., `spacing-16` = 64px)
- Usage guidance (when to use each level)

**Sizing**:
- Icon sizes (sm, md, lg)
- Avatar sizes
- Touch/tap targets (44pt iOS, 48dp Android, 44px Web)

**Border**:
- Radius scale (none, sm, md, lg, full)
- Border widths (thin, default, thick)

**Shadow / Elevation**:
- Elevation levels (sm, md, lg, xl)
- Platform-appropriate values (CSS box-shadow, iOS shadow, Material elevation)

**Duration**:
- Animation timings (fast: 100ms, normal: 200ms, slow: 300ms)
- Easing functions

**Opacity**:
- Disabled state, overlay, hover highlight, pressed state

**Token Modes** (if applicable):
- Support arbitrary modes beyond light/dark (e.g., high-contrast, brand-A, brand-B)
- For each mode, document which semantic tokens change and which are mode-invariant
- Default mode and fallback behavior
- Platform mapping:
  - Figma variable modes → mode sets
  - iOS: `UIUserInterfaceStyle` / `ColorScheme` / custom `UITraitCollection`
  - Android: `isSystemInDarkTheme()` / Material `ColorScheme` / custom themes
  - Web: `prefers-color-scheme` / `prefers-contrast` / CSS custom property overrides / class-based toggling
- At minimum, include light and dark modes if the project supports theming

**Platform Code Blocks**:

For each detected platform, include a code block showing how to consume the tokens:

- **iOS (Swift)**:
  ```swift
  extension Color {
      static let primary = Color("primary") // or Color(hex: "#...")
      static let textPrimary = Color("textPrimary")
  }
  ```

- **Android (Compose)**:
  ```kotlin
  object AppTokens {
      val colorPrimary = Color(0xFF3B82F6)
      val spacingMd = 16.dp
  }
  ```

- **Web (CSS Custom Properties)**:
  ```css
  :root {
      --color-primary: #3B82F6;
      --spacing-md: 1rem;
  }
  ```

- **Web (Tailwind Config)** (if Tailwind detected):
  ```js
  module.exports = {
      theme: {
          extend: {
              colors: { primary: { DEFAULT: '#3B82F6' } },
          },
      },
  };
  ```

### 7. Validate

- **Alias resolution**: Every semantic token references a defined primitive. No broken references.
- **Completeness**: At minimum, color, typography, and spacing categories defined.
- **Contrast**: Semantic color pairings meet WCAG AA contrast ratios (4.5:1 for text, 3:1 for large text).
- **Constitution alignment**: Token values align with project principles.
- **Consistency**: Token naming follows a consistent pattern throughout.

### 8. Write file

- Write to `.specify/memory/design-tokens.md` with version and date.
- For updates: note which tokens changed and which components may be affected.

### 9. Output summary

Provide:
- File location
- Version information
- Token count per category
- Platforms with code blocks generated
- If `.specify/memory/design-system.md` exists: note that design system Visual Foundation should reference these tokens
- If `.specify/memory/components/*.md` exist: list components that should use these tokens
- Next steps: suggest running `component` to spec components using these tokens, or `design-system` to create the overarching design system

## Spec-Driven Integration

This token spec participates in the Spec Kit pipeline:

- **Feeds into `specify`**: Feature specs that reference colors, spacing, or typography should use token names, not raw values. The specify command loads tokens as context.
- **Feeds into `plan`**: The plan command's quickstart.md and tech stack sections reference the token consumption pattern (Swift extension, CSS vars, Compose object, etc.).
- **Feeds into `tasks`**: Implementation tasks include "use token `{name}` from design-tokens.md" rather than hardcoded values.
- **Reverse flow**: When `specify` or `component` identifies token gaps (e.g., a new semantic color needed), it suggests running this command to add them.

## W3C DTCG Reference

Token categories and type taxonomy follow the W3C Design Tokens Community Group specification (2025.10). Token naming follows the Category/Type/Item structure popularized by Style Dictionary. The command documents tokens in Markdown with platform-specific code blocks rather than generating DTCG JSON directly, but references the standard for teams that want to export to tooling.

## Self-Assessment Checklist

Before finalizing, verify:

- **Hierarchy integrity**: Every semantic token resolves to a primitive. No orphans.
- **Category coverage**: At minimum color, typography, and spacing are defined.
- **Platform accuracy**: Code blocks match the detected/specified platforms.
- **Constitution alignment**: Checked (or "no constitution found" noted).
- **Contrast compliance**: Text color / background color pairings meet WCAG AA.
- **Naming consistency**: All tokens follow the same naming pattern.

## Behavioral Notes

- Be specific — use actual hex values, pixel sizes, and font names. Never use placeholder values like "your-brand-color".
- When the design system spec exists, derive token values from it. Do not contradict it.
- The 3-tier hierarchy is a guideline — small projects may skip component tokens.
- Always include both light and dark mode if the project supports theming.
- Code blocks must be syntactically valid for the target platform.
- When updating, preserve existing token values unless the user explicitly asks to change them.
- Reference the W3C DTCG standard in the file header for teams that want interoperability with tools like Style Dictionary or Tokens Studio.
- When Figma MCP data is available, prefer Figma values over asking the user. Note the Figma source in the header.
- Check design principles from `.specify/memory/design-system.md` for consistency when making token decisions.