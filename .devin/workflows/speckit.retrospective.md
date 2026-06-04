---
description: Analyze a completed feature or session against its spec, capture lessons
  learned, and propose actionable improvements
---


<!-- Extension: forge -->
<!-- Config: .specify/extensions/forge/ -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It may contain specific areas to focus on, links to conversation transcripts, or additional artifacts to review.

## Goal

Systematically inspect work done during a **single feature or chat session** to:

- Measure spec adherence and detect drift
- Identify what worked and what caused friction
- Surface patterns and decisions worth codifying
- Propose concrete, forward-looking improvements (edits, experiments, process changes)

This is **not** a generic sprint retrospective. It analyzes one session's transcript, specification, planning artifacts, and implementation to produce a structured report with actionable next steps.

## Constraints

- **Single session scope**: Process exactly one feature or session. If the conversation references multiple distinct features, ask for clarification before proceeding.
- **Read all referenced artifacts**: Load any available transcripts, the active feature's `spec.md`, any generated `plan.md` and `tasks.md`, and any other files explicitly mentioned by the user. Use minimal necessary context to avoid overloading.
- **Adhere to the project constitution** (`.specify/memory/constitution.md`): If suggestions conflict with principles, mark them as such. Constitution-violating changes require a separate process and **MUST NOT** be silently applied.
- **Propose edits, do not apply them automatically**: All suggested modifications to source files (including `AGENTS.md` and `.windsurf/rules/*`) must be grouped as "Proposed Edits." Present diffs or detailed change instructions for user approval.
- **Human gate for spec changes**: Before any action that modifies `spec.md` (including `/speckit.specify` handoff), explicitly ask for user confirmation. Default is NO — only explicit approvals (`y`, `yes`) count as consent.
- **Interactive feedback required**: Before composing the report, you **must** complete the interactive gates in the execution steps. Only proceed once all gates are passed or the user signals to skip.

## Execution Steps

### 1. Initialize Context

- Locate the feature directory. Parse `FEATURE_DIR`, `FEATURE_SPEC`, `PLAN`, and `TASKS` if they exist. Abort if the active feature directory or spec is missing.
- Collect the full chat transcript for the session (provided by the user) and any attachments.

### 2. Validate Completeness

Calculate task completion from `tasks.md`:

```text
completion_rate = (completed_tasks / total_tasks) * 100
```

Completion thresholds:
- **≥80%**: Proceed with full retrospective
- **50–79%**: Warn about incomplete implementation, continue with partial analysis
- **<50%**: **STOP** and confirm with user before continuing

### 3. Load Artifacts

From the feature directory and project root, load:
- `spec.md`: Functional requirements (FR-XXX), non-functional requirements (NFR-XXX), success criteria (SC-XXX), user stories, assumptions, edge cases
- `plan.md`: Architecture, data model, phases, constraints, dependencies
- `tasks.md`: All tasks with status, file paths, blockers
- `.specify/memory/constitution.md` (if exists)
- `AGENTS.md` and `.windsurf/rules/*` (if suggestions may affect agent instructions)

Do not modify any loaded files at this stage.

### 4. Discover Implementation

- Extract file paths from completed tasks plus recent git history
- Inventory: Models, APIs, Services, Tests, Config changes
- Audit: Libraries, frameworks, integrations actually used

### 5. Analyze the Session

Review the transcript and artifacts to reconstruct what was attempted and achieved:

1. **Spec drift analysis** — Compare implementation against spec:
   - Requirement coverage (implemented, partial, not implemented, modified, unspecified)
   - Success criteria validation
   - Architecture drift against plan
   - Task fidelity (completed / modified / added / dropped)

2. **Severity classification** — Classify each finding:
   - **CRITICAL**: Core functionality gaps or constitution violations
   - **SIGNIFICANT**: Deviations affecting UX, performance, or operations
   - **MINOR**: Small or cosmetic variations
   - **POSITIVE**: Improvements over spec (innovations worth preserving)

3. **Root cause analysis** — For key deviations capture:
   - Discovery point (planning / implementation / testing / review)
   - Cause (spec gap, tech constraint, scope evolution, misunderstanding, improvement, process skip)
   - Prevention recommendation

4. **Identify successes, friction points, patterns, decisions, and knowledge gaps** — Cross-reference with clarification categories (Functional, Domain & Data Model, Interaction & UX, Non-Functional, Integration, Edge Cases, Constraints, Terminology) to ensure broad coverage.

### Drift Classification Guidelines

**Count as drift**: Features differing from spec, dropped requirements, scope creep, changes in technical approach.

**Not drift**: Implementation details left unspecified, bounded optimizations, bug fixes, refactoring, test improvements.

### 6. Gather User Feedback (Interactive)

**⚠️ MANDATORY GATE**: Complete this interactive sequence and receive user responses before drafting the report. Do NOT proceed to step 7 until all sub-steps are answered.

1. **Identify Issues for Confirmation** (Question 1):
   - Present a numbered list of the most significant problems or tasks encountered, with an "Other" option for free-form input.
   - Ask: *"Which issue(s) caused the most friction?"*
   - **STOP and wait for user response.**

2. **Solicit Improvement Suggestions** (Question 2):
   - Based on confirmed problems and best practices, generate 2–4 recommended improvements.
   - Ask: *"Do you agree with these recommendations, or would you like to suggest different improvements?"*
   - **STOP and wait for user response.**

3. **Final Check** (Question 3 — Optional):
   - Ask: *"Any other issues or insights to include, or should I proceed with the report?"*
   - **STOP and wait for user response OR explicit "proceed" signal.**

