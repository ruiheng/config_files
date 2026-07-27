---
name: browser-test
description: Validate browser behavior with agent-browser.
---

# Browser Test

Handle `browser_check_requested` and its setup round trip; report the result to requester.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Input

Provide `browser_check_requested`, `browser_setup_requested`, or `browser_setup_provided`.

## Primary Tool

Use `agent-browser`: `open` -> `snapshot -i` -> `@e...` interactions -> `console`/`errors` -> screenshot. Use command help only when needed.

## First-Use Environment Check

Before the first browser action in a workflow turn, confirm `agent-browser` with `command -v agent-browser`.

## Output Format

Use this exact structure as the message body:

```markdown
Task: <task_id>
Action: browser_check_report
From: browser-tester <browser_tester_session_id>
To: <requester_role> <requester_session_id>
Planner: <planner_session_id_or_N/A>
Round: <round>
Browser Check: <browser_check_id>

## Decision
PASS / FAIL / UNKNOWN

## Coverage
[What batch of scenarios or checks were actually exercised]

## Findings
- [finding or `None`]

## Code Change Summary
- Code changed: [yes/no]
- Branch: [branch name or `N/A`]
- Commit: [short prefix or `N/A`]
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

Use the `agent-deck-workflow` skill for shared protocol.

Resolve by `Action:` before generic fields:
- all actions: `browser_check_id`: required `Browser Check` header; if absent, fail and request a fresh message; never infer it from Task/Round
- `browser_check_requested`:
  - `task_id`, `round`: explicit -> headers -> ask/default
  - `planner_session_id` (optional): explicit -> message body -> omit when absent or `N/A`
  - `browser_tester_session_id`, `requester_session_id`: `To`, `From`
  - `browser_tester_workspace`, `requester_workspace`: message body -> current workspace -> ask
  - `requester_role`: `From` -> `requester`
  - setup contact id/workspace/role: message body `Setup Contact` -> requester values
- `browser_setup_requested`:
  - `task_id`, `round`: headers
  - tester id/workspace: `From`, `Reply workspace`; contact id/role: `To`
  - omit requester, planner, and original Setup Contact resolution
- `browser_setup_provided`:
  - `task_id`, `round`: headers; contact id/role: `From`; tester id: `To`
  - recover requester, planner, and browser frame only from the matching check history

## Setup Round Trip

For a `browser_check_requested` blocked by login, auth, environment, or test data:
- send `browser_setup_requested` with `From: browser-tester`, `To: Setup Contact`, Task/Round/Browser Check, tester reply workspace, and missing prerequisites; require target at its declared workspace, then `waypost_defer` the claimed check once with `until` set to a bounded setup deadline; never release or re-defer it
- on `browser_setup_requested`, reply `browser_setup_provided` with `From: Setup Contact`, `To: browser-tester`, Task/Round/Browser Check, and setup or `Unavailable: <reason>`, then ACK; never send secrets through Waypost
- on `browser_setup_provided`, ACK; do not resume a check in that turn. Recover the ACKed reply later with `waypost_read` by `Browser Check`
- on the deferred check, read its ACKed matching reply: reply -> continue (`Unavailable` -> `UNKNOWN`); no reply at deadline -> send `UNKNOWN` (`setup unanswered`) and ACK the check. Never resume from an unclaimed reply or match by Task/Round alone

Execution flow (`browser_check_requested`):
1. run the first-use environment check
   - if `agent-browser` is unavailable, stop and report the blocker instead of improvising with another browser tool
2. execute the requested browser steps with `agent-browser`
   - if the request explicitly allows browser-tester edits, it may modify display-adjacent code on the requested branch before rerunning browser validation
   - for missing login, auth, environment, or test data, use Setup Round Trip once; if setup is unavailable, report `UNKNOWN`
3. collect runtime evidence
4. produce one `browser_check_report`
5. use `waypost`
6. first call `agent_deck_require_session` with:
   - `session_id = <requester_session_id>`
   - `workdir = <requester_workspace>`
7. send it back to the requester with `waypost_send`
   - `from_address = agent-deck/<browser_tester_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "browser report: <task_id> r<round>"`
   - `body = <browser-check report body>`

## Rules

- cover the full requested batch by the shortest useful path; report covered, failed, and unverified points
- if environment, auth, data, setup, or identity blocks reliable validation, report `UNKNOWN` or the explicit blocker
- by default, do not change code from this role
- if the request explicitly allows browser-tester edits, limit them to display-adjacent code and keep them on the requested branch
- keep findings factual and tied to observed browser evidence
- prefer setup-contact-provided login/auth/setup context over re-discovering it from scratch
- treat `Browser Check` as the check correlation key; Task/Round describe scope only
- return the report to requester, not Setup Contact
- use the requester workspace from the message body for reply-path session verification; do not substitute the browser-tester's current workspace
- Do not naturally end after writing the report; this workflow turn is complete only after the required `waypost_send` back to the requester has succeeded
