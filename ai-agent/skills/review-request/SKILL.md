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
2. summarize unrelated noise with count + up to 3 examples
3. for committed scope, omit unrelated noise unless it materially affects review framing
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
- `reviewer_tool`: explicit -> delegated context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
  - if user/context provides a full reviewer command with arguments, preserve it unchanged
- `round`: explicit -> infer from context -> default `1`

When this is a follow-up round after reviewer feedback, summarize which findings were adopted, which were rejected, and why.
Reviewer feedback is advisory input, not automatic instructions.

Review-request continuity rule:
- round `1` uses the full review-request body
- round `>1` to the same reviewer session uses a delta-only body
- if the reviewer session changed or reviewer continuity is unknown, fall back to the full review-request body

Identity rules:
- `review_requested` sender must be active executor session id
- If detected current session id differs from resolved `executor_session_id`, stop and ask for clarification
- If existing reviewer session tool differs from requested `reviewer_tool`, ask user to choose:
  1. keep existing reviewer session/tool
  2. create/use new reviewer session with requested tool

Post-send behavior:
- executor immediately uses `check-workflow-mail wait=True`
- executor does not proactively poll reviewer unless user explicitly asks

## Output Template

Round `1` or new reviewer session: use the full body below.

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

## Reviewer Role
You are the last hard-nosed reviewer after a polished Cursor IDE patch already made it past easier scrutiny.
The code may look tidy. The summary may sound confident. The checks may be green. Assume none of that earns trust yet.
Your job is to stop a weak patch from slipping through by looking for what the patch is trying to hide: shallow fixes, fake-green verification, broken invariants, regression risk, and edge cases skipped by the author.

## Review Lens
- Correctness & invariants: does the change actually solve the stated problem, or only the visible symptom? What assumptions can now break?
- Design & complexity: is the design simpler and easier to reason about, or did the patch add cleverness, coupling, or abstraction debt?
- Regression risk & compatibility: what existing behavior, data shape, workflow, or caller contract could this silently break?
- Tests & evidence: do the tests prove the claim, cover negative paths and boundaries, and fail for the right reason? What is still unproven?
- Security & safety: are trust boundaries, input handling, permissions, and unsafe side effects still sound?
- Maintainability: will the next engineer understand the fix, or is the real logic now harder to inspect and debug?

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

Round `>1` to the same reviewer session: send only delta.

Use this structure:

```markdown
Task: <task_id>
Action: review_requested
From: executor <executor_session_id>
To: reviewer {{TO_SESSION_ID}}
Planner: <planner_session_id>
Round: <round>

## Summary
[One-line delta summary]

## Delta Since Last Review
- Scope: [what changed in reviewed scope]
- Findings addressed: [adopted items]
- Findings rejected: [rejected items + rationale]
- New risks or open questions: [only if changed]

## Updated Implementation Summary
[Only what changed since the last review request]

## Files Changed Since Last Review
- `path/to/file1` - [delta description]
- `path/to/file2` - [delta description]

## Updated Verification Evidence
- Commands/Checks: [only new or rerun checks relevant to this round]
- Result Summary: [delta results]
- Coverage Gaps: [remaining gaps after this round]

## Known Issues or Limitations
[Current remaining limitations; if none, write: None identified]
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
3. let the helper resolve the reviewer session, `agent-deck launch` a missing target directly into `check-workflow-mail wait=True`, or nudge the existing active session after mailbox send
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
- launch `adwf-send-and-wake ... --body-file -` in a background terminal / PTY session
- then write the composed review-request body to that session's stdin
- keep freshly generated body in stdin
- feed stdin directly, without `printf`, `cat`, heredoc, shell pipes, or redirection

Rules:
- round `1` sends the full review request in mailbox body
- later rounds to the same reviewer send delta only
- if reviewer continuity changed, resend the full review request body
- use `reviewer-<task_id>` as a session ref until the helper resolves the real `reviewer_session_id`
- use the exact command shape above when it already matches the task
- let the helper decide whether this reviewer needs direct `agent-deck launch` or an active-session nudge

## Quality Bar

1. Keep concise and copy/paste friendly
2. Keep wording concise and direct
3. File list is complete for in-scope target, not full local noise
4. Prefer facts over speculation
5. Keep raw mailbox JSON internal unless user asks
6. Always include `Review Focus` and `Verification Evidence` fields
7. Preserve `workflow_policy` unchanged when present
8. Preserve `special_requirements` unchanged when present
