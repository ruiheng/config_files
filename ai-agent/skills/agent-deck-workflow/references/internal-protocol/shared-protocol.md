# Shared Workflow Protocol

This document is the shared contract for all workflow skills.
It defines transport, identity, branch-plan, and mailbox semantics.
Role-specific execution behavior belongs in the action skill for that role.

Core transport rule:
- `agent-mailbox` carries the real workflow message
- `agent-deck` is used to resolve, create, or start target sessions and to nudge them to check mail
- use the `agent_mailbox` MCP tools as the default transport interface
- use `check-agent-mail` for receiver-side wake handling

Default role/session rule:
- use one distinct session per role
- treat planner/reviewer same-session operation as an explicit exception, not an implied default

## Terminology

- `task_id`: stable task identifier (`YYYYMMDD-HHMM-<slug>`)
- `*_session_id`: Agent Deck session UUID
- `*_session_ref`: human-friendly session reference (`title` or `id`)
- `inbox_address`: `agent-deck/<agent-deck-session-id>`
- `start_branch`: planner's current git branch when delegation begins
- `integration_branch`: branch where accepted work lands; this is task-local mainline and is not assumed to be `main`/`master`
- `task_branch`: branch where coder commits
- `workflow_policy`: optional per-task automation override
- `special_requirements`: optional free-form fallback requirements carried unchanged across the same `task_id`

## Scope

- workflow shape: one long-lived `planner`, per-task `coder` + `reviewer` + `architect`, plus optional long-lived `browser-tester`
- same-session multi-role mapping is allowed only when workflow context says so explicitly
- runtime shape: single shared workspace
- governance: human-led unless `workflow_policy` overrides specific gates
- delegated coder commits are workflow-authorized for the recorded task and do not require per-commit user approval

## Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:
1. explicit `task_id` or `planner_session_id`
2. inbound mailbox body already carries workflow metadata
3. user explicitly asks for agent-deck workflow

Session binding rule:
- use mailbox tools directly
- bind only when mailbox context is actually missing

## Context Resolution Priority

Use this priority chain for each field:
`explicit input -> parsed mailbox body / workflow context -> deterministic default -> ask one short clarification question`

Session identity nuance:
- `planner_session_id` must come from explicit or existing workflow context
- before identity comparisons, resolve all session refs/titles to UUIDs
- use `*_session_ref` for planned worker titles before a real session exists
- only write `*_session_id` when the real session id is known

## Role vs Session Identity

- default mapping is one distinct session per active role: `planner_session_id`, `coder_session_id`, `reviewer_session_id`, and `architect_session_id` should differ unless workflow context explicitly assigns an exception
- a session may hold multiple roles for the same task only when workflow context explicitly assigns that mapping
- `*_session_id` fields identify role ownership; tool/provider choice is separate
- saying "reviewer uses codex" means "create or resume a reviewer session with a Codex command", not "the current Codex session self-assigns reviewer role"
- even when planner and reviewer use the same provider/model/command, keep a distinct reviewer session unless same-session mapping is explicit
- when `from_session_id == to_session_id`, treat it as explicit local continuation already established by workflow context
- skip cross-session wakeup only when target session is the current session

## Branch Roles and Resolution

- resolve branch roles when planner creates the delegate message, not during closeout
- `integration_branch` is the task-local landing line and may be any real target branch
- `task_branch` is where coder commits; in the normal merge-based flow it must differ from `integration_branch`

Deterministic default order:
1. preserve explicit or existing branch values
2. detect `start_branch` from planner's current branch when delegation begins
3. if `start_branch` is the intended landing line, set `integration_branch = start_branch` and default `task_branch = task/<task_id>`
4. if `start_branch` already is the intended topic branch, reuse it as `task_branch` and resolve `integration_branch` from explicit user intent or a high-confidence tracked/base branch

Rules:
- never assume `master` or `main` unless the task really lands there
- once the delegate message records `start_branch`, `integration_branch`, and `task_branch`, later roles should treat that branch plan as immutable task context unless the user explicitly changes it
- planner should pass explicit `--task-branch` and `--integration-branch` to `planner-closeout-batch.sh` whenever that branch plan is known

## Mailbox Transport

Preferred transport interface:
- `mailbox_bind`
- `mailbox_status`
- `mailbox_send`
- `mailbox_recv`
- `mailbox_ack`
- `mailbox_release`
- `mailbox_defer`
- `mailbox_fail`
- `agent_deck_resolve_session`
- `agent_deck_ensure_session`

Transport rules:
- use `mailbox_send` for normal cross-session workflow delivery
- use `mailbox_recv` to claim mail
- use lifecycle tools for `ack` / `release` / `defer` / `fail`
- use `mailbox_bind` only for custom addresses or recovery when mailbox context is missing
- keep the full workflow body in the MCP `body` string instead of generated Markdown handoff files
- for agent-deck-managed targets, use `agent_deck_ensure_session` to resolve/create/start the target session

