---
name: browser-test-request
description: Generates a browser-check mailbox message for runtime page validation and sends it to a browser-tester session.
---

# Browser Test Request

Generate a concise mailbox message that asks a browser-tester to validate a concrete browser flow with `agent-browser`.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines browser-check-request-specific behavior.

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
- optional `accounts_or_env`
- optional `browser_tester_tool`
- optional `round`

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox/review context -> ask
- `planner_session_id`: explicit -> mailbox/review context -> omit when not available
- `requester_session_id`: explicit -> current session id -> mailbox/review context -> ask
- `requester_role`: explicit -> mailbox/review context -> infer from current workflow stage -> default `requester`
- `browser_tester_session_ref`: explicit -> mailbox/review context -> default `browser-tester-<task_id>`
- `browser_tester_session_id`: explicit actual id -> resolved/created from `browser_tester_session_ref` before send
- `browser_tester_tool`: explicit -> mailbox/review context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
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
[What runtime behavior must be verified]

## Target
- URL or route: [value]
- Entry point: [how to reach it]
- Accounts / env / flags: [value or `None`]

## Steps
1. [step]
2. [step]

## Assertions
- [expected visible result]
- [expected network / console / error condition]

## Evidence To Return
- Decision: PASS / FAIL / UNKNOWN
- Findings with reproduction steps
- Console and page errors summary
- Screenshots only when they add evidence

## Known Constraints
[Any known setup limits or missing prerequisites]
```

## Mailbox Send

Recommended subject:
- `browser check: <task_id> r<round>`

Exact command shape:

```bash
adwf-send-and-wake \
  --from-session-id "<requester_session_id>" \
  --to-session-ref "<browser_tester_session_ref>" \
  --ensure-target-title "<browser_tester_session_ref>" \
  --ensure-target-cmd "<browser_tester_tool>" \
  --parent-session-id "<requester_session_id>" \
  --subject "browser check: <task_id> r<round>" \
  --body-file - \
  --json
```

Codex-style execution rule:
- launch `adwf-send-and-wake ... --body-file -` in a background terminal / PTY session
- then write the composed mailbox body to that session's stdin
- keep freshly generated body in stdin
- feed stdin directly, without `printf`, `cat`, heredoc, shell pipes, or redirection

## Rules

- keep the request focused on one browser flow or one tight group of related checks
- specify assertions, not just exploration goals
- keep the body self-contained; browser-tester should not need workflow files
- use `browser-tester-<task_id>` as a session ref until the helper resolves the real `browser_tester_session_id`
- the report returns to the requester session, not to a fixed reviewer session
