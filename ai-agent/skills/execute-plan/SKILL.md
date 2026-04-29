---
name: execute-plan
description: Execute one supervisor-assigned goal inside one workspace, decompose it locally, drive resulting tasks to completion serially, and send one final report back to the supervisor.
---

# Execute Plan

Execute one supervisor-provided goal inside one workspace.
This session owns one planner lane.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide the mailbox body from `execute_plan`.

## Core Model

- this planner lane is one supervisor-dispatched planner run with its own planner session, workspace contract, integration branch, and cleanup lifecycle
- this planner owns one workspace
- this planner lane uses one workspace only
- planner default role is coordinator, not coder
- this planner owns task decomposition inside that workspace
- tasks inside that workspace execute serially
- the planner should auto-advance whenever the next step is clear
- if a blocker cannot be resolved locally, stop and ask the user directly
- do not send routine blocker mail to supervisor
- planner should default code-changing work to `delegate-task`; direct planner implementation is the fallback only when that skill's own decision gate says delegation is not justified
- code-changing tasks are complete only after commit, any required review, closeout merge, and progress recording
- claiming `execute_plan` does not require planner to implement code personally; dispatch, review, closeout, and final report still count as completing the workflow
- planner is not done when implementation is done; planner is done only after one final `plan_report_delivered` message is successfully sent to supervisor

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `plan_id`: explicit -> mailbox body -> ask
- `supervisor_session_id`: explicit -> mailbox body `From` header -> ask
- `planner_session_id`: explicit -> mailbox body `To` / `Planner` header -> current session id -> ask
- `workspace`: explicit -> mailbox body `Workspace path` -> ask
- `planner_workspace`: derive internally from `workspace`
- `worker_workspace`: derive internally from `workspace`
- `integration_branch`: explicit -> mailbox body -> ask
  - this is the already-created planner-owned branch for this dispatched plan, not the supervisor landing branch
- `per_task_review`: explicit -> mailbox body -> default `required`
- `final_review`: explicit -> mailbox body -> default `skip`

## Execution Flow

1. read the goal, workspace contract, and review policy from the mailbox body
   - set internal `planner_workspace = workspace` and `worker_workspace = workspace`
2. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-workspaces.sh --worker-workspace <worker_workspace> --planner-workspace <planner_workspace> --integration-branch <integration_branch> --planner-session-id <planner_session_id> --supervisor-session-id <supervisor_session_id>`
3. decompose the goal into the smallest reasonable serial task sequence for this workspace
4. execute that task sequence serially
5. for each implementation task:
   - start with `delegate-task` and apply its own decision gate for whether delegation is justified
   - if `delegate-task` says delegation is justified, send the task and pass the chosen `Per-task review` policy into the delegate brief
   - if `delegate-task` says the work should be done directly, planner may use `Direct Planner Implementation`
6. do not proactively wait for coder/reviewer/architect progress; if no immediate local step remains, stop and resume on the next mailbox wake
7. when the goal is complete:
   - if `Final integration review: required`, run `review-request` against the planner-owned integration branch with `requester_role = planner` and `review_lane = integration_final`
   - if that final review returns serious issues, decide whether to fix locally or spawn a new task; prefer a new task for non-trivial fixes
8. send one final `plan_report_delivered` message to supervisor; do not treat the plan as complete before this mailbox send succeeds
9. after the final report is sent, if no more tasks remain in this workspace, run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-workspaces.sh --worker-workspace <worker_workspace> --planner-workspace <planner_workspace> --planner-session-id <planner_session_id> --release-workspaces`

## Direct Planner Implementation

Use this only after checking `delegate-task` and concluding, per that skill's own rules, that delegation is not justified and the work should be done directly.
Direct planner implementation is allowed only when all of the following hold:
- single local change
- no new cross-module behavior
- no schema, registry, or runtime contract change
- no new first-class model or state field
- no meaningful design choice remains
- narrow verification is sufficient
- delegation would be pure coordination overhead

If any item is uncertain, delegate instead.
Once code is edited, planner is also coder for that task.

Required sequence:
1. use the already-prepared workspace from `Execution Flow`; never commit on detached `HEAD`
2. create an explicit `task_branch` from `integration_branch`
   - default: `task/<plan_id>-<short-slug>` or `task/<task_id>`
   - `task_branch` must differ from `integration_branch`
   - reuse an existing `task_branch` only when it is clearly the same unfinished direct task
3. make the change in `worker_workspace`
4. verify the change with the narrowest meaningful checks
5. stage and commit the task change without asking the user for routine commit confirmation
6. if `Per-task review: required`:
   - run `review-request` with `requester_role = planner`, `review_lane = task`, the recorded branch plan, and the delivery commit or task branch as scope
   - let `review-request` create or reuse the reviewer on demand with `parent_session_id = <planner_session_id>`
   - after reviewer acceptance, handle the resulting `closeout_delivered` with `planner-closeout` before marking the task done
7. if `Per-task review: skip`, run `planner-closeout-batch.sh` directly with the recorded `task_branch`, `integration_branch`, `worker_workspace`, `planner_workspace`, `task_id`, and task dir before marking the task done
8. record the result under `Tasks Completed`

Direct-task git writes, commits, review requests, and closeout are workflow-authorized on this direct-work path.
Ask the user only for real scope/tradeoff decisions, explicit human gates, dirty-worktree conflicts, or branch ownership blockers.

## Decision Rules

- `delegate-task` owns the delegate-vs-direct decision rule for code-changing tasks; do not invent a second local classifier here
- understanding the implementation does not by itself authorize direct implementation
- use direct planner implementation only after `delegate-task` indicates the work should be done directly; for this path, planner still implements in the prepared `worker_workspace`
- prefer a new delegated task when the fix is substantial, touches multiple components, or would benefit from a focused coder
- keep the decomposition local to this planner; supervisor assigns the goal, not the internal task breakdown
- do not treat completed implementation, review, or closeout as plan completion; the plan completes only after `plan_report_delivered` is successfully sent to supervisor
- if user input is needed for scope, priority, or tradeoff, ask the user directly and stop
- when all current tasks in this workspace are complete and the final report is delivered, release `.agent-artifacts/planner-workspace.json`
- use `prepare-workspaces.sh --release-workspaces` for that release; do not delete the record files ad hoc
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
- run workspace prepare once at the start of plan execution; treat the resulting detached-HEAD state in `worker_workspace` as authoritative until an explicit task branch is attached
- do not infer a task start point from current `HEAD`; use the explicit `integration_branch` from workflow context instead
- when self-implementing on the direct-work path, attach a real task branch from `integration_branch` before committing
- treat workspace prep as an early closeout viability gate too: if another worktree already holds `integration_branch` and planner closeout later needs to attach it here, stop immediately instead of letting the plan fail only at final closeout
- keep the planner workspace record aligned with the current planner session; if the workspace-prep script reports a live-session mismatch, stop instead of reusing the workspace
- pass `--override-workspaces` only after explicit user confirmation to replace the mirrored `planner-workspace.json` records
- after the planner has no remaining work in this workspace, release the workspace records with `prepare-workspaces.sh --release-workspaces`
- do not naturally end after the last task if the final report to supervisor is still pending
- if this turn owns a claimed `execute_plan` delivery, complete the final report and the delivery lifecycle step before ending
