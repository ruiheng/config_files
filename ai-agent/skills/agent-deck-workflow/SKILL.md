---
name: agent-deck-workflow
description: Human-led planner/executor/reviewer workflow protocol on top of agent-deck. Use for role handoff rules, control-message semantics, review-loop branching, and closeout policy.
---

# Agent Deck Workflow

Use this skill for the three-role workflow protocol (planner, executor, reviewer).

For generic `agent-deck` CLI/TUI operations, troubleshooting, and full command reference, use the official `agent-deck` skill.

## Scope

- Workflow shape: one long-lived `planner`, per-task `executor` + `reviewer`.
- Runtime shape: single shared workspace.
- Governance: human-led; user confirmation gates are mandatory at stop/closeout points.
- Git approval exception: in delegated executor flow, task-scoped executor commits are allowed without per-commit user approval; this workflow rule overrides generic git-approval defaults.

## Execution Environment (Required)

All `agent-deck` commands in this workflow must run outside sandbox (host shell with real tmux/session context).

## Skill-Local Script Dependency (Required)

This workflow uses skill-local helper script:

- `scripts/dispatch-control-message.sh`

Path rules:

1. Resolve script path relative to this skill directory.
2. Never assume project-root `scripts/...` path.
3. If skill directory cannot be resolved, stop and ask user to attach/install this skill.

## Relationship with Official Skill

- Official `agent-deck` skill: generic command manual and operational reference.
- This `agent-deck-workflow` skill: role protocol, branching rules, and message contract for this project.
- If both skills are present, prefer this skill for workflow decisions and official skill for generic command lookup.

## Task Metadata Convention

Use stable task id:

`task_id = YYYYMMDD-HHMM-<slug>`

Resource naming:

- Executor session: `executor-<task_id>`
- Reviewer session: `reviewer-<task_id>`
- Branch: `task/<task_id>`
- Artifacts root: `.agent-artifacts/<task_id>/`

## Control Message Contract

Use JSON control messages for agent-to-agent communication.

- Message templates: `references/message-templates.md`
- JSON is internal protocol data by default.
- Do not print raw control JSON in user-facing output unless user explicitly asks for payload.

## Role Inference (Allowed)

Role inference is valid in this workflow and should be used when explicit role assignment is absent.

Role inference priority:
1. explicit user instruction
2. control-message `action` + `to_session_id`
3. task context/artifact path/branch convention (`task/<task_id>`)
4. currently invoked workflow skill

Role is task-scoped, not agent-scoped. One agent may switch roles across tasks (or even within one task) when workflow signals are consistent.
If role signals conflict, stop and ask one short clarification question before acting.

## Human-Led Three-Role Flow

### 1) Planner Starts Task

- Planner prepares delegate artifact.
- Planner dispatches `execute_delegate_task` to executor.

### 2) Executor Implements and Requests Review

- Executor performs implementation and first delivery commit.
- In delegated execution, executor task-scoped git writes (branch create/switch, stage, commit) do not require per-commit user approval.
- Executor dispatches `review_requested` to reviewer.
- After dispatch, executor enters waiting state.
- Executor must not proactively poll reviewer output unless user explicitly asks.

### 3) Reviewer Loop

Reviewer evaluates and chooses one of two outcomes:

1. `rework_required`
- Dispatch to executor.
- Executor resumes implementation and later sends next review request.

2. `stop_recommended`
- Provide user-friendly summary (not raw JSON) and wait for user decision.
- No automatic dispatch to executor in this step.

User decision branches after `stop_recommended`:

1. User chooses closeout.
- Reviewer runs `review-closeout` and dispatches `closeout_delivered` to planner.

2. User chooses another iteration.
- Reviewer dispatches `user_requested_iteration` to executor.

### 4) Planner Closeout Batch (After User Confirmation)

Planner receives closeout but must wait for explicit user confirmation before finalizing.

Then perform one batch closeout step:

1. Merge `task/<task_id>` into integration branch (follow repo/user policy).
2. Record progress (status, merged branch, residual concerns).
3. Optional hygiene: prune stale task branches with keep-N policy:
   - `ai-agent/skills/agent-deck-workflow/scripts/prune-task-branches.sh --keep <N>` (preview)
   - `ai-agent/skills/agent-deck-workflow/scripts/prune-task-branches.sh --keep <N> --apply` (execute)
   - Policy: keep newest N `task/` branches; for older ones, delete only if they are ancestors of current base (default `HEAD`).
4. Optionally plan and dispatch next task if needed.

## Role-Skill Mapping

- Planner: `delegate-task`, `handoff`
- Executor: `review-request`
- Reviewer: `review-code`, `review-closeout`

## Do / Do Not

Do:

- Keep long context file-based (`delegate-task`, `review-request`, `review-report`, `closeout`).
- Keep cross-session messages short and pointer-based.
- Keep human confirmation gates on stop/closeout.

Do not:

- Auto-merge before user confirmation.
- Send large report bodies inline via `session send`.
- Keep proactive polling loops after dispatch.
- Treat protocol JSON as default user-facing output.
