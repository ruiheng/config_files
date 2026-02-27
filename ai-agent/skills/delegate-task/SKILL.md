---
name: delegate-task
description: Analyzes a task and produces a structured implementation brief file for another AI agent to execute.
---

# Delegate Task

Analyze the user's task and produce a structured implementation brief file for another AI agent to execute.

## Pre-Output Decomposition Check (Required)

Before generating the final task brief, evaluate whether the request should be split into smaller independent tasks.

Use this quick check:
- Can parts be implemented independently with low coupling?
- Can parts be validated independently with clear acceptance criteria?
- Would splitting reduce risk or enable parallel execution?

If the task is **not worth splitting**, proceed directly to "Output File" and "Brief Format".

If the task **is worth splitting**:
1. Provide a short split recommendation (proposed sub-tasks and why).
2. Ask the user to choose:
   - keep as one delegated task, or
   - split into multiple delegated tasks.
3. Stop and wait for the user's decision.
4. After the user's decision, rerun this skill and generate the final brief in the selected mode.

Do not output the full final brief before the user decision when a split recommendation is made.

## Output File (Required)

Create a file named `delegate-task-<unique>.md`.
- `<unique>` can be any short unique suffix.
- Default location is project root unless `output_path` is provided.
- If a filename collision occurs, generate a new unique suffix.

Agent Deck mode (host detection-first):
- Run `agent-deck session current --json` in host shell (outside sandbox).
- If detection succeeds, use detected session metadata.
- If detection fails (for example `not in a tmux session`), ask for explicit metadata.

In Agent Deck mode:
- This skill depends on `agent-deck-workflow` skill script:
  - `scripts/dispatch-control-message.sh` (from the `agent-deck-workflow` skill directory, not this skill directory)
- Required dependency behavior:
  1. ensure `agent-deck-workflow` skill is available/loaded
  2. resolve `agent-deck-workflow` skill directory
  3. invoke `<agent_deck_workflow_skill_dir>/scripts/dispatch-control-message.sh`
  4. if unresolved, stop and ask user to attach/install `agent-deck-workflow` skill
- Resolve `planner_session` by priority:
  1. explicit input `planner_session`
  2. existing Agent Deck metadata in context
  3. host-shell detection from `agent-deck session current --json`
  4. ask one short clarification question if still missing
- Resolve `task_id` by priority:
  1. explicit input `task_id`
  2. a task id already present in user request/context
  3. generate one (`YYYYMMDD-HHMM-<slug>`)
- Write to `.agent-artifacts/<task_id>/delegate-task-<task_id>.md`.
- Create parent directories if missing.
- Default executor session is `executor-<task_id>` unless `executor_session` is explicitly provided.
- Resolve execution parameters by priority:
  1. explicit `executor_session` / `executor_tool` / `group`
  2. values inferable from workflow context
  3. defaults: `executor-<task_id>`, current tool, current group

After writing the file:
- Return only a short confirmation with the file path and a one-line summary.
- Do not print the full brief inline unless the user explicitly asks.
- In Agent Deck mode, construct one JSON control payload for `agent-deck session send` (internal protocol, not user-facing output):
- Control payload schema reference (internal only; do not print to user by default):

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "<planner_session>",
  "to_session": "executor-<task_id>",
  "round": 1,
  "action": "execute_delegate_task",
  "artifact_path": ".agent-artifacts/<task_id>/delegate-task-<task_id>.md",
  "note": "Read and follow the delegate task file."
}
```

- In Agent Deck mode, run one dispatch helper command in host shell (outside sandbox). Do not replace this with many manual sub-steps.

```bash
"<agent_deck_workflow_skill_dir>/scripts/dispatch-control-message.sh" \
  --task-id "<task_id>" \
  --planner-session "<planner_session>" \
  --to-session "executor-<task_id>" \
  --action "execute_delegate_task" \
  --artifact-path ".agent-artifacts/<task_id>/delegate-task-<task_id>.md" \
  --note "Read and follow the delegate task file." \
  --group "<group>" \
  --cmd "<executor_tool>"
