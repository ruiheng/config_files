---
name: delegate-task
description: Analyze a task and create a delegate brief for another AI agent.
---

# Delegate Task

Create a concise, execution-ready brief file for another AI agent.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines delegate-task-specific behavior.

## 1) Quick Check (Required)

Before writing any delegate brief:

- Check whether splitting is useful:
  - components can be implemented independently
  - components can be validated independently
  - split reduces risk
- If splitting is recommended, ask user to choose:
  - keep one delegated task, or
  - split into multiple delegated tasks
- Wait for user decision before final brief(s).

Execution mode gates:

- Unless there is explicit evidence parallel execution is safe, use serial mode.
- In serial mode, if one delegated task is in progress, wait for closeout before generating/dispatching next task.
- In serial mode, handle only the current next sub-task.

## 2) Output Artifact

Create one file:

- Name: `delegate-task-<unique>.md`
- Default location: project root (unless `output_path` provided)
- If collision occurs, generate a new unique suffix

Agent Deck mode:

- Follow shared rules in `agent-deck-workflow/SKILL.md`:
  - `Shared Protocol (For All Workflow Skills)`
  - `Task Metadata Convention`
- Skill-specific planner identity rule:
  - delegate creator is planner sender
  - `planner_session_id` is expected to equal detected `current_session_id`
  - if explicit/context planner id conflicts with detected current session id, ask user to confirm before dispatch
- Resolve by priority:
  - `task_id`: explicit -> context -> generate `YYYYMMDD-HHMM-<slug>`
  - `planner_session_id`: detected current session id -> explicit -> context -> ask
  - `executor_session_id`: explicit -> context -> default `executor-<task_id>`
  - `executor_tool`: explicit -> context -> default current AI tool
  - `reviewer_tool`: explicit -> context -> default `executor_tool`
  - `workflow_policy` (optional): explicit -> context -> omit when not set
- In Agent Deck mode write to:
  - `.agent-artifacts/<task_id>/delegate-task-<task_id>.md`

## 3) Brief Template

Generate sections:

1. `Objective` (one sentence)
2. `Components to Address` (3-6 components: name, responsibility, key question)
3. `Critical Decisions` (2-4: options, trade-offs, recommendation)
4. `Constraints & Risks` (hard constraints, key risks, mitigations)
5. `Context to Acquire`:
   - `Read Before Starting`
   - `Reference as Needed`
   - `Know It Exists`
6. `Acceptance Criteria` (testable checklist)
7. `Important Notes`:
   - in Agent Deck delegated execution, executor task-scoped git writes are pre-authorized
   - after first delivery commit, executor runs `review-request` unless user waives review
8. `Workflow Policy` (optional, only when overriding default human-gated behavior)
9. `Agent Deck Context` (only in Agent Deck mode): `task_id`, `planner_session_id`, default `executor_session_id`, artifact root, `executor_tool`, `reviewer_tool`

Tool-routing rule:
- If user specifies executor/reviewer tool preference (for example `claude`, `codex`, `gemini`), persist in delegate brief context.

## 4) Agent-Deck Dispatch (When Agent Deck Mode Is On)

- Use shared dispatch guidance from `agent-deck-workflow/SKILL.md` (`Dispatch Helper Usage`).
- Use one helper command in host shell.

```bash
<agent_deck_workflow_skill_dir>/scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session-id "<planner_session_id>" \
  --to-session-id "<executor_session_id>" \
  --action "execute_delegate_task" \
  --artifact-path ".agent-artifacts/<task_id>/delegate-task-<task_id>.md" \
  --note "Read and follow the delegate task file." \
  --workflow-policy-json '<workflow_policy_json_optional>' \
  --cmd "<executor_tool>"
```

Typical `--cmd` values (copy-ready):

```bash
--cmd "codex"
--cmd "claude"
--cmd "gemini"
--cmd "codex --model gpt-5-codex --approval-mode on-request"
--cmd "claude --model sonnet --permission-mode acceptEdits"
--cmd "gemini --model gemini-2.5-pro --yolo"
```

Rules:
- Always quote `--cmd` when it contains spaces.
- `--cmd` only applies when creating a missing target session; existing sessions keep their original tool command.

Control payload requirements:
- Semantic rules: `agent-deck-workflow/references/message-templates.md`
- Full JSON appendix: `agent-deck-workflow/references/internal-protocol/message-templates.md`
- Use `*_session_id` fields.

## 5) User-Facing Output Contract

After writing/dispatching:

- Return short confirmation:
  - delegate file path
  - one-line objective summary
  - selected `executor_tool` / `reviewer_tool` in Agent Deck mode
  - helper output summary (`dispatch_ok ...`) in Agent Deck mode
- Keep raw control JSON internal unless user explicitly asks.
- If helper fails, report stderr summary and include shared diagnostics checklist from `agent-deck-workflow/SKILL.md`.
