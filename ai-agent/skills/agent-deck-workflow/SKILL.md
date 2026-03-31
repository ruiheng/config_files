---
name: agent-deck-workflow
description: Human-led planner/coder/reviewer workflow protocol with a per-task architect lane and an optional browser-tester worker, using agent-mailbox as the authoritative message layer and agent-deck only for wakeups.
---

# Agent Deck Workflow

Use this skill as the single source of truth for the workflow roles:
`planner` (long-lived), `coder` (per-task), `reviewer` (per-task), `architect` (per-task), and optional long-lived `browser-tester` workers.

Core transport rule:
- `agent-mailbox` carries the real workflow message
- `agent-deck` is used to start target sessions or to nudge already active sessions to check mail
- use the `agent_mailbox` MCP tools as the default transport interface
- use `check-agent-mail` for receiver-side wake handling

Default role/session rule:
- use one distinct session per role
- treat planner/reviewer same-session operation as an explicit exception, not an implied default

## Terminology

- `task_id`: stable task identifier (`YYYYMMDD-HHMM-<slug>`)
- `*_session_id`: Agent Deck session UUID (resolve with `agent_deck_resolve_session`)
- `*_session_ref`: human-friendly session reference (`title` or `id`)
- `inbox_address`: derived mailbox endpoint address for one AI agent session: `agent-deck/<agent-deck-session-id>`
- `start_branch`: planner's current git branch when `delegate-task` begins
- `integration_branch`: branch where accepted work must land at closeout; this is the task-local mainline and is not assumed to be `main`/`master`
- `task_branch`: coder working branch; may be a dedicated `task/<task_id>` branch or a reused existing topic branch
- `workflow_policy`: optional per-task automation override; absent means human-gated defaults
- `special_requirements`: optional free-form fallback requirements from user/planner; carry unchanged across all roles for the same `task_id`

## Scope

- Workflow shape: one long-lived `planner`, per-task `coder` + `reviewer` + `architect`, plus optional long-lived `browser-tester` sessions
- Default session mapping: planner, coder, reviewer, and architect are separate sessions; browser-tester is optional, shared, and requester-scoped
- Same-session planner+reviewer is allowed only when explicitly assigned by workflow context
- Runtime shape: single shared workspace
- Governance: human-led; user confirmation gates remain required at stop/closeout points unless policy override is present
- Git approval exception: in delegated coder flow, task-scoped coder commits are allowed without per-commit user approval
- This delegated coder commit authorization overrides generic default rules that would otherwise require asking the user before commit

## Shared Protocol (For All Workflow Skills)

### Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:
1. explicit `task_id` or `planner_session_id`
2. inbound mailbox body already carries workflow metadata
3. user explicitly asks for agent-deck workflow

Session binding rule:
- use mailbox tools directly
- bind only when mailbox context is actually missing

### Context Resolution Priority

Use this priority chain for each field:
`explicit input -> parsed mailbox body / workflow context -> deterministic default -> ask one short clarification question`

Session identity nuance:
- `planner_session_id` must come from explicit/context workflow metadata
- before identity comparisons, resolve all session refs/titles to UUIDs:
  - explicit refs: `agent_deck_resolve_session`
- use `*_session_ref` for planned worker titles before a real session exists; only write `*_session_id` when you actually have the resolved session id

### Role vs Session Identity

- Default mapping is one distinct session per active role: `planner_session_id`, `coder_session_id`, `reviewer_session_id`, and `architect_session_id` should differ unless workflow context explicitly assigns an exception
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
- if multiple lifecycle operations are needed, run them one at a time and wait for success before the next step

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
- `review_requested`: coder asks reviewer to run full review from a delivery commit, includes the coder's already-run verification record, and reviewer must proactively send the next workflow message
- `tech_design_review_requested`: planner or coder asks architect to review the latest committed tech-design docs from a dedicated branch and return advisory guidance to the requester
- `tech_design_review_report`: architect returns advisory tech-design feedback to the original requester session
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
- reviewer should also check whether coder is preserving unnecessary self-imposed constraints that are making the task harder than required
- two review-loop thresholds apply unless overridden by `workflow_policy`:
  - `review_round_convergence_check_threshold = 3`
  - `review_round_hard_stop_threshold = 5`

Tech-design disagreement policy:
- architect feedback is advisory, not a user decision
- requester must evaluate architect feedback critically and adopt only the changes that are technically justified
- architect and requester may iterate over the design and argue specific points directly
- either side may stop and ask user for a decision when the disagreement becomes subjective, strategic, or stuck

