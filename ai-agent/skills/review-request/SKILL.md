---
name: review-request
description: Generates a review-request document for code review from uncommitted changes, a specific commit, or a branch.
---

# Review Request

Generate a copy/paste-friendly review handoff document for later code review.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines review-request-specific behavior.

## Required Scope Selection

Before generating the document, determine one scope:
1. `uncommitted changes`
2. `specific commit`
3. `branch`

Workflow continuity rule:
- In an ongoing implementation session, if scope is not explicit, inherit from active delegated task for current `task_id`.
- Ask a clarification question only when multiple scopes are equally plausible or no reliable scope can be inferred.

## Inputs

- Scope type: `uncommitted` | `commit` | `branch`
- Scope value:
  - `uncommitted`: no value
  - `commit`: commit hash
  - `branch`: branch name
- Optional:
  - `base_branch` (for branch scope)
  - `original_task`
  - `delegate_task_path`
  - `output_path` (default: project root)

## Original Task Source (Required)

Populate `## Original Task` by priority:
1. explicit `original_task`
2. active delegated-task context in current session
3. `delegate_task_path`
4. ask one short clarification question

## Data Collection (Read-Only)

Use read-only git commands only.

- Uncommitted:
  - `git status --short`
  - `git diff --name-status`
  - `git diff --cached --name-status`
  - `git ls-files --others --exclude-standard`
- Commit:
  - `git show --name-status --format=fuller <commit>`
- Branch:
  - choose base: `base_branch` -> `main` -> `master`
  - `git log --oneline <base>..<branch>`
  - `git diff --name-status <base>...<branch>`

## Scope Hygiene and Noise Control (Required)

Classify changes into:
- In-scope: directly related to original task
- Noise/out-of-scope: unrelated local files, temporary artifacts, env files

Rules:
1. `Files Modified/Created` includes in-scope files only.
2. Do not list unrelated noise file-by-file.
3. For uncommitted scope, summarize unrelated noise with count + up to 3 examples.
4. Ask one short clarification question if relevance is uncertain.

## Output File

Create `review-request-<unique>.md`.
- Default path: project root unless `output_path` provided.
- If collision occurs, regenerate unique suffix.

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Dispatch Helper Usage`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> branch `task/<task_id>` -> delegated context/path -> ask
- `planner_session_id`: explicit/context -> ask
- `executor_session_id`: explicit -> current session id -> delegated context -> ask
- `reviewer_session_id`: explicit -> delegated context -> default `reviewer-<task_id>`
- `workflow_policy` (optional): explicit -> delegated context -> omit
- `special_requirements` (optional fallback): explicit -> delegated context -> omit
- `executor_tool`: explicit -> delegated context -> default current AI tool
  - if user/context provides a full command with arguments, preserve it unchanged
  - if it resolves to provider-only `claude`, normalize to `claude --model sonnet --permission-mode acceptEdits`
  - if it resolves to provider-only `codex`, normalize to `codex --model gpt-5.4 --ask-for-approval on-request`
  - if it resolves to provider-only `gemini`, normalize to `gemini --model gemini-2.5-pro`
- `reviewer_tool`: explicit -> delegated context -> map from normalized `executor_tool`:
  - if user/context provides a full reviewer command with arguments, preserve it unchanged
  - `executor_tool` starts with `codex` -> `claude --model sonnet --permission-mode acceptEdits`
  - `executor_tool` starts with `claude` -> `codex --model gpt-5.4 --ask-for-approval on-request`
  - otherwise -> `claude --model sonnet --permission-mode acceptEdits`
- `round`: explicit -> infer from context -> default `1`

Then write to `.agent-artifacts/<task_id>/review-request-r<round>.md`.
Create parent directories when missing.

Dispatch to reviewer with canonical flags:

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session-id "<planner_session_id>" \
  --from-session-id "<executor_session_id>" \
  --to-session-id "<reviewer_session_id>" \
  --round "<round>" \
  --action "review_requested" \
  --artifact-path ".agent-artifacts/<task_id>/review-request-r<round>.md" \
  --note "You are the reviewer for this task. Fully load and follow agent-deck-workflow/SKILL.md (especially Control Message Contract + Reviewer Decision Flow), and follow reviewer behavior rather than executor or planner behavior. Read the review-request file and produce a full review report, then use ~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh to proactively send the next control message to executor-<task_id>." \
  --workflow-policy-json '<workflow_policy_json_optional>' \
  --special-requirements-json '<special_requirements_json_optional>' \
  --cmd "<reviewer_tool>"
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

Identity rules:
- `review_requested` sender must be active executor session id.
- If detected current session id differs from resolved `executor_session_id`, stop and ask for clarification.
- If existing reviewer session tool differs from requested `reviewer_tool`, ask user to choose:
  1. keep existing reviewer session/tool
  2. create/use new reviewer session with requested tool

Post-dispatch behavior:
- Executor enters waiting state.
- Executor does not proactively poll reviewer unless user explicitly asks.

## Output Template

Use this exact structure:

```markdown
# Review Request

## Scope
- Type: [uncommitted | commit | branch]
- Target: [working tree | commit hash | branch name]
- Base (if branch): [base branch or N/A]

## Agent Deck Context (Optional)
- Task ID: [<task_id> when available]
- Planner Session ID: [<planner_session_id> when available]
- Round: [<round> when available]
- Workflow Policy: [<workflow_policy_json> when available]
- Special Requirements: [<special_requirements_json> when available]

## Original Task
[Original task text from explicit input or active session context (optionally from `delegate_task_path` if provided). Use `Not provided` only after explicit clarification that no task text is available.]

## Review Focus
- [Primary risk/review angle 1]
- [Primary risk/review angle 2]

## Implementation Summary
[Concise summary of what changed and why]

## Files Modified/Created (In-Scope Only)
- `path/to/file1` - [brief description of changes]
- `path/to/file2` - [brief description of changes]

## Verification Evidence
- Commands/Checks: [tests, type-check, lint, manual checks; if unknown write: Not provided]
- Result Summary: [pass/fail/high-level outcomes; if unknown write: Not provided]
- Coverage Gaps: [known missing tests or validation gaps; if none write: None identified]

## Working Tree Noise Summary (Optional, mostly for uncommitted scope)
- Excluded unrelated items: [count]
- Examples (max 3): [`path/a`, `path/b`]

## Known Issues or Limitations
[Known limitations; if none, write: None identified]
```

## Quality Bar

1. Keep concise and copy/paste friendly.
2. Use neutral language.
3. File list is complete for in-scope target, not full local noise.
4. Prefer facts over speculation.
5. Keep raw control JSON internal unless user asks.
6. Always include `Review Focus` and `Verification Evidence` fields.
7. Preserve `workflow_policy` unchanged when present.
8. Preserve `special_requirements` unchanged when present.
