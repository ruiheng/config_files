# Agent Deck Message Templates (JSON)

Use these templates for short `agent-deck session send` control messages.
Keep large content in files and send only file pointers.

## Schema

All messages should follow this JSON shape:

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<source_session_id>",
  "to_session_id": "<target_session_id>",
  "round": "<number_or_final>",
  "action": "<action_name>",
  "artifact_path": "<path_or_empty>",
  "note": "<short_instruction_or_summary>"
}
```

Field rules:

- `schema_version`: protocol version, currently `1.0`
- `task_id`: stable id (`YYYYMMDD-HHMM-<slug>`)
- `planner_session_id`: required, must be preserved across all rounds/messages
- `required_skills`: required list of skills receiver must load before acting; include `agent-deck-workflow` for workflow control messages
- `round`: integer for loop rounds; use `"final"` for closeout
- `action`: machine-friendly snake_case verb phrase
- `artifact_path`: required when a file is the source of truth; empty string only when not applicable

## Planner -> Executor (Task Start)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<planner_session_id>",
  "to_session_id": "<executor_session_id>",
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
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<executor_session_id>",
  "to_session_id": "<reviewer_session_id>",
  "round": "<n>",
  "action": "review_requested",
  "artifact_path": ".agent-artifacts/<task_id>/review-request-r<n>.md",
  "note": "Read the review-request file and produce a full review report. Then proactively send the next control message. If must-fix issues remain, send rework guidance to executor. If no must-fix remains, recommend stop and wait for user confirmation."
}
```

## Reviewer -> Executor (Rework Needed)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<reviewer_session_id>",
  "to_session_id": "<executor_session_id>",
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
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<reviewer_session_id>",
  "to_session_id": "user",
  "round": "<n>",
  "action": "stop_recommended",
  "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
  "note": "Stop condition met (no must-fix / iteration cap / stalled progress). Please confirm whether to accept and proceed to closeout."
}
```

Usage note:

- This is primarily a user-facing decision payload.
- In many setups, reviewer should present a readable summary to user and wait; no cross-session dispatch is required at this step.

## Reviewer -> Executor (User Requests Another Iteration)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<reviewer_session_id>",
  "to_session_id": "<executor_session_id>",
  "round": "<n>",
  "action": "user_requested_iteration",
  "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
  "note": "User requested another implementation iteration. Address requested follow-ups and submit a new review request."
}
```

## Reviewer -> Planner (After User Acceptance)

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session_id": "<planner_session_id>",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "<reviewer_session_id>",
  "to_session_id": "<planner_session_id>",
  "round": "final",
  "action": "closeout_delivered",
  "artifact_path": ".agent-artifacts/<task_id>/closeout-<task_id>.md",
  "note": "Task review loop is complete after user confirmation. Planner should complete required closeout actions: merge task branch and update progress records. Planning next task is optional."
}
```

Protocol note:

- `planner_session_id` is immutable for one `task_id`.
- Executor and reviewer must carry forward the same `planner_session_id` value in every round.
- After `review_requested` is dispatched, executor should wait; reviewer must proactively send the next control message.
- Self-handoff guard: if reviewer detects `planner_session_id` equals current session id, do not dispatch `closeout_delivered`; stop and wait for user instruction.
