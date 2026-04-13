---
name: tech-design-review
description: Reviews the latest committed tech-design docs on a branch and sends an advisory report back to the requester session.
---

# Tech-Design Review

Review committed tech-design docs and return an advisory report.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide one of:
1. the mailbox body from `tech_design_review_requested`
2. direct scope + committed design docs + base branch + problem/goals/constraints

Direct-use mode is valid.
In mailbox mode, treat the body as a review brief and committed-doc pointer, not as the full design source.
Inspect the latest committed docs on the stated branch before judging the design.
For later rounds, derive document changes from git instead of trusting any hand-written diff.

## Review Dimensions

Review the requested tech-design snapshot using these dimensions:
- problem framing and scope
- constraints, assumptions, and success criteria
- decision quality and tradeoffs
- simplicity, coupling, and change surface
- compatibility, migration, and rollback
- operational readiness, observability, and failure handling
- security, privacy, and data boundary risks
- unresolved questions that block implementation confidence

This is not code review.

## Architect Role

Review this like a senior engineer in a mature production environment:
- skeptical of hand-wavy claims
- protective of compatibility and operational clarity
- intolerant of unclear ownership, hidden coupling, and weak migration stories

## Inspection Order

1. Validate the problem and scope first.
- Is this solving a real problem?
- Are non-goals, constraints, and success conditions clear enough to judge the proposal?

2. Review the proposed design through the dimensions above.
- Focus first on decision quality, coupling, and change surface.
- Then review migration, operations, and security.

3. Distinguish missing evidence from design failure.
- A weakly justified claim is not automatically a wrong design, but it is still a reviewable gap.
- Call out when the proposal direction looks sound but the support, constraints, or rollout detail is too thin.

4. Produce one advisory report.
- Prioritize the few objections or caveats most likely to change implementation confidence.

## Required Baseline

Before reviewing quality, verify:
- problem statement is stated
- tech-design branch is stated
- tech-design base branch is stated
- in-scope design docs are stated
- alternatives or rejected options are stated
- major constraints are stated

Hard block:
- if problem statement or in-scope design docs are missing, ask one short clarification question in direct-use mode
- in mailbox mode, continue but mark the report as `NEEDS_REVISION` and list the missing critical items under `Major Risks`

Soft gaps:
- if tech-design base branch, alternatives/rejected options, or major constraints are missing, continue the review
- record the missing items under `Design Gaps`

If critical context is still missing after one clarification in direct-use mode:
- mark the report as `NEEDS_REVISION`
- list the missing items under `Major Risks`

## Output Format

Mailbox mode uses the full structure below:

```markdown
Task: <task_id>
Action: tech_design_review_report
From: architect <architect_session_id>
To: <requester_role> <requester_session_id>
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line architect summary]

## Reviewed Scope
- Base branch: [branch the tech-design branch started from]
- Branch: [tech-design branch]
- Commit: [reviewed branch HEAD]
- Docs reviewed:
  - `path/to/doc1.md`
  - `path/to/doc2.md`

## Decision
SOUND | SOUND_WITH_CAVEATS | NEEDS_REVISION

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

## Post-Review Integration
- Merge target: [tech-design base branch]
- Design branch: [tech-design branch]
- History rule: requester/planner merges the design branch after accepted review; architect does not merge

## Residual Risk
[What remains uncertain after this review]
```

Direct-use mode skips the mailbox header block and starts at `## Summary`.

Decision guidance:
- `SOUND`: the design is coherent and implementation-ready with no material blockers
- `SOUND_WITH_CAVEATS`: the core direction is sound, but specific gaps or caveats should be resolved before or during implementation
- `NEEDS_REVISION`: the current design is missing critical framing, contains a material flaw, or is too incomplete to trust as the implementation basis

## Direct-Use Mode

When invoked directly by the user instead of mailbox workflow:
- skip the mailbox header block
- keep the same review sections starting at `## Summary`
- return the report directly in the conversation

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> ask
- `architect_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `planner_session_id`: explicit -> mailbox body `Planner` header -> omit when `N/A`
- `tech_design_base_branch`: explicit -> mailbox body `Base branch` -> ask
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow:
1. review the latest committed tech-design docs on the referenced branch
   - for round `>1` in the same architect session, compare current branch `HEAD` against the previous reviewed commit from the prior report/mailbox context
   - if the previous reviewed commit is unavailable, use git history for the in-scope docs and state the baseline uncertainty under `Residual Risk`
2. produce one `tech_design_review_report`
3. use `agent_mailbox`
4. first call `agent_deck_ensure_session` with:
   - `session_id = <requester_session_id>`
   - `workdir = <current workspace>`
5. send the report back with `mailbox_send`
   - `from_address = agent-deck/<architect_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "tech-design report: <task_id> r<round>"`
   - `body = <tech-design review report body>`
6. do not naturally end after drafting the report; this workflow turn is complete only after the required `mailbox_send` back to the requester has succeeded

## Rules

- architect is review-only in this lane
- review docs and design rationale only
- do not merge branches; post-review integration belongs to the requester/planner
- keep feedback advisory, skeptical, and evidence-based
- report back to the original requester session, not to planner by default
- include the tech-design base branch and reviewed commit in the report so requester/planner can preserve the docs in git history
- if the design is accepted, requester/planner should merge the tech-design branch into its recorded base branch with `git merge`; never tell them to squash, rebase, cherry-pick, or copy files manually
- if the requester sends a later round to the same architect session, treat it as a continuation and focus on the git-derived delta
- never rely on a request body's hand-written doc diff as the source of truth
- do not treat your own feedback as final authority; the requester may disagree and argue the design tradeoff
- ask the user to decide when the disagreement becomes subjective, strategic, or stuck
- prefer concrete design objections over generic taste comments
- focus on the highest-leverage risks first: wrong problem, bad tradeoff, hidden coupling, broken migration, weak operational story
- acknowledge design strengths that should be preserved during implementation, especially when they create useful constraints or simplify the solution space
