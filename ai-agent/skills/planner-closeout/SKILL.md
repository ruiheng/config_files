---
name: planner-closeout
description: Handles a `closeout_delivered` workflow message and completes planner-side closeout.
---

# Planner Closeout

Complete planner-side closeout from a `closeout_delivered` workflow message.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide the mailbox body from `closeout_delivered`.
Use this skill only after that closeout message is actually received.

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `planner_session_id`: explicit -> mailbox body `To` / `Planner` header -> current session id -> ask
- `reviewer_session_id`: explicit -> mailbox body `Accepted Review By` header -> ask
- `start_branch`: explicit -> mailbox body -> ask
- `integration_branch`: explicit -> mailbox body -> ask
- `task_branch`: explicit -> mailbox body -> ask
- `task_dir`: explicit -> mailbox body `Task dir` / `Worker dir` -> ask
- `delivery_id` (optional): explicit leased delivery context -> omit when unavailable
- `lease_token` (optional): explicit leased delivery context -> omit when unavailable

Branch-plan rule:
- `integration_branch` is the existing non-task branch that receives the completed task; `task_branch` is the completed task line named by the recorded plan
- use the recorded branch plan from `closeout_delivered` unchanged
- do not infer, rename, or repair branch plan during planner closeout
- if recorded `integration_branch` looks like `task/*`, stop and ask for the real integration branch before running closeout
- if any required branch-plan field, including `task_dir`, is missing, ask one short clarification question instead of guessing

## Execution Flow

1. resolve `task_id`, planner identity, and the recorded branch plan from the closeout message
2. inspect `Residual Follow-up For Planner` and `UI Manual Confirmation Package` before running planner closeout
3. run the planner closeout batch script with the recorded branch plan
4. if this turn started from a claimed `closeout_delivered` delivery, pass `--ack-delivery-id` and `--ack-lease-token` so the script can ack after required closeout state is written
5. report the result after planner closeout finishes

Required closeout command shape:

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh \
  --task-id <task_id> \
  --task-branch <task_branch> \
  --integration-branch <integration_branch> \
  --task-dir <task_dir> \
  --planner-session-id <planner_session_id>
```

Optional command additions:
- add `--ack-delivery-id <delivery_id> --ack-lease-token <lease_token>` when this turn owns a claimed `closeout_delivered` delivery
- add `--override-planner-workspace` only after explicit user confirmation to replace `.agent-artifacts/planner-workspace.json`

## Rules

- this skill is the planner-side runtime handler for `closeout_delivered`
- use the closeout body as the primary planner handoff; do not reread the full review unless the closeout body is insufficient
- coder/reviewer execution is asynchronous and may take unbounded time; this skill starts only after the closeout message actually arrives
- do not start planner closeout speculatively while coder or reviewer work is still in progress
- the planner closeout script owns required closeout actions, progress recording, and planner-side cleanup
- if the shared workspace still shows active coder changes when closeout starts, stop and report the blocker instead of altering workspace state around those changes
- if planner closeout fails, report the blocker and the exact manual action from the script output
- keep mailbox JSON internal unless the user explicitly asks
- do not naturally end after deciding what to do; this turn is complete only after planner closeout succeeds or a concrete blocker is reported

## User-Facing Output

After planner closeout:
- report whether required closeout actions succeeded
- include the recorded branch pair and task id
- include whether mailbox ack ran
- include any manual unblock step when closeout or cleanup failed