Review-request continuity:
- first `review_requested` to a reviewer session carries the full task and review context
- later `review_requested` messages to that same reviewer session carry only the delta since the previous review round
- later review rounds should stay terse; do not restate round 1 context unless it materially changed
- if the reviewer session changes, resend the full review context to the new reviewer session
- `review_requested` should carry a concise record of coder-run lint, build/link, compile/type-check, test, and other verification results so reviewer can usually avoid rerunning the same slow checks
- later terse review requests do not reduce reviewer responsibility: when rounds accumulate or similar issues recur, reviewer should examine whether the work is failing to converge and should widen scope beyond the latest diff when needed
- when `round >= review_round_convergence_check_threshold`, reviewer should become actively skeptical about false constraints, patch layering, and lack of convergence
- when `round >= review_round_hard_stop_threshold`, reviewer should stop the normal coder-reviewer loop and escalate to the user instead of sending another routine rework pass

Tech-design review continuity:
- first `tech_design_review_requested` to an architect session carries the full tech-design context
- later `tech_design_review_requested` messages to that same architect session carry only the delta since the previous architect round
- if the architect session changes, resend the full tech-design context to the new architect session
- `tech_design_review_requested` is based on the latest committed design docs on a branch, not uncommitted working tree notes
- default tech-design branch is `tech-design/<task_id>`

User-facing responses should provide readable decisions, not raw mailbox JSON.

### Delivery Order Contract

Use `mailbox_send` for the normal mailbox delivery path.

Expected behavior:
1. use `agent_deck_ensure_session` when a target session must be resolved, created, or started
2. queue the mailbox body with `mailbox_send`

### Receiver Contract

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
- `execute_delegate_task`: start the delegated implementation flow immediately
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

### Error Handling and Diagnostics

If workflow send/worker-start fails, report concise stderr summary and run these checks:
1. Is sender/target session reachable? (`agent_deck_resolve_session`)
2. Is command running in the expected workflow session context?
3. Did `mailbox_send` / `mailbox_recv` / lifecycle tools return success?

If sandbox-external execution triggers an approval prompt, explain it as a host-shell permission requirement.
If a target missed the mailbox work, retry the nudge path instead of resending mailbox content.

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

### Architect Loop

Architect rules:
1. `architect` is a per-task focused session, not a shared long-lived service
2. requester may be planner or coder
3. input is the latest committed tech-design docs on a branch, typically `tech-design/<task_id>`
4. architect reviews docs and design rationale; it does not edit code or docs in this lane
5. architect sends one `tech_design_review_report` back to the original requester
6. requester decides whether to revise the design docs, proceed, or ask for another architect round
7. architect feedback is advisory; requester may disagree and continue the discussion
8. either architect or requester may ask the user to decide when the disagreement is fundamentally subjective or strategic

### Browser Tester Loop

Browser tester rules:
1. `browser-tester` does runtime verification only; it does not change code or decide acceptance
   - exception: when the request explicitly allows browser-tester edits for display-adjacent code, it may make those changes on its own branch
