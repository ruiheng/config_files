---
name: browser-test-request
description: Generates a browser-check mailbox message for runtime page validation and sends it to a browser-tester session.
---

# Browser Test Request

Generate a concise mailbox message that asks a browser-tester to validate one coherent browser test batch with `agent-browser`.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Inputs

- `task_id`
- `planner_session_id` (optional)
- `requester_session_id`
- `requester_role`
- `browser_tester_session_ref` or `browser_tester_session_id`
- `goal`
- `target_url` or route
- `steps`
- `assertions`
- optional `allow_display_adjacent_edits`
- optional `browser_tester_branch`
- optional `accounts_or_env`
- optional `login_or_auth`
- optional `test_data_or_setup`
- optional `browser_tester_tool`
- optional `round`

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox/review context -> ask
- `planner_session_id`: explicit -> mailbox/review context -> omit when not available
- `requester_session_id`: explicit -> current session id -> mailbox/review context -> ask
- `requester_role`: explicit -> mailbox/review context -> infer from current workflow stage -> default `requester`
- `browser_tester_session_ref`: explicit -> mailbox/review context -> default `browser-tester`
- `browser_tester_session_id`: explicit actual id -> resolved/created from `browser_tester_session_ref` before send
- `browser_tester_tool`: explicit -> mailbox/review context -> default `codex -m gpt-5.4 -c model_reasoning_effort="medium"`
- `round`: explicit -> context -> default `1`

Identity rules:
- `browser_check_requested` sender must be active requester session id
- resolve current session id once and reuse it for sender validation in the whole turn

## Mailbox Body

Use this exact structure:

```markdown
Task: <task_id>
Action: browser_check_requested
From: <requester_role> <requester_session_id>
To: browser-tester {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line browser-check summary]

## Goal
[What runtime behavior or feature area must be verified]

## Target
- URL or route: [value]
- Entry point: [how to reach it]
- Accounts / env / flags: [value or `None`]
- Login / auth: [credentials source, auth profile, or `Ask requester/user`]
- Test data / setup: [seed data, fixtures, prerequisites, or `None`]

## Steps
1. [step]
2. [step]

## Assertions
- [expected visible result]
- [expected network / console / error condition]

## Test Points
- [related scenario / assertion group 1]
- [related scenario / assertion group 2]
- [related edge case or regression check]

## Browser Tester Edit Permission
- Allowed: [yes/no]
- Branch: [branch name or `N/A`]
- Scope: [display-adjacent only | read-only]

## Known Constraints
[Any known setup limits or missing prerequisites]
```

## Mailbox Send

Recommended subject:
- `browser check: <task_id> r<round>`

Use the `agent_mailbox` MCP tools:
- use `agent_mailbox`
- call `agent_deck_ensure_session` with:
  - `session_ref = <browser_tester_session_ref>`
  - `ensure_title = <browser_tester_session_ref>`
  - `ensure_cmd = <browser_tester_tool>`
  - `parent_session_id = <requester_session_id>`
  - normal workflow: do not pass `listener_message`
- call `mailbox_send` with:
  - `from_address = agent-deck/<requester_session_id>`
  - `to_address = agent-deck/<browser_tester_session_id>`
  - `subject = "browser check: <task_id> r<round>"`
  - `body = <browser-check mailbox body>`

Default browser tester agent command:

```bash
codex -m gpt-5.4 -c model_reasoning_effort="medium"
```

## Rules

- keep the request focused on one page, feature area, or one coherent validation batch
- include all related test points for that batch in one request instead of splitting them into many tiny mailbox tasks
- prefer a compact test matrix of related scenarios, states, and regressions over a module-style task breakdown
- specify assertions, not just exploration goals
- keep the body self-contained; browser-tester should not need workflow files
- use a stable long-lived browser-tester session ref such as `browser-tester`
- the report returns to the requester session, not to a fixed reviewer session
- if browser-tester edits are allowed, request body must say so explicitly and provide the branch name
- browser-tester edits are only for display-adjacent code
- requester should provide required login, auth, environment, and test-data context whenever possible
- leave `listener_message` empty unless a rare bootstrap/control case truly needs a pre-mailbox startup instruction