**CHECKPOINT**: Only proceed to step 7 after receiving responses to questions 1–3 (or user signals to skip remaining questions).

### 7. Calculate Metrics

```text
Spec Adherence % = ((IMPLEMENTED + MODIFIED + (PARTIAL × 0.5)) / (Total Requirements − UNSPECIFIED)) × 100
```

Where Total Requirements is the count of all FR-XXX, NFR-XXX, SC-XXX from `spec.md`.

If precise numbers are unavailable, estimate qualitatively (High / Medium / Low) and note the limitation.

## Report Structure

Your output **must** follow this structure. If a section is empty, explicitly note "N/A" rather than omitting it.

### YAML Frontmatter

```yaml
---
feature: "<feature name>"
date: "YYYY-MM-DD"
completion_rate: "<X%>"
spec_adherence: "<X%>"
critical_findings: <count>
significant_findings: <count>
---
```

### Sections

1. **Session Overview**
   - One or two concise paragraphs summarizing the session's goal, main activities, and final state. State the date and any relevant context. Avoid quoting verbatim; summarize in your own words.

2. **Requirement Coverage Matrix**
   - Table mapping each FR/NFR/SC to status (Implemented, Partial, Not Implemented, Modified, Unspecified) with notes.

3. **Problems and Tasks Addressed**
   - Bullet list of specific problems tackled or tasks executed. For each: related artifact(s), whether fully or partially resolved, and root cause if a bug or flaw was uncovered.

4. **What Went Well (Strengths)**
   - Successful strategies, decisions, or implementations. Relate each to a broader best practice when possible.

5. **What Could Be Improved**
   - Areas of friction, mistakes, inefficiencies, or miscommunications. Categorize them (specification clarity, data modeling, UX, testing gaps, tool usage, constitution adherence). Explain why each hindered progress.
   - For positive deviations (innovations), document: what improved, why it's better, reusability potential, whether it's a constitution candidate.

6. **Patterns, Decisions and Rationale**
   - Significant patterns (architectural or behavioral) that emerged. Key decisions made, including alternatives considered and why the chosen approach was preferred. Note whether these should be added to `decisions.md` or captured as rules.

7. **Metrics and Indicators**
   - Spec adherence %, completion rate %, severity counts.
   - Additional qualitative metrics: tasks completed vs deferred, coverage of spec requirements, ratio of clarifications requested to needed, bug count, estimated time per task.

8. **Knowledge Gaps & Follow-Up**
   - Topics where the session revealed insufficient knowledge. Recommend research tasks, documentation updates, or training.
   - Open questions for stakeholders.

9. **Proposed Edits & Action Items**
   - Concrete modifications to project artifacts (spec, plan, tasks, documentation, agent rules). For each:
     - Target file(s) and section(s)
     - Brief rationale referencing retrospective insights
     - Diff or explicit replacement text
   - Group by priority (Critical, High, Medium, Low). Indicate whether constitutionally mandated, recommended, or optional.
   - **Proposed Spec Changes** (if any): Explicit list of intended `spec.md` edits, grouped by FR/NFR/SC with rationale. These require the human gate in step 10.

10. **Experiments & Best Practices to Try**
    - Propose 1–3 experiments or process changes based on recognized best practices. Explain expected benefit and how to measure success.

11. **Constitution Compliance**
    - Check each constitution article against implementation. Treat violations as CRITICAL. If none, state "No violations detected."

12. **Team Health & Communication** *(Optional)*
    - If the session surfaced interpersonal or process issues (unclear communication, conflicting interpretations), briefly describe and propose improvements. Otherwise, omit.

## Self-Assessment Checklist

Before finalizing the report, run this checklist and mark each item PASS or FAIL:

- **Evidence completeness**: Every major deviation includes concrete evidence (file, task, or behavior).
- **Coverage integrity**: FR/NFR/SC coverage is complete with no missing requirement IDs.
- **Metrics sanity**: `completion_rate` and `spec_adherence` formulas are applied correctly.
- **Severity consistency**: CRITICAL/SIGNIFICANT/MINOR/POSITIVE labels match stated impact.
- **Constitution review**: Constitution violations are explicitly listed (or "None" is stated).
- **Human gate readiness**: If spec changes are proposed, "Proposed Spec Changes" is populated and ready for user confirmation.
- **Actionability**: Recommendations are specific, prioritized, and directly tied to findings.

**Blocking rule**: If any of these fail — Coverage integrity, Metrics sanity, Human gate readiness (when applicable), or Constitution review — do not finalize the report. Fix the gaps first.

## Finalization

1. **Save report** to `FEATURE_DIR/retrospective.md`
2. If spec changes are proposed:
   - Present a short summary referencing the Proposed Spec Changes section.
   - Ask: *"Do you want me to modify spec.md now? (y/N)"*
   - Treat any response other than `y` or `yes` as NO.
   - Require separate confirmation for each spec-modifying action.
   - If declined, do not modify spec — continue with report-only recommendations.
3. **Prioritize follow-up actions**:
   1. CRITICAL: constitution violations, breaking changes, security issues
   2. HIGH: significant drift and process improvements
   3. MEDIUM: best practices and constitution candidates
   4. LOW: minor optimizations

## Behavioral Notes

- Be objective and factual; do not invent details absent from the transcript or artifacts. Where information is missing, state it as a knowledge gap.
- Use simple, clear language. Avoid jargon unless necessary and defined.
- Respect privacy and confidentiality: summarize without exposing sensitive data.
- When suggesting best practices, provide rationale tailored to the project context.
- Facts over judgments. Process over blame. Positive deviations are learning opportunities.