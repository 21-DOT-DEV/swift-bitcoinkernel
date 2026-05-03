---
description: "Initialize or update a project design system specification"
handoffs:
  - label: Define Design Tokens
    agent: speckit.forge.design-tokens
    prompt: Initialize design tokens based on the design system
  - label: Spec a Component
    agent: speckit.forge.component
    prompt: Spec a component from the design system's component library
  - label: Create Feature Spec
    agent: speckit.specify
    prompt: Create a feature spec (the design system is available as context)
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may describe the project, specify platform targets, name a component library, or request updates to specific sections.

## Goal

Create or update a design system specification at `.specify/memory/design-system.md`. The design system is the single source of truth for visual design, component patterns, and UX guidelines across all target platforms.

This command is **independent but composable** — it works standalone, but cross-references `design-tokens` and `component` artifacts when they exist.

## Execution Flow

### 1. Check if design system exists

- Load `.specify/memory/design-system.md` if present.
- If exists: identify what the user wants to update or add. Propose a version bump.
- If not exists: prepare to create from scratch.

### 2. Load project context

Read these files if they exist (do not fail if absent):

- **Constitution** (`.specify/memory/constitution.md`): Project principles. The design system must align.
- **Design guidelines** (`DESIGN.md`): Project-specific design rules.
- **Existing tokens** (`.specify/memory/design-tokens.md`): Reference in Visual Foundation.
- **Existing components** (`.specify/memory/components/*.md`): Reference in Component Library.
- **Agent instructions** (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`).

### 3. Extract Figma context (optional)

If the user provides a Figma file or frame URL in `$ARGUMENTS`:

- Check if Figma MCP tools are available (e.g., `get_file`, `get_node`).
- If available, extract design context from the linked Figma file:
  - **Variables** → color palette, typography values, spacing scale
  - **Components** → component library inventory with variant counts
  - **Layout data** → grid system, responsive approach, frame dimensions
- Use extracted Figma data as the starting point for generation — do not ask the user to re-specify values already in Figma.
- If Figma MCP is not available or no URL is provided, skip this step and proceed with manual input.

### 4. Determine scope

- **New design system**: Collect comprehensive requirements.
- **Update**: Identify specific sections to modify, validate changes don't conflict with existing specs.

### 5. Collect requirements (interactive)

Only ask for information the user hasn't already provided. Make informed defaults for anything not specified.

**Visual Foundation** (only ask if not specified):
- Color palette intent and brand colors
- Typography choices (font families, type scale)
- Spacing system (base unit, scale)
- Icon system preference

**Component Approach** (only ask if not specified):
- Using existing library (shadcn/ui, SwiftUI native, Material Components, etc.) or custom?
- Component customization level

**Platform Targets** (only ask if not specified):
- iOS (SwiftUI / UIKit)
- Android (Jetpack Compose / XML)
- Web (React, Vue, HTML/CSS, etc.)
- Multi-platform

**UX Standards** (only ask if not specified):
- Accessibility target (default: WCAG AA)
- Responsive approach (mobile-first, adaptive, etc.)
- Animation philosophy (minimal, moderate, rich)

**Technology Stack** (only ask if not specified):
- CSS framework, component library, platform tooling

**Do NOT ask about**: Standard spacing scales (default 4px/8px base), standard breakpoints, basic accessibility (always WCAG AA minimum), icon libraries (suggest popular choices).

### 6. Generate design system spec

Write the following sections to `.specify/memory/design-system.md`:

**Header**:
- Design system name, version, creation/update date
- Platform targets
- One-paragraph description

**Design Principles**:
- 3-7 guiding principles that drive all design decisions
- Each principle: **Name** + one-sentence description + concrete implication
- Example: "**Clarity**: Prioritize readability over visual flair. → Prefer high-contrast text, generous whitespace, and familiar patterns over novelty."
- These principles are checked by `component` and `design-tokens` commands for consistency
- Derive from constitution if available; otherwise, infer from the project's domain and platform

**Visual Foundation**:
- Color palette (primary, secondary, accent, semantic, neutral)
- Typography (font families, type scale, weight usage)
- Spacing (base unit, scale, usage guidance)
- Iconography (icon set, sizing, usage)
- If `.specify/memory/design-tokens.md` exists, reference it here instead of duplicating values

**Component Library**:
- Core components list with brief descriptions
- Component status overview table:
  ```markdown
  | Component | Status | Platforms | Spec |
  |-----------|--------|-----------|------|
  | Button    | Ready  | iOS, Web  | [→](components/button.md) |
  | Card      | Draft  | iOS       | — |
  ```
  Status values: `Draft` → `In Progress` → `Ready` → `Deprecated`
- Composition patterns (common component combinations)
- Component states (standard states all components must support)
- If `.specify/memory/components/*.md` files exist, list and reference them with their status

**UX Guidelines**:
- Accessibility standards (target level, keyboard nav, screen reader, contrast)
- Responsiveness (breakpoints, approach, platform-specific layout)
- Interactions and animations (philosophy, timing, motion preferences)
- Feedback and messaging (success, error, warning, info patterns)

**Implementation Notes**:
- Technology stack (frameworks, libraries, versions)
- File structure conventions
- Naming conventions (CSS classes, Swift types, Compose functions, etc.)
- Platform-specific implementation guidance

**Governance**:
- Versioning rules (MAJOR / MINOR / PATCH)
- Change management process
- Compliance checks

### 7. Validate

**Quality checklist** (verify before writing):
- [ ] All mandatory sections completed
- [ ] Visual foundation clearly defined
- [ ] Component patterns documented
- [ ] Accessibility standards specified
- [ ] Technology choices specified and justified
- [ ] Aligns with constitution principles (if constitution exists)
- [ ] Version number follows semantic versioning
- [ ] No unresolved placeholders (except items marked `[NEEDS CLARIFICATION]`)

**Constitution alignment**:
- Compare design principles with constitution
- If conflicts found, flag them and suggest resolution
- Do not proceed with conflicting decisions without user confirmation

### 8. Write file

- Write to `.specify/memory/design-system.md`
- For updates: include a sync impact note as a comment at the top listing potentially affected specs/plans
- Include version and date in the header

### 9. Output summary

Provide:
- File location
- Version information
- Key design decisions documented
- Technology choices confirmed
- Next steps: suggest running `design-tokens` to define token values, `component` to spec individual components, or `specify` to create feature specs referencing the design system

## Spec-Driven Integration

This design system artifact participates in the Spec Kit pipeline:

- **Feeds into `specify`**: When creating feature specs, the design system is loaded as context. Feature specs involving UI should reference design system patterns, component names, and token names — not raw values.
- **Feeds into `plan`**: The plan command uses the design system for technical context — tech stack, component library, and naming conventions inform architecture decisions and contracts.
- **Feeds into `tasks`**: Tasks for UI features should reference specific design system components and tokens by name.
- **Reverse flow**: When `specify` identifies UI requirements that need new components or tokens not yet in the design system, it suggests running `design-tokens` or `component` to fill the gap.

## Versioning Rules

- **MAJOR** (X.0.0): Breaking changes — switching component library, complete palette overhaul, changes requiring rewrites
- **MINOR** (0.X.0): Additive — new components, new color variations, extended spacing, new patterns
- **PATCH** (0.0.X): Refinements — shade tweaks, doc improvements, clarifications, typo fixes

## Self-Assessment Checklist

Before finalizing, verify:

- **Completeness**: All 7 sections present and populated (including Design Principles).
- **Platform coverage**: All declared target platforms have specific guidance.
- **Constitution alignment**: Checked (or "no constitution found" noted).
- **Cross-references**: Existing tokens and components referenced (not duplicated).
- **Actionability**: A developer could start implementing from this spec.

## Behavioral Notes

- Be specific and concrete — use actual values, not vague descriptions ("Primary: #3B82F6", not "a modern blue").
- Provide rationale for design decisions (why these colors, why this library).
- Include practical examples showing how tokens, components, and patterns work together.
- Document accessibility explicitly — contrast ratios, keyboard patterns, screen reader guidance.
- When updating, preserve existing decisions unless the user explicitly asks to change them.
- Do not generate a design system template — generate the actual design system content based on the project.
- When Figma MCP data is available, prefer Figma values over asking the user. Note the Figma source in the header.
