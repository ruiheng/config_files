# Agent Deck Message Templates (JSON)

Use these templates for short `agent-deck session send` control messages.
Keep large content in files and send only file pointers.

## Schema

All messages should follow this JSON shape:

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "<source_session>",
  "to_session": "<target_session>",
  "round": "<number_or_final>",
  "action": "<action_name>",
  "artifact_path": "<path_or_empty>",
  "note": "<short_instruction_or_summary>"
}
```

Field rules:

- `schema_version`: protocol version, currently `1.0`
- `task_id`: stable id (`YYYYMMDD-HHMM-<slug>`)
- `planner_session`: required, must be preserved across all rounds/messages
- `round`: integer for loop rounds; use `"final"` for closeout
- `action`: machine-friendly snake_case verb phrase
- `artifact_path`: required when a file is the source of truth; empty string only when not applicable

## Planner -> Executor (Task Start)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "<planner_session>",
  "to_session": "executor-<task_id>",
  "round": 1,
  "action": "execute_delegate_task",
  "artifact_path": ".agent-artifacts/<task_id>/delegate-task-<task_id>.md",
  "note": "Read and follow the delegate task file. Start implementation in branch task/<task_id>. After first implementation pass, commit and prepare review request."
}
```

## Executor -> Reviewer (Review Request)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "executor-<task_id>",
  "to_session": "reviewer-<task_id>",
  "round": "<n>",
  "action": "review_requested",
  "artifact_path": ".agent-artifacts/<task_id>/review-request-r<n>.md",
  "note": "Read the review-request file and produce a full review report. If must-fix issues remain, return actionable items. If no must-fix remains, recommend stop and wait for user confirmation."
}
```

## Reviewer -> Executor (Rework Needed)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "reviewer-<task_id>",
  "to_session": "executor-<task_id>",
  "round": "<n>",
  "action": "rework_required",
  "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
  "note": "Must-fix items remain. Address the issues in the report and send an updated review request for the next round."
}
```

## Reviewer -> User (Stop Recommendation)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "reviewer-<task_id>",
  "to_session": "user",
  "round": "<n>",
  "action": "stop_recommended",
  "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
  "note": "Stop condition met (no must-fix / iteration cap / stalled progress). Please confirm whether to accept and proceed to closeout."
}
```

## Reviewer -> Planner (After User Acceptance)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "reviewer-<task_id>",
  "to_session": "<planner_session>",
  "round": "final",
  "action": "closeout_delivered",
  "artifact_path": ".agent-artifacts/<task_id>/closeout-<task_id>.md",
  "note": "Task review loop is complete after user confirmation. Update planning records and schedule next task."
}
```

Protocol note:

- `planner_session` is immutable for one `task_id`.
- Executor and reviewer must carry forward the same `planner_session` value in every round.
