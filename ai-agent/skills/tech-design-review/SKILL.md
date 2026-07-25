---
name: tech-design-review
description: Reviews an exact tech-design snapshot and returns an advisory report. Use for immutable draft artifacts produced by an architect-author, mature committed design docs on a branch, or direct user-requested design review. In Waypost mode, reply only to the inbound requester.
---

# Tech-Design Review

Use `agent-deck-workflow` for shared transport protocol.

## Input Mode

Determine mode from the input, not session metadata:

- message mode: a Waypost body with `Action: tech_design_review_requested`
- direct-use mode: every other invocation, including a user request inside Agent Deck

Review one exact source:

- `immutable-artifact`: the exact `.agent-artifacts/.../rNNN.md` path in the request
- `committed-docs`: the stated docs at the stated branch commit

In direct-use mode, accept either source plus available problem/goals/constraints.

## Review

Review as a skeptical senior engineer. Prioritize:

- problem framing, scope, constraints, and success criteria
- decision quality, alternatives, tradeoffs, simplicity, coupling, and change surface
- compatibility, migration, rollout, rollback, and failure handling
- operations, observability, security, privacy, and data boundaries
- unresolved questions that block implementation confidence

This is not code review. Distinguish missing evidence from a wrong design and focus on the few findings most likely to change implementation confidence.

## Baseline Gate

Require a readable exact review target and enough problem framing to judge it.

- direct-use mode: ask one short clarification question when either is missing
- message mode: return `NEEDS_REVISION` and list missing critical input under `Findings`; never bypass the requester to ask the user

Treat missing alternatives, constraints, or operational detail as design gaps unless they make the proposal unjudgeable.

## Snapshot Inspection

For `immutable-artifact`:

- review only the named file as the authoritative design round
- do not edit it or substitute a newer file
- repository inspection may validate claims, but must not change the reviewed target
- on later rounds, compare against the prior artifact path from this session's report/Waypost history when useful

For `committed-docs`:

- inspect the named docs at the stated commit; do not silently review a moving worktree snapshot
- on later rounds, compare against the previous reviewed commit when available
- if the prior baseline is unavailable, state that under `Residual Risk`

## Output

Message mode uses:

```markdown
Task: <task_id>
Action: tech_design_review_report
From: architect_reviewer <architect_session_id>
To: <requester_role> <requester_session_id>
Round: <round>

## Summary
[One-line architect summary]

## Reviewed Scope
[Use exactly one form]
- Mode: immutable-artifact
- Artifact: `.agent-artifacts/.../rNNN.md`

or

- Mode: committed-docs
- Base branch: <base branch>
- Branch: <design branch>
- Commit: <reviewed commit>
- Docs:
  - `path/to/doc.md`

## Decision
SOUND | SOUND_WITH_CAVEATS | NEEDS_REVISION

## Findings
- [prioritized finding, consequence, and recommended direction, or `None`]

## Questions To Resolve
- [requester-owned decision or blocker, or `None`]

## Residual Risk
[remaining uncertainty or `None`]
```

Decision guidance:

- `SOUND`: coherent and implementation-ready with no material blockers
- `SOUND_WITH_CAVEATS`: deliverable, with only non-blocking caveats already recorded in the reviewed snapshot
- `NEEDS_REVISION`: another reviewed snapshot is required before handoff

In direct-use mode, omit the message header and return the same sections directly in the conversation.

## Message Delivery

In message mode only:

1. resolve `task_id`, round, reviewer id, and requester identity from explicit input then message headers/context
2. produce one report against the exact target
3. send it to the inbound `From` session:
   - `from_address = agent-deck/<architect_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "tech-design review report: <task_id> r<round>"`
   - `body = <report>`
4. follow the shared Async sender rule

In direct-use mode, do not send Waypost.

## Rules

- remain review-only
- keep findings concrete, skeptical, evidence-based, and advisory
- do not use `SOUND_WITH_CAVEATS` when a doc revision is still required
- return subjective, strategic, or stuck decisions to the requester in message mode; ask the user only in direct-use mode
- do not treat optional review focus as a limit on independent review
