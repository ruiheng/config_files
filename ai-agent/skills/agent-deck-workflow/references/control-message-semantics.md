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

- `execute_delegate_task`: planner starts delegated implementation. Executor must create/switch to `task/<task_id>` before any code change.
- `review_requested`: executor asks reviewer to run full review.
- `rework_required`: reviewer blocks and returns must-fix findings.
- `stop_recommended`: reviewer reports no must-fix items and asks user to choose closeout vs next iteration.
- `user_requested_iteration`: reviewer forwards user's iteration decision to executor.
- `closeout_delivered`: reviewer sends closeout artifact to planner after acceptance. Planner then runs `<agent_deck_workflow_skill_dir>/scripts/planner-closeout-batch.sh` for required closeout actions.

## Policy Propagation

If `context.workflow_policy` exists, executor/reviewer preserve it unchanged for the same `task_id`.
If `context.special_requirements` exists, planner/executor/reviewer preserve it unchanged for the same `task_id`.

## Same-Session Role Overlap

Roles are task-scoped. If workflow context explicitly assigns both reviewer and planner roles to the same session, `closeout_delivered` may target the same session id.
Dispatch should be skipped only when the target session is also the current session (local continuation).

## User-Facing Rule

Control payload is internal transport data.
Default user output should be human-readable decision summaries plus artifact paths.

Planner closeout ordering rule:
- required actions (`merge`, `progress update`) are hard requirements
- optional actions (`notify`, `next-task dispatch`) are best-effort and must not block required completion
