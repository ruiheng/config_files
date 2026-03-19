---
name: delegate-task
description: Use only for non-trivial implementation tasks that require meaningful code changes; do not use for simple tasks or documentation-only work.
---

# Delegate Task

Create a concise, execution-ready brief file for another AI agent.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines delegate-task-specific behavior.

Use this skill only when delegation is justified. Default bias is not to delegate.
If the task is simple, mostly mechanical, or documentation-only, do the work directly instead of invoking this skill.

## 1) Quick Check (Required)

Before writing any delegate brief:

- Reject delegation immediately when any of these are true:
  - task is pure documentation, wording, summarization, or other non-code work
  - task is a small or obvious code change that one agent can complete directly with low risk
  - task is mostly file reading, inspection, or answering questions
  - expected code change is narrow enough that splitting adds overhead instead of reducing risk
- Delegate only when all of these are true:
  - task requires meaningful code modification, not just docs or prompts
  - task has enough complexity, scope, or validation burden that a separate executor is useful
  - delegated execution creates a clearer ownership boundary or lowers delivery risk
- Check whether splitting is useful:
  - components can be implemented independently
  - components can be validated independently
  - split reduces risk
- If delegation is not clearly worthwhile, stop and do not create a delegate brief.
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
  - `start_branch`: detected current git branch when delegate begins -> explicit -> context -> ask
  - `integration_branch`: explicit -> context -> if `start_branch` is the intended landing line for this delegated change, use `start_branch`; otherwise infer from explicit user intent or a high-confidence tracked/base branch for `start_branch`; if confidence is low, ask rather than guessing
    - never assume `main`/`master`; branch names are evidence, not truth
  - `executor_session_id`: explicit -> context -> default `executor-<task_id>`
  - `reviewer_session_id`: explicit -> context -> default `reviewer-<task_id>`
  - `task_branch`: explicit -> context -> if `start_branch` is already the intended topic branch for this delegated change, reuse `start_branch`; otherwise default `task/<task_id>` created from `integration_branch`
    - in the normal merge-based workflow, `task_branch` must differ from `integration_branch`
  - `executor_tool`: explicit -> context -> default current AI tool
    - if user/context provides a full command with arguments, preserve it unchanged
    - if it resolves to provider-only `claude`, normalize to `claude --model sonnet --permission-mode acceptEdits`
    - if it resolves to provider-only `codex`, normalize to `codex --model gpt-5.4 --ask-for-approval on-request`
    - if it resolves to provider-only `gemini`, normalize to `gemini --model gemini-2.5-pro`
  - `reviewer_tool`: explicit -> context -> map from normalized `executor_tool`:
    - if user/context provides a full reviewer command with arguments, preserve it unchanged
    - `executor_tool` starts with `codex` -> `claude --model sonnet --permission-mode acceptEdits`
    - `executor_tool` starts with `claude` -> `codex --model gpt-5.4 --ask-for-approval on-request`
    - otherwise -> `claude --model sonnet --permission-mode acceptEdits`
    - `reviewer_tool` selects how the reviewer session is created/resumed; it does not collapse reviewer role into the current planner/executor session
    - if planner/executor and reviewer all use Codex, still keep `reviewer_session_id` distinct unless same-session reviewer assignment is explicitly requested in workflow context
  - `workflow_policy` (optional): explicit -> context -> omit when not set
  - `special_requirements` (optional fallback): explicit -> context -> extract user constraints not represented by existing structured fields -> omit when empty
- In Agent Deck mode write to:
  - `.agent-artifacts/<task_id>/delegate-task-<task_id>.md`

## 3) Brief Template

Generate sections:

1. `Objective` (one sentence)
2. `Components to Address` (3-6 components: name, responsibility, key question)
3. `Critical Decisions` (2-4: options, trade-offs, recommendation)
4. `Branch Plan`:
   - `start_branch`
   - `integration_branch`
   - `task_branch`
   - short rationale for why this task uses a dedicated task branch or reuses the existing topic branch