2. use `agent-browser` as the primary validation tool
3. treat browser-tester as a long-lived service session that keeps browser state warm across tasks
4. return one `browser_check_report` to the original requester with PASS / FAIL / UNKNOWN plus evidence
5. if environment or test preconditions are missing, return `UNKNOWN` instead of guessing
6. browser-tester should rely on requester nudges rather than a long-running wait loop
7. after sending the report, browser-tester does not need to enter a blocking wait state
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
  "ui_manual_confirmation": "auto",
  "review_round_convergence_check_threshold": 3,
  "review_round_hard_stop_threshold": 5
}
```

Rules:
- If absent, apply human-gated defaults
- If present, coder, reviewer, and architect carry it forward unchanged for the same `task_id`
- If `special_requirements` is present in context, planner/coder/reviewer/architect carry it forward unchanged for the same `task_id`
- Safety checks and must-fix handling remain unchanged
- Unattended mode (`mode=unattended` or `auto_dispatch_next_task=true`) enables strict post-closeout health gate
- Review-loop thresholds default to:
  - `review_round_convergence_check_threshold = 3`
  - `review_round_hard_stop_threshold = 5`
- Threshold semantics:
  - at or above `review_round_convergence_check_threshold`, reviewer should actively test whether the work is solving the wrong problem or preserving unnecessary self-imposed constraints
  - at or above `review_round_hard_stop_threshold`, reviewer should stop routine iteration and escalate to the user

`ui_manual_confirmation`:
- `auto` (default): detect likely UI impact heuristically
- `required`: always require manual UI confirmation in human-gated mode
- `skip`: skip manual UI confirmation requirement

## Execution Environment (Required)

Use the `agent_mailbox` MCP tools as the default workflow transport surface.
When shell fallback is unavoidable, run `agent-deck` and `agent-mailbox` commands in host shell (outside sandbox).
When a workflow turn needs multiple lifecycle steps, execute them sequentially, never in parallel.
Read-only observation commands may run in parallel when safe.
When workflow commands create sessions via `--cmd`, use full commands instead of bare provider names.
Use full recommended commands unless the user explicitly supplied a different full command:
- Claude: `claude --model sonnet --permission-mode acceptEdits`
- Codex: `codex --model gpt-5.4 --ask-for-approval on-request`
- Gemini: `gemini --model gemini-2.5-pro`

## Task Metadata Convention

Use stable naming:
- coder session: `coder-<task_id>`
- reviewer session: `reviewer-<task_id>`
- architect session: `architect-<task_id>`
- browser-tester session: use a stable long-lived title such as `browser-tester`; do not default to `browser-tester-<task_id>`
- inbox address: `agent-deck/<agent-deck-session-id>`
- default dedicated task branch: `task/<task_id>`
- default dedicated tech-design branch: `tech-design/<task_id>`
- default integration branch: planner's current branch at delegate creation when that branch is the intended landing line
- existing topic branch reuse: allowed when planner determines the current branch already is the correct `task_branch`
- `.agent-artifacts/` is for non-message supplemental material only; workflow should not create Markdown handoff artifacts as the default transport
- `coder_session_ref` / `reviewer_session_ref` may be planned before creation; resolve them to real `*_session_id` values before mailbox addressing

## Human-Led Core Flow

### 1) Planner Starts Task

- planner prepares one mailbox message body for the coder
- planner resolves and records branch plan (`start_branch`, `integration_branch`, `task_branch`) inside that message body before sending
- planner ensures mailbox context is available, then queues the message to coder inbox with `mailbox_send`

### 2) Coder Implements and Requests Review

- coder implements and commits first delivery
- delegated coder commits for the recorded task are workflow-authorized and do not need extra user approval
- this commit authorization overrides generic default rules that would otherwise require asking the user before commit
- coder prepares one mailbox review request body for reviewer
- workflow `review_requested` is based on that committed delivery state, not the uncommitted working tree
- coder uses `mailbox_send` to queue the message to reviewer inbox
- coder does not proactively poll reviewer unless user asks

### 2a) Optional Tech-Design Review Lane

- planner or coder may request architect feedback before implementation or during a design revision cycle
- requester prepares committed design docs on `tech-design/<task_id>` or another explicit tech-design branch
- requester sends `tech_design_review_requested` to `architect-<task_id>`
- architect reviews and sends `tech_design_review_report` back to the requester
- architect does not edit the tech-design docs in this lane
- later rounds to the same architect session should send only the design delta since the previous round

### 3) Reviewer Loop

Reviewer chooses one branch:

1. `rework_required`
- send to coder
- coder evaluates the findings critically, applies the technically justified changes, and may disagree with specific points
- next `review_requested` should summarize any disagreement or partial adoption clearly
- if similar findings keep recurring across rounds, reviewer should shift from local diff review to broader design/convergence review
- if coder and reviewer cannot converge, either may stop and ask user for a decision
- if `round >= review_round_hard_stop_threshold` and rounds are still stuck in a recurring loop, reviewer should stop the coder-reviewer loop and escalate to the user instead of sending another routine rework pass

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
10. reusable custom coder/reviewer/architect sessions should be preserved; default cleanup should remove only disposable task-scoped sessions such as `coder-<task_id>`, `reviewer-<task_id>`, and `architect-<task_id>`

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
3. Planner uses `agent_deck_ensure_session` and `mailbox_send` for the normal coder delivery path.
4. Coder implements on recorded `task_branch`, commits, runs `review-request`, and sends `review_requested`.
5. Reviewer runs `review-code`.
6. If runtime browser validation is needed, reviewer runs `browser-test-request` and sends `browser_check_requested`.
7. Browser-tester runs `browser-test` and sends `browser_check_report` back to the requester.
8. The requester interprets the report and chooses the next step.
9. Planner merges recorded `task_branch` into recorded `integration_branch` and updates progress.
10. Planner or coder may separately use the architect lane when committed tech-design review is needed.

## Role-Skill Mapping

- Planner: `delegate-task`, `handoff`
- Planner or Coder: `tech-design-review-request`, `browser-test-request`
- Coder: `review-request`
- Reviewer: `review-code`, `review-closeout`, `browser-test-request`
- Architect: `tech-design-review`
- Browser tester: `browser-test`
- Roles are task-scoped; same-session multi-role assignment is an explicit exception and must be stated in workflow context rather than inferred from provider/tool choice

## Operating Rules

- keep the real workflow content in mailbox body
- keep delivery driven by post-send nudges, not by long-running wait loops
- keep human confirmation gates in human-gated mode
- treat accepted review residuals as planning input for follow-up tracking rather than silently discarding them
- resolve and record branch plan at delegate start, then reuse it consistently through closeout
- let `planner-closeout-batch.sh` own integration-branch switching when `--integration-branch` is explicitly supplied
- run planner required closeout actions via `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh`
- keep workflow transport free of generated Markdown handoff files
- finish required closeout actions even when optional notify or dispatch steps fail
