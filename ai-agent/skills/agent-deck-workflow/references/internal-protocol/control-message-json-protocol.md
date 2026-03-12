# Agent Deck Message Templates (JSON)

Use these templates for short `agent-deck session send` control messages.
Keep large content in files and send only file pointers.

## Schema

All messages should follow this JSON shape:

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "<action_name>",
    "artifact_path": "<path_or_empty>",
    "note": "<optional_short_instruction_or_summary>"
  },
  "context": {
    "task_id": "<task_id>",
    "round": "<number_or_final>",
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<source_session_id>",
    "to_session_id": "<target_session_id>",
    "workflow_policy": { "<optional_policy_fields>": "<optional_values>" },
    "special_requirements": "<optional_json_value>"
  }
}
```

Field rules:

- `preconditions.must_fully_load_skills`: required list of skills receiver must fully load before acting.
- `execution.action`: machine-friendly snake_case verb phrase.
- `execution.artifact_path`: required when a file is the source of truth; empty string only when not applicable.
- `execution.note`: optional short instruction; omit when not needed. When present, prefer explicit wording to follow `agent-deck-workflow/SKILL.md` control-message rules.
- `context.task_id`: stable id (`YYYYMMDD-HHMM-<slug>`).
- `context.round`: integer for loop rounds; use `"final"` for closeout.
- `context.planner_session_id`: required, immutable within one task.
- `context.from_session_id`: required, must be the real sender session id for this message.
- `context.to_session_id`: required target session id.
- `context.workflow_policy`: optional override object; include only when overriding default human-gated behavior.
  - UI override key (optional): `ui_manual_confirmation` with values `"auto" | "required" | "skip"`.
- `context.special_requirements`: optional free-form JSON value for user requirements not covered by structured fields; carry unchanged across all rounds and roles.

Sender invariants:
- `execute_delegate_task`: sender is planner (`context.from_session_id = context.planner_session_id`).
- `review_requested`: sender is executor.
- `rework_required` / `user_requested_iteration` / `closeout_delivered`: sender is reviewer.
- Never default sender to planner for non-planner actions.

## Planner -> Executor (Task Start)

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "execute_delegate_task",
    "artifact_path": ".agent-artifacts/<task_id>/delegate-task-<task_id>.md",
    "note": "You are the executor for this task. Fully load and follow agent-deck-workflow/SKILL.md, and follow executor behavior rather than reviewer or planner behavior. Read and follow the delegate task file. MUST create/switch to branch task/<task_id> before any code change (for example: git switch task/<task_id> || git switch -c task/<task_id>). If branch setup fails, stop and report. After first implementation pass, commit, prepare the review-request artifact, and dispatch review_requested to reviewer."
  },
  "context": {
    "task_id": "<task_id>",
    "round": 1,
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<planner_session_id>",
    "to_session_id": "<executor_session_id>"
  }
}
```

## Executor -> Reviewer (Review Request)

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "review_requested",
    "artifact_path": ".agent-artifacts/<task_id>/review-request-r<n>.md",
    "note": "You are the reviewer for this task. Fully load and follow agent-deck-workflow/SKILL.md (especially Control Message Contract + Reviewer Decision Flow), and follow reviewer behavior rather than executor or planner behavior. Read the review-request file and produce a full review report, then proactively dispatch the required follow-up control message via ~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh. If must-fix issues remain, send rework_required to executor; if no must-fix remains, present stop_recommended to user rather than planner, unless policy allows immediate closeout."
  },
  "context": {
    "task_id": "<task_id>",
    "round": "<n>",
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<executor_session_id>",
    "to_session_id": "<reviewer_session_id>"
  }
}
```

## Reviewer -> Executor (Rework Needed)

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "rework_required",
    "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
    "note": "Must-fix items remain. Evaluate the findings critically, apply the technically justified changes, and send an updated review request for the next round. If you disagree with specific findings, explain that disagreement and rationale clearly in the next review request. If convergence fails, stop and ask user for a decision."
  },
  "context": {
    "task_id": "<task_id>",
    "round": "<n>",
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<reviewer_session_id>",
    "to_session_id": "<executor_session_id>"
  }
}
```

## Reviewer -> User (Stop Recommendation)

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "stop_recommended",
    "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
    "note": "Stop condition met (no must-fix / iteration cap / stalled progress). Please confirm whether to accept and proceed to closeout."
  },
  "context": {
    "task_id": "<task_id>",
    "round": "<n>",
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<reviewer_session_id>",
    "to_session_id": "user"
  }
}
```

Usage note:

- This is primarily a user-facing decision payload.
- In many setups, reviewer should present a readable summary to user and wait; no cross-session dispatch is required at this step.

## Reviewer -> Executor (User Requests Another Iteration)

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "user_requested_iteration",
    "artifact_path": ".agent-artifacts/<task_id>/review-report-r<n>.md",
    "note": "User requested another implementation iteration. Address requested follow-ups and submit a new review request."
  },
  "context": {
    "task_id": "<task_id>",
    "round": "<n>",
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<reviewer_session_id>",
    "to_session_id": "<executor_session_id>"
  }
}
```

## Reviewer -> Planner (After User Acceptance)

```json
{
  "preconditions": {
    "must_fully_load_skills": ["agent-deck-workflow"]
  },
  "execution": {
    "action": "closeout_delivered",
    "artifact_path": ".agent-artifacts/<task_id>/closeout-<task_id>.md",
    "note": "Task review loop is complete after closeout acceptance (user or policy). Planner should run ~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh to complete required closeout actions. When --integration-branch is supplied, the script is expected to switch there before merge if the worktree is safe. Planning next task is optional."
  },
  "context": {
    "task_id": "<task_id>",
    "round": "final",
    "planner_session_id": "<planner_session_id>",
    "from_session_id": "<reviewer_session_id>",
    "to_session_id": "<planner_session_id>"
  }
}
```

Protocol note:

- `context.planner_session_id` is immutable for one `task_id`.
- Executor and reviewer must carry forward the same `context.planner_session_id` value in every round.
- If `context.workflow_policy` is present, carry it forward unchanged for the same `task_id`.
- If `context.special_requirements` is present, carry it forward unchanged for the same `task_id`.
- After `review_requested` is dispatched, executor should wait; reviewer must proactively send the next control message.
- Roles are task-scoped; if workflow context explicitly assigns both reviewer and planner roles to one session, `closeout_delivered` may target the same session id.
- Skip dispatch only when target session equals current session (local continuation); otherwise dispatch may proceed even if `context.from_session_id == context.to_session_id`.
- For UI-related tasks, reviewer should keep UI manual confirmation package in artifacts and closeout content for future re-check, regardless of whether current round already got human confirmation.
- Planner closeout ordering is strict: required actions (`merge`, `progress update`) must complete first; notification/next-task dispatch failures are optional and must not block required completion.
- Planner should not run separate git state-changing commands in parallel with `planner-closeout-batch.sh`; let the closeout script own integration-branch switching when `--integration-branch` is provided.
