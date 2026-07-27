---
name: planner-closeout
description: Handles accepted-review and coder completion/blocker handoffs; runs workspace closeout with a complete handoff.
---

# Planner Closeout

Handle accepted-review `closeout_delivered` or coder `code_delivery_complete`.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Input

Provide the message body from `closeout_delivered` or `code_delivery_complete`.
Use this skill only after that terminal handoff is actually received.

## Agent Deck Mode

Use the `agent-deck-workflow` skill for shared protocol:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> message body -> ask
- `planner_session_id`: explicit -> message body `To` / `Planner` header -> current session id -> ask
- `worker_workspace`, `planner_workspace`, `task_dir`, `workspace_lifecycle` (completed workspace-closeout): message body -> ask
- `reviewer_session_id` (review-backed closeout only): explicit -> message body `Accepted Review By` header -> omit
- `start_branch`, `integration_branch`, `task_branch` (workspace-closeout only): explicit -> message body -> ask
- blocked `code_delivery_complete`: require task/planner identity; use other supplied fields only
- `delivery_id` (optional): explicit leased delivery context -> omit when unavailable
- `lease_token` (optional): explicit leased delivery context -> omit when unavailable

Action and Handoff gate:
- `closeout_delivered` / completed `code_delivery_complete`: require a complete Handoff and recorded branch plan
- completed `code_delivery_complete` requires `Per-task review: skip`; blocked accepts `required | skip` and needs no Handoff
- for workspace-closeout delivery, reject a missing or partial Handoff; do not recover or downgrade it

Branch-plan rule with a Handoff:
- `integration_branch` is the existing non-task branch that receives the completed task; `task_branch` is the completed task line named by the recorded plan
- use the recorded branch plan from the terminal handoff unchanged
- do not infer, rename, or repair branch plan during planner closeout
- if recorded `integration_branch` looks like `task/*`, stop and ask for the real integration branch before running closeout
- if any required branch-plan or workspace-handoff field is missing, ask one short clarification question instead of guessing

## Execution Flow

1. parse `Action:` and `Outcome` for code delivery before applying Handoff gates
2. for `closeout_delivered`, inspect `Residual Follow-up For Planner` and `UI Manual Confirmation Package`; for `code_delivery_complete`, inspect `Outcome` and `Checks`
3. for a completed workspace-closeout delivery, run the planner closeout batch with the recorded branch plan; for a blocked code delivery, retain workspace/lock state, report the blocker, and ack the claimed delivery without batch closeout
4. if this turn started from a claimed completed workspace-closeout delivery, pass `--ack-delivery-id` and `--ack-lease-token`; the batch ACK covers delivery merge/progress, not post-closeout cleanup
5. attempt recorded temporary-worktree cleanup after batch; report its status without reopening delivery
6. report the result after planner closeout finishes

Required closeout command shape:

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh \
  --task-id <task_id> \
  --task-branch <task_branch> \
  --integration-branch <integration_branch> \
  --worker-workspace <worker_workspace> \
  --planner-workspace <planner_workspace> \
  --task-dir <task_dir> \
  --planner-session-id <planner_session_id>
```

Optional command additions:
- add `--reviewer-session-id <reviewer_session_id>` for `closeout_delivered`; omit it for `code_delivery_complete`
- add `--ack-delivery-id <delivery_id> --ack-lease-token <lease_token>` when handling a claimed workspace-closeout delivery
- add `--override-planner-workspace` only after explicit user confirmation to replace the mirrored `planner-workspace.json` records

## Rules

- this skill is the planner-side runtime handler for `closeout_delivered` and `code_delivery_complete`
- completed workspace terminal messages need a complete Handoff and Branch Plan; do not recover missing fields
- accept completed `code_delivery_complete` only with `Per-task review: skip`; accept blocked delivery under either policy. Do not route either through `review-closeout` or invent an accepted review
- run batch closeout for `code_delivery_complete` only when its `Outcome` is completed; a blocked outcome is a planner blocker, not a merge or cleanup request
- for a blocked code delivery, retain the active task, branch, workspace, and sessions; report the blocker and ack without requesting missing Handoff data
- use the terminal body as the primary planner handoff; reread the full review only when a review-backed handoff is insufficient
- coder/reviewer execution is asynchronous and may take unbounded time; this skill starts only after the closeout message actually arrives
- do not start planner closeout speculatively while coder or reviewer work is still in progress
- run the planner closeout script for `closeout_delivered` and completed `code_delivery_complete` only
- for `temporary; cleanup=planner`, require a complete Handoff, then require `task_dir` and `worker_workspace` to resolve to the same path before batch or cleanup; otherwise retain both paths and report the mismatch
- for `temporary; cleanup=planner`, after batch success, try to remove or rehome sessions using `task_dir`; remove the listed non-primary worktree only when none remains. Report `cleanup=complete` on success; otherwise retain it and report `cleanup=pending`. This best-effort cleanup does not delay, reopen, or replay delivery.
- after planner closeout, later tasks in the same workflow must run workspace prepare again before their own closeout path
- do not dispatch another planner lane into the same workspace merely because the reservation record was released; let the supervisor/dispatcher schedule lanes
- if the shared workspace still shows active coder changes when closeout starts, stop and report the blocker instead of altering workspace state around those changes
- if planner closeout fails, report the blocker and the exact manual action from the script output
- keep message JSON internal unless the user explicitly asks
- do not end until batch succeeds or a concrete blocker is reported; report temporary cleanup as `complete` or `pending`

## User-Facing Output

After terminal handling:
- for workspace-closeout, report required-action result, recorded branch pair, ack state, lifecycle/cleanup status, and any unblock step
- for a blocked code delivery, report the blocker, retained task state, and ack state; no merge or cleanup ran
