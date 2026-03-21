---
name: agent-deck-workflow
description: Human-led planner/coder/reviewer workflow protocol with an optional browser-tester worker, using agent-mailbox as the authoritative message layer and agent-deck only for wakeups.
---

# Agent Deck Workflow

Use this skill as the single source of truth for the workflow roles:
`planner` (long-lived), `coder` (per-task), `reviewer` (per-task), and optional long-lived `browser-tester` workers.

Core transport rule:
- `agent-mailbox` carries the real workflow message
- `agent-deck` is used either to start target sessions into mailbox-wait mode or to nudge already active sessions to check mail
- receiver-side wake handling should go through `check-workflow-mail`

Default role/session rule:
- use one distinct session per role
- treat planner/reviewer same-session operation as an explicit exception, not an implied default

## Terminology

- `task_id`: stable task identifier (`YYYYMMDD-HHMM-<slug>`)
- `*_session_id`: Agent Deck session UUID (resolve with `agent-deck session show <session_id_or_ref> --json | jq -r '.id'`)
- `*_session_ref`: human-friendly session reference (`title` or `id`)
- `inbox_address`: derived mailbox endpoint address for one workflow session: `agent-deck/<session_id>`
- `start_branch`: planner's current git branch when `delegate-task` begins
- `integration_branch`: branch where accepted work must land at closeout; this is the task-local mainline and is not assumed to be `main`/`master`
- `task_branch`: coder working branch; may be a dedicated `task/<task_id>` branch or a reused existing topic branch
- `workflow_policy`: optional per-task automation override; absent means human-gated defaults
- `special_requirements`: optional free-form fallback requirements from user/planner; carry unchanged across all roles for the same `task_id`

## Scope

- Workflow shape: one long-lived `planner`, per-task `coder` + `reviewer`, plus optional long-lived `browser-tester` sessions
- Default session mapping: planner, coder, and reviewer are separate sessions; browser-tester is optional, shared, and requester-scoped
- Same-session planner+reviewer is allowed only when explicitly assigned by workflow context
- Runtime shape: single shared workspace
- Governance: human-led; user confirmation gates remain required at stop/closeout points unless policy override is present
- Git approval exception: in delegated coder flow, task-scoped coder commits are allowed without per-commit user approval

## Shared Protocol (For All Workflow Skills)

### Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:
1. explicit `task_id` or `planner_session_id`
2. inbound mailbox body already carries workflow metadata
3. user explicitly asks for agent-deck workflow

`agent-deck session current --json` is best-effort context only and must run in host shell.
If it fails, continue with explicit/context metadata.

Current-session caching rule:
- resolve `current_session_id` at most once per workflow turn
- reuse that cached value for sender validation, inbox derivation, and same-session checks
- re-run `agent-deck session current --json` only when the execution context actually changed

### Context Resolution Priority

Use this priority chain for each field:
`explicit input -> parsed mailbox body / workflow context -> deterministic default -> ask one short clarification question`

Session identity nuance:
- `planner_session_id` must come from explicit/context workflow metadata
- `current_session_id` is used for sender identity verification and role safety checks
- before identity comparisons, resolve all session refs/titles to UUIDs:
  - explicit refs: `agent-deck session show <ref> --json | jq -r '.id'`
  - current session: cached result from one `agent-deck session current --json`
- exception (`delegate-task` only): planner sender legitimately equals current session, so `planner_session_id` may start from detected `current_session_id`
- in all other skills, `current_session_id` is not a replacement source for `planner_session_id`
- use `*_session_ref` for planned worker titles before a real session exists; only write `*_session_id` when you actually have the resolved session id

### Role vs Session Identity

- Default mapping is one distinct session per active role: `planner_session_id`, `coder_session_id`, and `reviewer_session_id` should differ unless workflow context explicitly assigns an exception
- A session may hold multiple roles for the same task only when workflow context explicitly assigns that multi-role mapping
- `*_session_id` fields identify which session currently holds each role mapping
- Tool/provider choice is separate from session identity
- Saying "reviewer uses codex" means "the reviewer session should be created or resumed with a Codex command", not "the current Codex planner/coder session should self-assign reviewer role"
- Even when planner and reviewer use the same provider/model/command, keep a distinct reviewer session unless same-session reviewer assignment is explicitly stated in workflow context
- When `from_session_id == to_session_id`, this is an explicit local same-session continuation already established by workflow context, not something inferred from matching tool names
- Skip cross-session wakeup only when the target session is the current session; otherwise wake the target session after mail is queued

