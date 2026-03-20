# Skills Workflow

This document describes the multi-agent workflow built around the skills in this directory.

## Roles

- Agent 1, **Planner** (`delegate-task`): planning agent, prepares the execution brief and sends it through mailbox
- Agent 2, **Executor** (implementation): executes tasks and applies code changes
- Agent 3, **Reviewer** (`review-code`): review agent, produces the full review report directly in mailbox body
- User: makes acceptance decisions when the workflow is human-gated

## Core Transport

- `agent-mailbox` is the authoritative workflow message layer
- `agent-deck` is used only to wake the target session so it can receive mail
- Workflow messages live in mailbox `subject` + `body`
- When sending mailbox body text, prefer `agent-mailbox send --body-file -` and feed stdin directly
- Prefer `adwf-send-and-wake` for cross-session workflow delivery
- Run every `agent-mailbox` command outside sandbox
- Run mailbox state-mutating `agent-mailbox` commands serially, not in parallel
- The workflow does not generate Markdown handoff files by default

## End-to-End Loop

1. User asks Planner to prepare work.
2. Planner runs `delegate-task` and sends one delegate mailbox message to Executor.
3. Planner wakes Executor.
4. Executor implements changes.
5. Executor runs `review-request` and sends one review-request mailbox message to Reviewer.
6. Executor wakes Reviewer.
7. Reviewer runs `review-code` and sends either:
   - `rework_required` back to Executor, or
   - `stop_recommended` to the user decision point.
8. If user wants another iteration, Reviewer sends `user_requested_iteration` to Executor.
9. Repeat until the user decides quality is acceptable, or policy auto-accepts.
10. After acceptance, Reviewer runs `review-closeout` and sends one closeout mailbox message to Planner.
11. Planner reads the closeout mailbox body, then batches merge/progress/next-task work.
12. Executor and Reviewer can be fully exited.

## Flow Diagram

```mermaid
flowchart TD
    P[Planner] -->|mailbox: execute_delegate_task| E[Executor]
    E -->|mailbox: review_requested| R[Reviewer]
    R -->|review result| DEC{Quality Accepted?}
    DEC -- No --> E
    DEC -- Yes --> R
    R -->|mailbox: closeout_delivered| P

    style DEC fill:#fff3cd,stroke:#b58900,stroke-width:1px
```

## Operational Notes

- `review-code` remains the authoritative full review output
- `review-closeout` is the compact planner handoff after acceptance
- The receiver should always read mailbox `body` first
- External files are supplemental references only, not the default transport

## Incremental Automation with Agent Deck

Current recommended operating mode:

1. Keep `planner` as a long-lived session.
2. Create `executor-<task_id>` and `reviewer-<task_id>` per task.
3. Keep user confirmation as the gate before final acceptance/closeout unless workflow policy overrides it.
4. Keep workflow content in mailbox body instead of generated Markdown files.
5. Keep planner closeout actions batched after acceptance.

Use skills:

- Project workflow skill: `agent-deck-workflow` (`ai-agent/skills/agent-deck-workflow/SKILL.md`)
- Official docs bundle (reference-only, not a loaded skill): `ai-agent/skills/agent-deck/references/`

Official reference sync policy:

- `install.sh` should not fetch network content at install time.
- Official `agent-deck` references are stored as a pinned local snapshot under `ai-agent/skills/agent-deck/references/`.
- Update explicitly when needed:
  - `ai-agent/scripts/sync-official-agent-deck-skill.sh <ref>`
- After sync, review diff and commit the snapshot update.
- Keep `ai-agent/skills/agent-deck/` as reference-only (no `SKILL.md`) to avoid prompt conflicts and context overhead.

Migration note:

- The runnable workflow skill is `agent-deck-workflow`.
- The mailbox-first protocol replaces the old artifact-first handoff model.
