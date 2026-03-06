---
name: review-code
description: Reviews code changes for logical correctness, design quality, and security. Use after code has been written to validate implementation quality.
---

# Review Code

Review code changes for logical correctness, design quality, and security.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines review-code-specific behavior.

## Input

Provide one of:
1. `review-request-*.md` file
2. original task + implementation summary + code changes

## Input Completeness Gate (Required)

Before reviewing quality, verify:
- scope is explicit (uncommitted / commit / branch and target)
- review focus or risk angles are stated
- verification evidence is present (tests, results, known gaps)

If critical context is missing:
- mark as `NEEDS_REVISION`
- list missing items in `Critical Issues`
- keep evidence factual; do not fabricate assumptions

## What to Review

- Logic correctness
- Design quality and coupling
- Security boundaries
- Edge-case handling
- Maintainability
- Compatibility/regression risk
- Verification coverage quality

## UI-Change Detection and Human Confirmation

In human-gated mode, detect likely user-facing UI changes.

Heuristics:
- frontend/template/style files changed (`*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.html`, `*.css`, `*.scss`, `*.less`)
- UI routes/pages/components changed
- design token/theme/layout/visible text changed
- browser-tool validation required

Policy rules:
- default: if UI change detected and no must-fix remains, require human UI confirmation before closeout
- override via `workflow_policy.ui_manual_confirmation`:
  - `auto` (default)
  - `required`
  - `skip`
- unattended mode may auto-closeout when policy allows

## What Not to Review

- syntax validity (linters)
- style/formatting (formatters)
- comment/string typos

## Output Format

```markdown
### Summary
[APPROVED / NEEDS_REVISION]: Brief rationale (1-2 sentences)

### Request Completeness Check
- Scope clarity: [PASS / FAIL]
- Review focus/risk angles: [PASS / FAIL]
- Verification evidence: [PASS / FAIL]
If any FAIL, explain why in `Critical Issues`.

### Critical Issues
Must fix before merge:
- [ ] **[CATEGORY]**: Description | Suggestion: How to fix
If none, write: `- None.`

### Design Concerns
Architecture/decision questions:
- **[Concern]**: Description | Suggestion: Alternative approach
If none, write: `- None.`

### Minor Suggestions
Optional improvements:
- [ ] Description
If none, write: `- None.`

### Security Check
- Injection risks: [PASS / FAIL / UNKNOWN] - [brief basis]
- Unsafe data exposure: [PASS / FAIL / UNKNOWN] - [brief basis]
- Input validation: [PASS / FAIL / UNKNOWN] - [brief basis]

### Verification Questions
For the implementer/author:
- [Q1] Question

### UI Manual Confirmation Package
- UI impact: [none detected | detected]
- Changed UI surfaces: [routes/pages/components]
- Manual check steps (human-run): [short checklist]
- Expected visible outcomes: [what user should see]
- Notes: [optional, no screenshot/recording required]
```

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Dispatch Helper Usage`
- `Reviewer Decision Flow`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> review path `.agent-artifacts/<task_id>/...` -> Agent Deck context -> ask
- `planner_session_id`: explicit/context only -> ask
- `current_session_id`: best-effort from `agent-deck session current --json`
- `reviewer_session_id`: explicit -> `current_session_id` -> inbound payload `context.to_session_id` -> ask
- `executor_session_id`: explicit -> inbound payload `context.from_session_id` -> default `executor-<task_id>`
- `round`: explicit -> parse from `-r<round>.md` -> ask
- `workflow_policy` (optional): explicit -> request/delegate context -> human-gated defaults
- `special_requirements` (optional fallback): explicit -> inbound payload `context.special_requirements` -> request/delegate context -> omit

Important identity clarification:
- `current_session_id` is for sender validation and safety checks.
- `planner_session_id` must come from explicit/context workflow metadata, not current-session detection.

Default policy when missing:
- `mode = "human_gated"`
- `auto_accept_if_no_must_fix = false`
- `auto_dispatch_next_task = false`
- `ui_manual_confirmation = "auto"`

Execution flow in Agent Deck mode:
1. Write report to `.agent-artifacts/<task_id>/review-report-r<round>.md`.
2. Choose action:
   - `rework_required` if `NEEDS_REVISION`, must-fix exists, or completeness FAIL.
   - `stop_recommended` if no must-fix remains.
3. For `rework_required`, dispatch to executor.
4. For `stop_recommended`:
   - if `auto_accept_if_no_must_fix=true`, run `review-closeout`
   - else present user decision summary and wait
   - in human-gated mode, request manual UI confirmation when required

Dispatch example (`rework_required`):

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session-id "<planner_session_id>" \
  --from-session-id "<reviewer_session_id>" \
  --to-session-id "<executor_session_id>" \
  --round "<round>" \
  --action "rework_required" \
  --artifact-path ".agent-artifacts/<task_id>/review-report-r<round>.md" \
  --note "Must-fix items remain. Address the review findings and submit the next review request." \
  --workflow-policy-json '<workflow_policy_json_optional>' \
  --special-requirements-json '<special_requirements_json_optional>' \
  --no-ensure-session \
  --no-start-session
```

Dispatch example (`user_requested_iteration` after user chooses iterate):

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session-id "<planner_session_id>" \
  --from-session-id "<reviewer_session_id>" \
  --to-session-id "<executor_session_id>" \
  --round "<round>" \
  --action "user_requested_iteration" \
  --artifact-path ".agent-artifacts/<task_id>/review-report-r<round>.md" \
  --note "User requested another implementation iteration. Address the requested follow-ups and submit a new review request." \
  --workflow-policy-json '<workflow_policy_json_optional>' \
  --special-requirements-json '<special_requirements_json_optional>' \
  --no-ensure-session \
  --no-start-session
```

User-facing output requirement for `stop_recommended`:
1. `### Review Decision`
2. `### Key Findings Snapshot`
3. `### Residual Risk`
4. `### Verification Summary`
5. `### UI Confirmation Gate`
6. `### Decision Needed`

When `auto_accept_if_no_must_fix=true`, skip decision prompt and state `Auto-accepted by workflow policy`.

Required interaction behavior:
- For `rework_required`, dispatch automatically after report generation.
- For `stop_recommended` with manual decision, wait for explicit user choice.
- Preserve `workflow_policy` unchanged in outbound dispatches.
- Preserve `special_requirements` unchanged in outbound dispatches.
- Keep control JSON internal unless user explicitly asks.

Sender identity rule:
- Reviewer-originated actions (`rework_required`, `user_requested_iteration`, `closeout_delivered`) use `from_session_id = reviewer_session_id`.
