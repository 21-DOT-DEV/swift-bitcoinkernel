---
description: Review changed code for quality, correctness, security, and project guideline
  compliance
---


<!-- Extension: forge -->
<!-- Config: .specify/extensions/forge/ -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may specify files to review, areas to focus on, or scope constraints (e.g., "only staged changes", "only files in Sources/").

## Goal

Perform a focused code review of changed files, evaluating quality across eight dimensions with confidence-scored findings. The review is constitution-aware, supports project-specific review guidelines, and produces an actionable report grouped by severity.

This is a **single-purpose code quality reviewer** — not an orchestrator. It reviews code directly and reports findings.

## Review Scope

### Determine what to review

Use the following priority order:

1. **User-specified scope**: If the user named specific files, directories, or scoping instructions, use those exactly.
2. **Git diff detection**: Otherwise, detect changed files:
   - **Feature branch**: Diff current branch against default branch (`main`/`master`) from merge-base, plus staged and unstaged changes.
   - **Default branch**: Staged and unstaged changes only.
3. **Fallback**: If no changes are detected, inform the user and ask what to review.

### Load project context

Read these files if they exist (do not fail if absent):

- **Constitution** (`.specify/memory/constitution.md`): Project principles. Violations are CRITICAL.
- **Review guidelines** (`REVIEW.md` at repo root): Project-specific review rules structured as:
  - **Always check**: Rules that must always be enforced (e.g., "new API endpoints must have tests")
  - **Style**: Project conventions beyond what linters catch (e.g., "prefer early returns over nested conditionals")
  - **Skip**: Files or patterns to exclude from review (e.g., "generated files under `src/gen/`")
- **Agent instructions** (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`): Additional project conventions.

If a `REVIEW.md` exists, its rules take precedence over general heuristics for the areas it covers.

## Review Dimensions

Evaluate changed code across these eight dimensions. Not all dimensions apply to every change — skip dimensions that are irrelevant to the files under review.

### 1. Logic & Correctness
- Algorithms produce correct results for all inputs
- Edge cases handled (nil/null, empty collections, boundary values, overflow)
- Control flow is complete (no missing branches, unreachable code)
- State mutations are intentional and safe
- Concurrency: no race conditions, proper synchronization

### 2. Security
- No secrets, keys, or credentials in code or logs
- Input validation present for external data
- No injection vulnerabilities (SQL, command, path traversal)
- Authentication and authorization checks in place where needed
- Cryptographic operations use vetted libraries and safe parameters
- Error messages do not leak internal details

### 3. Project Guidelines Compliance
- Adherence to constitution principles
- Import patterns and framework conventions followed
- Naming conventions consistent with project style
- Error handling follows project patterns
- Platform compatibility requirements met
- Logging follows project standards

### 4. Test Coverage
- New functionality has corresponding tests
- Edge cases and error paths tested
- Tests are behavioral (test outcomes, not implementation details)
- No flaky patterns (timing-dependent, order-dependent, external-service-dependent)
- Critical paths have sufficient coverage

### 5. Performance
- No unnecessary allocations in hot paths
- Appropriate data structures and algorithms for the scale
- No N+1 queries or unbounded iterations
- Resource cleanup (file handles, connections, memory) is correct
- No regressions to existing performance characteristics

### 6. Documentation & Clarity
- Public APIs have clear documentation
- Complex logic has explanatory comments
- Comments are accurate (not stale or misleading)
- Intent is clear from naming and structure without requiring comments

### 7. Duplication & Design
- No copy-paste code that should be extracted
- Abstractions are appropriate (not premature, not missing)
- Single Responsibility: functions and types have focused purpose
- Dependencies flow in one direction (no circular references)

### 8. Dependency Management
- No unnecessary new dependencies introduced
- Dependency versions are pinned or bounded
- License compatibility verified for new dependencies
- No vendored code that diverges from upstream without documentation

## Confidence Scoring

Rate each finding from 0–100:

| Range | Meaning |
|-------|---------|
| 0–25 | Likely false positive or pre-existing issue |
| 26–50 | Minor nitpick not in project rules |
| 51–75 | Valid but low-impact |
| 76–89 | Important issue requiring attention |
| 90–100 | Critical bug, security vulnerability, or constitution violation |

**Only report findings with confidence ≥ 76.**

This threshold exists to eliminate noise. When in doubt about confidence, err on the side of not reporting. Quality over quantity.

## Constitution Compliance

If a constitution exists, check every finding and every changed file against its principles:

- **Constitution violations are automatically CRITICAL** (confidence 90+) regardless of the dimension they fall under.
- Flag the specific article or principle violated.
- If a proposed fix would itself violate the constitution, note the conflict and do not suggest it.

## Execution Steps

1. **Determine scope** — Identify files to review per the priority order above.
2. **Load context** — Read constitution, `REVIEW.md`, and agent instructions.
3. **Review each file** — Evaluate against applicable dimensions. Score each finding.
4. **Filter** — Discard findings below confidence 76.
5. **Classify** — Group by severity (Critical ≥ 90, Important 76–89).
6. **Check constitution** — Escalate any constitution violations to Critical.
7. **Run self-assessment** — Verify report quality before finalizing.
8. **Output report** — Structured format per below.

## Output Format

### Summary header

```text
Files reviewed: <count>
Findings: <critical count> critical, <important count> important
Strengths: <count>
```

### Critical Issues (confidence ≥ 90)

For each:
- **Description** and confidence score
- **File** and line number
- **Dimension**: Which of the 8 dimensions this falls under
- **Rule**: Specific project guideline, constitution article, or `REVIEW.md` rule violated (if applicable)
- **Fix**: Concrete suggestion with code snippet where helpful

### Important Issues (confidence 76–89)

Same format as Critical.

### Strengths

Briefly note what the changed code does well. Examples: clean error handling, good test coverage, clear naming, performance-conscious design. Keep to 3–5 items maximum.

### Recommended Actions

Prioritized list:
1. Fix all Critical issues before merging
2. Address Important issues
3. Consider re-running review after fixes: `/speckit.forge.review-code`

## Self-Assessment Checklist

Before finalizing the report, verify:

- **Scope completeness**: All changed files were reviewed (or exclusions from `REVIEW.md` noted).
- **Confidence integrity**: No findings below 76 are included.
- **Constitution check**: Constitution was loaded and checked (or "no constitution found" noted).
- **Evidence quality**: Every finding includes file path, line number, and concrete fix.
- **False positive filter**: No speculative or stylistic-only findings unless backed by project rules.

If any check fails, fix the gap before outputting the report.

## Behavioral Notes

- Be precise and factual. Every finding must reference a specific file and line.
- Do not invent issues. If the code is clean, say so — a short "no issues found" report is a valid outcome.
- Do not comment on formatting if the project uses automated formatters (SwiftFormat, Prettier, etc.).
- Respect `REVIEW.md` skip rules — do not review excluded files or patterns.
- When suggesting fixes, ensure they are idiomatic for the project's language and conventions.
- For security findings in cryptographic code, be especially rigorous — false negatives here are more costly than false positives.