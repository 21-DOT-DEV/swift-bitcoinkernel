---
description: Design and spec a reusable component for web and/or mobile
handoffs:
- label: Define Design Tokens
  agent: speckit.forge.design-tokens
  prompt: Define tokens referenced by this component
- label: Spec Another Component
  agent: speckit.forge.component
  prompt: Spec a related component
- label: Create Feature Spec
  agent: speckit.specify
  prompt: Create a feature spec using this component
---


<!-- Extension: forge -->
<!-- Config: .specify/extensions/forge/ -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It should name the component and may describe variants, platform targets, or specific requirements (e.g., `"Button with primary, secondary, destructive variants for SwiftUI"`).

## Goal

Create or update a component specification at `.specify/memory/components/<component-name>.md`. Each component gets a standalone spec covering purpose, anatomy, variants, states, API, accessibility, platform notes, and code examples.

This command is **independent but composable** — it works standalone, but references the design system and design tokens when they exist.

## Execution Flow

### 1. Parse user input

- Extract the component name (required — ask if not provided).
- Extract any specified variants, platform targets, or constraints.
- Determine file path: `.specify/memory/components/<component-name>.md` (kebab-case).

### 2. Load project context

Read these files if they exist (do not fail if absent):

- **Design system** (`.specify/memory/design-system.md`): Platform targets, component library approach, UX guidelines.
- **Design tokens** (`.specify/memory/design-tokens.md`): Use token names in code examples instead of raw values.
- **Existing components** (`.specify/memory/components/*.md`): Check for related components, ensure consistency.
- **Constitution** (`.specify/memory/constitution.md`): Project principles.
- **Agent instructions** (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`).

### 3. Extract Figma context (optional)

If the user provides a Figma component URL in `$ARGUMENTS`:

- Check if Figma MCP tools are available (e.g., `get_file`, `get_node`).
- If available, extract component context from Figma:
  - **Variants and properties** → variant names, boolean/enum props
  - **Anatomy** → layer structure, required vs optional parts
  - **Applied variables/styles** → token references for colors, spacing, typography
- Use extracted Figma data as the starting point — do not ask the user to re-describe what Figma already defines.
- If Figma MCP is not available or no URL is provided, skip and proceed with manual input.

### 4. Check if component exists

- If `.specify/memory/components/<component-name>.md` exists: update mode — identify what the user wants to change.
- If not: create from scratch.

### 5. Detect platform targets

Use this priority:
1. User-specified platforms in `$ARGUMENTS`.
2. Platforms declared in `.specify/memory/design-system.md`.
3. Auto-detect from code (SwiftUI/UIKit → iOS, Compose → Android, React/HTML/CSS → Web).
4. Ask if ambiguous.

Only include sections for relevant platforms — do not generate iOS guidance for a web-only project.

### 6. Generate component spec

Write the following sections:

**Header**:
- Component name, version, creation/update date
- **Also known as**: Alternative names from other design systems (e.g., Accordion = "Collapse, Disclosure, Expandable"). Source from cross-system naming patterns (UI Guideline, Component Gallery). Omit if no well-known alternatives exist.
- **Status**: `Draft` | `In Progress` | `Ready` | `Deprecated`
  - Health dimensions (brief assessment):
    - **Functionality**: Does the spec cover all required use cases?
    - **Relevance**: Is the spec current with the design system?
    - **Reliability**: Are all states, edge cases, and accessibility covered?
- One-sentence purpose

**Purpose & Context**:
- What problem this component solves
- Where it's used (pages, flows, patterns)
- Relationship to other components (parent, child, sibling)

**Anatomy**:
- Visual parts breakdown (e.g., "Container → Icon (optional) + Label + Trailing Icon (optional)")
- Required vs optional parts
- Slot / children areas
- Mermaid diagram if the component has non-trivial structure

**Variants**:
- Named variants with descriptions (e.g., primary, secondary, outline, ghost, destructive)
- Visual differences per variant
- When to use each variant

**Sizes**:
- Available sizes (sm, md, lg or project-specific scale)
- Dimensions and internal spacing per size
- Touch target compliance per platform (44pt iOS, 48dp Android, 44px Web)

**States**:
- All interaction states: default, hover, active/pressed, focus, disabled, loading, error, selected
- Visual changes for each state (color, opacity, border, shadow)
- Transition timing (e.g., "150ms ease-in-out for color transitions")
- Which states apply per platform (hover is web/desktop only, pressed is mobile)

**Props / API**:
- Platform-appropriate API definition:
  - **SwiftUI**: `init` parameters and view modifiers
  - **Compose**: `@Composable` function parameters
  - **React/Web**: TypeScript props interface
- Required vs optional props with types
- Default values
- Callback signatures (onTap, onClick, onChange, etc.)

**Accessibility**:
- Semantic role (button, link, heading, etc.)
- Screen reader label guidance (what should be announced)
- Keyboard interaction pattern:
  - Web: Tab to focus, Enter/Space to activate, Escape to dismiss
  - iOS: VoiceOver gestures, rotor actions
  - Android: TalkBack navigation, custom actions
- Focus management (focus order, focus trapping for modals)
- ARIA attributes (web) / accessibility traits (iOS) / semantics (Android)
- Color contrast requirements

**Platform Notes**:
Include only for platforms the project targets:
- **iOS**: HIG alignment, SF Symbols usage, Dynamic Type support, SwiftUI-specific patterns
- **Android**: Material alignment, Compose theming integration, configuration changes
- **Web**: HTML semantics, CSS considerations, responsive behavior, progressive enhancement

**Usage Guidelines**:
- Do's: correct usage patterns, recommended compositions
- Don'ts: anti-patterns, misuse scenarios
- Common compositions with other components

**Related Components**:
- Parent components (e.g., Button → ButtonGroup)
- Child components (e.g., Form → FormField, FormLabel)
- Sibling components (e.g., Button ↔ IconButton, LinkButton)
- Link to their spec files if they exist in `.specify/memory/components/`

**Content Guidelines**:
- How to write labels, placeholders, error messages, and tooltips for this component
- Capitalization rules (sentence case vs title case, per platform convention)
- Character limits and truncation behavior
- Localization considerations (text expansion, RTL support)

**Code Examples**:
- One basic usage example per target platform
- Use design token names if `.specify/memory/design-tokens.md` exists (e.g., `Color.primary` not `Color(hex: "#3B82F6")`)
- Show at least two variants if the component has variants

### 7. Validate

- **Constitution alignment**: Design decisions align with project principles.
- **Design system consistency**: Component follows the design system's patterns, spacing, and conventions.
- **Accessibility completeness**: Every interactive element has screen reader guidance, keyboard pattern, and contrast requirements.
- **Cross-platform coherence**: Same component behaves consistently across platforms (adapted to platform idioms, not identical).
- **Token usage**: Code examples use design tokens, not raw values (when tokens exist).

### 8. Write file

- Write to `.specify/memory/components/<component-name>.md`
- Create the `components/` directory if it doesn't exist.

### 9. Output summary

Provide:
- File location
- Component name and version
- Platforms covered
- Variant count and state count
- If `.specify/memory/design-system.md` exists: suggest adding the component to the Component Library section
- Next steps: suggest running `design-tokens` if tokens don't exist yet, or `specify` to create a feature spec using this component

## Spec-Driven Integration

This component spec participates in the Spec Kit pipeline:

- **Feeds into `specify`**: Feature specs can reference this component by name. Success criteria may include "uses [ComponentName] from the design system."
- **Feeds into `plan`**: The plan command uses component API from this spec for technical context. Data model entities may map to component props.
- **Feeds into `tasks`**: Implementation tasks reference this spec for API, states, accessibility requirements, and code examples.
- **Reverse flow**: When `specify` identifies a UI pattern that needs a new component, it suggests running this command first.

## Component Naming

- File name: kebab-case (e.g., `button.md`, `transaction-card.md`, `fee-picker.md`)
- One component per file — do not combine multiple components
- Compound components (e.g., `Form` with `FormField`, `FormLabel`) go in one file named after the parent

## Self-Assessment Checklist

Before finalizing, verify:

- **All sections present**: Purpose, anatomy, variants, sizes, states, props, accessibility, platform notes, related components, content guidelines, usage, examples.
- **Platform accuracy**: Only relevant platforms included; guidance matches correct platform idioms.
- **Accessibility complete**: Every interactive state has screen reader, keyboard, and contrast guidance.
- **Constitution alignment**: Checked (or "no constitution found" noted).
- **Token integration**: Code examples use tokens when available.
- **Actionability**: A developer could implement this component from the spec alone.

## Behavioral Notes

- Be specific — use actual values, dimensions, and color token names.
- Every variant and state must be explicitly defined; do not leave any as "standard" or "default behavior."
- Code examples must be syntactically valid for the target platform.
- Do not duplicate design token values — reference the token file.
- When updating, preserve existing decisions unless the user explicitly asks to change them.
- If the component is similar to a platform-native component, note the differences and justify the custom version.
- When Figma MCP data is available, prefer Figma values over asking the user. Note the Figma source in the header.
- Check design principles from `.specify/memory/design-system.md` for consistency when making design decisions.