Worker wake rule:
- use `agent_deck_ensure_session` to resolve/create/start agent-deck-managed targets
- after `mailbox_send`, the normal non-local nudge should already be handled
- a newly created or newly started target should run `mailbox_wait` for its first mail before running `check-agent-mail`
- do not rely on long-running agent-mail polling processes for delivery

Inbox rule:
- derive inbox address as `agent-deck/<agent-deck-session-id>`
- no separate registration step is needed
- if multiple lifecycle operations are needed, run them one at a time

## Mailbox Message Contract

Every workflow message has two parts:
- `subject`: one-line summary for quick triage
- `body`: full Markdown task content and the main source of truth

Recommended body header:

```markdown
Task: <task_id>
Action: <action_name>
From: <role> <from_session_id>
To: <role> <to_session_id>
Planner: <planner_session_id>
Round: <round_or_final>
```

Required action names:
- `execute_delegate_task`
- `review_requested`
- `tech_design_review_requested`
- `tech_design_review_report`
- `browser_check_requested`
- `browser_check_report`
- `rework_required`
- `user_requested_iteration`
- `closeout_delivered`

Sender invariants:
- `execute_delegate_task`: sender is planner
- `review_requested`: sender is coder
- `tech_design_review_requested`: sender is the requesting workflow session
- `tech_design_review_report`: sender is architect
- `browser_check_requested`: sender is the requesting workflow session
- `browser_check_report`: sender is browser-tester
- `rework_required`, `user_requested_iteration`, `closeout_delivered`: sender is reviewer
- never default sender to planner for non-planner actions

Action contract:
- `execute_delegate_task`: planner starts delegated implementation
- `review_requested`: coder asks reviewer to review a committed delivery and includes coder-run verification evidence
- `tech_design_review_requested`: requester asks architect to review committed design docs on a branch
- `tech_design_review_report`: architect returns advisory design feedback to the requester
- `browser_check_requested`: requester asks browser-tester to validate a browser flow; request may explicitly allow display-adjacent edits
- `browser_check_report`: browser-tester returns PASS / FAIL / UNKNOWN evidence to the requester
- `rework_required`: reviewer blocks and sends must-fix follow-up to coder
- `user_requested_iteration`: reviewer forwards the user's iteration decision to coder
- `closeout_delivered`: reviewer sends accepted closeout to planner for closeout and follow-up planning

Review disagreement policy:
- reviewer findings are advisory, not automatically binding
- coder must evaluate reviewer findings critically and adopt only technically justified changes
- when coder disagrees, the next `review_requested` body should state the disagreement and rationale clearly
- if coder and reviewer cannot converge, either role may stop and ask the user for a decision

Tech-design disagreement policy:
- architect feedback is advisory, not a user decision
- requester must evaluate architect feedback critically and adopt only technically justified changes
- either side may stop and ask the user for a decision when the disagreement becomes subjective, strategic, or stuck

Review-request continuity:
- first `review_requested` to a reviewer session carries the full task and review context
- later `review_requested` messages to the same reviewer session carry only the delta since the previous round
- if the reviewer session changes, resend the full review context
- `review_requested` should carry a concise record of coder-run lint, build/link, compile/type-check, test, and other verification results

Tech-design review continuity:
- first `tech_design_review_requested` to an architect session carries the full design context
- later messages to that same architect session carry only the delta
- if the architect session changes, resend the full design context
- `tech_design_review_requested` is based on the latest committed design docs on a branch, not uncommitted notes
- default tech-design branch is `tech-design/<task_id>`

User-facing responses should provide readable decisions, not raw mailbox JSON.

## Delivery Order Contract

Use `mailbox_send` for the normal mailbox delivery path.

Expected behavior:
1. use `agent_deck_ensure_session` when a target session must be resolved, created, or started
2. queue the mailbox body with `mailbox_send`

## Receiver Contract

When a workflow session is woken:
1. run `mailbox_recv`
2. treat the returned `body` as the primary task input
3. parse the `Action:` header and immediately execute that workflow stage
4. only read supplemental files when the body explicitly requires them
5. `mailbox_ack` only after the message has been successfully incorporated into local working state
6. use `mailbox_release` / `mailbox_defer` / `mailbox_fail` instead of silently dropping leased work
7. keep mailbox lifecycle steps serialized

Apply the message action before `ack`.

Action execution defaults after `recv`:
- `execute_delegate_task`: start delegated implementation immediately
- `review_requested`: start review immediately
- `tech_design_review_requested`: start tech-design review immediately
- `tech_design_review_report`: requester resumes design decision-making immediately
- `browser_check_requested`: start browser validation immediately
- `browser_check_report`: requester resumes decision-making immediately
- `rework_required`: continue coder iteration immediately
- `user_requested_iteration`: continue coder iteration immediately
- `closeout_delivered`: start planner closeout interpretation immediately
- only pause for user input when the message body explicitly requires a user decision

