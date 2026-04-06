---
name: review-code
description: Reviews code changes for logical correctness, design quality, and security. Use after code has been written to validate implementation quality.
---

# Review Code

Review code changes for logical correctness, design quality, and security.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide one of:
1. the mailbox body from `review_requested`
2. the mailbox body from `browser_check_report` plus current review context
3. original task + implementation summary + code changes

## Input Completeness Gate (Required)

Before reviewing quality, verify:
- scope is explicit (uncommitted / commit / branch and target)
- branch plan is explicit (`start_branch`, `integration_branch`, `task_branch`)
- implementation intent is explicit (what change is meant to accomplish)
- behavior/compatibility constraints are explicit (what must not change)
- review focus or risk angles are stated
- verification evidence is present (tests, results, known gaps)

If critical context is missing:
- mark as `NEEDS_REVISION`
- list missing items in `Critical Issues`
- keep evidence factual; do not fabricate assumptions

## Review Discipline

Before enumerating issues, build a short frame:
- intended change
- invariants and existing behavior that must remain stable
- declared non-goals or out-of-scope areas

Use this frame to filter findings.
Promote only findings that are:
- supported by concrete evidence in code, tests, or behavior
- relevant to the intended change, preserved invariants, or material future maintenance risk
- specific enough that the implementer can act on it

Demote or drop findings that are:
- mostly style or taste
- only weakly related to the task
- a speculative future concern without present evidence
- duplicative of a stronger finding

If a concern may be real but evidence is incomplete, prefer:
- `Design Concerns` for architectural caution
- `Verification Questions` for missing proof

Do not inflate the `Critical Issues` section with low-confidence or low-impact commentary.

Default mode is single-reviewer, multi-lens analysis.
Do not automatically launch extra agents or specialist lanes.
Recommend a focused follow-up review only when one risk area is important, evidence is insufficient, and the extra review could change the decision.

Use these thresholds unless overridden by `workflow_policy`:
- `review_round_convergence_check_threshold = 3`
- `review_round_hard_stop_threshold = 5`

When `round >= review_round_convergence_check_threshold`, check for non-convergence:
- the same issue or invariant break reappears after being "fixed"
- issues bounce between related areas (`A -> B -> A`)
- the patch only moves the failure to a nearby symptom (`A -> B -> C`)
- the implementation grows by patch-on-patch edits without making the design simpler

At or above `review_round_convergence_check_threshold`, also check whether coder is solving the wrong problem by preserving extra self-imposed constraints:
- compatibility burdens not required by the task
- abstractions or edge cases that were not actually requested
- local design rules that are making convergence worse instead of improving correctness

If non-convergence is visible:
- widen review scope beyond the latest diff
- inspect the broader implementation, recent rounds, and affected boundaries
- check whether coder introduced extra self-imposed constraints, compatibility burdens, abstractions, or edge-case requirements that were not actually required by the task
- use `Design Concerns` to call out likely design failure, not just the latest local defect
- recommend `code-health-review` or equivalent structural follow-up when a local fix is unlikely to converge
- if repeated rounds appear to be preserving unnecessary self-imposed constraints, say so explicitly and challenge those constraints directly
- if `round >= review_round_hard_stop_threshold` and the work is still not converging, stop iterating with coder and escalate to the user instead of sending another normal rework loop

## What to Review

- logic correctness
- design quality and coupling
- security boundaries
- edge-case handling
- maintainability
- compatibility/regression risk
- verification coverage quality
- convergence across rounds when this is not round `1`

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
- Branch plan continuity: [PASS / FAIL]
- Intent clarity: [PASS / FAIL]
- Behavior/compatibility constraints: [PASS / FAIL]
- Review focus/risk angles: [PASS / FAIL]
- Verification evidence: [PASS / FAIL]
If any FAIL, explain why in `Critical Issues`.

### Intent And Constraints
- Intended change: [summary]
- Must-preserve behavior: [summary]
- Non-goals / out-of-scope: [summary or `None`]

