---
name: agent-deck-workflow
description: Human-led planner/executor/reviewer workflow protocol with agent-mailbox as the authoritative message layer and agent-deck used only for session wakeups.
---

# Agent Deck Workflow

Use this skill as the single source of truth for the three-role workflow:
`planner` (long-lived), `executor` (per-task), `reviewer` (per-task).

Core transport rule:
- `agent-mailbox` carries the real workflow message
- `agent-deck` only wakes the target session so it can receive mail

Default role/session rule:
- use one distinct session per role
- treat planner/reviewer same-session operation as an explicit exception, not an implied default

This workflow does not require loading the official `agent-deck` skill by default.
The cloned official `agent-deck` skill is a local reference library only.

## Terminology

- `task_id`: stable task identifier (`YYYYMMDD-HHMM-<slug>`)
- `*_session_id`: Agent Deck session UUID (resolve with `agent-deck session show <session_id_or_ref> --json | jq -r '.id'`)
- `*_session_ref`: human-friendly session reference (`title` or `id`)
- `inbox_address`: mailbox endpoint address for one workflow session: `workflow/session/<session_id>`
- `start_branch`: planner's current git branch when `delegate-task` begins
- `integration_branch`: branch where accepted work must land at closeout; this is the task-local mainline and is not assumed to be `main`/`master`
- `task_branch`: executor working branch; may be a dedicated `task/<task_id>` branch or a reused existing topic branch
- `workflow_policy`: optional per-task automation override; absent means human-gated defaults
- `special_requirements`: optional free-form fallback requirements from user/planner; carry unchanged across all roles for the same `task_id`

## Scope

- Workflow shape: one long-lived `planner`, per-task `executor` + `reviewer`
- Default session mapping: planner, executor, and reviewer are separate sessions
- Same-session planner+reviewer is allowed only when explicitly assigned by workflow context
- Runtime shape: single shared workspace
- Governance: human-led; user confirmation gates remain required at stop/closeout points unless policy override is present
- Git approval exception: in delegated executor flow, task-scoped executor commits are allowed without per-commit user approval

## Shared Protocol (For All Workflow Skills)

### Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:
1. explicit `task_id` or `planner_session_id`
2. inbound mailbox body already carries workflow metadata
3. user explicitly asks for agent-deck workflow

`agent-deck session current --json` is best-effort context only and must run in host shell.
If it fails, continue with explicit/context metadata.

### Context Resolution Priority

Use this priority chain for each field:
`explicit input -> parsed mailbox body / workflow context -> deterministic default -> ask one short clarification question`

Session identity nuance:
- `planner_session_id` must come from explicit/context workflow metadata
- `current_session_id` is used for sender identity verification and role safety checks
- before identity comparisons, resolve all session refs/titles to UUIDs:
  - explicit refs: `agent-deck session show <ref> --json | jq -r '.id'`
  - current session: `agent-deck session current --json | jq -r '.id'`
- exception (`delegate-task` only): planner sender legitimately equals current session, so `planner_session_id` may start from detected `current_session_id`
- in all other skills, `current_session_id` is not a replacement source for `planner_session_id`

### Role vs Session Identity

- Default mapping is one distinct session per role: `planner_session_id`, `executor_session_id`, and `reviewer_session_id` should differ unless workflow context explicitly assigns an exception
- A session may hold multiple roles for the same task only when workflow context explicitly assigns that multi-role mapping
- `*_session_id` fields identify which session currently holds each role mapping
- Tool/provider choice is separate from session identity
- Saying "reviewer uses codex" means "the reviewer session should be created or resumed with a Codex command", not "the current Codex planner/executor session should self-assign reviewer role"
- Even when planner and reviewer use the same provider/model/command, keep a distinct reviewer session unless same-session reviewer assignment is explicitly stated in workflow context
- When `from_session_id == to_session_id`, this is an explicit local same-session continuation already established by workflow context, not something inferred from matching tool names
- Skip cross-session wakeup only when the target session is the current session; otherwise wake the target session after mail is queued

### Branch Roles and Resolution

- Resolve branch roles when planner creates the delegate message, not during closeout
- `integration_branch` is the branch that accepted work merges into. It is the task-local mainline and may be `develop`, `release/*`, another feature branch, or anything else the task actually targets
- `task_branch` is the branch where executor commits. In the normal merge-based flow it must differ from `integration_branch`
- Deterministic default order:
  1. preserve explicit/context branch values when already provided
  2. detect `start_branch` from planner's current branch when `delegate-task` begins
  3. if `start_branch` is the intended landing line for this delegated change, set `integration_branch = start_branch` and default `task_branch = task/<task_id>`
  4. if `start_branch` is already the intended topic branch for this delegated change, reuse it as `task_branch` and resolve `integration_branch` from explicit user intent or a high-confidence tracked/base branch; if confidence is low, ask one short clarification instead of guessing
