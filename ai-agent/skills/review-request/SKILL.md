---
name: review-request
description: Generates a review-request mailbox message for code review from uncommitted changes, a specific short commit ref, or a branch.
---

# Review Request

Generate a copy/paste-friendly mailbox message for code review.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Required Scope Selection

Before generating the message, determine one scope:
1. `uncommitted changes`
2. `specific short commit ref`
3. `branch`

Workflow continuity rule:
- In an ongoing implementation session, if scope is not explicit, inherit from active delegated task for current `task_id`
- Ask a clarification question only when multiple scopes are equally plausible or no reliable scope can be inferred

Branch plan continuity rule:
- preserve recorded `start_branch`, `integration_branch`, and `task_branch` from delegated task context
- treat that branch plan as immutable task context unless the user explicitly changes it

## Inputs

- Scope type: `uncommitted` | `commit` | `branch`
- Scope value:
  - `uncommitted`: no value
  - `commit`: short commit ref
  - `branch`: branch name
- Optional:
  - `base_branch` (for branch scope)
  - `original_task`
  - `requester_role`
  - `requester_session_id`
  - `reviewer_session_id`
  - `review_lane`
  - `coder_tool`
  - `coder_tool_profile`
  - `reviewer_tool`
  - `reviewer_tool_profile`
  - `start_branch`
  - `integration_branch`
  - `task_branch`

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
  - `git show --name-status --format=fuller <short-commit-ref>`
- Branch:
  - choose base: `base_branch` -> recorded `integration_branch` -> ask
  - `git log --oneline <base>..<branch>`
  - `git diff --name-status <base>...<branch>`

## Scope Hygiene and Noise Control (Required)

Classify changes into:
- in-scope: directly related to original task
- noise/out-of-scope: unrelated local files, temporary artifacts, env files

Rules:
1. `Changed Paths Summary` includes in-scope files only
2. summarize unrelated noise with count + up to 3 examples
3. for committed scope, omit unrelated noise unless it materially affects review framing
4. ask one short clarification question if relevance is uncertain

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> branch `task/<task_id>` -> delegated context -> ask
- `planner_session_id`: explicit/context -> ask
- `requester_role`: explicit -> delegated context -> current workflow role -> default `coder`
- `requester_session_id`: explicit -> current session id -> delegated context -> ask
- `reviewer_session_id`: explicit actual id -> delegated context actual id -> required existing reviewer allocated by planner before send
- `review_lane`: explicit -> delegated context -> default `task`
- `workflow_policy` (optional): explicit -> delegated context -> default unattended policy
- `special_requirements` (optional fallback): explicit -> delegated context -> omit
- `coder_tool_profile`: explicit -> delegated context -> omit when `coder_tool` is already a full command -> default current-tool continuity or resolver role default `coder`
- `coder_tool_cmd`: explicit full command -> delegated context resolved command -> current AI tool when continuity is intended -> resolve through `~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js`
- `reviewer_tool_profile`: explicit -> delegated context -> omit when `reviewer_tool` is already a full command -> default resolver role default `reviewer`
- `reviewer_tool_cmd`: explicit full command -> delegated context resolved command -> resolve through `~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js`
- `round`: explicit -> infer from context -> default `1`
- `start_branch`: explicit -> delegated context -> ask
- `integration_branch`: explicit -> delegated context -> ask
- `task_branch`: explicit -> delegated context -> ask

Branch-plan guard:
- `integration_branch` must be the non-task landing branch; if it looks like `task/*`, ask for the real integration branch instead of sending the review request

When this is a follow-up round after reviewer feedback, summarize which findings were adopted, which were rejected, and why.
Reviewer feedback is advisory input, not automatic instructions.

Review-request continuity rule:
- round `1` uses the full review-request body
- round `>1` to the same reviewer session uses a delta-only body
- if the reviewer session changed or reviewer continuity is unknown, fall back to the full review-request body
- delta-only means terse:
  - do not repeat the original task, branch plan, file list, or unchanged verification
  - summarize only what changed since the last review and what you want the reviewer to re-check
  - if the whole message is effectively "please re-review after addressing the prior findings", prefer a short subject and a one-line body
  - if the transport or tooling can support it, body can be minimal; otherwise keep it to a single short sentence

Identity rules:
- `review_requested` sender must be the active requester session id for this review lane
- use the bound mailbox sender context for sender validation
- If the allocated reviewer session tool differs from requested `reviewer_tool_cmd` or the requested `reviewer_tool_profile` policy, ask user to choose:
  1. keep existing reviewer session/tool
  2. ask planner to replace reviewer assignment with a different reviewer session/tool

Commit reference rule:
- in mailbox content, use a short commit ref, not a full 40-char hash

Post-send behavior:
- requester does not proactively poll reviewer unless user explicitly asks

## Output Template

Round `1` or new reviewer session: use the full body below.

Use this exact structure as the mailbox body:

