<div align="center">
  <h1>Forge</h1>
  <h3><em>SDLC workflows for roadmaps, retrospectives, reviews, and design.</em></h3>
</div>

<p align="center">
  <a href="https://github.com/21-DOT-DEV/spec-kit-extensions/releases"><img src="https://img.shields.io/github/v/release/21-DOT-DEV/spec-kit-extensions" alt="GitHub release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/21-DOT-DEV/spec-kit-extensions" alt="License" /></a>
</p>

---

Forge extends [Spec Kit](https://github.com/github/spec-kit) with commands for the parts of software development that happen before and after the core specify → plan → tasks → implement cycle: product strategy, retrospectives, code & design reviews, and design systems.

## Why Forge?

Spec Kit gives you a powerful pipeline — `specify → plan → tasks → implement` — but real projects need more than feature implementation. Forge fills the gaps:

- **Before you specify**: Define your product roadmap and design system so feature specs have context.
- **While you build**: Review code quality, design system compliance, and UX heuristics before merging.
- **After you ship**: Run retrospectives to capture lessons learned and improve your process.

Every Forge command produces `.specify/memory/` artifacts that the Spec Kit pipeline reads as context. Design tokens inform feature specs. Component specs feed into implementation plans. Retrospective insights shape future constitutions. The commands are independent but composable — use one or use all.

## Quick Start

1. **Install**:
   ```
   specify extension add forge
   ```

2. **Run a command** in any project with Spec Kit:
   ```
   /speckit.forge.roadmap "Build a photo sharing app with album organization"
   ```

3. **See the output** at `.specify/memory/roadmap.md` — then use `/speckit.specify` to turn roadmap features into implementation-ready specs.

## Commands

### Strategy

| Command | Alias | Description |
|---------|-------|-------------|
| `speckit.forge.roadmap` | `speckit.roadmap` | Create or update a multi-file product roadmap |
| `speckit.forge.retrospective` | `speckit.retrospective` | Analyze a completed feature or session, capture lessons learned, propose improvements |

### Review

| Command | Alias | Description |
|---------|-------|-------------|
| `speckit.forge.review-code` | `speckit.review-code` | Review changed code for quality, correctness, security, and guideline compliance |
| `speckit.forge.review-design` | `speckit.review-design` | Review UI code for design system compliance (HIG, Material, Web) |
| `speckit.forge.review-ux` | `speckit.review-ux` | Evaluate UI code against Nielsen's 10 usability heuristics |

### Design

| Command | Alias | Description |
|---------|-------|-------------|
| `speckit.forge.design-system` | `speckit.design-system` | Initialize or update a project design system specification |
| `speckit.forge.component` | `speckit.component` | Design and spec a reusable component for web and/or mobile |
| `speckit.forge.design-tokens` | `speckit.design-tokens` | Manage design tokens (colors, spacing, typography) |

## Usage

### Strategy

**Create a new roadmap**:

```
/speckit.forge.roadmap "Build a Swift cryptography library targeting Bitcoin, Lightning, and Nostr developers"
```

This generates:
- `.specify/memory/roadmap.md` — high-level index (vision, phases, metrics, changelog)
- `.specify/memory/roadmap/phase-*.md` — detailed per-phase files with features, dependencies, and risks

**Update an existing roadmap**:

```
/speckit.forge.roadmap "Mark Phase 1 complete, add BIP-39 mnemonic support to Phase 4"
```

The command detects existing artifacts and performs an incremental update with semantic versioning.

**Run a retrospective**:

```
/speckit.forge.retrospective
```

After a feature or session, this:
1. Validates task completion (warns if <80% done)
2. Analyzes spec adherence and drift
3. Asks you interactively what caused friction and what to improve
4. Generates a `retrospective.md` with metrics, proposed edits, and experiments

### Review

**Review code changes**:

```
/speckit.forge.review-code
```

Before a PR, this:
1. Detects changed files (feature branch diff or staged/unstaged)
2. Reviews across 8 dimensions (logic, security, guidelines, tests, performance, docs, design, dependencies)
3. Scores each finding by confidence (only reports ≥76)
4. Outputs a severity-grouped report with file:line references and fix suggestions

Customize with a `REVIEW.md` at repo root ("Always check" / "Style" / "Skip" sections).

**Review design system compliance**:

```
/speckit.forge.review-design
```

Auto-detects the design system from code (SwiftUI → Apple HIG, Compose → Material Design 3, React/HTML → Web/WCAG) and reviews across 6 dimensions: foundations, layout, components, accessibility, content display, and platform conventions.

Customize with a `DESIGN.md` at repo root ("Design System" / "Always check" / "Style" / "Skip" sections).

**Evaluate UX heuristics**:

```
/speckit.forge.review-ux
```

Evaluates UI code against Nielsen's 10 usability heuristics, identifying code-level UX issues like missing loading states, unclear error messages, and lack of undo support.

### Design

**Initialize a design system**:

```
/speckit.forge.design-system "Mobile-first SwiftUI app with custom component library targeting WCAG AA"
```

Creates `.specify/memory/design-system.md` with design principles, visual foundation (colors, typography, spacing), component library with status tracking, UX guidelines, implementation notes, and governance rules. Supports iOS, Android, and Web projects. Optionally pulls context from Figma via MCP.

**Spec a reusable component**:

```
/speckit.forge.component "Button with primary, secondary, and destructive variants"
```

Creates `.specify/memory/components/button.md` with anatomy, variants, sizes, states, props/API, accessibility, platform-specific notes, content guidelines, related components, usage guidelines, and code examples.

**Define design tokens**:

```
/speckit.forge.design-tokens "Initialize tokens for our SwiftUI app with dark mode support"
```

Creates `.specify/memory/design-tokens.md` with a 3-tier token hierarchy (primitive → semantic → component), token modes (light, dark, high-contrast), and platform-specific code blocks (Swift extensions, Compose objects, CSS custom properties).

## Installation

### From the community catalog (once published)

```
specify extension add forge
```

### From a GitHub release

```
specify extension add --from https://github.com/21-DOT-DEV/spec-kit-extensions/releases/latest
```

See [all releases](https://github.com/21-DOT-DEV/spec-kit-extensions/releases) for specific versions.

### Local development

```
git clone https://github.com/21-DOT-DEV/spec-kit-extensions.git
specify extension add --dev /path/to/spec-kit-extensions
```

### Verify installation

```
specify extension list
# Should show:
# ✓ Forge
#   Commands: 8 | Status: Enabled
```

## Development

```bash
# Clone the repo
git clone https://github.com/21-DOT-DEV/spec-kit-extensions.git
cd spec-kit-extensions

# Install in dev mode (symlinks to your local copy)
specify extension add --dev .

# Make changes to commands/ and test in any project with Spec Kit installed
```

## Requirements

- [Spec Kit](https://github.com/github/spec-kit) >= 0.1.0
- An AI coding agent (Windsurf, Claude Code, Cursor, GitHub Copilot, etc.)

## Contributing

Contributions are welcome. To get started:

1. Fork and clone the repository
2. Install in dev mode: `specify extension add --dev .`
3. Edit or add commands in `commands/` (Markdown with YAML frontmatter)
4. Test in any project with Spec Kit installed

See the Spec Kit [Extension Development Guide](https://github.com/github/spec-kit/tree/main/extensions) for command format and publishing details. Open an [issue](https://github.com/21-DOT-DEV/spec-kit-extensions/issues) for bugs, ideas, or questions.

## Acknowledgements

Forge draws on research and patterns from many sources:

- **[Spec Kit](https://github.com/github/spec-kit)** — the parent toolkit and spec-driven development methodology
- **[Supernova.io](https://www.supernova.io/)** — component health tracking, design system management patterns
- **[UI Guideline](https://www.uiguideline.com/)** — cross-system component naming research from 20 top design systems
- **[Component Gallery](https://component.gallery/)** — component examples and alternative names from 95+ design systems
- **[W3C Design Tokens Community Group](https://www.w3.org/community/design-tokens/)** — token format specification and taxonomy
- **[Nielsen Norman Group](https://www.nngroup.com/)** — the 10 usability heuristics adapted for code-level UX review
- **[Figma MCP](https://help.figma.com/hc/en-us/articles/32132100833559)** — design context extraction via Model Context Protocol
- **Apple HIG, Material Design 3, WCAG 2.2** — platform design guidelines for review commands

## License

[MIT](LICENSE)