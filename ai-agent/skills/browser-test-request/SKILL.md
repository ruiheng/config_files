---
name: browser-test-request
description: Request Agent Deck browser validation.
---

# Browser Test Request

Generate a concise Waypost message that asks a browser-tester to validate one coherent browser test batch with `agent-browser`.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Inputs

- `task_id`
- `planner_session_id` (optional)
- `requester_session_id`
- `requester_workspace`
- `requester_role`
- optional `setup_contact_session_id`
- optional `setup_contact_workspace`
- optional `setup_contact_role`
- optional `browser_tester_session_id`
- optional `browser_tester_session_ref`
- optional `browser_tester_workspace`
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
- optional `browser_tester_tool_profile`
- optional `round`
- optional `browser_check_id`

## Agent Deck Mode

Use the `agent-deck-workflow` skill for shared protocol.

Skill-specific context resolution:
- `task_id`: explicit -> message/review context -> ask
- `planner_session_id`: explicit -> message/review context -> omit when not available
- `requester_session_id`: explicit -> message/review context -> current session id -> ask
- `requester_workspace`: explicit -> current workspace -> ask
- `requester_role`: explicit -> message/review context -> infer from current workflow stage -> default `requester`
- `setup_contact_session_id`: explicit -> review context original requester -> requester_session_id
- `setup_contact_workspace`: explicit -> review context original requester workspace -> requester_workspace
- `setup_contact_role`: explicit -> review context original requester -> requester_role
- `browser_tester_session_id`: explicit actual id -> workflow context actual id -> omit
- `browser_tester_session_ref`: explicit -> workflow context -> default `browser-tester`
- `browser_tester_workspace`: explicit -> message/review context -> current workspace
- `browser_tester_tool_profile`: explicit/context -> resolver default only on create
- `browser_tester_tool_cmd`: explicit -> context/existing metadata -> shared resolver only on create
- `round`: explicit -> context -> default `1`
- `browser_check_id`: explicit -> generate one opaque unique ID for this request; never derive it from task/round

Identity rules:
- `browser_check_requested` sender must use the resolved `requester_session_id`
- for a review-driven check, route report to reviewer; preserve original requester as setup contact
- otherwise setup contact defaults to requester; current session id is only a final fallback and diagnostic source

## Waypost Message Body

Use this exact structure:

```markdown
Task: <task_id>
Action: browser_check_requested
From: <requester_role> <requester_session_id>
To: browser-tester {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>
Browser Check: <browser_check_id>

## Summary
[One-line browser-check summary]

## Goal
[What runtime behavior or feature area must be verified]

## Target
- URL or route: [value]
- Entry point: [how to reach it]
- Accounts / env / flags: [value or `None`]
- Login / auth: [credentials source, auth profile, or `Ask Setup Contact/user`]
- Test data / setup: [seed data, fixtures, prerequisites, or `None`]

## Workspace Routing
- Requester workspace: [absolute path]
- Browser tester workspace: [absolute path]

## Setup Contact
- Contact: [role + session id]
- Workspace: [absolute path]

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

## Tool Context
- Browser tester tool profile: [browser_tester_tool_profile or `explicit`]
- Browser tester tool cmd: [browser_tester_tool_cmd]
```

## Waypost Message Send

Recommended subject:
- `browser check: <task_id> r<round>`

Use the `waypost` MCP tools:
- use `waypost`
- resolve the browser tester target before send:
  - if `browser_tester_session_id` is already known, call `agent_deck_require_session`
    - `session_id = <browser_tester_session_id>`
    - `workdir = <browser_tester_workspace>`
    - keep the existing browser tester tool metadata; do not resolve a fresh `browser_tester_tool_cmd`
  - otherwise call `agent_deck_resolve_session`
    - `session = <browser_tester_session_ref>`
  - if that ref resolves and its returned `path` matches `<browser_tester_workspace>`, call `agent_deck_require_session`
    - `session_id = <resolved browser_tester_session_id>`
    - `workdir = <browser_tester_workspace>`
    - keep the existing browser tester tool metadata; do not resolve a fresh `browser_tester_tool_cmd`
  - if that ref does not resolve, or it resolves to a different workspace path, call `agent_deck_create_session`
    - first resolve `browser_tester_tool_profile` / `browser_tester_tool_cmd` by the shared tool-resolution contract for role `browser_tester`
      - preserve explicit full `browser_tester_tool` unchanged when provided
      - otherwise resolve the role `browser_tester` command
    - `ensure_title = <browser_tester_session_ref>`
    - `ensure_cmd = <browser_tester_tool_cmd>`
    - `workdir = <browser_tester_workspace>`
    - `no_parent_link = true`
- use the returned `session_id` as the authoritative `browser_tester_session_id`
- fill `{{TO_SESSION_ID}}` in the message body before sending
- call `waypost_send` with:
  - `from_address = agent-deck/<requester_session_id>`
  - `to_address = agent-deck/<browser_tester_session_id>`
  - `subject = "browser check: <task_id> r<round>"`
  - `body = <browser-check message body>`

## Rules

- one coherent batch; group related scenarios in a compact matrix and state assertions
- keep the body self-contained; browser-tester should not need workflow files
- prefer reusing the long-lived `browser-tester` session for this environment
- if a resolved `browser-tester` ref points at a different workspace, ignore that hit and create a workspace-local browser tester instead
- if no reusable `browser-tester` session exists in the requested workspace, create it from this request flow and continue
- carry both requester and browser-tester workspaces in the message body so later `agent_deck_require_session` calls can verify the correct worktree
- on require paths, preserve existing session tool metadata
- once this request resolves or creates the target, use the returned real `browser_tester_session_id` for the actual message send
- a review-driven report returns to reviewer; otherwise it returns to the supplied requester
- setup questions go to Setup Contact; reports always return to requester
- retain `Browser Check` unchanged in setup traffic and report
- if browser-tester edits are allowed, request body must say so explicitly and provide the branch name
- browser-tester edits are only for display-adjacent code
- review-driven tester edits are provisional; delivery owner must submit them in a new review round before acceptance
- leave `listener_message` empty unless a rare bootstrap/control case truly needs a pre-message startup instruction