```markdown
Task: <task_id>
Action: review_requested
From: <requester_role> <requester_session_id>
To: reviewer {{TO_SESSION_ID}}
Planner: <planner_session_id>
Round: <round>

## Summary
[One-line review request summary]

## Scope
- Type: [uncommitted | commit | branch]
- Target: [working tree | short commit ref | branch name]
- Base (if branch): [base branch or N/A]

## Original Task
[Original task text from explicit input or active session context. Use `Not provided` only after explicit clarification that no task text is available.]

## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Stability rule: treat this recorded branch plan as immutable task context unless the user explicitly changes it

## Review Context
- Lane: [task | integration_final]

## Tool Context
- Coder tool profile: [coder_tool_profile or `explicit`]
- Coder tool cmd: [coder_tool_cmd]
- Reviewer tool profile: [reviewer_tool_profile or `existing-session`]
- Reviewer tool cmd: [reviewer_tool_cmd or `existing-session`]

## Review Focus
- [Primary risk/review angle 1]
- [Primary risk/review angle 2]

## Implementation Summary
[Brief intent-level summary; do not restate the whole diff]

## Changed Paths Summary
- In-scope changed paths: [count + key paths, or `See scope target` when the git target is enough]
- Out-of-scope noise: [count + up to 3 examples, or `None`]

## Checks Already Run
- Lint: [command/result or `Not run`]
- Build/Link: [command/result or `Not run`]
- Compile/Type-check: [command/result or `Not run`]
- Tests: [command/result or `Not run`]
- Other verification: [manual/browser/scripted checks or `None`]
- Coverage gaps: [known missing tests or validation gaps; if none write: None identified]

## Workflow Policy
[resolved workflow policy]

## Special Requirements
[only when present]

## Known Issues or Limitations
[Known limitations; if none, write: None identified]
```

Round `>1` to the same reviewer session: send only delta.
Keep the body as short as possible:
- include only sections that changed
- omit unchanged sections entirely
- do not fill the template just because it exists
- if the only meaningful update is "I addressed the prior findings, please re-review", use a one-line body

Use this structure:

```markdown
Task: <task_id>
Action: review_requested
From: <requester_role> <requester_session_id>
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

## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Change status: [unchanged | explicitly updated this round]

## Review Context
- Lane: [task | integration_final]

## Updated Implementation Summary
[Only what changed since the last review request; do not restate the whole diff]

## Changed Paths Since Last Review
- [count + key paths, or `See scope target` when the git target is enough]

## Checks Already Run Since Last Review
- Lint: [new or rerun command/result or `No change`]
- Build/Link: [new or rerun command/result or `No change`]
- Compile/Type-check: [new or rerun command/result or `No change`]
- Tests: [new or rerun command/result or `No change`]
- Other verification: [new manual/browser/scripted checks or `No change`]
- Coverage gaps: [remaining gaps after this round]

## Known Issues or Limitations
[Current remaining limitations; if none, write: None identified]
```

## Mailbox Send + Wakeup

Recommended subject:
- `review request: <task_id> r<round>`

Preferred path: use the `agent_mailbox` MCP tools.

Workflow send sequence:
1. use `agent_mailbox`
2. require an existing `reviewer_session_id` from delegated task context or explicit input; if missing, ask planner instead of creating reviewer locally
3. compose the body with `{{TO_SESSION_ID}}` where the real reviewer session id must appear
4. call `agent_deck_require_session`
   - identify target with `session_id = <reviewer_session_id>`
   - pass `workdir = <current workspace>`
   - do not pass create-only lifecycle fields; this step only verifies/starts the planner-assigned reviewer session
5. use the returned `session_id` as the authoritative `reviewer_session_id`
6. fill the final body and call `mailbox_send` with:
   - `from_address = agent-deck/<requester_session_id>`
   - `to_address = agent-deck/<reviewer_session_id>`
   - `subject = "review request: <task_id> r<round>"`
   - `body = <review-request mailbox body>`

Rules:
- round `1` sends the full review request in mailbox body
- later rounds to the same reviewer send delta only
- if reviewer continuity changed, resend the full review request body
- include a `Checks Already Run` section so reviewer can reuse coder-run verification instead of rerunning the same slow checks
- for each recorded check, include enough command/result detail to show scope and outcome
- keep `coder_tool_profile` / `reviewer_tool_profile` as policy metadata; do not hardcode model/version defaults in this skill
- do not duplicate `Checks Already Run` in a separate verification section; record coverage gaps inside `Checks Already Run`
- treat `reviewer-<task_id>` as the planner-side allocation label; sender should prefer the delegated `reviewer_session_id` over creating a new reviewer session
- do not create reviewer sessions from coder/requester flow; planner owns reviewer allocation
- `mailbox_send` handles the normal non-local reviewer nudge

## Quality Bar

1. Keep concise and copy/paste friendly
2. Keep wording concise and direct
3. Changed paths summary is enough for routing; reviewer should use the git target for exact file details
4. Prefer facts over speculation
5. Keep raw mailbox JSON internal unless user asks
6. Always include `Review Focus` and `Checks Already Run` fields
7. Preserve `workflow_policy` unchanged when present
8. Preserve `special_requirements` unchanged when present
