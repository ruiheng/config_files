# Skills Workflow

This document describes the multi-agent workflow built around the skills in this directory.

## Roles

- Agent 1, **Planner** (`delegate-task`): planning agent, prepares the execution brief and sends it through mailbox
- Agent 2, **Coder** (implementation): executes tasks and applies code changes
- Agent 3, **Reviewer** (`review-code`): review agent, produces the full review report directly in mailbox body
- Agent 4, **Browser Tester** (`browser-test`): runtime validation agent, checks browser behavior with `agent-browser` and reports evidence back to the requester session
- User: makes acceptance decisions when the workflow is human-gated

## Core Transport

- `agent-mailbox` is the authoritative workflow message layer
- `agent-deck` is used either to start target sessions into mailbox-wait mode or to nudge already active sessions to check mail
- Workflow messages live in mailbox `subject` + `body`
- When sending mailbox body text, prefer `agent-mailbox send --body-file -` and feed stdin directly
- Use `adwf-send-and-wake` for cross-session workflow delivery
- In Codex-style environments, launch `adwf-send-and-wake --body-file -` in a background terminal / PTY session and write body text to that session's stdin
- Run every `agent-mailbox` command outside sandbox
- Run mailbox state-mutating `agent-mailbox` commands serially, not in parallel
- The workflow does not generate Markdown handoff files by default

## End-to-End Loop

1. User asks Planner to prepare work.
2. Planner runs `delegate-task`, starts Coder into `check-workflow-mail wait=True` when needed, or nudges the existing Coder session, then sends one delegate mailbox message.
3. Coder implements changes.
4. Coder runs `review-request`, starts Reviewer into `check-workflow-mail wait=True` when needed, or nudges the existing Reviewer session, then sends one review-request mailbox message.
5. Reviewer runs `review-code` and sends either:
   - `rework_required` back to Coder, or
   - `browser_check_requested` to Browser Tester, or
   - `stop_recommended` to the user decision point.
6. Browser Tester runs `browser-test` and sends `browser_check_report` back to the requester session.
7. If user wants another iteration, Reviewer sends `user_requested_iteration` to Coder.
8. Repeat until the user decides quality is acceptable, or policy auto-accepts.
9. After acceptance, Reviewer runs `review-closeout` and sends one closeout mailbox message to Planner.
10. Planner reads the closeout mailbox body, then batches merge/progress/next-task work.
11. Coder, Reviewer, and Browser Tester can be fully exited.

## Flow Diagram

```mermaid
flowchart TD
    P[Planner] -->|mailbox: execute_delegate_task| C[Coder]
    C -->|mailbox: review_requested| R[Reviewer]
    R -->|mailbox: browser_check_requested| B[Browser Tester]
    X[Requester] -->|mailbox: browser_check_requested| B
    B -->|mailbox: browser_check_report| X
    R -->|review result| DEC{Quality Accepted?}
    DEC -- No --> C
    DEC -- Yes --> R
    R -->|mailbox: closeout_delivered| P

    style DEC fill:#fff3cd,stroke:#b58900,stroke-width:1px
```

## Operational Notes

- `review-code` remains the authoritative full review output
- `browser-test` is runtime evidence only; acceptance stays with whichever role requested the check
- `review-closeout` is the compact planner handoff after acceptance
- The receiver should always read mailbox `body` first
- A received workflow mail is executable work, not a notification to acknowledge and ignore
- Use `check-workflow-mail` as the receiver-side wake handler
- External files are supplemental references only, not the default transport

## Incremental Automation with Agent Deck

Current recommended operating mode:

1. Keep `planner` as a long-lived session.
2. Create `coder-<task_id>`, `reviewer-<task_id>`, and `browser-tester-<task_id>` per task when needed.
3. Keep coder/reviewer/browser-tester in `check-workflow-mail wait=True` when they are idle and expecting the next workflow step.
4. Keep user confirmation as the gate before final acceptance/closeout unless workflow policy overrides it.
5. Keep workflow content in mailbox body instead of generated Markdown files.
6. Keep planner closeout actions batched after acceptance.

Use skills:

- Project workflow skill: `agent-deck-workflow` (`ai-agent/skills/agent-deck-workflow/SKILL.md`)
- Receiver wake handler: `check-workflow-mail` (`ai-agent/skills/check-workflow-mail/SKILL.md`)
- Browser check request: `browser-test-request` (`ai-agent/skills/browser-test-request/SKILL.md`)
- Browser tester: `browser-test` (`ai-agent/skills/browser-test/SKILL.md`)
- Agent Deck skill + docs bundle: `ai-agent/skills/agent-deck/SKILL.md` and `ai-agent/skills/agent-deck/references/`
