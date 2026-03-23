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
1. the mailbox body from `review_requested`
2. the mailbox body from `browser_check_report` plus current review context
3. original task + implementation summary + code changes

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

- logic correctness
- design quality and coupling
- security boundaries
- edge-case handling
- maintainability
- compatibility/regression risk
- verification coverage quality

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

## Verification Reuse Rule

- Treat `Checks Already Run` in `review_requested` as the primary record of coder-run verification
- Usually reuse recorded lint, build/link, compile/type-check, and test results instead of rerunning the same slow checks
- Rerun only when the recorded evidence is missing, stale, too broad, too narrow, suspicious, or does not answer the actual review risk
- When rerunning is necessary, prefer the narrowest command that answers the open question

## Output Format

Use this exact structure as the full review report. When reviewer sends follow-up mail, the `Action:` line must match the outbound workflow action.

```markdown
Task: <task_id>
Action: <rework_required | stop_recommended>
From: reviewer <reviewer_session_id>
To: coder <coder_session_id>
Planner: <planner_session_id>
Round: <round>

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
- `Reviewer Decision Flow`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `planner_session_id`: explicit -> mailbox body -> ask
- `reviewer_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `coder_session_id`: explicit -> mailbox body `From` header -> ask
- `browser_tester_session_ref` (optional): explicit -> mailbox/review context -> default `browser-tester`
- `browser_tester_session_id` (optional): explicit actual id -> mailbox/review context -> omit until browser validation is requested
- `round`: explicit -> mailbox body `Round` header -> default `1`
- `workflow_policy` (optional): explicit -> request context -> human-gated defaults
- `special_requirements` (optional fallback): explicit -> request context -> omit
- `checks_already_run` (optional): explicit -> mailbox body -> use for rerun decisions

Important identity clarification:
- `planner_session_id` must come from explicit/context workflow metadata

Default policy when missing:
- `mode = "human_gated"`
- `auto_accept_if_no_must_fix = false`
- `auto_dispatch_next_task = false`
- `ui_manual_confirmation = "auto"`

Execution flow in Agent Deck mode:
1. Produce the full review report in the format above
2. Choose action:
   - `rework_required` if `NEEDS_REVISION`, must-fix exists, or completeness FAIL
   - `browser_check_requested` if code review is acceptable so far but runtime browser evidence is still required
   - `stop_recommended` if no must-fix remains and browser validation is not required or already passed
3. For `rework_required`, send the full review report as mailbox body to coder
4. For `browser_check_requested`, run `browser-test-request`; the browser report will return to the requester session
5. For `stop_recommended`:
   - if `auto_accept_if_no_must_fix=true`, run `review-closeout`
   - else present user decision summary and wait
   - in human-gated mode, request manual UI confirmation when required

Mailbox subject (`rework_required`):
- `rework required: <task_id> r<round>`

Mailbox body rules (`rework_required`):
- use the full review report above as the body
- set `Action: rework_required`
- if `agent_mailbox` is not already bound for this session, bind it first
- first call `agent_deck_ensure_session` with `session_id = <coder_session_id>`
- send it with `mailbox_send`
  - `from_address = agent-deck/<reviewer_session_id>`
  - `to_address = agent-deck/<coder_session_id>`
  - `subject = "rework required: <task_id> r<round>"`
  - `body = <full review report>`
- if the target is non-local and `agent_deck_ensure_session` returned `notify_needed = true`, use `notify_send` for `agent-deck/<coder_session_id>`
- include enough evidence and fix guidance that coder can continue from the mailbox body alone

Mailbox subject (`user_requested_iteration` after user chooses iterate):
- `iteration requested: <task_id> r<round>`

Mailbox body rules (`user_requested_iteration`):
- restate the user decision and the required follow-ups in the body
- keep `Action: user_requested_iteration`
- include enough of the prior review findings that coder can continue without opening external workflow files
- if `agent_mailbox` is not already bound for this session, bind it first
- first call `agent_deck_ensure_session` with `session_id = <coder_session_id>`
- send it with `mailbox_send`
  - `from_address = agent-deck/<reviewer_session_id>`
  - `to_address = agent-deck/<coder_session_id>`
  - `subject = "iteration requested: <task_id> r<round>"`
  - `body = <iteration mailbox body>`
- if the target is non-local and `agent_deck_ensure_session` returned `notify_needed = true`, use `notify_send` for `agent-deck/<coder_session_id>`

User-facing output requirement for `stop_recommended`:
1. `### Review Decision`
2. `### Key Findings Snapshot`
3. `### Residual Risk`
4. `### Verification Summary`
5. `### UI Confirmation Gate`
6. `### Decision Needed`

When `auto_accept_if_no_must_fix=true`, skip decision prompt and state `Auto-accepted by workflow policy`.

Required interaction behavior:
- For `rework_required`, send automatically after the report is ready
- After sending `rework_required` or `user_requested_iteration`, reviewer immediately uses `check-workflow-mail wait=True` when expecting the next workflow message
- For `stop_recommended` with manual decision, wait for explicit user choice
- Preserve `workflow_policy` unchanged in outbound messages
- Preserve `special_requirements` unchanged in outbound messages
- Keep mailbox JSON internal unless user explicitly asks
- Use `mailbox_send` for cross-session reviewer messages

Sender identity rule:
- reviewer-originated actions (`rework_required`, `user_requested_iteration`, `closeout_delivered`) use `from_session_id = reviewer_session_id`
