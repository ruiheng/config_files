---
name: execute-plan
description: Execute one supervisor-assigned goal inside one workspace, decompose it locally, drive resulting tasks to completion serially, and send one final report back to the supervisor.
---

# Execute Plan

Execute one supervisor-provided goal inside one workspace.
This session owns one planner lane.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Input

Provide the message body from `execute_plan`.

## Core Model

- this planner lane is one supervisor-dispatched planner run with its own planner session, workspace contract, integration branch, and cleanup lifecycle
- this planner owns one workspace
- this planner lane uses one workspace only
- workspace reservation records are prepared per task and released by closeout; planner-lane exclusivity comes from this serial execution contract, not from keeping a record across task gaps
- planner default role is coordinator, not coder
- this planner owns task decomposition inside that workspace
- tasks inside that workspace execute serially
- the planner should auto-advance whenever the next step is clear
- if a blocker cannot be resolved locally, stop and ask the user directly
- do not send routine blocker message to supervisor
- planner should use `delegate-task` Selection-Only Use to choose direct execution, a native harness when available, or persistent Agent Deck; when neither external surface fits, use planner-owned nonpersistent delivery. Use `delegate-code-task` only for a Waypost Agent Deck code task
- code-changing tasks are complete only after commit, any required review, closeout merge, and progress recording
- claiming `execute_plan` does not require planner to implement code personally; dispatch, review, closeout, and final report still count as completing the workflow
- planner is not done when implementation is done; planner is done only after one final `plan_report_delivered` message is successfully sent to supervisor

## Agent Deck Mode

Use the `agent-deck-workflow` skill for shared protocol.

Skill-specific context resolution:
- `plan_id`: explicit -> message body -> ask
- `supervisor_session_id`: explicit -> message body `From` header -> ask
- `planner_session_id`: explicit -> message body `To` / `Planner` header -> current session id -> ask
- `workspace`: explicit -> message body `Workspace path` -> ask
- `planner_workspace`: derive internally from `workspace`
- `worker_workspace`: derive internally from `workspace`
- `integration_branch`: explicit -> message body -> ask
  - this is the already-created planner-owned branch for this dispatched plan, not the supervisor landing branch
- `per_task_review`: explicit -> message body -> default `required`
- `final_review`: explicit -> message body -> default `skip`

## Execution Flow

1. read the goal, workspace contract, and review policy from the message body
   - set internal `planner_workspace = workspace` and `worker_workspace = workspace`
2. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-workspaces.sh --worker-workspace <worker_workspace> --planner-workspace <planner_workspace> --integration-branch <integration_branch> --planner-session-id <planner_session_id> --supervisor-session-id <supervisor_session_id>`
3. decompose the goal into the smallest reasonable serial task sequence for this workspace
4. execute that task sequence serially
5. for each implementation task:
   - before starting the task, run workspace prepare for the recorded workspace and integration branch
   - use `delegate-task` in Selection-Only Use; use Direct Planner Implementation only when every condition below passes. Otherwise use a native harness when available, persistent Agent Deck only when independently justified, or Planner-Owned Nonpersistent Fallback; do not run generic Dispatch
   - for an Agent Deck code task in this plan, choose its Waypost worker mode; a direct user-led session is outside this branch/review/closeout handoff
   - if it selects a persistent Waypost Agent Deck worker, use `delegate-code-task` and pass the selected `session_reason` and `Per-task review` policy into the code brief
   - if it selects a native harness subagent, use Native Harness Implementation
   - if it selects local execution, planner may use `Direct Planner Implementation`
   - if no native harness is available and Agent Deck is not justified, use Planner-Owned Nonpersistent Fallback
6. coder/reviewer/architect progress may take unbounded time; after sending asynchronous cross-session work, follow the shared Async sender rule
   - for a persistent code worker, handle a later `code_delivery_complete` with `planner-closeout` before starting the next task; only skipped review may complete through it, while a blocker retains task state
7. when the goal is complete:
   - if `Final integration review: required`, run `review-request` against the planner-owned integration branch with `requester_role = planner` and `review_lane = integration_final`
   - if that final review returns serious issues, decide whether to fix locally or spawn a new task; prefer a new task for non-trivial fixes
8. send one final `plan_report_delivered` message to supervisor; do not treat the plan as complete before this message send succeeds
9. after the final report is sent, report completion to supervisor

## Direct Planner Implementation

Use this only after `delegate-task` Selection-Only Use selects local execution. It is eligible only when all of the following hold:
- single local change
- no new cross-module behavior
- no schema, registry, or runtime contract change
- no new first-class model or state field
- no meaningful design choice remains
- narrow verification is sufficient
- delegation would be pure coordination overhead

If any condition fails, do not use the direct fast path: use Native Harness Implementation when available; use `delegate-code-task` only when Agent Deck has an independent lifecycle or user-interaction reason; otherwise use Planner-Owned Nonpersistent Fallback.

## Native Harness Implementation

Use this only after `delegate-task` Selection-Only Use selects a native harness subagent. Use Planner-Owned Code Delivery with the harness as executor. The harness owns bounded implementation, not branch, commit, review, or closeout ownership.

## Planner-Owned Nonpersistent Fallback

Use this when the task fails the direct gate, no native harness is available, and Agent Deck is not justified. The planner is the executor under Planner-Owned Code Delivery; create no worker session or Waypost task.

## Planner-Owned Code Delivery

Use this after direct, harness, or planner-owned fallback selection. The planner owns the task branch, delivery commit, review, and closeout.

1. use the already-prepared workspace from `Execution Flow`; never commit on detached `HEAD`
2. create an explicit `task_branch` from `integration_branch`
   - default: `task/<plan_id>-<short-slug>` or `task/<task_id>`
   - `task_branch` must differ from `integration_branch`
   - reuse an existing `task_branch` only when it is clearly the same unfinished task
3. run the selected executor:
   - planner: make the change in `worker_workspace`
   - harness: give it the recorded task branch, workspace, objective, and acceptance criteria; it may edit and validate, but must not switch branches or commit. Do not alter the shared workspace until it returns.
4. if a harness ran, confirm the recorded `task_branch` is still checked out
5. verify the result with the narrowest meaningful checks
6. stage and commit the task change without asking the user for routine commit confirmation
7. if `Per-task review: required`:
   - run `review-request` with `requester_role = planner`, `review_lane = task`, `closeout_contract = workspace-v2`, the recorded branch plan, workspace handoff (`worker_workspace`, `task_dir = worker_workspace`, `workspace_lifecycle = shared; cleanup=none`), and the delivery commit or task branch as scope
   - let `review-request` create or reuse the reviewer on demand with `parent_session_id = <planner_session_id>` and the planner session group, including empty string for root
   - after `review-request` sends the request, follow the shared Async sender rule
   - when a later inbound reviewer acceptance produces `closeout_delivered`, handle it with `planner-closeout` before marking the task done
8. if `Per-task review: skip`, run workspace prepare for this planner-owned task, then run `planner-closeout-batch.sh` directly with the recorded `task_branch`, `integration_branch`, `worker_workspace`, `planner_workspace`, `task_id`, and task dir before marking the task done; a persistent Waypost coder instead returns `code_delivery_complete` for `planner-closeout`
9. record the result under `Tasks Completed`

Planner-owned git writes, commits, review requests, and closeout are workflow-authorized for either executor.
Ask the user only for real scope/tradeoff decisions, explicit human gates, dirty-worktree conflicts, or branch ownership blockers.

## Decision Rules

- `delegate-task` Selection-Only Use owns execution-surface selection; `delegate-code-task` owns dispatch and lifecycle for persistent Waypost Agent Deck code work
- understanding the implementation does not by itself authorize direct implementation
- if code fails the direct gate, use a harness when available; use Agent Deck only for an independent lifecycle/user-interaction reason; otherwise use Planner-Owned Nonpersistent Fallback
- use direct planner implementation only after `delegate-task` Selection-Only Use selects local execution; for this path, planner still implements in the prepared `worker_workspace`
- native harness code work uses Planner-Owned Code Delivery; the planner retains branch, commit, review, and closeout ownership
- planner-owned nonpersistent fallback creates no worker/session; it uses the same delivery lifecycle
- use an Agent Deck code task when durable history, explicit session/workspace control, or user-visible and intervenable execution justifies it; otherwise prefer the lighter selected surface
- keep the decomposition local to this planner; supervisor assigns the goal, not the internal task breakdown
- do not treat completed implementation, review, or closeout as plan completion; the plan completes only after `plan_report_delivered` is successfully sent to supervisor
- if user input is needed for scope, priority, or tradeoff, ask the user directly and stop
- do not rely on `.agent-artifacts/planner-workspace.json` as a cross-task lock; each task that can reach closeout must prepare its own reservation first
- do not ask for routine confirmation before planner-owned branch, commit, review-request, closeout, or final-report actions

## Final Report Template

```markdown
Task: <plan_id>
Action: plan_report_delivered
From: planner <planner_session_id>
To: supervisor <supervisor_session_id>
Planner: <planner_session_id>
Round: final

## Summary
[Completed / blocked summary]

## Goal Status
- Outcome: [completed | blocked]
- Integration branch: [integration_branch]

## Tasks Completed
- <task_id or planner-defined step>: [result]

## Review Summary
- Per-task review policy used: [required | skip]
- Final integration review: [required | skip]
- Final review result: [not run | approved | needs follow-up]

## Open Items
- [item or `None`]
```

## Rules

- keep plan execution serial inside this workspace
- own the internal breakdown needed to complete the goal; do not ask supervisor to pre-split ordinary implementation tasks
- keep `worker_workspace` and `planner_workspace` equal for the full dispatched plan; do not introduce a second workspace
- preserve the workspace `integration_branch` for the full plan unless the user explicitly changes it
- treat `integration_branch` as the planner-owned branch prepared for this dispatched plan; do not reinterpret it as the supervisor landing branch and do not silently jump onto some older leftover branch
- run workspace prepare before each task that may later require closeout; treat the resulting detached-HEAD state in `worker_workspace` as authoritative until an explicit task branch is attached
- do not infer a task start point from current `HEAD`; use the explicit `integration_branch` from workflow context instead
- when self-implementing on the direct-work path, attach a real task branch from `integration_branch` before committing
- treat workspace prep as an early closeout viability gate too: if another worktree already holds `integration_branch` and planner closeout later needs to attach it here, stop immediately instead of letting the plan fail only at final closeout
- keep the planner workspace record aligned with the current planner session; if the workspace-prep script reports a live-session mismatch, stop instead of reusing the workspace
- pass `--override-workspaces` only after explicit user confirmation to replace the mirrored `planner-workspace.json` records
- do not run ad hoc workspace record cleanup; closeout helpers own release and `prepare-workspaces.sh --release-workspaces` is only for explicit script-reported cleanup recovery
- do not naturally end after the last task if the final report to supervisor is still pending
- if this turn owns a claimed `execute_plan` delivery, complete the final report and the delivery lifecycle step before ending
