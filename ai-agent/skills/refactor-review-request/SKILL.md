---
name: refactor-review-request
description: Generates and sends a mailbox request for advisory refactor review against a target scope without asking the reviewer to implement changes.
---

# Refactor Review Request

Generate a concise mailbox message that asks a refactor reviewer to inspect code for duplication and simplification opportunities.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Inputs

- `task_id`
- `requester_session_id`
- `requester_role`
- `scope`
- `refactor_goal`
- optional `constraints`
- optional `original_task`
- optional `current_pain_points`
- optional `reviewer_tool`
- optional `planner_session_id`
- optional `round`

Later rounds / existing reviewer lane:
- `refactor_reviewer_session_id`

Round `1` or new reviewer allocation:
- optional `refactor_reviewer_session_ref`

## Continuity Rule

- round `1` uses the full body below
- later rounds to the same refactor-reviewer session send only the delta since the previous round
- if reviewer continuity changed or is unknown, fall back to the full body

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> workflow context -> ask
- `requester_session_id`: explicit -> current session id -> ask
- `requester_role`: explicit -> infer from current workflow stage -> default `requester`
- `planner_session_id`: explicit -> workflow context -> default `N/A`
- `refactor_reviewer_session_id`: explicit actual id -> workflow context actual id -> ask
- `refactor_reviewer_session_ref`: explicit -> workflow context -> default `refactor-reviewer-<task_id>`
  - use only when allocating a new reviewer session before the first send
- `scope`: explicit -> workflow context -> ask
- `refactor_goal`: explicit -> workflow context -> default `identify duplication and simplification opportunities`
- `reviewer_tool`: explicit -> workflow context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
- `round`: explicit -> workflow context -> default `1`

## Mailbox Body

Round `1` or new reviewer session: use the full body below.

```markdown
Task: <task_id>
Action: refactor_review_requested
From: <requester_role> <requester_session_id>
To: refactor-reviewer {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line refactor review request summary]

## Scope
[Files, module, branch, or code area in scope]

## Refactor Goal
[What kind of simplification is wanted]

## Original Task
[Original task or `N/A`]

## Constraints
- [constraint or `None`]

## Current Pain Points
- [pain point or `None`]

## Review Boundaries
- advisory only
- no implementation
- preserve existing behavior unless explicitly stated otherwise
```

Round `>1` to the same reviewer session: send only delta.

```markdown
Task: <task_id>
Action: refactor_review_requested
From: <requester_role> <requester_session_id>
To: refactor-reviewer {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line delta summary]

## Delta Since Last Round
- Scope changes: [what changed or `None`]
- New pain points: [what changed or `None`]
- Constraints changed: [what changed or `None`]
- Previous advice adopted or rejected: [brief summary or `N/A`]

## Current Review Goal
[What this round should focus on]
```

## Mailbox Send

Recommended subject:
- `refactor review request: <task_id> r<round>`

Use the `agent_mailbox` MCP tools:
1. use `agent_mailbox`
2. compose the body with `{{TO_SESSION_ID}}` where the real reviewer session id must appear
3. if this is round `1` for a new reviewer session, call `agent_deck_create_session`
   - `ensure_title = <refactor_reviewer_session_ref>`
   - `ensure_cmd = <reviewer_tool>`
   - `workdir = <current workspace>`
   - `parent_session_id = <requester_session_id>`
   - `no_parent_link = false`
   - record the returned `refactor_reviewer_session_id` and carry it in all later workflow turns
4. otherwise call `agent_deck_require_session`
   - `session_id = <refactor_reviewer_session_id>`
   - `workdir = <current workspace>`
5. use the returned `session_id` as the authoritative `refactor_reviewer_session_id`
6. fill the final body and call `mailbox_send` with:
   - `from_address = agent-deck/<requester_session_id>`
   - `to_address = agent-deck/<refactor_reviewer_session_id>`
   - `subject = "refactor review request: <task_id> r<round>"`
   - `body = <refactor review request body>`

## Rules

- request advisory refactor review only
- keep the body self-contained
- do not ask the reviewer to implement changes
- focus on one coherent code area or one review goal per request
- later rounds to the same reviewer should be delta-only
- if reviewer continuity changes, resend full context
- create new refactor-reviewer sessions through `agent_deck_create_session` with `parent_session_id = <requester_session_id>` and `no_parent_link = false`
- after the first create step, later workflow turns must reuse the real `refactor_reviewer_session_id`; do not fall back to `refactor_reviewer_session_ref`
