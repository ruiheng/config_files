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
- `requester_workspace`
- `requester_role`
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

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox/review context -> ask
- `planner_session_id`: explicit -> mailbox/review context -> omit when not available
- `requester_session_id`: explicit -> mailbox/review context -> current session id -> ask
- `requester_workspace`: explicit -> current workspace -> ask
- `requester_role`: explicit -> mailbox/review context -> infer from current workflow stage -> default `requester`
- `browser_tester_session_id`: explicit actual id -> workflow context actual id -> omit
- `browser_tester_session_ref`: explicit -> workflow context -> default `browser-tester`
- `browser_tester_workspace`: explicit -> mailbox/review context -> current workspace
- `browser_tester_tool_profile`: explicit -> mailbox/review context -> omit when `browser_tester_tool` is already a full command -> default resolver role default `browser_tester` only when creating a new browser-tester session
- `browser_tester_tool_cmd`: explicit full command -> mailbox/review context resolved command -> existing session metadata on require paths -> resolve through `~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js` only on create path
- `round`: explicit -> context -> default `1`

Identity rules:
- `browser_check_requested` sender must use the resolved `requester_session_id`
- current session id is only a final fallback and diagnostic source; review workflows must preserve the original requester from mailbox/review context

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

## Workspace Routing
- Requester workspace: [absolute path]
- Browser tester workspace: [absolute path]

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

## Mailbox Send

Recommended subject:
- `browser check: <task_id> r<round>`

Use the `agent_mailbox` MCP tools:
- use `agent_mailbox`
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
    - first resolve `browser_tester_tool_profile` / `browser_tester_tool_cmd`
      - preserve explicit full `browser_tester_tool` unchanged when provided
      - otherwise run `node ~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js --role browser_tester --profile <browser_tester_tool_profile when present> --format json`
      - if browser-tester session creation later fails because the resolved command is unusable and the chosen profile has more candidates, rerun the resolver with `--exclude-command <failed browser_tester_tool_cmd>` and retry once with the next candidate
    - `ensure_title = <browser_tester_session_ref>`
    - `ensure_cmd = <browser_tester_tool_cmd>`
    - `workdir = <browser_tester_workspace>`
    - `no_parent_link = true`
- use the returned `session_id` as the authoritative `browser_tester_session_id`
- fill `{{TO_SESSION_ID}}` in the mailbox body before sending
- call `mailbox_send` with:
  - `from_address = agent-deck/<requester_session_id>`
  - `to_address = agent-deck/<browser_tester_session_id>`
  - `subject = "browser check: <task_id> r<round>"`
  - `body = <browser-check mailbox body>`

## Rules

- keep the request focused on one page, feature area, or one coherent validation batch
- include all related test points for that batch in one request instead of splitting them into many tiny mailbox tasks
- prefer a compact test matrix of related scenarios, states, and regressions over a module-style task breakdown
- specify assertions, not just exploration goals
- keep the body self-contained; browser-tester should not need workflow files
- prefer reusing the long-lived `browser-tester` session for this environment
- if a resolved `browser-tester` ref points at a different workspace, ignore that hit and create a workspace-local browser tester instead
- if no reusable `browser-tester` session exists in the requested workspace, create it from this request flow and continue
- carry both requester and browser-tester workspaces in the mailbox body so later `agent_deck_require_session` calls can verify the correct worktree
- keep `browser_tester_tool_profile` as policy metadata and `browser_tester_tool_cmd` as the concrete session-create input for newly created sessions; on require paths, preserve existing session tool metadata
- once this request resolves or creates the target, use the returned real `browser_tester_session_id` for the actual mailbox send
- the report returns to the requester session, not to a fixed reviewer session
- if browser-tester edits are allowed, request body must say so explicitly and provide the branch name
- browser-tester edits are only for display-adjacent code
- requester should provide required login, auth, environment, and test-data context whenever possible
- leave `listener_message` empty unless a rare bootstrap/control case truly needs a pre-mailbox startup instruction