Idle behavior:
- do not rely on long-running wait loops to preserve workflow continuity
- use `check-agent-mail` when a wakeup nudge arrives or when a human explicitly asks for a mailbox check

## Error Handling and Diagnostics

If workflow send or worker start fails, report concise stderr summary and run these checks:
1. is sender/target session reachable (`agent_deck_resolve_session`)?
2. is the command running in the expected workflow session context?
3. did `mailbox_send` / `mailbox_recv` / lifecycle tools return success?

If sandbox-external execution triggers an approval prompt, explain it as a host-shell permission requirement.
If a target missed mailbox work, retry the nudge path instead of resending mailbox content.

If closeout cleanup fails, include:
1. blocked reason (`provider_guard_blocked`, `manual_close_required`, `worker_cap_exceeded`)
2. session archive path (`.agent-artifacts/<task_id>/session-archive-<task_id>.json`)
3. exact manual action to unblock

Planner closeout execution rule:
1. required actions (`merge`, `progress update`) are hard requirements
2. optional actions (`notify`, `next-task dispatch`, hygiene cleanup) are best-effort
3. optional-action failures must not roll back or block required closeout completion
4. when `--integration-branch` is provided, `planner-closeout-batch.sh` is responsible for switching to that branch before merge if the worktree is in a safe state
5. planner should not run git state-changing commands in parallel with `planner-closeout-batch.sh`
6. `planner-closeout-batch.sh` should run closeout health gate by default; use `--skip-health-gate` only for explicit troubleshooting

Planner post-acceptance interpretation rule:
1. `closeout_delivered` means accepted review loop complete; normal closeout should proceed
2. planner must inspect the closeout mailbox body before finalizing follow-up planning
3. non-blocking accepted findings should be evaluated as inputs to progress/todo updates or next-task planning
4. planner should decide whether each residual item needs explicit tracking, a queued next task/subtask, or no extra tracking
5. planner should not reopen the accepted task by default unless the closeout body clearly shows a must-fix issue was accepted by mistake or new contradictory evidence appears

## Execution Environment

Use the `agent_mailbox` MCP tools as the default workflow transport surface.
When shell fallback is unavoidable, run `agent-deck` and `agent-mailbox` commands in host shell.
When a workflow turn needs multiple lifecycle steps, execute them sequentially, never in parallel.
Read-only observation commands may run in parallel when safe.
When workflow commands create sessions via `--cmd`, use full commands instead of bare provider names.

Recommended commands unless the user explicitly supplied another full command:
- Claude: `claude --model sonnet --permission-mode acceptEdits`
- Codex: `codex --model gpt-5.4 --ask-for-approval on-request`
- Gemini: `gemini --model gemini-2.5-pro`

## Task Metadata Convention

Use stable naming:
- coder session: `coder-<task_id>`
- reviewer session: `reviewer-<task_id>`
- architect session: `architect-<task_id>`
- browser-tester session: `browser-tester`
- inbox address: `agent-deck/<agent-deck-session-id>`
- default dedicated task branch: `task/<task_id>`
- default dedicated tech-design branch: `tech-design/<task_id>`
- default integration branch: planner's current branch at delegate creation when that branch is the intended landing line
- existing topic branch reuse is allowed when planner determines the current branch already is the correct `task_branch`
- `.agent-artifacts/` is for non-message supplemental material only
- `coder_session_ref` / `reviewer_session_ref` may be planned before creation; resolve them to real `*_session_id` values before mailbox addressing

## Shared Lifecycle Summary

1. planner sends `execute_delegate_task`
2. coder implements on recorded `task_branch`, commits, and sends `review_requested`
3. reviewer chooses one of: `rework_required`, `browser_check_requested`, or accepted closeout path
4. browser-tester, when used, returns one `browser_check_report` to the requester
5. architect lane, when used, exchanges `tech_design_review_requested` and `tech_design_review_report`
6. accepted review becomes `closeout_delivered` to planner
7. planner runs closeout, merges recorded `task_branch` into recorded `integration_branch`, updates progress, and decides residual follow-up tracking

## Skill Ownership Map

- planner-only: `delegate-task`, `scripts/planner-closeout-batch.sh`
- coder-only: `review-request`
- reviewer-only: `review-code`, `review-closeout`
- requester-side dispatch: `tech-design-review-request`, `browser-test-request`
- architect worker: `tech-design-review`
- browser-tester worker: `browser-test`

## Operating Rules

- keep real workflow content in mailbox body
- keep delivery driven by post-send nudges, not long-running wait loops
- keep human confirmation gates unless `workflow_policy` overrides them
- treat accepted review residuals as planning input rather than silently discarding them
- resolve and record branch plan at delegate start, then reuse it consistently through closeout
- let `planner-closeout-batch.sh` own integration-branch switching when `--integration-branch` is supplied
- run planner required closeout actions via `scripts/planner-closeout-batch.sh`
- finish required closeout actions even when optional notify or dispatch steps fail