5. `Constraints & Risks` (hard constraints, key risks, mitigations)
6. `Context to Acquire`:
   - `Read Before Starting`
   - `Reference as Needed`
   - `Know It Exists`
7. `Acceptance Criteria` (testable checklist)
8. `Important Notes`:
   - in Agent Deck delegated execution, executor task-scoped git writes are pre-authorized
   - executor must follow the recorded branch plan and must not invent a different working branch just because `task/<task_id>` is the default naming convention
   - after first delivery commit, executor runs `review-request` unless user waives review
   - matching provider names do not merge roles: "reviewer uses codex" means use/create the recorded `reviewer_session_id` with a Codex command unless workflow context explicitly says planner and reviewer are the same session
9. `Workflow Policy` (optional, only when overriding default human-gated behavior)
10. `Agent Deck Context` (only in Agent Deck mode): `task_id`, `planner_session_id`, default `executor_session_id`, default `reviewer_session_id`, artifact root, `start_branch`, `integration_branch`, `task_branch`, `executor_tool`, `reviewer_tool`
11. `Special Requirements` (optional fallback; only when needed): free-form constraints/instructions that must be preserved across executor/reviewer/planner messages

Tool-routing rule:
- If user specifies a full executor/reviewer command, persist it unchanged in delegate brief context.
- If user specifies only provider preference (for example `claude`, `codex`, `gemini`), persist the normalized full command with recommended arguments.

## 4) Agent-Deck Dispatch (When Agent Deck Mode Is On)

- Use shared dispatch guidance from `agent-deck-workflow/SKILL.md` (`Dispatch Helper Usage`).
- Use one helper command in host shell.

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session-id "<planner_session_id>" \
  --to-session-id "<executor_session_id>" \
  --action "execute_delegate_task" \
  --artifact-path ".agent-artifacts/<task_id>/delegate-task-<task_id>.md" \
  --note "You are the executor for this task. Fully load and follow agent-deck-workflow/SKILL.md, and follow executor behavior rather than reviewer or planner behavior. Read and follow the delegate task file, especially Branch Plan / Agent Deck Context. MUST implement on the recorded task_branch. If that branch does not exist, create it from the recorded integration_branch; if it already exists, switch to it. Do not invent a different branch or assume task/<task_id> when the delegate file says to reuse an existing topic branch. If branch setup fails, stop and report. After first implementation pass, commit, prepare the review-request artifact, and dispatch review_requested to the recorded reviewer_session_id. Do not self-review unless workflow context explicitly assigns your current session as reviewer." \
  --workflow-policy-json '<workflow_policy_json_optional>' \
  --special-requirements-json '<special_requirements_json_optional>' \
  --cmd "<executor_tool>"
```

Typical `--cmd` values (copy-ready):

```bash
--cmd "codex --model gpt-5.4 --ask-for-approval on-request"
--cmd "claude --model sonnet --permission-mode acceptEdits"
--cmd "gemini --model gemini-2.5-pro"
```

Rules:
- Do not emit bare provider names like `claude`, `codex`, or `gemini` as default workflow session commands.
- Always quote `--cmd` when it contains spaces.
- `--cmd` only applies when creating a missing target session; existing sessions keep their original tool command.

Control payload requirements:
- Follow `agent-deck-workflow/SKILL.md` (`Control Message Contract`)
- Use `*_session_id` fields.

## 5) User-Facing Output Contract

After writing/dispatching:

- Return short confirmation:
  - delegate file path
  - one-line objective summary
  - selected `task_branch` / `integration_branch`
  - selected `executor_session_id` / `reviewer_session_id` in Agent Deck mode
  - selected `executor_tool` / `reviewer_tool` in Agent Deck mode
  - helper output summary (`dispatch_ok ...`) in Agent Deck mode
- Keep raw control JSON internal unless user explicitly asks.
- If helper fails, report stderr summary and include shared diagnostics checklist from `agent-deck-workflow/SKILL.md`.
