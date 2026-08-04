---
name: review-request
description: Request Agent Deck code review.
---

# Review Request

Generate a copy/paste-friendly Waypost message for code review.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Required Scope Selection

Before generating the message, determine one scope:
1. `uncommitted changes`
2. `specific short commit ref`
3. `branch`

`integration_final`: `branch` only; require explicit `base_branch` distinct from target. Reject `commit` / `uncommitted`; do not convert or send.

Workflow continuity rule:
- In an ongoing implementation session, if scope is not explicit, inherit from active delegated task for current `task_id`
- Ask a clarification question only when multiple scopes are equally plausible or no reliable scope can be inferred

For a task review with a complete Workspace Handoff:
- preserve recorded `start_branch`, `integration_branch`, and `task_branch` from delegated task context
- treat that branch plan as immutable task context unless the user explicitly changes it

## Inputs

- Scope type: `uncommitted` | `commit` | `branch`
- Scope value:
  - `uncommitted`: no value
  - `commit`: short commit ref
  - `branch`: branch name
- Optional:
  - `base_branch` (branch or short commit ref, for branch scope)
  - `original_task`
  - `requester_role`
  - `requester_session_id`
  - `reviewer_session_ref`
  - `reviewer_session_id`
  - `review_lane`: `task` | `integration_final` | `standalone`
  - `review_focus` (explicit optional emphasis; do not infer)
  - `author_intent`
  - `author_noted_issues`
  - `user_decisions` (all prior task-scope decisions made by the user)
  - `coder_tool`
  - `coder_tool_profile`
  - `reviewer_tool`
  - `reviewer_tool_profile`
  - `start_branch`
  - `integration_branch`
  - `task_branch`
  - complete `Workspace Handoff`: `worker_workspace`, `task_dir`, `workspace_lifecycle`

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
  - `integration_final`: require explicit `base_branch`, distinct from target; never fall back to `integration_branch`
  - otherwise choose base: `base_branch` -> recorded `integration_branch` -> ask
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
4. if a material change is outside the original task and no User Decision covers it, ask the user before sending; never hide it as noise
5. ask one short clarification question if relevance is uncertain

## Review Independence

Provide task intent, scope, constraints, and verification evidence, not a pre-review.
- Treat `Author Intent`, `Optional Review Focus`, and `Author-Noted Issues or Limitations` as non-authoritative and non-exhaustive context.
- Let the reviewer inspect the full scope and choose risk angles independently.
- Omit optional focus and author notes when the original task plus git target are enough.

## Agent Deck Mode

Use the `agent-deck-workflow` skill for shared protocol.

Skill-specific context resolution:
- `task_id`: explicit -> branch `task/<task_id>` -> delegated context -> ask
- `review_lane`: explicit -> delegated context -> `task` for an active delegated task -> `standalone`
- `planner_session_id`: `task` / `integration_final` -> explicit/context -> ask; `standalone` -> omit
- `planner_workspace`: `task` / `integration_final` -> explicit -> delegated context -> current workspace when requester is planner -> ask; `standalone` -> omit
- `requester_role`: explicit -> delegated context -> current workflow role -> default `coder`
- `requester_session_id`: explicit -> current session id -> delegated context -> ask
- `reviewer_session_ref`: explicit -> delegated context -> `reviewer-<review_lane>-<owner_session_id>-<task_id>`; owner is planner for `task` / `integration_final`, requester for `standalone`
- `reviewer_session_id`: explicit actual id -> delegated context actual id -> created on demand when missing
- `workflow_policy` (optional): explicit -> delegated context -> default unattended policy
- `special_requirements` (optional fallback): explicit -> delegated context -> omit
- `user_decisions` (optional): explicit -> delegated context -> omit
- `coder_tool_profile`: explicit -> delegated context -> omit when `coder_tool` is already a full command -> default current-tool continuity or resolver role default `coder`
- `coder_tool_cmd`: explicit full command -> delegated context resolved command -> current AI tool when continuity is intended -> shared tool-resolution contract for role `coder`
- `reviewer_tool_profile`: explicit -> delegated context -> omit when `reviewer_tool` is already a full command -> default resolver role default `reviewer`
- `reviewer_tool_cmd`: explicit full command -> delegated context resolved command -> shared tool-resolution contract for role `reviewer`
- `round`: explicit -> infer from context -> default `1`
- `workspace_handoff`: task -> explicit/delegated complete handoff -> preserve; missing/partial -> ask; `integration_final` / `standalone` -> omit
- `start_branch`, `integration_branch`, `task_branch` (task only): explicit -> delegated context -> ask; otherwise omit

