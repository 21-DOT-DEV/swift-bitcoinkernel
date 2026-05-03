---
description: "Evaluate UI code against Nielsen's 10 usability heuristics"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may specify files to review, heuristics to focus on (e.g., `"error handling"`, `"H1 H5 H9"`), or areas of concern.

## Goal

Evaluate changed UI code against Nielsen's 10 usability heuristics, identifying UX issues that are detectable from code. Produce an actionable report with concrete fixes tied to specific heuristic violations.

This is a **single-purpose UX heuristic evaluator** — it checks usability patterns in code. For design system compliance, use `review-design`. For code quality, use `review-code`.

## Review Scope

### Determine what to review

Use the following priority order:

1. **User-specified scope**: If the user named specific files, directories, or scoping instructions, use those exactly.
2. **Git diff detection**: Otherwise, detect changed files:
   - **Feature branch**: Diff current branch against default branch (`main`/`master`) from merge-base, plus staged and unstaged changes.
   - **Default branch**: Staged and unstaged changes only.
3. **Fallback**: If no changes are detected, inform the user and ask what to review.

Filter to UI-relevant files only (views, screens, components, controllers, templates). Skip models, networking, and backend logic unless they directly affect user-facing behavior.

### Load project context

Read these files if they exist (do not fail if absent):