### Recorded Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Stability rule: preserve this branch plan unchanged through closeout unless the user explicitly changes it

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
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `planner_session_id`: explicit -> mailbox body -> ask
- `reviewer_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `coder_session_id`: explicit -> mailbox body `From` header -> ask
- `browser_tester_session_ref` (optional): explicit -> mailbox/review context -> default `browser-tester`
- `browser_tester_session_id` (optional): explicit actual id -> mailbox/review context -> omit until browser validation is requested
- `round`: explicit -> mailbox body `Round` header -> default `1`
- `start_branch`: explicit -> mailbox body -> ask
- `integration_branch`: explicit -> mailbox body -> ask
- `task_branch`: explicit -> mailbox body -> ask
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
- `review_round_convergence_check_threshold = 3`
- `review_round_hard_stop_threshold = 5`

Execution flow in Agent Deck mode:
1. Produce the full review report in the format above
   - preserve the recorded branch plan from `review_requested` unchanged in the review report
2. Choose action:
   - `rework_required` if `NEEDS_REVISION`, must-fix exists, or completeness FAIL, unless the non-convergence stop rule below applies
   - `browser_check_requested` if code review is acceptable so far but runtime browser evidence is still required
   - `stop_recommended` if no must-fix remains and browser validation is not required or already passed
   - if `round >= review_round_hard_stop_threshold` and similar issues are still recurring or progress is clearly non-converging, do not send another routine `rework_required`; present the situation to the user and wait for a decision
3. For `rework_required`, send the full review report as mailbox body to coder
4. For `browser_check_requested`, run `browser-test-request`; the browser report will return to the requester session
5. For `stop_recommended`:
   - if `auto_accept_if_no_must_fix=true`, the final no-must-fix review report should proceed to `review-closeout`
   - normally, the agent that currently holds the final review report should run `review-closeout`
   - if the same final no-must-fix report is delivered to coder in unattended flow, coder may run `review-closeout` from that report instead of treating it as another rework round
   - else present user decision summary and wait for explicit acceptance or iteration decision
   - after explicit acceptance in human-gated flow, run `review-closeout`
   - in human-gated mode, request manual UI confirmation when required before acceptance and closeout

Mailbox subject (`rework_required`):
- `rework required: <task_id> r<round>`

Mailbox body rules (`rework_required`):
- use the full review report above as the body
- set `Action: rework_required`
- use `agent_mailbox`
- first call `agent_deck_ensure_session` with `session_id = <coder_session_id>`
- send it with `mailbox_send`
  - `from_address = agent-deck/<reviewer_session_id>`
  - `to_address = agent-deck/<coder_session_id>`
  - `subject = "rework required: <task_id> r<round>"`
  - `body = <full review report>`
- include enough evidence and fix guidance that coder can continue from the mailbox body alone

Mailbox subject (`user_requested_iteration` after user chooses iterate):
- `iteration requested: <task_id> r<round>`

Mailbox body rules (`user_requested_iteration`):
- restate the user decision and the required follow-ups in the body
- keep `Action: user_requested_iteration`
- include enough of the prior review findings that coder can continue without opening external workflow files
- use `agent_mailbox`
- first call `agent_deck_ensure_session` with `session_id = <coder_session_id>`
- send it with `mailbox_send`
  - `from_address = agent-deck/<reviewer_session_id>`
  - `to_address = agent-deck/<coder_session_id>`
  - `subject = "iteration requested: <task_id> r<round>"`
  - `body = <iteration mailbox body>`

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
- For `stop_recommended` with manual decision, wait for explicit user choice; if accepted, run `review-closeout`; if iteration is requested, send `user_requested_iteration`
- In unattended flow, any accepted final no-must-fix report that lands with reviewer or coder must be treated as `review-closeout` input, not as another rework cycle
- Preserve `workflow_policy` unchanged in outbound messages
- Preserve `special_requirements` unchanged in outbound messages
- Keep mailbox JSON internal unless user explicitly asks
- Use `mailbox_send` for normal cross-session reviewer messages
- Do not naturally end after writing the review report; if this action requires `rework_required`, `user_requested_iteration`, or `review-closeout`, complete that workflow step before ending the turn

Sender identity rule:
- reviewer-originated actions (`rework_required`, `user_requested_iteration`) use `from_session_id = reviewer_session_id`
- `closeout_delivered` uses the session id of the agent that actually executes `review-closeout`; preserve `reviewer_session_id` in the closeout body as the source of the accepted review
