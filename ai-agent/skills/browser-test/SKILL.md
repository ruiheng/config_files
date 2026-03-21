---
name: browser-test
description: Validates browser behavior with agent-browser and sends a browser-check report back to the requester session.
---

# Browser Test

Run browser validation from a `browser_check_requested` mailbox body and report the result back to the requester session.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines browser-test-specific behavior.

## Input

Provide the mailbox body from `browser_check_requested`.

## Primary Tool

Use `agent-browser` as the main validation tool.

Preferred commands:
- `agent-browser open`
- `agent-browser wait`
- `agent-browser snapshot -i`
- `agent-browser click`
- `agent-browser fill`
- `agent-browser get`
- `agent-browser console`
- `agent-browser errors`
- `agent-browser screenshot`

## Output Format

Use this exact structure as the mailbox body:

```markdown
Task: <task_id>
Action: browser_check_report
From: browser-tester <browser_tester_session_id>
To: <requester_role> <requester_session_id>
Planner: <planner_session_id_or_N/A>
Round: <round>

## Decision
PASS / FAIL / UNKNOWN

## Coverage
[What flow or checks were actually exercised]

## Findings
- [finding or `None`]

## Code Change Summary
- Code changed: [yes/no]
- Branch: [branch name or `N/A`]
- Commit: [hash or `N/A`]
- Files changed: [list or `None`]

## Evidence
- Steps executed: [summary]
- Console errors: [summary or `None`]
- Page errors: [summary or `None`]
- Network observations: [summary or `None`]
- Screenshots: [paths or `None`]

## Reproduction
1. [short repro path]

## Residual Risk
[What remains unverified]
```

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `planner_session_id`: explicit -> mailbox body -> ask
- `browser_tester_session_id`: explicit -> current session id -> mailbox body `To` header -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow:
1. execute the requested browser steps with `agent-browser`
   - if the request explicitly allows browser-tester edits, it may modify display-adjacent code on the requested branch before rerunning browser validation
2. collect runtime evidence
3. produce one `browser_check_report`
4. send it back to the requester with `adwf-send-and-wake --from-session-id "<browser_tester_session_id>" --to-session-id "<requester_session_id>" --subject "browser report: <task_id> r<round>" --body-file -`
5. after sending, immediately use `check-workflow-mail wait=True`

Codex-style execution rule:
- launch `adwf-send-and-wake ... --body-file -` in a background terminal / PTY session
- then write the composed report body to that session's stdin
- keep freshly generated body in stdin
- feed stdin directly, without `printf`, `cat`, heredoc, shell pipes, or redirection

## Rules

- validate the requested browser behavior, not unrelated product areas
- prefer the shortest path that proves or disproves the assertion
- return `UNKNOWN` when environment, auth, data, or setup blocks a reliable result
- by default, do not change code from this role
- if the request explicitly allows browser-tester edits, limit them to display-adjacent code and keep them on the requested branch
- keep findings factual and tied to observed browser evidence
- when idle, stay in `check-workflow-mail wait=True` instead of exiting