- **Constitution** (`.specify/memory/constitution.md`): Project principles. Violations are CRITICAL.
- **Design guidelines** (`DESIGN.md` at repo root): If present, apply its "Always check" and "Skip" rules.
- **Agent instructions** (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`): Additional project conventions.

## Nielsen's 10 Heuristics

Evaluate each heuristic against the changed code. Not all heuristics apply to every file — skip those that are irrelevant. Each heuristic includes concrete, code-reviewable checks.

### H1: Visibility of System Status

The system should always keep users informed about what is going on through appropriate feedback within reasonable time.

- Loading indicators present for asynchronous operations
- Progress feedback for multi-step or long-running tasks
- Network/connectivity state communicated to the user
- Success and failure confirmation after user actions
- Real-time state reflected in the UI (e.g., save status, sync status)

### H2: Match Between System and Real World

The system should speak the users' language, with words, phrases, and concepts familiar to the user.

- Labels and messages use user-facing language (not developer jargon, error codes, or internal identifiers)
- Icons match common real-world expectations
- Date, currency, and number formatting is locale-aware
- Terminology is consistent with the domain the user understands
- Information presented in a natural and logical order

### H3: User Control and Freedom

Users often perform actions by mistake. They need a clearly marked "emergency exit" to leave the unwanted action.

- Undo/redo support where data changes are reversible
- Cancel and dismiss actions always available in flows and modals
- Destructive actions gated by confirmation (delete, send, submit)
- Navigation allows going back from any screen
- Users can exit multi-step flows without losing all progress

### H4: Consistency and Standards

Users should not have to wonder whether different words, situations, or actions mean the same thing.

- Same action uses the same label, icon, and position throughout the app
- Terminology consistent across all screens
- Similar features behave the same way
- Platform conventions followed (partially covered by `review-design`)

### H5: Error Prevention

Even better than good error messages is a careful design which prevents a problem from occurring in the first place.

- Input validation before submission (client-side)
- Dangerous actions require confirmation dialogs
- Form constraints prevent invalid states (e.g., disabled submit until valid)
- Type-appropriate inputs used (numeric keyboard for numbers, email keyboard for email)
- Default values set to safe/common choices

### H6: Recognition Rather Than Recall

Minimize the user's memory load by making elements, actions, and options visible.

- Recently used items accessible (history, recents)
- Search and filter available in long lists or data sets
- Defaults populated where possible
- Placeholder text or hints guide input
- Context preserved when navigating between screens (no unexpected resets)

### H7: Flexibility and Efficiency of Use

Accelerators — unseen by the novice user — may speed up interaction for expert users.

- Keyboard shortcuts for power users (desktop and web)
- Bulk actions available for lists and multi-select
- Customizable preferences or settings
- Progressive disclosure — advanced options hidden by default
- Shortcuts for repeated actions (e.g., quick-add, swipe actions)

### H8: Aesthetic and Minimalist Design

Dialogues should not contain information which is irrelevant or rarely needed.

- No redundant information competing for attention on the same screen
- Visual hierarchy clear — primary and secondary actions visually distinct
- Content density appropriate for the context
- Whitespace used to separate logical groups
- Decorative elements do not distract from content

### H9: Help Users Recognize, Diagnose, and Recover from Errors

Error messages should be expressed in plain language, precisely indicate the problem, and constructively suggest a solution.

- Error messages are human-readable (not raw error codes or stack traces)
- Messages suggest a specific corrective action
- Inline validation provides immediate, specific feedback per field
- Retry mechanisms present for transient failures (network errors)
- Error states are visually distinct and recoverable (not dead-ends)

### H10: Help and Documentation

Even though it is better if the system can be used without documentation, it may be necessary to provide help.

- Onboarding or first-run experience present for new users
- Tooltips or contextual help for complex features
- Empty states provide guidance on what to do next
- Help is accessible without leaving the current context
- FAQ, documentation, or support links reachable from the app

## Confidence Scoring

Rate each finding from 0–100:

| Range | Meaning |
|-------|---------|
| 0–25 | Likely false positive or subjective preference |
| 26–50 | Minor UX polish, not a usability problem |
| 51–75 | Valid but low-impact for most users |
| 76–89 | Important — clear usability problem affecting task completion |
| 90–100 | Critical — user cannot complete task, data loss risk, or constitution violation |

**Only report findings with confidence ≥ 76.**

Constitution violations are automatically CRITICAL (confidence 90+).

## Execution Steps

1. **Determine scope** — Identify UI files to review.
2. **Load context** — Read constitution, `DESIGN.md`, and agent instructions.
3. **Review each file** — Evaluate against all 10 heuristics. Score each finding.
4. **Filter** — Discard findings below confidence 76.
5. **Classify** — Group by severity (Critical ≥ 90, Important 76–89).
6. **Run self-assessment** — Verify report quality.
7. **Output report**.

## Output Format

### Summary header

```text
UX REVIEW — Nielsen's Heuristics
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
- **Tag and location**: `[Hn <ShortName> Lnn]` (e.g., `[H1 Visibility L55]`, `[H9 ErrorRecovery L88]`)
- **Description** and confidence score
- **Heuristic**: Full name and number
- **Fix**: Concrete suggestion

### Important Issues (confidence 76–89)

Same format as Critical.

### Strengths

Briefly note UX patterns the code handles well (3–5 items max). Examples: comprehensive error handling, good loading state coverage, strong input validation.

## Self-Assessment Checklist

Before finalizing, verify:

- **Heuristic coverage**: All 10 heuristics were considered (not necessarily all flagged — some may be N/A).
- **Scope completeness**: All changed UI files reviewed (or skip rules noted).
- **Confidence integrity**: No findings below 76 included.
- **Constitution check**: Constitution loaded and checked (or "no constitution found" noted).
- **Evidence quality**: Every finding includes file path, line number, heuristic reference, and concrete fix.
- **No design system overlap**: Findings focus on usability, not design system compliance (that belongs to `review-design`).

If any check fails, fix the gap before outputting.

## Behavioral Notes

- Be precise and factual. Every finding must reference a specific file and line.
- Do not invent issues. If the UX patterns are sound, say so.
- Do not comment on visual design, color choices, or typography — those belong to `review-design`.
- Do not comment on code logic, performance, or tests — those belong to `review-code`.
- Focus on what is detectable from code. Do not speculate about runtime behavior you cannot verify from source.
- Respect `DESIGN.md` skip rules.
- When suggesting fixes, provide code-level guidance (not wireframes or design mockups).