Handoff gate:
- task: require complete Handoff and recorded Branch Plan
- `integration_final` / `standalone`: omit task Branch Plan and Handoff

Workspace-closeout branch-plan guard:
- `integration_branch` must be the non-task landing branch; if it looks like `task/*`, ask for the real integration branch instead of sending the review request

When this is a follow-up round after reviewer feedback, summarize which findings were adopted, which were rejected, and why.
Reviewer feedback is advisory input, not automatic instructions.

Review-request continuity rule:
- round `1` uses the full review-request body
- round `>1` to the same reviewer session uses a delta-only body
- if the reviewer session changed or reviewer continuity is unknown, fall back to the full review-request body
- a task review remains `task` through every round
- task repeats its complete Handoff and Branch Plan every round; a full request includes all User Decisions and a delta includes decisions made since the prior review
- every delta retains `Task`, `Action`, `From`, `To`, `Round`, and Lane; task / `integration_final` also retain Planner fields
- delta-only means terse:
  - do not repeat the original task, file list, or unchanged verification; task always repeats Branch Plan and Handoff
  - summarize only changed scope, responses to prior findings, and new verification evidence; let the reviewer decide what to re-check
  - one-line body applies only to delta content; task retains its required fields

Identity rules:
- `review_requested` sender must be the active requester session id for this review lane
- use the bound Waypost sender context for sender validation
- Reuse an existing reviewer/tool unless an explicit requested command or profile conflicts; inferred/default differences do not.
- For an explicit conflict, ask whether to keep the reviewer or reassign it.

Reviewer reuse gate:
- expected parent = owner; expected group = owner's group. Owner is planner for `task` / `integration_final`, requester for `standalone`
- inspect candidate: `agent-deck session show <candidate_id_or_ref> --json`; check `path`, `parent_session_id`, `group`, `command`, `profile`
- reuse only when path, parent, and group match expected ownership
- compare explicit `reviewer_tool` / `reviewer_tool_profile` with candidate command/profile; on conflict ask keep or reassign, never silently require
- if a default ref resolves to an ineligible session, derive a fresh lane-scoped ref before create; for an input/context ID/ref mismatch, ask and do not create

Commit reference rule:
- in message content, use a short commit ref, not a full 40-char hash

## Output Template

Round `1` or new reviewer session: use the full body below.
Omit `## User Decisions` when no temporary scope decision exists.

Use this structure as the message body. Omit task Branch Plan and Handoff for `integration_final` / `standalone`; task includes both. `standalone` also omits planner headers. Keep tool routing internal.

```markdown
Task: <task_id>
Action: review_requested
From: <requester_role> <requester_session_id>
To: reviewer {{TO_SESSION_ID}}
Round: <round>

## Summary
[One-line review request summary]

## Scope
- Type: [uncommitted | commit | branch]
- Target: [working tree | short commit ref | branch name]
- Base (branch): [base ref or N/A]

## Original Task
[Original task text from explicit input or active session context. Use `Not provided` only after explicit clarification that no task text is available.]

## User Decisions
[all user scope decisions known for this task; only when present]

## Review Context
- Lane: [task | integration_final | standalone]

## Optional Review Focus
- [Explicit optional emphasis; must not limit the full independent review]

## Author Intent (Optional)
[Brief non-authoritative intent note; do not restate the diff]

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

## Author-Noted Issues or Limitations (Optional)
[Non-exhaustive author notes]
```

For `task` / `integration_final`, insert after `To` in either template:

```markdown
Planner: <planner_session_id>
Planner workspace: <planner_workspace>
```

For task, insert after `Original Task`:

```markdown
## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Stability rule: treat this recorded branch plan as immutable task context unless the user explicitly changes it

## Workspace Handoff
- Worker workspace: [worker_workspace]
- Task dir: [task_dir]
- Workspace lifecycle: [shared; cleanup=none | temporary; cleanup=planner]
```

Round `>1` to the same reviewer session: send only delta.
Keep the body as short as possible:
- include only sections that changed
- task always repeats Branch Plan and Handoff; other lanes omit unchanged sections
- do not fill the template just because it exists
- `integration_final` / `standalone` may use a one-line body; task keeps its Branch Plan and Handoff

