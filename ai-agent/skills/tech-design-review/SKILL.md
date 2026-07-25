---
name: tech-design-review
description: Reviews tech-design artifacts or docs in direct or Waypost workflows.
---

# Tech-Design Review

Use `agent-deck-workflow` for shared transport protocol.

## Input Mode

Determine mode from the input, not session metadata:

- message mode: a Waypost body with `Action: tech_design_review_requested`
- direct-use mode: every other invocation, including a user request inside Agent Deck

Message mode requires one exact snapshot:

- `immutable-artifact`: the exact `.agent-artifacts/.../rNNN.md` path in the request
- `committed-docs`: the stated docs at the stated branch commit

In direct-use mode, review the exact readable target named by the user; it may also be named workspace docs. Use available problem/goals/constraints.

## Review

Review as a skeptical senior engineer. Prioritize:

- the simplest coherent solution and a concrete reason for every proposed change
- over-design: speculative flexibility/scale, unnecessary layers or abstractions, duplicated paths, and excessive coupling/change surface
- persisted data/schema changes: necessity, ownership, migration, and rollback
- forward/backward compatibility: which old/new clients, readers, writers, or data versions must interoperate and why; do not assume it
- problem framing, constraints, success criteria, alternatives, and tradeoffs
- rollout, failure handling, operations, observability, security, privacy, and data boundaries
- unresolved questions that block implementation confidence

This is not code review. Distinguish missing evidence from a wrong design and focus on the few findings most likely to change implementation confidence.

## Baseline Gate

Require a readable exact review target and enough problem framing to judge it.

- direct-use mode: ask one short clarification question when either is missing
- message mode: use `NEEDS_INPUT` only when the request cannot identify/read the target or lacks request-owned context required to judge it; list the missing input under `Findings` and never ask the user

Use `NEEDS_REVISION` for material design omissions, including gaps that make the proposal unjudgeable.

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

In direct-use mode, review named workspace docs as currently read and record moving-snapshot uncertainty under `Residual Risk` when relevant.

## Output

Message mode uses:

```markdown
Task: <task_id>
Action: tech_design_review_report
From: architect_reviewer <reviewer_session_id>
To: <requester_role> <requester_session_id>
Round: <round>

## Summary
[One-line review conclusion]

## Reviewed Scope
[Use the applicable form. With `NEEDS_INPUT`, include resolved scope and mark missing fields.]
- Mode: immutable-artifact
- Artifact: `.agent-artifacts/.../rNNN.md`

or

- Mode: committed-docs
- Base branch: <base branch>
- Branch: <design branch>
- Commit: <reviewed commit>
- Docs:
  - `path/to/doc.md`

## Persisted Data Changes
[Required]

## Decision
SOUND | SOUND_WITH_CAVEATS | NEEDS_REVISION | NEEDS_INPUT

## Findings
- [prioritized finding, consequence, and recommended direction, or `None`]

## Questions To Resolve
- [requester-owned decision or blocker, or `None`]

## Residual Risk
[remaining uncertainty or `None`]
```

Decision guidance:

- `SOUND`: coherent and implementation-ready with no unresolved design findings or caveats
- `SOUND_WITH_CAVEATS`: deliverable, with only non-blocking design caveats already recorded in the reviewed target
- `NEEDS_REVISION`: design changes and another reviewed snapshot are required before handoff
- `NEEDS_INPUT`: message mode only; the requester must correct critical review input, and may resend the same target

`Residual Risk` may accompany a positive decision unless it blocks implementation confidence.

In direct-use mode, omit the message header, use the same report sections, and describe the actual named target under `Reviewed Scope`.

## Message Delivery

In message mode only:

1. resolve `task_id`, round, `reviewer_session_id`, and requester identity through the shared context rules
2. produce one report against the exact target
3. send it to the inbound `From` session:
   - `from_address = agent-deck/<reviewer_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "tech-design review report: <task_id> r<round>"`
   - `body = <report>`
4. follow the shared Async sender rule

In direct-use mode, do not send Waypost.

## Rules

- remain review-only
- keep findings concrete, evidence-based, and advisory
- always include `Persisted Data Changes`
- do not use `SOUND_WITH_CAVEATS` when a doc revision is still required
- put unresolved decisions under `Questions To Resolve`; address only the requester in message mode and the user in direct-use mode
- do not treat optional review focus as a limit on independent review