### Branch Roles and Resolution

- Resolve branch roles when planner creates the delegate message, not during closeout
- `integration_branch` is the branch that accepted work merges into. It is the task-local mainline and may be `develop`, `release/*`, another feature branch, or anything else the task actually targets
- `task_branch` is the branch where coder commits. In the normal merge-based flow it must differ from `integration_branch`
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
- every `agent-mailbox` command must run outside sandbox
- mailbox state-mutating commands must run serially
- read-only observation commands may run in parallel when safe (for example `watch`)

Send-body rule:
- for cross-session workflow delivery, use `adwf-send-and-wake`
- use bare `agent-mailbox send` only when sender and receiver are the same current session
- prefer `agent-mailbox send --body-file -` and feed the body through stdin
- use a real file only when that file already exists independently and is intentionally the body source
- in agent-tool environments, invoke `adwf-send-and-wake --body-file -` directly for cross-session delivery and write body via stdin
- if the workflow body was generated in the current turn, pass it via stdin
- in Codex-style agent environments, launch `adwf-send-and-wake --body-file -` in a background terminal / PTY session, then write the body to that session's stdin
- if host-shell approval is required, request approval for `adwf-send-and-wake ...` itself

Worker listener rule:
- newly started coder/reviewer/browser-tester sessions should enter `check-workflow-mail wait=True` in the foreground before the sender queues mailbox work
- for already active target sessions, sender may use `agent-deck session send` to nudge the target to run `check-workflow-mail`
- `check-workflow-mail wait=True` must run in the foreground of the target session; never start it in a background terminal, detached process, or parallel watcher
- keep at most one active `check-workflow-mail wait=True` listener per session

Inbox rule:
- derive inbox address as `agent-deck/<session_id>`
- no separate registration step is needed
- if multiple mailbox state-mutating operations are needed, run them one at a time and wait for success before the next mailbox step

### Mailbox Message Contract

Every workflow message has two parts:
- `subject`: one-line summary for quick triage
- `body`: full Markdown task content and the main source of truth

Keep workflow content in mailbox body instead of generating Markdown handoff files.

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
- `browser_check_requested`
- `browser_check_report`
- `rework_required`
- `user_requested_iteration`
- `closeout_delivered`

Sender invariants:
- `execute_delegate_task`: sender is planner
- `review_requested`: sender is coder
- `browser_check_requested`: sender is the requesting workflow session
- `browser_check_report`: sender is browser-tester
- `rework_required`, `user_requested_iteration`, `closeout_delivered`: sender is reviewer
- never default sender to planner for non-planner actions

Action contract:
- `execute_delegate_task`: planner starts delegated implementation
- `review_requested`: coder asks reviewer to run full review and reviewer must proactively send the next workflow message
- `browser_check_requested`: any workflow session may ask browser-tester to validate a concrete browser flow and return runtime evidence; when the request explicitly allows it, browser-tester may directly modify display-adjacent code on its own branch before reporting back
- `browser_check_report`: browser-tester returns PASS / FAIL / UNKNOWN evidence to the original requester session
- `rework_required`: reviewer blocks and sends must-fix follow-up to coder
- `user_requested_iteration`: reviewer forwards user's iterate decision to coder and restates the required follow-ups in the message body
- `closeout_delivered`: reviewer sends accepted closeout to planner; planner should treat the closeout body as planning input for residual follow-up tracking, not as a default reason to reopen accepted review

Review disagreement policy:
- reviewer findings are advisory, not automatically binding on coder
- coder must evaluate reviewer findings critically and adopt only the changes that are technically justified
- when coder disagrees, the next `review_requested` body should state the disagreement and rationale clearly
- if coder and reviewer cannot converge, either role may stop and ask user for a decision

Review-request continuity:
- first `review_requested` to a reviewer session carries the full task and review context
- later `review_requested` messages to that same reviewer session carry only the delta since the previous review round
- if the reviewer session changes, resend the full review context to the new reviewer session

User-facing responses should provide readable decisions, not raw mailbox JSON.

### Delivery Order Contract

