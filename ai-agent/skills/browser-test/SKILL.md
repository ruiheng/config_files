---
name: browser-test
description: Validates browser behavior with agent-browser and sends a browser-check report back to the requester session.
---

# Browser Test

Run browser validation from a `browser_check_requested` mailbox body and report the result back to the requester session.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

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

## Basic agent-browser Help

Keep this basic CLI shape in mind while executing browser checks:

```text
agent-browser - fast browser automation CLI for AI agents

Usage: agent-browser <command> [args] [options]

Core Commands:
  open <url>                 Navigate to URL
  click <sel>                Click element (or @ref)
  type <sel> <text>          Type into element
  fill <sel> <text>          Clear and fill
  press <key>                Press key (Enter, Tab, Control+a)
  wait <sel|ms>              Wait for element or time
  screenshot [path]          Take screenshot
  snapshot                   Accessibility tree with refs (for AI)
  eval <js>                  Run JavaScript
  close                      Close browser

Navigation:
  back                       Go back
  forward                    Go forward
  reload                     Reload page

Get Info:  agent-browser get <what> [selector]
  text, html, value, attr <name>, title, url, count, box, styles, cdp-url

Check State:  agent-browser is <what> <selector>
  visible, enabled, checked

Examples:
  agent-browser open example.com
  agent-browser snapshot -i
  agent-browser click @e2
  agent-browser fill @e3 "test@example.com"
  agent-browser get text @e1
  agent-browser screenshot --full
  agent-browser wait --load networkidle
```

For browser-test work, default to `snapshot -i` to get stable element refs, then interact via `@e...` refs when possible.

## First-Use Environment Check

Before the first browser action in a workflow turn, run a minimal environment check:
1. confirm `agent-browser` is available with `command -v agent-browser`
2. use `agent_mailbox`

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

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `planner_session_id`: explicit -> mailbox body -> ask
- `browser_tester_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_workspace`: explicit -> mailbox body -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow:
1. run the first-use environment check
   - if `agent-browser` is unavailable, stop and report the blocker instead of improvising with another browser tool
2. execute the requested browser steps with `agent-browser`
   - if the request explicitly allows browser-tester edits, it may modify display-adjacent code on the requested branch before rerunning browser validation
   - if login, auth, environment, or test-data prerequisites are missing, ask the requester first; ask the user directly when requester context is unavailable or user input is clearly required
3. collect runtime evidence
4. produce one `browser_check_report`
5. use `agent_mailbox`
6. first call `agent_deck_ensure_session` with:
   - `session_id = <requester_session_id>`
   - `workdir = <requester_workspace>`
7. send it back to the requester with `mailbox_send`
   - `from_address = agent-deck/<browser_tester_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "browser report: <task_id> r<round>"`
   - `body = <browser-check report body>`

## Rules

- validate the full requested browser test batch, not just one narrow sub-step and not unrelated product areas
- prefer the shortest path that still covers the requested scenarios, assertions, and regression checks
- when the request includes multiple related test points, report which ones were covered, which failed, and which remained unverified
- return `UNKNOWN` when environment, auth, data, or setup blocks a reliable result
- if `agent-browser` is missing, or required session identity cannot be resolved from explicit metadata plus bound mailbox sender context, state that explicitly in the report or blocker message
- by default, do not change code from this role
- if the request explicitly allows browser-tester edits, limit them to display-adjacent code and keep them on the requested branch
- keep findings factual and tied to observed browser evidence
- prefer requester-provided login/auth/setup context over re-discovering it from scratch
- use the requester workspace from the mailbox body for reply-path session verification; do not substitute the browser-tester's current workspace
- Do not naturally end after writing the report; this workflow turn is complete only after the required `mailbox_send` back to the requester has succeeded
