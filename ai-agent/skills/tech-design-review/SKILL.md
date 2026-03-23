---
name: tech-design-review
description: Reviews a committed tech-design snapshot and sends an advisory report back to the requester session.
---

# Tech-Design Review

Review committed tech-design docs from a `tech_design_review_requested` mailbox body and return an advisory report to the requester session.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines architect-side review behavior.

## Input

Provide the mailbox body from `tech_design_review_requested`.

## Review Scope

Review the committed tech-design snapshot for:
- problem framing
- design soundness
- missing constraints
- hidden coupling
- operational risk
- migration and rollback shape
- unresolved questions that block implementation confidence

This is not code review.

## Required Baseline

Before reviewing quality, verify:
- tech-design branch is stated
- tech-design commit is stated
- in-scope design docs are stated

If critical context is missing:
- mark the report as `NEEDS_REVISION`
- list the missing items under `Major Risks`

## Output Format

Use this exact structure as the mailbox body:

```markdown
Task: <task_id>
Action: tech_design_review_report
From: architect <architect_session_id>
To: <requester_role> <requester_session_id>
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line architect summary]

## Decision
SOUND | NEEDS_REVISION

## Major Risks
- [risk or `None`]

## Design Gaps
- [gap or `None`]

## Alternatives
- [alternative or `None`]

## Questions To Resolve
- [question or `None`]

## What Looks Good
- [strength or `None`]

## Residual Risk
[What remains uncertain after this review]
```

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `architect_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `planner_session_id`: explicit -> mailbox body `Planner` header -> omit when `N/A`
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow:
1. review the committed tech-design snapshot referenced in the mailbox body
2. produce one `tech_design_review_report`
3. if `agent_mailbox` is not already bound for this session, bind it first
4. first call `agent_deck_ensure_session` with `session_id = <requester_session_id>`
5. send the report back with `mailbox_deliver`
   - `from_address = agent-deck/<architect_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "tech-design report: <task_id> r<round>"`
   - `body = <tech-design review report body>`

## Rules

- architect is review-only in this lane
- review docs and design rationale only
- keep feedback advisory and evidence-based
- report back to the original requester session, not to planner by default
- if the requester sends a later round to the same architect session, treat it as a continuation and focus on the delta
- do not treat your own feedback as final authority; the requester may disagree and argue the design tradeoff
- ask the user to decide when the disagreement becomes subjective, strategic, or stuck
