---
name: tech-design-review
description: Review a technical design.
---

# Tech-Design Review

Use agent-deck-workflow for shared transport protocol.

## Input Mode

Determine mode from the input, not session metadata:

- message mode: a Waypost body with Action: tech_design_review_requested
- direct-use mode: every other invocation

Message mode requires one named review target:

- draft-round: one complete, self-contained .agent-artifacts/.../rNNN.md file named in the request
- committed-docs: the stated docs at the stated branch commit

In direct-use mode, review the readable target named by the user. Use available problem, goals, and constraints.

## Review Limit

This limit applies to message mode. Require a positive Max Review Rounds from lane setup. If it is missing or invalid, return NEEDS_INPUT without reviewing.

- A reviewed replacement snapshot uses the next round. NEEDS_INPUT and a same-snapshot reconsideration keep the round.
- Review at or below the maximum; do not start a later round without user approval.
- At final NEEDS_REVISION: pause before reporting; summarize why earlier rounds did not converge, any recurring/structural issue, and what another iteration could resolve; ask the user to stop or continue, then apply the answer.
- If the user stops, end. If they continue, set the next stopping point from remaining work and likelihood of convergence, not a fixed extension. Record the new maximum and any user constraints in the held normal NEEDS_REVISION report, then send it to inbound From.

Continue resumes the existing lane; do not restart review.

## Review

Review as a skeptical senior engineer. Prioritize:

- problem framing, constraints, and success criteria
- the smallest coherent approach and user fit: every material component must serve a stated problem, goal, or constraint
- scope and over-design: speculative scale/flexibility, layers, abstractions, data/configuration/compatibility paths, duplicate paths, or edge cases without a direct need
- relevant state, configuration, and compatibility changes: necessity, ownership, migration/rollback, operations, and required interoperability
- material benefits, risks, alternatives, tradeoffs, and rollout, failure, safety, or data-boundary consequences
- unresolved user-owned decisions and their consequences

This is not code review. Judge reasonableness as well as correctness; prefer removing scope that lacks a direct user need. Assess only relevant concerns and focus on the few findings most likely to change implementation confidence.

## Baseline Gate

Require a readable, self-contained review target and enough problem framing to judge it.

- direct-use mode: ask one short clarification question when either is missing
- message mode: use NEEDS_INPUT only when the request cannot identify/read the target or lacks request-owned context required to judge it; list the missing input under Findings and never ask the user

Use NEEDS_REVISION for material design omissions, including gaps that make the proposal unjudgeable or a draft round that relies on an earlier round, a diff, or an “unchanged” reference.

## Snapshot Inspection

For draft-round:

- review the named file as the requested design round
- do not edit it or switch to a newer round
- require it to contain the full current design; use prior rounds only to compare changes, never to supply missing design content
- repository inspection may validate claims, but must not change the reviewed target
- on later rounds, compare against the prior artifact from this session's report or Waypost history when useful

For committed-docs:

- inspect the named docs at the stated commit; do not silently review a moving worktree snapshot
- on later rounds, compare against the previous reviewed commit when available
- if the prior baseline is unavailable, state that under Residual Risk

In direct-use mode, review named workspace docs as currently read and record moving-snapshot uncertainty under Residual Risk when relevant.

## Output

For a normal message-mode review, use:

~~~markdown
Task: <task_id>
Action: tech_design_review_report
From: architect_reviewer <reviewer_session_id>
To: <review_sender_role> <review_sender_session_id>
Round: <round>
Max Review Rounds: <max_review_rounds>

## Summary
[One-line review conclusion]

## Reviewed Scope
[Use the applicable form. With NEEDS_INPUT, include resolved scope and mark missing fields.]
- Mode: draft-round
- Artifact: .agent-artifacts/.../rNNN.md

or

- Mode: committed-docs
- Base branch: <base branch>
- Branch: <design branch>
- Commit: <reviewed commit>
- Docs:
  - path/to/doc.md

## Persisted Data Changes
[Required]

## Decision
SOUND | SOUND_WITH_CAVEATS | NEEDS_REVISION | NEEDS_INPUT

## Findings
- [prioritized finding, consequence, and recommended direction, or None]

## Questions To Resolve
- [requester-owned decision or blocker, or None]

## Residual Risk
[remaining uncertainty or None]
~~~

Decision guidance:

- SOUND: coherent and implementation-ready with no unresolved design findings or caveats
- SOUND_WITH_CAVEATS: deliverable, with only non-blocking caveats already recorded in the reviewed target
- NEEDS_REVISION: design changes and another reviewed snapshot are required before handoff
- NEEDS_INPUT: message mode only; the requester must correct critical review input and may resend the same target

Residual Risk may accompany a positive decision unless it blocks implementation confidence.

In direct-use mode, omit the message header, use the same report sections, and describe the actual named target under Reviewed Scope.

## Message Delivery

In message mode:

1. resolve task_id, round, reviewer_session_id, inbound From identity, and maximum through the shared context rules
2. apply the baseline gate and review-limit rule
3. send a normal report to inbound From for every completed review and NEEDS_INPUT. Wait without sending while asking the limit decision; after user continuation, send the held report; after a stop, end:
   - from_address = agent-deck/<reviewer_session_id>
   - to_address = agent-deck/<inbound_from_session_id>
   - subject = tech-design review report: <task_id> r<round>
   - body = <report>
4. follow the shared Async sender rule

In direct-use mode, do not send Waypost.

## Rules

- remain review-only
- keep findings concrete, evidence-based, and advisory
- always include Persisted Data Changes
- do not use SOUND_WITH_CAVEATS when a doc revision is still required
- put unresolved decisions under Questions To Resolve; address only the requester in message mode and the user in direct-use mode
- do not treat optional review focus as a limit on independent review
