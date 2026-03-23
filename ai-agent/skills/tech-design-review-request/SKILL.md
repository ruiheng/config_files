---
name: tech-design-review-request
description: Generates a tech-design review mailbox message from committed design docs and sends it to a per-task architect session.
---

# Tech-Design Review Request

Generate a concise mailbox message that asks an architect to review a committed tech-design snapshot.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines tech-design-review-request-specific behavior.

## Inputs

- `task_id`
- `requester_session_id`
- `requester_role`
- `architect_session_ref` or `architect_session_id`
- `tech_design_branch`
- `tech_design_commit`
- `design_docs_in_scope`
- `problem`
- `goals`
- `constraints`
- `proposed_tech_design`
- optional `alternatives_considered`
- optional `open_questions`
- optional `feedback_requested`
- optional `planner_session_id`
- optional `architect_tool`
- optional `round`

## Required Git State

- the review target must be a committed tech-design snapshot
- default branch is `tech-design/<task_id>`
- use read-only git commands to collect context

Minimum checks:
- `git rev-parse --verify <tech_design_commit>`
- `git branch --contains <tech_design_commit>`
- `git show --stat --format=fuller <tech_design_commit>`

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox/workflow context -> ask
- `requester_session_id`: explicit -> current session id -> ask
- `requester_role`: explicit -> infer from current workflow stage -> default `requester`
- `planner_session_id`: explicit -> workflow context -> omit when unavailable
- `architect_session_ref`: explicit -> workflow context -> default `architect-<task_id>`
- `architect_session_id`: explicit actual id -> workflow context actual id -> resolved/created from `architect_session_ref` before send
- `tech_design_branch`: explicit -> workflow context -> default `tech-design/<task_id>`
- `tech_design_commit`: explicit -> ask
- `architect_tool`: explicit -> workflow context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
- `round`: explicit -> workflow context -> default `1`

Continuity rule:
- round `1` uses the full body below
- later rounds to the same architect session send only the delta since the previous architect round
- if the architect session changed or continuity is unknown, fall back to the full body
- architect feedback is advisory; later rounds may explicitly disagree with earlier architect feedback and explain why

## Mailbox Body

Round `1` or new architect session: use the full body below.

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <requester_role> <requester_session_id>
To: architect {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line tech-design review summary]

## Problem
[What problem this tech design is meant to solve]

## Goals
- [goal]

## Constraints
- [constraint]

## Proposed Tech Design
[Committed design snapshot summary]

## Alternatives Considered
- [alternative or `None identified`]

## Open Questions
- [question or `None`]

## Tech Design Snapshot
- Branch: [tech-design branch]
- Commit: [commit hash]
- Design docs in scope:
  - `path/to/doc1.md`
  - `path/to/doc2.md`

## Feedback Requested
- [what kind of feedback is wanted]

## Known Risks or Gaps
[Current known risks, tradeoffs, or `None identified`]
```

Round `>1` to the same architect session: send only delta.

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <requester_role> <requester_session_id>
To: architect {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line delta summary]

## Delta Since Last Architect Round
- Design updates: [what changed in the docs or decisions]
- Previous feedback adopted: [brief summary]
- Previous feedback rejected: [brief summary + rationale]
- New open questions: [only what changed]

## Updated Tech Design Snapshot
- Branch: [tech-design branch]
- Commit: [new commit hash]
- Design docs changed this round:
  - `path/to/doc1.md`

## Feedback Requested
- [what remains unresolved in this round]

## Known Risks or Gaps
[Current remaining risks or `None identified`]
```

## Mailbox Send

Recommended subject:
- `tech-design review: <task_id> r<round>`

Use the `agent_mailbox` MCP tools:
1. if `agent_mailbox` is not already bound for this session, bind it first
2. compose the body with `{{TO_SESSION_ID}}` where the real architect session id must appear
3. call `agent_deck_ensure_session` with:
   - `session_ref = <architect_session_ref>`
   - `ensure_title = <architect_session_ref>`
   - `ensure_cmd = <architect_tool>`
   - `parent_session_id = <planner_session_id_or_requester_session_id>`
4. use the returned `session_id` as the authoritative `architect_session_id`
5. fill the final body and call `mailbox_deliver` with:
   - `from_address = agent-deck/<requester_session_id>`
   - `to_address = agent-deck/<architect_session_id>`
   - `subject = "tech-design review: <task_id> r<round>"`
   - `body = <tech-design review request body>`

## Rules

- send tech-design review from committed docs only
- keep the body self-contained; architect should not need workflow files
- architect is review-only in this lane
- keep later rounds to the same architect session delta-only
- if architect continuity changes, resend full context
- treat architect feedback as advisory input, not as a user decision
- when disagreeing, state the disagreement and rationale clearly in the next round
- either requester or architect may ask the user to decide when the disagreement becomes subjective or stuck