```

Required reporting in Agent Deck mode:
- Report the helper output line(s) only (for example `dispatch_ok ...` and session summary).
- Do not print raw JSON payload in user-facing output unless user explicitly requests the control payload.
- If the helper fails, include stderr summary and stop (do not claim launch/send succeeded).

## Brief Format

Generate the following sections:

---

### Objective
One sentence describing the core goal.

### Components to Address
Identify 3-6 logical components. For each:
- **Name**: What this component handles
- **Responsibility**: What it must do
- **Key Question**: The critical question it must answer

### Critical Decisions
List 2-4 key decisions. For each:
- **Decision**: What must be decided
- **Options**: 2-3 viable alternatives
- **Trade-offs**: Brief pros/cons
- **Recommendation**: Your suggestion with reasoning

### Constraints & Risks
- **Hard Constraints**: Non-negotiable limits
- **Key Risks**: What could cause failure
- **Mitigation**: How to detect or avoid

### Context to Acquire
Files and resources to know about, categorized by urgency:

- **Read Before Starting**: Files that must be read before implementation
- **Reference as Needed**: Files to consult during implementation
- **Know It Exists**: Files to be aware of but may not need to read immediately

For each, note what information it contains and why it matters.

### Acceptance Criteria
Specific, testable conditions:
- [ ] Criterion 1: [Specific observable outcome]
- [ ] Criterion 2: [Specific observable outcome]

### Important Notes
- **GIT OPERATIONS MUST FOLLOW WORKFLOW MODE**:
  - In Agent Deck delegated execution, executor should create/use a task branch and create a delivery commit before triggering review handoff.
  - In Agent Deck delegated execution, task-scoped git write operations by executor (branch create/switch, stage, commit) are pre-authorized and do not require per-commit user approval.
  - Outside Agent Deck mode, follow explicit user/repo git constraints for this task.
- **ANALYZE BEFORE ACTING**: Read all files in "Read Before Starting" first, then acquire remaining context incrementally as needed.
- **ASK IF UNCLEAR**: Ask clarifying questions if needed.

### Agent Deck Context (Include When Agent Deck Mode Is On)
- **Task ID**: `<task_id>`
- **Planner Session**: `<planner_session>`
- **Default Executor Session**: `executor-<task_id>`
- **Artifact Root**: `.agent-artifacts/<task_id>/`

### Review Loop (Required In Agent Deck Mode)

- In Agent Deck mode, after implementation + verification are complete and the executor has created its first delivery commit, the executor must invoke the `review-request` skill.
- The `review-request` output is used to hand off to `reviewer-<task_id>` via the Agent Deck control message flow.
- After `review-request` dispatch succeeds, executor should enter waiting state for reviewer response and should not keep polling reviewer output unless user explicitly asks.
- Skip this step only when the user explicitly instructs to skip review for this task.
- Do not silently finish a delegated task in Agent Deck mode without triggering the first review handoff.

### Language Guidelines
- Use English by default for all output, including code comments. Switch to the user's local language only when English becomes a communication barrier.
- Keep business/domain terms in original form (e.g., 白金会员, 代金券)
- Use English for technical terms (e.g., constructor, polymorphism)

---

## Guidelines

1. **Focus on problems, not solutions** - Describe what needs solving, not how
2. **Components are logical groupings** - Not ordered steps
3. **Be specific in criteria** - Concrete, observable outcomes
4. **Language** - English primary; keep business terms in original form
5. **Git boundary** - In Agent Deck delegated mode, explicitly allow task-scoped executor git writes (including commit) without per-commit user approval; otherwise follow explicit user/repo constraints
6. **Context matters** - Specify mandatory files first, then use incremental context acquisition
7. **Review handoff is required in Agent Deck mode** - After first delivery commit, invoke `review-request` unless the user explicitly waives review
8. **Decomposition gate** - If splitting is recommended, pause for user decision and only then produce the final brief
9. **File-first output** - Write the final brief to `delegate-task-<unique>.md`; avoid inline full-text output by default
