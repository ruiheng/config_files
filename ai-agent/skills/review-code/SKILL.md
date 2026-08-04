---
name: review-code
description: Review code changes for correctness and security.
---

# Review Code

Review code changes for logical correctness, design quality, and security.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Input

Provide one of:
1. the message body from `review_requested`
2. the message body from `browser_check_report` plus matching review context
3. original task + code changes, with optional author intent or notes

## Input Completeness Gate (Required)

Before reviewing quality, verify:
- scope is explicit (uncommitted / commit / branch and target)
- task carries complete Workspace Handoff and Branch Plan (`start_branch`, `integration_branch`, `task_branch`)
- `integration_final` carries branch target and base
- implementation intent is explicit (what change is meant to accomplish)
- behavior/compatibility constraints are explicit (what must not change)
- verification evidence is present (tests, results, known gaps)
- `integration_final` / `standalone` carry neither Handoff nor task Branch Plan

If critical context is missing:
- mark as `NEEDS_REVISION`
- list missing items in `Critical Issues`
- keep evidence factual; do not fabricate assumptions

## Review Discipline

Treat the original task and explicit behavior/compatibility constraints as authoritative review contracts.
Treat `Author Intent`, `Optional Review Focus`, and `Author-Noted Issues or Limitations` as author context:
- non-authoritative and non-exhaustive
- never a substitute for inspecting the full review scope
- never a reason to skip independent risk discovery
- optional focus may set emphasis but must not constrain the review; its absence is not missing context

Before quality review, compare the full change scope with the original task and recorded User Decisions. If a material change widens the task, changes an explicit constraint, or adds unrelated behavior without a recorded user decision:
- ask the user immediately with the concrete change and impact
- do not send `rework_required`, `stop_recommended`, or closeout until the user replies
- add the reply to the task's user-decision record and carry it in `### User Decision Summary`

Treat a recorded User Decision as task-specific scope authority, not a general license for adjacent changes. If the user rejects the change, require its removal or exclusion through the normal rework path.

Before enumerating issues, build a short frame:
- intended change
- invariants and existing behavior that must remain stable
- declared non-goals or out-of-scope areas

Before listing findings, assess whether the overall approach is coherent and converging. When multiple defects share a cause or fixes only move symptoms, report the root design issue instead of another set of local fixes.

Use this frame to filter findings.
Promote only findings that are:
- supported by concrete evidence in code, tests, or behavior
- relevant to the intended change, preserved invariants, or material future maintenance risk
- specific enough that the implementer can act on it

Treat a design issue as must-fix when it explains multiple concrete defects or makes local fixes unlikely to converge.

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

## Review Focus

Correctness, design, security, regressions, verification, and—after round `1`—convergence.

## UI-Change Detection and Confirmation Policy

Detect likely user-facing UI changes. Human confirmation is opt-in by workflow policy, not the default.

Heuristics:
- frontend/template/style files changed (`*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.html`, `*.css`, `*.scss`, `*.less`)
- UI routes/pages/components changed
- design token/theme/layout/visible text changed
- browser-tool validation required

Policy rules:
- default: record detected UI impact; do not require human confirmation before closeout
- override via `workflow_policy.ui_manual_confirmation`:
  - `skip` (default)
  - `required`
  - `auto`
- use `required` only when the user or workflow policy explicitly wants a human UI gate
- `auto` is an explicit heuristic mode, not the default

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

Use this structure as the full review report. When reviewer sends follow-up message, the `Action:` line must match the outbound workflow action.
Omit `### User Decision Summary` when no user scope decision exists.

