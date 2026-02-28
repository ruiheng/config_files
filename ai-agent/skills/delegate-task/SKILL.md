---
name: delegate-task
description: Analyze a task and create a delegate brief for another AI agent.
---

# Delegate Task

Create a concise, execution-ready brief file for another AI agent.

## 1) Quick Check (Required)

Before writing any delegate brief:

- Check if splitting is useful:
  - Can parts be implemented independently with low coupling?
  - Can parts be validated independently with clear acceptance criteria?
  - Does splitting reduce risk?
- If splitting is recommended, first ask user to choose:
  - keep as one delegated task, or
  - split into multiple delegated tasks.
- Stop and wait for user decision before generating final brief(s).

Execution mode gates (hard rules):

- Unless there is explicit evidence that parallel execution is safe, you MUST use serial mode.
- In serial mode, if there is already a delegated in-progress task, you MUST stop and wait for its closeout before generating or dispatching the next task.
- In serial mode, only handle the current next sub-task. Do not pre-generate delegate briefs for later sub-tasks.

## 2) Output Artifact

Create one file:

- Name: `delegate-task-<unique>.md`
- Default location: project root (unless `output_path` is provided)
- If name collides, generate a new unique suffix

Agent Deck mode:

- Detect context by running `agent-deck session current --json` in host shell (outside sandbox).
- If detection fails, ask for explicit metadata.
- For this skill, `planner_session_id` means the session id of the sender creating this delegate task (the current session in Agent Deck).
- If current session id is detected, use it as `planner_session_id`.
- If explicit/context `planner_session_id` is also provided and does not match detected current session id, stop and ask for confirmation (do not auto-override).
- Resolve by priority:
  - `task_id`: explicit input -> context -> generate `YYYYMMDD-HHMM-<slug>`
  - `planner_session_id`: detected current session id -> explicit input (`planner_session_id` or compatibility alias `planner_session`) -> context -> ask
  - `executor_session` / `executor_tool`: explicit input -> context -> defaults
- In Agent Deck mode, write to:
  - `.agent-artifacts/<task_id>/delegate-task-<task_id>.md`

## 3) Brief Template

Generate these sections in the brief:

1. `Objective` (one sentence)
2. `Components to Address` (3-6 logical components: name, responsibility, key question)
3. `Critical Decisions` (2-4 decisions: options, trade-offs, recommendation)
4. `Constraints & Risks` (hard constraints, key risks, mitigations)
5. `Context to Acquire`:
   - `Read Before Starting`
   - `Reference as Needed`
   - `Know It Exists`
6. `Acceptance Criteria` (specific, testable checklist)
7. `Important Notes`:
   - In Agent Deck delegated execution, executor task-scoped git writes (branch/switch, stage, commit) are pre-authorized.
   - In Agent Deck delegated execution, after first delivery commit the executor must invoke `review-request` unless user explicitly waives review.
8. `Agent Deck Context` (only when Agent Deck mode is on): task id, planner session id, default executor session, artifact root.

## 4) Agent-Deck Dispatch (When Agent Deck Mode Is On)

- Dependency: this skill uses the `agent-deck-workflow` skill helper:
  - `scripts/dispatch-control-message.sh` from the `agent-deck-workflow` skill directory.
- If helper/script cannot be resolved, stop and ask user to attach/install `agent-deck-workflow`.
- Use one helper command (host shell, outside sandbox). Do not expand into many manual sub-steps.

```bash
"<agent_deck_workflow_skill_dir>/scripts/dispatch-control-message.sh" \
  --task-id "<task_id>" \
  --planner-session "<planner_session_id>" \
  --to-session "<executor_session_or_default>" \
  --action "execute_delegate_task" \
  --artifact-path ".agent-artifacts/<task_id>/delegate-task-<task_id>.md" \
  --note "Read and follow the delegate task file." \
  --cmd "<executor_tool>"
```

Control payload requirements:

- Follow `agent-deck-workflow/references/message-templates.md`.
- Use `*_session_id` fields.
- Include `required_skills`.

## 5) User-Facing Output Contract

After writing/dispatching:

- Return a short confirmation:
  - delegate file path
  - one-line summary
  - helper output summary (for example `dispatch_ok ...`) in Agent Deck mode
- Do not print the full brief inline unless user asks.
- Do not print raw JSON control payload unless user asks.
- If helper fails, report stderr summary and stop (do not claim success).
