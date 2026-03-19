# Agent Deck Control Messages (Semantic Guide)

This file documents message semantics for workflow behavior.

For full JSON payload templates (internal protocol appendix), see:
- `references/internal-protocol/control-message-json-protocol.md`

## Message Envelope

Every workflow message carries these semantics:
- precondition gate (`preconditions.must_fully_load_skills`)
- execution intent (`execution.action`, `execution.artifact_path`, optional `execution.note`)
- workflow context (`context.task_id`, `context.round`, `context.planner_session_id`, `context.from_session_id`, `context.to_session_id`)
- optional policy override (`context.workflow_policy`)
- optional fallback requirements (`context.special_requirements`)

`preconditions.must_fully_load_skills` must include `agent-deck-workflow` for workflow control messages.
For reviewer-facing actions (especially `review_requested`), `execution.note` should explicitly direct receiver to follow `agent-deck-workflow/SKILL.md` control-message instructions before dispatching follow-up actions.

## Sender Invariants

- `execute_delegate_task`: sender is planner (`context.from_session_id = context.planner_session_id`)
- `review_requested`: sender is executor
- `rework_required`: sender is reviewer
- `user_requested_iteration`: sender is reviewer
- `closeout_delivered`: sender is reviewer

## Action Semantics

- `execute_delegate_task`: planner starts delegated implementation. Delegate artifact must already record `integration_branch` and `task_branch`. Executor must implement on the recorded `task_branch`, creating it from the recorded `integration_branch` only when that branch does not already exist.
- `review_requested`: executor asks reviewer to run full review.
- `rework_required`: reviewer blocks and returns must-fix findings. Findings are advisory input for executor, not automatic commands; executor should apply them critically and may explain disagreement in the next review request.
- `stop_recommended`: reviewer reports no must-fix items and asks user to choose closeout vs next iteration.
- `user_requested_iteration`: reviewer forwards user's iteration decision to executor.
- `closeout_delivered`: reviewer sends closeout artifact to planner after acceptance. Planner then runs `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh` for required closeout actions, normally with explicit recorded `--task-branch` and `--integration-branch`. When planner passes `--integration-branch`, the script may switch to that branch before merge if the worktree is safe.

## Policy Propagation

If `context.workflow_policy` exists, executor/reviewer preserve it unchanged for the same `task_id`.
If `context.special_requirements` exists, planner/executor/reviewer preserve it unchanged for the same `task_id`.
If executor and reviewer cannot converge on review findings, either role may stop and ask user for a decision.

## Same-Session Role Overlap

Roles are task-scoped. Default mapping is one distinct session per role.
If workflow context explicitly assigns both reviewer and planner roles to the same session, `closeout_delivered` may target the same session id as an explicit exception.
Dispatch should be skipped only when the target session is also the current session (local continuation).

## User-Facing Rule

Control payload is internal transport data.
Default user output should be human-readable decision summaries plus artifact paths.

Planner closeout ordering rule:
- required actions (`merge`, `progress update`) are hard requirements
- optional actions (`notify`, `next-task dispatch`) are best-effort and must not block required completion
- do not assume task mainline means `main`/`master`; reuse the recorded branch plan from delegate start
- planner should not run separate git state-changing commands in parallel with `planner-closeout-batch.sh`