```markdown
Task: <task_id>
Action: <rework_required | stop_recommended>
From: reviewer <reviewer_session_id>
To: <requester_role> <requester_session_id>
Review lane: <task | integration_final | standalone>
Round: <round>

### Summary
[APPROVED / NEEDS_REVISION]: Brief rationale (1-2 sentences)

### Request Completeness Check
- Scope clarity: [PASS / FAIL]
- Branch plan / Handoff: [PASS / FAIL / N/A]
- Intent clarity: [PASS / FAIL]
- Behavior/compatibility constraints: [PASS / FAIL]
- Verification evidence: [PASS / FAIL]
If any FAIL, explain why in `Critical Issues`.

### Intent And Constraints
- Intended change: [summary]
- Must-preserve behavior: [summary]
- Non-goals / out-of-scope: [summary or `None`]

### User Decision Summary
[all user scope decisions known at this round; the final task report summarizes the complete list for planner]

### Critical Issues
Must fix before merge:
- [ ] **[CATEGORY]**: Description | Suggestion: How to fix

### Design Concerns
Architecture/decision questions:
- **[Concern]**: Description | Suggestion: Alternative approach

### Minor Suggestions
Optional improvements:
- [ ] Description

### Security Check
- Injection risks: [PASS / FAIL / UNKNOWN] - [brief basis]
- Unsafe data exposure: [PASS / FAIL / UNKNOWN] - [brief basis]
- Input validation: [PASS / FAIL / UNKNOWN] - [brief basis]

### Verification Questions
For the implementer/author:
- [Q1] Question

```

When UI impact is detected or a human UI gate applies, append:

```markdown
### UI Manual Confirmation Package
- UI impact: [detected]
- Changed UI surfaces: [routes/pages/components]
- Manual check steps (human-run): [short checklist]
- Expected visible outcomes: [what user should see]
- Notes: [optional]
```

For `task` / `integration_final`, insert after `To`:

```markdown
Planner: <planner_session_id>
Planner workspace: <planner_workspace>
```

For task, insert this after `Intent And Constraints`:

```markdown
### Recorded Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Stability rule: preserve this branch plan unchanged through closeout unless the user explicitly changes it
```

For task, append its Handoff unchanged after `Recorded Branch Plan`:

```markdown
### Workspace Handoff
- Worker workspace: [worker_workspace]
- Task dir: [task_dir]
- Workspace lifecycle: [shared; cleanup=none | temporary; cleanup=planner]
```

For `integration_final` / `standalone`, omit Workspace Handoff and task Branch Plan.

For `integration_final`, insert after `Intent And Constraints`:

```markdown
### Final Review Scope
- Integration branch: [scope target]
- Review base: [scope base]
```

## Agent Deck Mode

Use the `agent-deck-workflow` skill for shared protocol:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
Review continuity:
- new/full `review_requested`: body starts a review; never use saved context
- confirmed delta: `round >1` and task/requester/reviewer/lane match current review. Body owns routing; use matching context only for omitted review frame
- unconfirmed delta: require full body, then treat it as new
- `browser_check_report`: match `Browser Check` to the sent check; its review frame owns requester routing. If context is lost, recover that check from history, then rebuild from full request + matching deltas.
- Miss/ambiguity: defer; require full request; never infer frame from report.

For `review_requested`, routing fields (`review_lane`, planner/requester, Branch Plan, Handoff) resolve `explicit -> body -> gate/default`; never saved context.
For a confirmed delta, review frame (scope, original task, unchanged intent/constraints, policy, requirements, checks) resolves `explicit -> body -> matching context`.
Run the completeness gate on resolved context, not the delta alone.

For `browser_check_report`, `explicit -> matching/recovered frame` owns all review routing/frame. Body supplies only envelope identity and browser evidence; never default lane or derive review context from it.

- `task_id`: explicit -> message body -> ask
- `browser_check_id` (browser report): required header -> matching sent check; never infer from task/round
- `reviewer_session_id`: explicit -> message body `To` header -> bound Waypost sender context -> ask
- `browser_tester_session_id` (optional): explicit actual id -> message/review context -> omit
- `browser_tester_session_ref` (optional): explicit -> message/review context -> default `browser-tester`
- `browser_tester_workspace` (optional): explicit -> message/review context -> current workspace
- `round`: explicit -> message body `Round` header -> default `1`

