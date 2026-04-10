---
name: dispatch-plan
description: Send an `execute_plan` workflow message to a planner that should complete one supervisor-assigned goal inside one workspace and report back to a supervisor.
---

# Dispatch Plan

Send one supervisor-assigned goal to a planner session.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Inputs

- `plan_id`
- `supervisor_session_id`
- `planner_session_ref` or `planner_session_id`
- `planner_workspace`
- `integration_branch` (required, explicit; do not infer)
- `goal`
- optional `planner_tool`
- optional `planner_group_name`
- optional `per_task_review`
- optional `final_review`
- optional `summary`
- optional `special_requirements`

## Rules

- this dispatch targets one planner in one workspace
- that planner owns task decomposition and must execute resulting tasks serially inside its workspace
- `integration_branch` must be provided explicitly; do not infer it from the worktree path, current branch, or repo metadata
- default `per_task_review = required`
- default `final_review = skip`
- blockers stop with a user question; do not add blocker mail to supervisor
- planner reports back only after the assigned goal is complete or blocked
- normal path is direct execution: resolve required inputs, run the planner-session helper, then send the mailbox body
- do not inspect `--help`, environment variables, or repo docs first unless the helper or send step actually fails

## Mailbox Body Template

```markdown
Task: <plan_id>
Action: execute_plan
From: supervisor <supervisor_session_id>
To: planner {{TO_SESSION_ID}}
Planner: {{TO_SESSION_ID}}
Round: 1

## Summary
[One-line plan summary]

## Goal
[What this planner must finish in this workspace]

## Workspace Contract
- Workspace path: [planner_workspace]
- Integration branch: [integration_branch]
- Execution model: planner-owned decomposition; serial tasks in one workspace
- Completion rule: finish the assigned goal, then report back to supervisor

## Review Policy
- Per-task review: [required | skip]
- Final integration review: [required | skip]

## Planning Contract
- Planner owns task decomposition and sequencing inside this workspace
- Keep task execution serial in this workspace
- Ask the user directly if the goal cannot be completed without a real scope or tradeoff decision

## Special Requirements
[only when present]
```

## Mailbox Send

1. use `agent_mailbox`
2. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/ensure-supervised-planner-session.sh --planner-session-ref <planner_session_ref> --planner-cmd <planner_tool> --planner-workspace <planner_workspace>`
   - add `--planner-group-name <planner_group_name>` when the plan already names a specific subgroup
3. use the returned `session_id` as the authoritative `planner_session_id`
4. fill `{{TO_SESSION_ID}}`
5. send with:
   - `from_address = agent-deck/<supervisor_session_id>`
   - `to_address = agent-deck/<planner_session_id>`
   - `subject = "plan dispatch: <plan_id>"`
   - `body = <execute-plan mailbox body>`

Rules:
- use the supervisor-side planner-session helper instead of creating planner sessions with direct parent-child wiring
- planner subgroup placement is part of the session helper, not part of mailbox transport
- treat the planner-session helper as a synchronous step; wait for it to return before composing or sending mailbox content
