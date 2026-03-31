# Automation Policy

Default workflow behavior is human-gated.

Planner may include a per-task `workflow_policy`, for example:

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

## Rules

- if `workflow_policy` is absent, apply human-gated defaults
- if present, planner/coder/reviewer/architect must carry it forward unchanged for the same `task_id`
- if `special_requirements` is present, carry it forward unchanged for the same `task_id`
- safety checks and must-fix handling do not change
- unattended mode (`mode=unattended` or `auto_dispatch_next_task=true`) enables strict post-closeout health gate

## Review-Loop Thresholds

Default thresholds:
- `review_round_convergence_check_threshold = 3`
- `review_round_hard_stop_threshold = 5`

Threshold semantics:
- at or above `review_round_convergence_check_threshold`, reviewer should actively test whether the work is solving the wrong problem or preserving unnecessary self-imposed constraints
- at or above `review_round_hard_stop_threshold`, reviewer should stop routine iteration and escalate to the user

## UI Manual Confirmation

`ui_manual_confirmation` values:
- `auto`: detect likely UI impact heuristically
- `required`: always require manual UI confirmation in human-gated mode
- `skip`: skip manual UI confirmation requirement

## Planner Closeout

If `workflow_policy.auto_dispatch_next_task=true`, planner may auto-dispatch the next queued task after merge plus progress update.

When planner is dispatching from a known queue or batch:
- report queue progress before each new dispatch in `current/total` form
- if total is unknown, say so explicitly instead of fabricating a ratio
- this progress is planner-owned state; helper scripts must not invent it
