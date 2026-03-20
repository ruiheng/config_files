---
name: review-request
description: Generates a review-request mailbox message for code review from uncommitted changes, a specific commit, or a branch.
---

# Review Request

Generate a copy/paste-friendly mailbox message for code review.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines review-request-specific behavior.

## Required Scope Selection

Before generating the message, determine one scope:
1. `uncommitted changes`
2. `specific commit`
3. `branch`

Workflow continuity rule:
- In an ongoing implementation session, if scope is not explicit, inherit from active delegated task for current `task_id`
- Ask a clarification question only when multiple scopes are equally plausible or no reliable scope can be inferred

## Inputs

- Scope type: `uncommitted` | `commit` | `branch`
- Scope value:
  - `uncommitted`: no value
  - `commit`: commit hash
  - `branch`: branch name
- Optional:
  - `base_branch` (for branch scope)
  - `original_task`

## Original Task Source (Required)

Populate `## Original Task` by priority:
1. explicit `original_task`
2. active delegated-task context in current session
3. ask one short clarification question

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
- in-scope: directly related to original task
- noise/out-of-scope: unrelated local files, temporary artifacts, env files

Rules:
1. `Files Modified/Created` includes in-scope files only
2. do not list unrelated noise file-by-file
3. for uncommitted scope, summarize unrelated noise with count + up to 3 examples
4. ask one short clarification question if relevance is uncertain

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> branch `task/<task_id>` -> delegated context -> ask
- `planner_session_id`: explicit/context -> ask
- `executor_session_id`: explicit -> current session id -> delegated context -> ask
- `reviewer_session_ref`: explicit -> delegated context -> default `reviewer-<task_id>`
- `reviewer_session_id`: explicit actual id -> delegated context actual id -> resolved/created from `reviewer_session_ref` before send
- `workflow_policy` (optional): explicit -> delegated context -> omit
- `special_requirements` (optional fallback): explicit -> delegated context -> omit
- `executor_tool`: explicit -> delegated context -> default current AI tool
  - if user/context provides a full command with arguments, preserve it unchanged
  - if it resolves to provider-only `claude`, normalize to `claude --model sonnet --permission-mode acceptEdits`
  - if it resolves to provider-only `codex`, normalize to `codex --model gpt-5.4 --ask-for-approval on-request`
  - if it resolves to provider-only `gemini`, normalize to `gemini --model gemini-2.5-pro`
- `reviewer_tool`: explicit -> delegated context -> map from normalized `executor_tool`
  - if user/context provides a full reviewer command with arguments, preserve it unchanged
  - `executor_tool` starts with `codex` -> `claude --model sonnet --permission-mode acceptEdits`
  - `executor_tool` starts with `claude` -> `codex --model gpt-5.4 --ask-for-approval on-request`
  - otherwise -> `claude --model sonnet --permission-mode acceptEdits`
- `round`: explicit -> infer from context -> default `1`

When this is a follow-up round after reviewer feedback, summarize which findings were adopted, which were rejected, and why.
Reviewer feedback is advisory input, not automatic instructions.

Identity rules:
- `review_requested` sender must be active executor session id
- If detected current session id differs from resolved `executor_session_id`, stop and ask for clarification
- If existing reviewer session tool differs from requested `reviewer_tool`, ask user to choose:
  1. keep existing reviewer session/tool
  2. create/use new reviewer session with requested tool

Post-send behavior:
- executor enters waiting state
- executor does not proactively poll reviewer unless user explicitly asks

## Output Template

Use this exact structure as the mailbox body:

```markdown
Task: <task_id>
Action: review_requested
From: executor <executor_session_id>
To: reviewer {{TO_SESSION_ID}}
Planner: <planner_session_id>
Round: <round>

## Summary
[One-line review request summary]

## Scope
- Type: [uncommitted | commit | branch]
- Target: [working tree | commit hash | branch name]
- Base (if branch): [base branch or N/A]

## Original Task
[Original task text from explicit input or active session context. Use `Not provided` only after explicit clarification that no task text is available.]

## Review Focus
- [Primary risk/review angle 1]
- [Primary risk/review angle 2]

## Response to Previous Review (Optional)
- Adopted findings: [brief summary or `N/A`]
- Rejected findings and rationale: [brief summary or `N/A`]
- Items needing user decision: [brief summary or `N/A`]

## Implementation Summary
[Concise summary of what changed and why]

## Files Modified/Created (In-Scope Only)
- `path/to/file1` - [brief description of changes]
- `path/to/file2` - [brief description of changes]

## Verification Evidence
- Commands/Checks: [tests, type-check, lint, manual checks; if unknown write: Not provided]
- Result Summary: [pass/fail/high-level outcomes; if unknown write: Not provided]
- Coverage Gaps: [known missing tests or validation gaps; if none write: None identified]

## Workflow Policy
[only when present]

## Special Requirements
[only when present]

## Known Issues or Limitations
[Known limitations; if none, write: None identified]
```

## Mailbox Send + Wakeup

Recommended subject:
- `review request: <task_id> r<round>`

Preferred path: use the installed helper `adwf-send-and-wake`.

Workflow send sequence:
1. compose the body with `{{TO_SESSION_ID}}` where the real reviewer session id must appear
2. run `adwf-send-and-wake` outside sandbox:
   - `--from-session-id "<executor_session_id>"`
   - `--to-session-ref "<reviewer_session_ref>"`
   - `--ensure-target-title "<reviewer_session_ref>"`
   - `--ensure-target-cmd "<reviewer_tool>"`
   - `--parent-session-id "<planner_session_id>"`
   - `--subject "review request: <task_id> r<round>"`
   - `--body-file -`
3. let the helper resolve/create the reviewer session, register endpoints, send the body, start the target, wait `10s`, and then wake it
4. use the helper result as the authoritative `reviewer_session_id`

Exact command shape:

```bash
adwf-send-and-wake \
  --from-session-id "<executor_session_id>" \
  --to-session-ref "<reviewer_session_ref>" \
  --ensure-target-title "<reviewer_session_ref>" \
  --ensure-target-cmd "<reviewer_tool>" \
  --parent-session-id "<planner_session_id>" \
  --subject "review request: <task_id> r<round>" \
  --body-file - \
  --json
```

Codex-style execution rule:
- start `adwf-send-and-wake ... --body-file -` directly
- then stream the composed review-request body through stdin tool input
- do not create a temporary review-request body file
- do not use `printf`, `cat`, heredoc, shell pipes, or redirection to feed the body

Rules:
- Do not create `review-request-*.md`
- Do not tell reviewer to go read a generated workflow file
- Do not run `adwf-send-and-wake --help` when this command shape already matches the task
- Do not create a temporary review-request body file for a freshly generated message
- Do not wrap `adwf-send-and-wake --body-file -` in `printf`, `cat`, heredoc, shell pipes, or redirection
- Do not use `reviewer-<task_id>` as if it were already a real session id
- Do not send wakeup before the helper's start-delay-wakeup sequence completes

## Quality Bar

1. Keep concise and copy/paste friendly
2. Use neutral language
3. File list is complete for in-scope target, not full local noise
4. Prefer facts over speculation
5. Keep raw mailbox JSON internal unless user asks
6. Always include `Review Focus` and `Verification Evidence` fields
7. Preserve `workflow_policy` unchanged when present
8. Preserve `special_requirements` unchanged when present