- Never assume `master` or `main` unless the task's actual landing branch resolves there
- Once the delegate message records `start_branch`, `integration_branch`, and `task_branch`, later roles should treat that branch plan as immutable task context unless user explicitly changes it
- Planner should pass explicit `--task-branch` and `--integration-branch` to `planner-closeout-batch.sh` whenever that branch plan is known

### Mailbox Transport

Authoritative transport:
- send workflow content with `agent-mailbox send`
- receive workflow content with `agent-mailbox recv`
- handle delivery lifecycle with `ack`, `release`, `defer`, or `fail`

Send-body rule:
- prefer `agent-mailbox send --body-file -` and feed the body through stdin
- do not create a temporary file just to pass mailbox body text
- only use a real file when that file already exists independently and is intentionally the body source

Wakeup transport:
- after a mailbox message is queued, use `agent-deck` only to wake the target session
- wakeup text must be short and must not repeat the workflow body

Before first send/receive for a session inbox:
- register `workflow/session/<session_id>` with `agent-mailbox endpoint register --address ...`
- registering the same address again is a safe retry

### Mailbox Message Contract

Every workflow message has two parts:
- `subject`: one-line summary for quick triage
- `body`: full Markdown task content and the main source of truth

Do not add a protocol version header.
Do not generate workflow-specific Markdown files just to carry the message.

Recommended body header:

```markdown
Task: <task_id>
Action: <action_name>
From: <role> <from_session_id>
To: <role> <to_session_id>
Planner: <planner_session_id>
Round: <round_or_final>
```

Then include normal Markdown sections. Required meaning:
- body is the primary task input
- file paths may appear in body, but only as supplemental references
- receiver should not go hunting for external files unless the body explicitly says they are needed

Required action names:
- `execute_delegate_task`
- `review_requested`
- `rework_required`
- `user_requested_iteration`
- `closeout_delivered`

Sender invariants:
- `execute_delegate_task`: sender is planner
- `review_requested`: sender is executor
- `rework_required`, `user_requested_iteration`, `closeout_delivered`: sender is reviewer
- never default sender to planner for non-planner actions

Action contract:
- `execute_delegate_task`: planner starts delegated implementation
- `review_requested`: executor asks reviewer to run full review and reviewer must proactively send the next workflow message
- `rework_required`: reviewer blocks and sends must-fix follow-up to executor
- `user_requested_iteration`: reviewer forwards user's iterate decision to executor and restates the required follow-ups in the message body
- `closeout_delivered`: reviewer sends accepted closeout to planner; planner should treat the closeout body as planning input for residual follow-up tracking, not as a default reason to reopen accepted review

Review disagreement policy:
- reviewer findings are advisory, not automatically binding on executor
- executor must evaluate reviewer findings critically and adopt only the changes that are technically justified
- when executor disagrees, the next `review_requested` body should state the disagreement and rationale clearly
- if executor and reviewer cannot converge, either role may stop and ask user for a decision

User-facing responses should provide readable decisions, not raw mailbox JSON.

### Wakeup Contract

After sending mail to `workflow/session/<to_session_id>`:
1. ensure the target session exists when the workflow expects it to exist
2. start the target session when needed
3. send one short reminder through `agent-deck`

Recommended reminder text:

```text
You have new workflow mail. Run: agent-mailbox recv --for workflow/session/<to_session_id> --json
```

Do not:
- paste the full workflow body into `agent-deck session send`
- summarize the body so aggressively that the receiver can skip `recv`
- send a "go read file X" reminder as the default path
- write a temporary Markdown file only to hand it to `agent-mailbox send`

### Receiver Contract

When a workflow session is woken:
1. run `agent-mailbox recv --for workflow/session/<current_session_id> --json`
2. treat the returned `body` as the primary task input
3. only read supplemental files when the body explicitly requires them
4. `ack` only after the message has been successfully incorporated into local working state
5. use `release` / `defer` / `fail` instead of silently dropping leased work

Do not `ack` immediately after reading.

### Error Handling and Diagnostics

If workflow send/wakeup fails, report concise stderr summary and run these checks:
1. Is the mailbox endpoint registered? (`agent-mailbox endpoint register --address workflow/session/<session_id>`)
2. Is sender/target session reachable? (`agent-deck session show <session_id_or_ref> --json`)
3. Is command running in correct tmux/session context? (`agent-deck session current --json`)
4. Did mailbox send/recv/ack/release/fail return success?