For newly started coder/reviewer sessions:
1. ensure the target session exists when the workflow expects it to exist
2. `agent-deck launch` a missing target session with a natural-language instruction to run `check-workflow-mail wait=True` in the foreground
3. send the mailbox message

For already active sessions:
1. send the mailbox message
2. send one short natural-language nudge through `agent-deck` telling the target to use `check-workflow-mail`

Recommended session-start instruction:

```text
Use the check-workflow-mail skill now with wait=True in the foreground. Do not run it in a background terminal or detached process. Wait for pending workflow mail for your current agent-deck session and execute its requested action.
```

Recommended active-session nudge:

```text
Use the check-workflow-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action.
```

Rules:
- keep `agent-deck session send` short; the real workflow body stays in mailbox
- for already active target sessions, mailbox send may be followed by an `agent-deck` nudge
- keep freshly generated workflow body in stdin
- keep mailbox state-mutating commands serialized

### Receiver Contract

When a workflow session is woken:
1. run the exact matching receive command outside sandbox:
   - single check: `agent-mailbox recv --for agent-deck/<current_session_id> --yaml`
   - blocking wait: `agent-mailbox recv --for agent-deck/<current_session_id> --wait --yaml`
2. treat the returned `body` as the primary task input
3. parse the `Action:` header and immediately execute that workflow stage
4. only read supplemental files when the body explicitly requires them
5. `ack` only after the message has been successfully incorporated into local working state, and run that `ack` outside sandbox
6. use `release` / `defer` / `fail` outside sandbox instead of silently dropping leased work
7. keep mailbox lifecycle steps serialized

Apply the message action before `ack`.

Action execution defaults after `recv`:
- `execute_delegate_task`: start the delegated implementation flow immediately
- `review_requested`: start review immediately
- `browser_check_requested`: start browser validation immediately
- `browser_check_report`: requester resumes decision-making immediately
- `rework_required`: continue coder iteration immediately
- `user_requested_iteration`: continue coder iteration immediately
- `closeout_delivered`: start planner closeout interpretation immediately
- only pause for user input when the message body explicitly requires a user decision

Idle behavior:
- when coder or reviewer is waiting for the next workflow message, use `check-workflow-mail wait=True` in the foreground instead of relying on a later `agent-deck session send`
- planner may also use `check-workflow-mail wait=True` in the foreground when running unattended and waiting for workflow mail

### Error Handling and Diagnostics

If workflow send/worker-start fails, report concise stderr summary and run these checks:
1. Is sender/target session reachable? (`agent-deck session show <session_id_or_ref> --json`)
2. Is command running in the expected tmux/session context? (reuse cached `current_session_id`; only re-run `agent-deck session current --json` if context may have changed)
3. Did mailbox send/recv/ack/release/fail return success?

If sandbox-external execution triggers an approval prompt, explain it as a host-shell permission requirement.
If a newly started target did not enter `check-workflow-mail wait=True` in the foreground, treat that as a workflow bug signal.
If an already active target missed the mailbox work, retry the `agent-deck session send` nudge instead of resending mailbox content.

If closeout cleanup fails, include:
1. blocked reason (`provider_guard_blocked`, `manual_close_required`, `worker_cap_exceeded`)
2. session archive path (`.agent-artifacts/<task_id>/session-archive-<task_id>.json`)
3. exact manual action to unblock (for example `agent-deck remove <session_id>`)

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

### Reviewer Decision Flow

Reviewer decision rules:
1. If must-fix items exist, send `rework_required` to coder
2. If browser validation is required and current browser evidence is missing or stale, run `browser-test-request`
3. If no must-fix items exist and `workflow_policy.auto_accept_if_no_must_fix=true`, run `review-closeout` and send `closeout_delivered` to planner
4. Otherwise, present `stop_recommended` to user and wait for user decision
5. If user chooses closeout, run `review-closeout` and send `closeout_delivered` to planner
6. If user chooses another iteration, send `user_requested_iteration` to coder

### Browser Tester Loop

Browser tester rules:
1. `browser-tester` does runtime verification only; it does not change code or decide acceptance
   - exception: when the request explicitly allows browser-tester edits for display-adjacent code, it may make those changes on its own branch