For non-browser inputs:
- `review_lane`: explicit -> message body -> `task` for an active delegated task -> `standalone`
- `planner_session_id`: `task` / `integration_final` -> explicit -> message body -> ask; `standalone` -> omit
- `planner_workspace`: `task` / `integration_final` -> explicit -> message body `Planner workspace` -> ask; `standalone` -> omit
- `requester_role`: explicit -> message body `From` -> default `coder`
- `requester_session_id`: explicit -> message body `From` -> ask
- `setup_contact_workspace` (browser): task -> Worker workspace; `integration_final` -> Planner workspace; standalone -> current workspace
- `workspace_handoff`: task -> explicit/message body complete -> preserve; missing/partial -> completeness FAIL; `integration_final` / `standalone` -> omit
- `start_branch`, `integration_branch`, `task_branch` (task only): explicit -> message body -> ask; otherwise omit
- `integration_branch`, `review_base` (`integration_final`): explicit -> message Scope target/base -> matching delta context -> ask; otherwise omit
- `workflow_policy` (optional): explicit -> message body -> matching delta context -> unattended defaults
- `special_requirements` (optional fallback): explicit -> message body -> matching delta context -> omit
- `user_decisions` (optional): explicit -> message body -> matching delta context -> omit
- `checks_already_run` (optional): explicit -> message body -> matching delta context -> use for rerun decisions

Task branch-plan guard:
- `integration_branch` must be the non-task landing branch; if it looks like `task/*`, treat branch plan continuity as FAIL and ask for the real integration branch before approval/closeout

Important identity clarification:
- `task` / `integration_final` require planner metadata; `standalone` requires only requester identity

Default policy when missing:
- `mode = "unattended"`
- `auto_accept_if_no_must_fix = true`
- `ui_manual_confirmation = "skip"`
- `review_round_convergence_check_threshold = 3`
- `review_round_hard_stop_threshold = 5`

Execution flow in Agent Deck mode:
1. Produce the full review report in the format above
   - for task, preserve supplied Branch Plan and Workspace Handoff unchanged
   - for `integration_final`, preserve Final Review Scope in every report
   - preserve known User Decisions; the final task `stop_recommended` report summarizes all of them under `### User Decision Summary`
2. Choose action:
   - `rework_required` if `NEEDS_REVISION`, must-fix exists, completeness FAIL, or a browser report says `Code changed: yes`, unless the non-convergence stop rule below applies
   - `browser_check_requested` if code review is acceptable so far but runtime browser evidence is still required
   - `stop_recommended` if no must-fix remains and browser validation is not required or already passed
   - if `round >= review_round_hard_stop_threshold` and similar issues are still recurring or progress is clearly non-converging, do not send another routine `rework_required`; present the situation to the user, then apply the Manual-decision rule
3. For `rework_required`, send the full review report back to the requester session from `review_requested`
   - requester may be `coder` or `planner`
4. For `browser_check_requested`, generate one opaque `browser_check_id`, pass it to `browser-test-request` with this reviewer as report requester, and retain it with the review frame; pass original `requester_role` / `requester_session_id` and `setup_contact_workspace` as Setup Contact; on `browser_check_report`, resume with its evidence and matched review frame
   - `Code changed: yes` is a must-fix delivery boundary: carry its branch/commit/files in `rework_required`, not acceptance. Requester must own, commit/verify, and resubmit the changed scope; do not closeout this round
