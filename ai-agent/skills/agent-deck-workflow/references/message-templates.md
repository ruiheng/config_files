# Agent Deck Control Messages (Semantic Guide)

This file documents message semantics for workflow behavior.

For full JSON payload templates (internal protocol appendix), see:
- `references/internal-protocol/message-templates.md`

## Message Envelope

Every workflow message carries these semantics:
- task identity (`task_id`)
- planner identity (`planner_session_id`, immutable within one task)
- sender/receiver identity (`from_session_id`, `to_session_id`)
- round marker (`round`, integer or `final`)
- action type (`action`)
- artifact pointer (`artifact_path`)
- optional note (`note`)
- optional policy override (`workflow_policy`)

`required_skills` should include `agent-deck-workflow` for workflow control messages.

## Sender Invariants

- `execute_delegate_task`: sender is planner (`from_session_id = planner_session_id`)
- `review_requested`: sender is executor
- `rework_required`: sender is reviewer
- `user_requested_iteration`: sender is reviewer
- `closeout_delivered`: sender is reviewer

## Action Semantics

- `execute_delegate_task`: planner starts delegated implementation.
- `review_requested`: executor asks reviewer to run full review.
- `rework_required`: reviewer blocks and returns must-fix findings.
- `stop_recommended`: reviewer reports no must-fix items and asks user to choose closeout vs next iteration.
- `user_requested_iteration`: reviewer forwards user's iteration decision to executor.
- `closeout_delivered`: reviewer sends closeout artifact to planner after acceptance. Planner then runs `scripts/planner-closeout-batch.sh` for required closeout actions.

## Policy Propagation

If `workflow_policy` exists, executor/reviewer preserve it unchanged for the same `task_id`.

## Same-Session Role Overlap

Roles are task-scoped. If workflow context explicitly assigns both reviewer and planner roles to the same session, `closeout_delivered` may target the same session id.
Dispatch should be skipped only when the target session is also the current session (local continuation).

## User-Facing Rule

Control payload is internal transport data.
Default user output should be human-readable decision summaries plus artifact paths.

Planner closeout ordering rule:
- required actions (`merge`, `progress update`) are hard requirements
- optional actions (`notify`, `next-task dispatch`) are best-effort and must not block required completion