Use this structure. Omit task Branch Plan and Handoff for `integration_final` / `standalone`; task includes both. `standalone` omits planner headers.

```markdown
Task: <task_id>
Action: review_requested
From: <requester_role> <requester_session_id>
To: reviewer {{TO_SESSION_ID}}
Round: <round>

## Summary
[One-line delta summary]

## Delta Since Last Review
- Scope: [what changed in reviewed scope]
- Findings addressed: [adopted items]
- Findings rejected: [rejected items + rationale]
- Author-noted new risks or open questions: [only if changed]

## User Decisions
[user scope decisions made since the last review; only when present]

## Review Context
- Lane: [task | integration_final | standalone]

## Author Update Since Last Review (Optional)
[Non-authoritative intent note for what changed; do not restate the diff]

## Changed Paths Since Last Review
- [count + key paths, or `See scope target` when the git target is enough]

## Checks Already Run Since Last Review
- Lint: [new or rerun command/result or `No change`]
- Build/Link: [new or rerun command/result or `No change`]
- Compile/Type-check: [new or rerun command/result or `No change`]
- Tests: [new or rerun command/result or `No change`]
- Other verification: [new manual/browser/scripted checks or `No change`]
- Coverage gaps: [remaining gaps after this round]

## Author-Noted Issues or Limitations (Optional)
[Current non-exhaustive author notes]
```

For task, insert after `Delta Since Last Review`:

```markdown
## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Change status: [unchanged | explicitly updated this round]

## Workspace Handoff
- Worker workspace: [worker_workspace]
- Task dir: [task_dir]
- Workspace lifecycle: [shared; cleanup=none | temporary; cleanup=planner]
```

## Waypost Message Send + Wakeup

Recommended subject:
- `review request: <task_id> r<round>`

Preferred path: use the `waypost` MCP tools.

Workflow send sequence:
1. use `waypost`
2. compose the body with `{{TO_SESSION_ID}}` where the real reviewer session id must appear
3. choose candidate: known `reviewer_session_id`, otherwise resolve `reviewer_session_ref`
4. apply Reviewer reuse gate; if it asks, stop. If eligible, call `agent_deck_require_session` with its `session_id` and `workdir = <current workspace>`
5. if no eligible candidate, resolve reviewer tool metadata by the shared tool-resolution contract for role `reviewer`, then call `agent_deck_create_session` with:
     - `ensure_title = <reviewer_session_ref>`
     - `ensure_cmd = <reviewer_tool_cmd>`
     - `workdir = <current workspace>`
     - `task` / `integration_final`: `parent_session_id = <planner_session_id>`, `group_path = <planner session group; empty string for root>`
     - `standalone`: `parent_session_id = <requester_session_id>`, `group_path = <requester session group; empty string for root>`
     - `no_parent_link = false`
6. use the returned `session_id` as the authoritative `reviewer_session_id`
7. fill the final body and call `waypost_send` with:
   - `from_address = agent-deck/<requester_session_id>`
   - `to_address = agent-deck/<reviewer_session_id>`
   - `subject = "review request: <task_id> r<round>"`
   - `body = <review-request message body>`

Rules:
- round `1` sends the full review request in message body
- later rounds to the same reviewer send delta only
- if reviewer continuity changed, resend the full review request body
- include a `Checks Already Run` section so reviewer can reuse coder-run verification instead of rerunning the same slow checks
- for each recorded check, include enough command/result detail to show scope and outcome
- keep tool/model routing internal; use shared tool-resolution policy
- do not duplicate `Checks Already Run` in a separate verification section; record coverage gaps inside `Checks Already Run`
- reuse only an ownership- and tool-compatible reviewer resolved by ID/ref; otherwise create a fresh lane-scoped reviewer
- create reviewers only from `review-request`: parent task/integration to planner; parent standalone to requester
- `waypost_send` may trigger a best-effort non-local reviewer nudge; correctness relies on Waypost message delivery
- follow the shared Async sender rule for the review reply

## Quality Bar

1. Keep concise and copy/paste friendly
2. Keep wording concise and direct
3. Changed paths summary is enough for routing; reviewer should use the git target for exact file details
4. Prefer facts over speculation
5. Keep raw message JSON internal unless user asks
6. Always include `Checks Already Run`; include `Optional Review Focus` only when the requester explicitly provides useful emphasis
7. Preserve `workflow_policy` unchanged when present
8. Preserve `special_requirements` unchanged when present
9. Preserve User Decisions unchanged when present