5. For `stop_recommended`:
   - never accept or close out while a material scope decision is awaiting the user
   - for `integration_final` / `standalone`, after automatic or explicit acceptance, send the full `stop_recommended` report to requester; do not run `review-closeout`
   - for task with `auto_accept_if_no_must_fix=true`, proceed to `review-closeout`
   - if the same final no-must-fix task-lane report is delivered to requester in unattended flow, requester may run `review-closeout` from that report instead of treating it as another rework round
   - only when `auto_accept_if_no_must_fix=false`, present user decision summary, then apply the Manual-decision rule
   - after explicit acceptance in human-gated flow, run `review-closeout` for task, or send the non-task result to requester
   - request human UI confirmation before acceptance/closeout only when `ui_manual_confirmation=required`, or when `ui_manual_confirmation=auto` and explicit policy wants heuristic UI gating

Waypost Message subject (`rework_required`):
- `rework required: <task_id> r<round>`

Waypost Message body rules (`rework_required`):
- use the full review report above as the body
- set `Action: rework_required`
- use `waypost`
- first call `agent_deck_require_session` with:
  - `session_id = <requester_session_id>`
  - `workdir = <current workspace>`
- send it with `waypost_send`
  - `from_address = agent-deck/<reviewer_session_id>`
  - `to_address = agent-deck/<requester_session_id>`
  - `subject = "rework required: <task_id> r<round>"`
  - `body = <full review report>`
- include enough evidence and fix guidance that the requester can continue from the message body alone

Waypost Message (`stop_recommended`, accepted non-task):
- use only for `integration_final` / `standalone` after automatic or explicit acceptance
- retain `Action: stop_recommended` and use the full review report as body
- use the `rework_required` target and send shape with subject `review complete: <task_id> r<round>`
- ACK a claimed review input only after this send succeeds

Waypost Message subject (`user_requested_iteration` after user chooses iterate):
- `iteration requested: <task_id> r<round>`

Waypost Message body rules (`user_requested_iteration`):
- restate the user decision and the required follow-ups in the body
- keep `Action: user_requested_iteration`
- include enough of the prior review findings that coder can continue without opening external workflow files
- use `waypost`
- first call `agent_deck_require_session` with:
  - `session_id = <requester_session_id>`
  - `workdir = <current workspace>`
- send it with `waypost_send`
  - `from_address = agent-deck/<reviewer_session_id>`
  - `to_address = agent-deck/<requester_session_id>`
  - `subject = "iteration requested: <task_id> r<round>"`
  - `body = <iteration message body>`

For a user-facing `stop_recommended`, include Review Decision, Key Findings Snapshot, Residual Risk, and Verification Summary. Add UI Confirmation Gate only when applicable; add Decision Needed only for a manual choice.

When `auto_accept_if_no_must_fix=true`, state `Auto-accepted by workflow policy`; do not ask for a decision.

Manual-decision rule: after presenting a decision to the user, end this turn. Do nothing until the user's next instruction.

Required interaction behavior:
- For `rework_required`, send automatically after the report is ready
- For accepted `integration_final` / `standalone` `stop_recommended`, send the full report to requester automatically
- For `stop_recommended` with manual decision, do that only when `auto_accept_if_no_must_fix=false`; after the user's decision, close out task, send accepted non-task result, or send `user_requested_iteration`
- In unattended flow, accepted no-must-fix task-lane reports that land with reviewer or requester must be treated as `review-closeout` input, not as another rework cycle
- In unattended flow, accepted `integration_final` / `standalone` reports return directly to requester; do not route them into `review-closeout`
- Preserve `workflow_policy` unchanged in outbound messages
- Preserve `special_requirements` unchanged in outbound messages
- Keep message JSON internal unless user explicitly asks
- Do not naturally end after writing the review report; if this action requires `rework_required`, accepted non-task `stop_recommended`, `user_requested_iteration`, or `review-closeout`, complete that workflow step before ending the turn

Sender identity rule:
- reviewer-originated actions (`rework_required`, `stop_recommended`, `user_requested_iteration`) use `from_session_id = reviewer_session_id`
- `closeout_delivered` uses the session id of the agent that executes `review-closeout`; preserve `reviewer_session_id` as the source of the accepted review