If closeout cleanup fails, include:
1. blocked reason (`provider_guard_blocked`, `manual_close_required`, `worker_cap_exceeded`)
2. health report path (`.agent-artifacts/workflow-health/health-<task_id>.json`)
3. exact manual action to unblock (for example `agent-deck remove <session_id>`)

Planner closeout execution rule:
1. required actions (`merge`, `progress update`) are hard requirements
2. optional actions (`notify`, `next-task dispatch`, hygiene cleanup) are best-effort
3. optional-action failures must not roll back or block required closeout completion
4. when `--integration-branch` is provided, `planner-closeout-batch.sh` is responsible for switching to that branch before merge if the worktree is in a safe state
5. planner should not run git state-changing commands in parallel with `planner-closeout-batch.sh`

Planner post-acceptance interpretation rule:
1. `closeout_delivered` means accepted review loop complete; normal closeout should proceed
2. planner must inspect the closeout mailbox body before finalizing follow-up planning
3. non-blocking accepted findings should be evaluated as inputs to progress/todo updates or next-task planning
4. planner should decide whether each residual item needs explicit tracking, a queued next task/subtask, or no extra tracking
5. planner should not reopen the accepted task by default unless the closeout body clearly shows a must-fix issue was accepted by mistake or new contradictory evidence appears

### Reviewer Decision Flow

Reviewer decision rules:
1. If must-fix items exist, send `rework_required` to executor
2. If no must-fix items exist and `workflow_policy.auto_accept_if_no_must_fix=true`, run `review-closeout` and send `closeout_delivered` to planner
3. Otherwise, present `stop_recommended` to user and wait for user decision. Do not send `stop_recommended` to planner
4. If user chooses closeout, run `review-closeout` and send `closeout_delivered` to planner
5. If user chooses another iteration, send `user_requested_iteration` to executor

## Automation Policy Override (Optional)

Default behavior is human-gated.

Planner may include per-task `workflow_policy`, for example:

```json
{
  "mode": "unattended",
  "auto_accept_if_no_must_fix": true,
  "auto_dispatch_next_task": true,
  "ui_manual_confirmation": "auto"
}
```

Rules:
- If absent, apply human-gated defaults
- If present, executor and reviewer carry it forward unchanged for the same `task_id`
- If `special_requirements` is present in context, planner/executor/reviewer carry it forward unchanged for the same `task_id`
- Safety checks and must-fix handling remain unchanged
- Unattended mode (`mode=unattended` or `auto_dispatch_next_task=true`) enables strict post-closeout health gate

`ui_manual_confirmation`:
- `auto` (default): detect likely UI impact heuristically
- `required`: always require manual UI confirmation in human-gated mode
- `skip`: skip manual UI confirmation requirement

## Execution Environment (Required)

All `agent-deck` and `agent-mailbox` commands must run in host shell (outside sandbox) to keep real tmux/session context and real mailbox state.
When workflow commands create sessions via `--cmd`, do not use bare provider names.
Use full recommended commands unless the user explicitly supplied a different full command:
- Claude: `claude --model sonnet --permission-mode acceptEdits`
- Codex: `codex --model gpt-5.4 --ask-for-approval on-request`
- Gemini: `gemini --model gemini-2.5-pro`

## Relationship with Official Skill Clone

- Do not modify cloned official `agent-deck` skill for project-specific behavior
- Do not require loading official `agent-deck` skill in normal execution
- Use official clone references only when command details are needed

## Task Metadata Convention

Use stable naming:
- executor session: `executor-<task_id>`
- reviewer session: `reviewer-<task_id>`
- inbox address: `workflow/session/<session_id>`
- default dedicated task branch: `task/<task_id>`
- default integration branch: planner's current branch at delegate creation when that branch is the intended landing line
- existing topic branch reuse: allowed when planner determines the current branch already is the correct `task_branch`
- `.agent-artifacts/` is for non-message supplemental material only; workflow should not create Markdown handoff artifacts as the default transport

## Human-Led Three-Role Flow

### 1) Planner Starts Task

- planner prepares one mailbox message body for the executor
- planner resolves and records branch plan (`start_branch`, `integration_branch`, `task_branch`) inside that message body before sending
- planner queues the message to executor inbox and wakes executor session

### 2) Executor Implements and Requests Review

- executor implements and commits first delivery
- executor prepares one mailbox review request body for reviewer
- executor queues the message to reviewer inbox and wakes reviewer session
- executor enters waiting state and does not proactively poll reviewer unless user asks

### 3) Reviewer Loop