2. use `agent-browser` as the primary validation tool
3. treat browser-tester as a long-lived service session that keeps browser state warm across tasks
4. return one `browser_check_report` to the original requester with PASS / FAIL / UNKNOWN plus evidence
5. if environment or test preconditions are missing, return `UNKNOWN` instead of guessing
6. when browser-tester has no active request, it should be in `check-workflow-mail wait=True` in the foreground
7. after sending the report, browser-tester returns to `check-workflow-mail wait=True` in the foreground
8. requester should provide required login, environment, and test data context in the request body whenever possible
9. if required access or setup information is missing, browser-tester should first ask the requester session; browser-tester may ask the user directly when requester context is unavailable or user input is clearly required

### Reviewer Default

- Default reviewer tool: `codex --model gpt-5.4 --ask-for-approval on-request`

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
- If present, coder and reviewer carry it forward unchanged for the same `task_id`
- If `special_requirements` is present in context, planner/coder/reviewer carry it forward unchanged for the same `task_id`
- Safety checks and must-fix handling remain unchanged
- Unattended mode (`mode=unattended` or `auto_dispatch_next_task=true`) enables strict post-closeout health gate

`ui_manual_confirmation`:
- `auto` (default): detect likely UI impact heuristically
- `required`: always require manual UI confirmation in human-gated mode
- `skip`: skip manual UI confirmation requirement

## Execution Environment (Required)

All `agent-deck` and `agent-mailbox` commands must run in host shell (outside sandbox) to keep real tmux/session context.
`agent-mailbox` is especially strict here: run it outside sandbox.
When a workflow turn needs multiple mailbox state-mutating commands, execute them sequentially, never in parallel.
Read-only observation commands may run in parallel when safe.
For cross-session workflow dispatch, use the installed helper `adwf-send-and-wake`.
When workflow commands create sessions via `--cmd`, use full commands instead of bare provider names.
Use full recommended commands unless the user explicitly supplied a different full command:
- Claude: `claude --model sonnet --permission-mode acceptEdits`
- Codex: `codex --model gpt-5.4 --ask-for-approval on-request`
- Gemini: `gemini --model gemini-2.5-pro`

## Task Metadata Convention

Use stable naming:
- coder session: `coder-<task_id>`
- reviewer session: `reviewer-<task_id>`
- browser-tester session: use a stable long-lived title such as `browser-tester`; do not default to `browser-tester-<task_id>`
- inbox address: `agent-deck/<session_id>`
- default dedicated task branch: `task/<task_id>`
- default integration branch: planner's current branch at delegate creation when that branch is the intended landing line
- existing topic branch reuse: allowed when planner determines the current branch already is the correct `task_branch`
- `.agent-artifacts/` is for non-message supplemental material only; workflow should not create Markdown handoff artifacts as the default transport
- `coder_session_ref` / `reviewer_session_ref` may be planned before creation; resolve them to real `*_session_id` values before mailbox addressing

## Human-Led Core Flow

### 1) Planner Starts Task

- planner prepares one mailbox message body for the coder
- planner resolves and records branch plan (`start_branch`, `integration_branch`, `task_branch`) inside that message body before sending
- planner either starts coder into `check-workflow-mail wait=True` in the foreground or nudges an already active coder, then queues the message to coder inbox

### 2) Coder Implements and Requests Review

- coder implements and commits first delivery
- coder prepares one mailbox review request body for reviewer
- coder either starts reviewer into `check-workflow-mail wait=True` in the foreground or nudges an already active reviewer, then queues the message to reviewer inbox
- coder enters `check-workflow-mail wait=True` in the foreground and does not proactively poll reviewer unless user asks

### 3) Reviewer Loop

Reviewer chooses one branch:

1. `rework_required`
- send to coder
- coder evaluates the findings critically, applies the technically justified changes, and may disagree with specific points
- next `review_requested` should summarize any disagreement or partial adoption clearly
- if coder and reviewer cannot converge, either may stop and ask user for a decision

2. `stop_recommended`
- provide user-facing summary to user and wait for user decision
- keep `stop_recommended` at the user decision point
- if `workflow_policy.auto_accept_if_no_must_fix=true`, reviewer may skip waiting and run closeout
- in human-gated mode, request manual UI confirmation when required by policy

3. `browser_check_requested`
- send to browser-tester
- use when runtime browser evidence is required before acceptance
- request may explicitly allow browser-tester to directly modify display-adjacent code on its own branch
- requester waits for one `browser_check_report`

### 4) Browser Tester Loop

