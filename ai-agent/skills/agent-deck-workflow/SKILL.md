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

## Dispatch Transport (Required)

Dispatch must be explicit-parameter based. Do not depend on `agent-deck session current` inference.

Priority order:

1. Prefer MCP tool `dispatch_control_message` from `agent-deck-workflow-mcp` (`ai-agent/mcp/agent-deck-workflow-mcp/server.mjs`).
2. Fallback to skill-local helper script only when MCP is unavailable:
   - `scripts/dispatch-control-message.sh`

Fallback script path rules:

1. Resolve script path relative to this skill directory.
2. Never assume project-root `scripts/...` path.
3. If skill directory cannot be resolved, stop and ask user to attach/install this skill.
4. Invoke the script directly (for example `"<skill_dir>/scripts/dispatch-control-message.sh" ...`), not via temporary shell variable wrappers.
5. When escalation approval is required, prefer a stable script-path prefix approval so future dispatches do not re-prompt every time.
6. For escalated dispatch execution, request approval with `prefix_rule` set to the script path only (for example `["<agent_deck_workflow_skill_dir>/scripts/dispatch-control-message.sh"]`), not the full command with task-specific args.
7. Validation check: in the approval dialog, reusable approval option must match script-path prefix. If it shows full task-specific command, cancel and retry with correct `prefix_rule`.

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
3. Plan and dispatch next task if needed.

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