Reviewer chooses one branch:

1. `rework_required`
- send to executor
- executor evaluates the findings critically, applies the technically justified changes, and may disagree with specific points
- next `review_requested` should summarize any disagreement or partial adoption clearly
- if executor and reviewer cannot converge, either may stop and ask user for a decision

2. `stop_recommended`
- provide user-facing summary to user and wait for user decision
- do not send `stop_recommended` to planner; this is the user decision point
- if `workflow_policy.auto_accept_if_no_must_fix=true`, reviewer may skip waiting and run closeout
- in human-gated mode, request manual UI confirmation when required by policy

### 4) Planner Closeout Batch (After Acceptance)

After closeout acceptance (explicit user or unattended policy):
1. inspect the accepted closeout mailbox body
2. decide whether residual accepted findings require follow-up tracking (`progress`, `todo`, next-task queue, or no action)
3. reuse recorded branch plan (`task_branch`, `integration_branch`); do not silently re-infer a different merge target
4. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh` for required closeout actions, passing explicit `--task-branch` and `--integration-branch` when known
5. if `--integration-branch` is provided and current branch differs, the script should switch to the integration branch itself; planner should not pre-stage a parallel `git switch`
6. required in script: merge recorded `task_branch` into recorded `integration_branch`
7. required in script: update progress record
8. optional in script: hygiene (`prune-task-branches.sh`) and health gate
9. optional in script: dispatch next task

If `workflow_policy.auto_dispatch_next_task=true`, planner may auto-dispatch next queued task after merge + progress update.
When planner is dispatching from a known queued batch/plan, planner must proactively report queue progress before each new dispatch in `current/total` form (for example `3/15`).
This progress is planner-owned state; workflow helper scripts must not invent or infer it.
If planner knows the queue is ordered but does not know the total yet, say that explicitly instead of fabricating a ratio.

Recommended planner invocation:

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh \
  --task-id "<task_id>" \
  --task-branch "<task_branch>" \
  --integration-branch "<integration_branch>" \
  --run-health-gate
```

If next-task dispatch is configured, pass it as `--next-dispatch-cmd "<command>"`.
Even when that command fails, required closeout actions remain completed.

Planner user-facing status contract for auto-dispatch:
- before each auto-dispatched task, show one short status line that includes the next dispatch progress
- preferred format: `Auto-dispatch progress: <current>/<total> | next task: <task_id_or_short_title>`
- if total is unknown, use an explicit unknown-total form such as `Auto-dispatch progress: 3/?`
- do not delegate this responsibility to `planner-closeout-batch.sh`; it does not own queue state

## Example: Complete Task Flow

1. User asks: "Add login rate limiting".
2. Planner runs `delegate-task` and sends one delegate mailbox message containing recorded `start_branch`, `integration_branch`, and `task_branch`.
3. Planner wakes `executor-<task_id>`.
4. Executor implements on recorded `task_branch`, commits, runs `review-request`, and sends `review_requested`.
5. Reviewer runs `review-code` and sends `rework_required` (if must-fix exists).
6. Executor fixes and sends another `review_requested`.
7. Reviewer approves, user confirms, reviewer runs `review-closeout` and sends `closeout_delivered`.
8. Planner merges recorded `task_branch` into recorded `integration_branch` and updates progress.

## Role-Skill Mapping

- Planner: `delegate-task`, `handoff`
- Executor: `review-request`
- Reviewer: `review-code`, `review-closeout`
- Roles are task-scoped; same-session multi-role assignment is an explicit exception and must be stated in workflow context rather than inferred from provider/tool choice

## Do / Do Not

Do:
- keep the real workflow content in mailbox body
- keep human confirmation gates in human-gated mode
- treat accepted review residuals as planning input for follow-up tracking rather than silently discarding them
- resolve and record branch plan at delegate start, then reuse it consistently through closeout
- let `planner-closeout-batch.sh` own integration-branch switching when `--integration-branch` is explicitly supplied
- run planner required closeout actions via `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh`

Do not:
- auto-merge before acceptance
- run `git switch` in parallel with planner closeout
- assume the merge target is `main` or `master` when the recorded task mainline is something else
- blindly create `task/<task_id>` when the delegate message explicitly says to reuse an existing topic branch as `task_branch`
- silently re-derive merge target from whatever branch happens to be checked out at closeout time when branch plan was already recorded earlier
- send workflow body through `agent-deck session send`
- create Markdown handoff files just to transport workflow messages
- run proactive polling loops after dispatch
- treat mailbox JSON output as default user-facing content
- block `merge + progress update` on optional notify/dispatch failures