- browser-tester runs the requested browser flow with `agent-browser`
- browser-tester sends `browser_check_report` back to the requester
- requester interprets the report and chooses the next step

### 5) Planner Closeout Batch (After Acceptance)

After closeout acceptance (explicit user or unattended policy):
1. inspect the accepted closeout mailbox body
2. decide whether residual accepted findings require follow-up tracking (`progress`, `todo`, next-task queue, or no action)
3. reuse recorded branch plan (`task_branch`, `integration_branch`) as the authoritative merge target
4. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh` for required closeout actions, passing explicit `--task-branch` and `--integration-branch` when known
5. if `--integration-branch` is provided and current branch differs, the script should switch to the integration branch itself; planner should not pre-stage a parallel `git switch`
6. required in script: merge recorded `task_branch` into recorded `integration_branch`
7. required in script: update progress record
8. optional in script: hygiene (`prune-task-branches.sh`) and dispatch next task
9. default in script: run closeout health gate and disposable worker cleanup
10. reusable custom coder/reviewer sessions should be preserved; default cleanup should remove only disposable task-scoped sessions such as `coder-<task_id>` and `reviewer-<task_id>`

If `workflow_policy.auto_dispatch_next_task=true`, planner may auto-dispatch next queued task after merge + progress update.
When planner is dispatching from a known queued batch/plan, planner must proactively report queue progress before each new dispatch in `current/total` form (for example `3/15`).
This progress is planner-owned state; workflow helper scripts must not invent or infer it.
If planner knows the queue is ordered but does not know the total yet, say that explicitly instead of fabricating a ratio.

Recommended planner invocation:

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh \
  --task-id "<task_id>" \
  --task-branch "<task_branch>" \
  --integration-branch "<integration_branch>"
```

If next-task dispatch is configured, pass it as `--next-dispatch-cmd "<command>"`.
Even when that command fails, required closeout actions remain completed.

Planner user-facing status contract for auto-dispatch:
- before each auto-dispatched task, show one short status line that includes the next dispatch progress
- preferred format: `Auto-dispatch progress: <current>/<total> | next task: <task_id_or_short_title>`
- if total is unknown, use an explicit unknown-total form such as `Auto-dispatch progress: 3/?`
- planner owns this progress reporting; `planner-closeout-batch.sh` does not

## Example: Complete Task Flow

1. User asks: "Add login rate limiting".
2. Planner runs `delegate-task` and sends one delegate mailbox message containing recorded `start_branch`, `integration_branch`, and `task_branch`.
3. Planner `agent-deck launch`es a missing `coder-<task_id>` into `check-workflow-mail wait=True` in the foreground or nudges the existing coder session.
4. Coder implements on recorded `task_branch`, commits, runs `review-request`, and sends `review_requested`.
5. Reviewer runs `review-code`.
6. If runtime browser validation is needed, reviewer runs `browser-test-request` and sends `browser_check_requested`.
7. Browser-tester runs `browser-test` and sends `browser_check_report` back to the requester.
8. The requester interprets the report and chooses the next step.
9. Planner merges recorded `task_branch` into recorded `integration_branch` and updates progress.

## Role-Skill Mapping

- Planner: `delegate-task`, `handoff`
- Coder: `review-request`
- Reviewer: `review-code`, `review-closeout`, `browser-test-request`
- Planner or Coder may also use `browser-test-request` when runtime browser evidence is needed
- Browser tester: `browser-test`
- Roles are task-scoped; same-session multi-role assignment is an explicit exception and must be stated in workflow context rather than inferred from provider/tool choice

## Operating Rules

- keep the real workflow content in mailbox body
- keep coder/reviewer in `check-workflow-mail wait=True` in the foreground when they are idle and waiting for the next workflow step
- keep long-lived browser-tester sessions in `check-workflow-mail wait=True` in the foreground whenever they are not actively executing a request
- keep human confirmation gates in human-gated mode
- treat accepted review residuals as planning input for follow-up tracking rather than silently discarding them
- resolve and record branch plan at delegate start, then reuse it consistently through closeout
- let `planner-closeout-batch.sh` own integration-branch switching when `--integration-branch` is explicitly supplied
- run planner required closeout actions via `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh`
- use `agent-deck session send` only as a short nudge for already active sessions
- keep workflow transport free of generated Markdown handoff files
- finish required closeout actions even when optional notify or dispatch steps fail
