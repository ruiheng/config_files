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
- `worker_workspace`
- `planner_workspace`
- `integration_branch` (planner-owned branch for this dispatched plan; must exist before send)
- `goal`
- optional `planner_tool`
- optional `per_task_review`
- optional `final_review`
- optional `summary`
- optional `special_requirements`

## Rules

- this dispatch targets one planner in one workspace
- that planner owns task decomposition and must execute resulting tasks serially inside its workspace
- when creating a new planner session and no planner title/ref is provided, use `planner-YYYYMMDD-HHMM-<slug>`; do not use bare `planner`
- `integration_branch` is the planner-owned branch for this dispatched plan, not the supervisor landing branch
- for a new plan dispatch, create a fresh `integration_branch` from the current supervisor branch before sending the mailbox body
- do not silently reuse an existing planner integration branch from an earlier run; reuse is allowed only when the user explicitly says this dispatch is resuming that same unfinished plan
- if the requested or derived `integration_branch` already exists and resume was not explicit, choose a new branch name or ask; do not dispatch onto an old branch tip
- create the planner integration branch without switching the supervisor worktree; use the current supervisor branch as the start-point
- if `planner_tool` is omitted, reuse the current session tool/command from agent-deck session metadata; do not infer it from environment variables
- default `per_task_review = required`
- default `final_review = skip`
- blockers stop with a user question; do not add blocker mail to supervisor
- planner reports back only after the assigned goal is complete or blocked
- normal path is direct execution: resolve required inputs, ensure the planner session through MCP, then send the mailbox body
- do not inspect `--help`, environment variables, or repo docs first unless the MCP ensure or send step actually fails

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
- Worker workspace: [worker_workspace]
- Workspace path: [planner_workspace]
- Integration branch: [integration_branch]
  Created by supervisor for this dispatched plan from the current supervisor branch; planner owns this branch for the full plan.
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

1. resolve the current supervisor branch; if the worktree is detached or the landing branch is unclear, stop and ask instead of guessing
2. resolve `planner_session_ref`; when creating a new planner and no existing ref/id is provided, generate `planner-YYYYMMDD-HHMM-<slug>` from the workspace or goal
3. resolve `integration_branch`
   - explicit branch name wins
   - otherwise derive a fresh planner-owned branch name from `plan_id`; prefer `plan/<plan_id>`
4. create the planner integration branch from the current supervisor branch before dispatch
   - do not switch the supervisor worktree onto that branch
   - if the preferred branch name already exists and resume was not explicit, choose a new unique suffix instead of reusing that ref
5. use `agent_mailbox`
6. call `agent_deck_ensure_session` for the planner target
   - identify target with `session_id` or `session_ref = <planner_session_ref>`
   - when creation may be needed, also pass:
     - `ensure_title = <planner_session_ref>`
     - `ensure_cmd = <planner_tool>`
     - `workdir = <planner_workspace>`
     - `parent_session_id = <supervisor_session_id>`
     - `no_parent_link = false`
7. use the returned `session_id` as the authoritative `planner_session_id`
8. fill `{{TO_SESSION_ID}}`
9. send with:
   - `from_address = agent-deck/<supervisor_session_id>`
   - `to_address = agent-deck/<planner_session_id>`
   - `subject = "plan dispatch: <plan_id>"`
   - `body = <execute-plan mailbox body>`

Rules:
- use `agent_deck_ensure_session`; do not create planner sessions through direct `agent-deck` CLI in the normal path
- treat MCP session ensure as a synchronous step; wait for it to return before composing or sending mailbox content
