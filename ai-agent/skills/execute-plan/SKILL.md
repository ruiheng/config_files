---
name: execute-plan
description: Execute one supervisor-assigned goal inside one workspace, decompose it locally, drive resulting tasks to completion serially, and send one final report back to the supervisor.
---

# Execute Plan

Execute one supervisor-provided goal inside one workspace.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide the mailbox body from `execute_plan`.

## Core Model

- this planner owns one workspace
- this planner owns task decomposition inside that workspace
- tasks inside that workspace execute serially
- the planner should auto-advance whenever the next step is clear
- if a blocker cannot be resolved locally, stop and ask the user directly
- do not send routine blocker mail to supervisor
- after the full plan completes, send one `plan_report_delivered` message to supervisor

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `plan_id`: explicit -> mailbox body -> ask
- `supervisor_session_id`: explicit -> mailbox body `From` header -> ask
- `planner_session_id`: explicit -> mailbox body `To` / `Planner` header -> current session id -> ask
- `integration_branch`: explicit -> mailbox body -> ask
  - this is the already-created planner-owned branch for this dispatched plan, not the supervisor landing branch
- `per_task_review`: explicit -> mailbox body -> default `required`
- `final_review`: explicit -> mailbox body -> default `skip`

## Execution Flow

1. read the goal, workspace contract, and review policy from the mailbox body
2. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-planner-workspace.sh --integration-branch <integration_branch> --planner-session-id <planner_session_id> --supervisor-session-id <supervisor_session_id>`
3. decompose the goal into the smallest reasonable serial task sequence for this workspace
4. execute that task sequence serially
5. for each implementation task, use `delegate-task` and pass the chosen `Per-task review` policy into the delegate brief
6. do not proactively wait for coder/reviewer/architect progress; if no immediate local step remains, stop and resume on the next mailbox wake
7. when the goal is complete:
   - if `Final integration review: required`, run `review-request` against the planner-owned integration branch with `requester_role = planner` and `review_lane = integration_final`
   - if that final review returns serious issues, decide whether to fix locally or spawn a new task; prefer a new task for non-trivial fixes
8. read `planner_group` from `.agent-artifacts/planner-workspace.json` and send one final `plan_report_delivered` message to supervisor
9. after the final report is sent, if no more tasks remain in this workspace, run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-planner-workspace.sh --planner-session-id <planner_session_id> --release-planner-workspace`

## Decision Rules

- prefer local planner fixes only for small, isolated integration issues, and only after taking an explicit branch step; after workspace prep, the planner workspace is announced as detached HEAD, so current workspace git state is not a valid inferred start point for commits or task branches
- prefer a new delegated task when the fix is substantial, touches multiple components, or would benefit from a focused coder
- keep the decomposition local to this planner; supervisor assigns the goal, not the internal task breakdown
- if user input is needed for scope, priority, or tradeoff, ask the user directly and stop
- when all current tasks in this workspace are complete and the final report is delivered, release `.agent-artifacts/planner-workspace.json`
- use `prepare-planner-workspace.sh --release-planner-workspace` for that release; do not delete the file ad hoc

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
- Planner group: [planner_group]

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
- preserve the workspace `integration_branch` for the full plan unless the user explicitly changes it
- treat `integration_branch` as the planner-owned branch prepared for this dispatched plan; do not reinterpret it as the supervisor landing branch and do not silently jump onto some older leftover branch
- before doing planner work, prepare the workspace and make sure it is detached at the explicit `integration_branch` tip commit
- treat the prepare-script detached-head notice as authoritative: do not infer a task start point from current `HEAD`; use the explicit `integration_branch` from workflow context instead
- treat workspace prep as an early closeout viability gate too: if another worktree already holds `integration_branch` and planner closeout later needs to attach it here, stop immediately instead of letting the plan fail only at final closeout
- keep the planner workspace record aligned with the current planner session; if the workspace-prep script reports a live-session mismatch, stop instead of reusing the workspace
- pass `--override-planner-workspace` only after explicit user confirmation to replace `.agent-artifacts/planner-workspace.json`
- after the planner has no remaining work in this workspace, release the planner workspace record with `prepare-planner-workspace.sh --release-planner-workspace`
- do not naturally end after the last task if the final report to supervisor is still pending
