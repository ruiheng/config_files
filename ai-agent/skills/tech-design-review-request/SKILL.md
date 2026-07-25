---
name: tech-design-review-request
description: Orchestrates tech-design drafting and independent review through Agent Deck. Use when separate architect sessions should draft or review a design, or when handling the resulting Waypost actions. Do not use for direct in-session design review.
---

# Tech-Design Review Request

Use `agent-deck-workflow` for shared transport and session protocol.

## Route First

Route inbound actions before starting a new lane:

- `tech_design_draft_requested` -> `Author Execution`
- `tech_design_review_report` -> `Report Handling`
- `tech_design_decision_requested` or `tech_design_delivered` -> `Original Requester Handling`

For a new request, select:

- `draft-review` when no defensible committed proposal exists or material requirements, interfaces, constraints, or tradeoffs remain unresolved
- `review-existing` only when the requester already has committed docs, their branch/base, and enough context to defend the proposal

Do not make the requester invent a proposal merely to obtain review.

## Roles

- original requester: owns the user conversation; archives and commits an accepted draft
- architect-author: inspects the repository, writes draft rounds, handles reviewer dialogue, and sends the final pointer
- architect-reviewer: independently reviews exact snapshots and never edits them

In `draft-review`, author and reviewer are separate sibling sessions. The reviewer replies to the author. Escalate only user-owned product or strategic decisions to the original requester.

## Immutable Draft Contract

Write rounds under `.agent-artifacts/tech-design/<author_session_id>/rNNN.md`.

- only the author writes this directory
- a round may be edited until its review request is sent; after sending, never modify or replace that file
- each revision uses the next monotonically numbered file; never reuse a round, and review only the exact named path
- drafting must not change Git state or workspace ownership

`.agent-artifacts/` must remain ignored. Stop if it is tracked or the artifact path is outside the shared workspace.

## Start Inputs

Common:

- `task_id`
- requester session id/role
- `problem`, `goals`, `constraints`
- optional `known_context`, `open_questions`, `feedback_requested`, `round`

New architect sessions:

- optional shared `architect_tool` / `architect_tool_profile`
- optional `architect_author_tool` / `architect_author_tool_profile`
- optional `architect_reviewer_tool` / `architect_reviewer_tool_profile`
- resolve each target independently: target-specific -> shared -> role `architect` defaults

`draft-review` additionally uses:

- `archive_branch`: explicit -> current branch only when it is clearly the formal-doc landing branch -> ask
- optional refs; default `architect-author-<task_id>` and `architect-reviewer-<task_id>`
- existing real author/reviewer session ids when resuming

`review-existing` additionally requires:

- `tech_design_branch`, `tech_design_base_branch`, committed `design_docs_in_scope` listing every reviewed doc and design asset
- existing `architect_session_id`, or optional new `architect_session_ref` defaulting to `architect-<task_id>`

## Round Resolution

Resolve `round`: explicit input or inbound message -> latest persisted workflow context -> `1` only for a clearly new lane.

- after `NEEDS_REVISION` or a decision/constraint delta, use the prior round plus one
- after `NEEDS_INPUT`, correct the reported input; keep the round for the same valid snapshot, and use the next round for a replacement target
- after interruption, resume the inbound round and target when still valid; do not allocate a round merely for interruption
- never infer round solely from filenames or reuse a dispatched file as a revised round; stop on conflicting history

## Draft-Review Start

Resolve requester identity from explicit input, then current session context. Resolve `archive_branch` by the rule above; stop on detached `HEAD` or an unclear landing branch.

Resolve both deterministic refs with `agent_deck_resolve_session`. For each target:

- found: verify its workdir and group, then call `agent_deck_require_session` with its real id and expected workdir
- not found: resolve its command by the input order above as `<target_architect_tool_cmd>`, then call `agent_deck_create_session` with:
  - `ensure_title = <deterministic ref for this target>`
  - `ensure_cmd = <target_architect_tool_cmd>`
  - `workdir = <current workspace>`
  - `parent_session_id = <requester_session_id>`
  - `group_path = <requester session group; empty string for root>`
  - `no_parent_link = false`

Require distinct author and reviewer real ids; stop if they match. Record both ids and derive the artifact directory from the author id. After interrupted setup, repeat this resolve-first flow; never create a target that resolves. After review history exists, recover missing real ids from Agent Deck or Waypost history and stop if recovery fails.

Send only the author. Omit empty optional sections:

```markdown
Task: <task_id>
Action: tech_design_draft_requested
From: <requester_role> <requester_session_id>
To: architect_author <author_session_id>
Reviewer: architect_reviewer <reviewer_session_id>
Round: <round>

## Goal
[Problem and desired outcome; state uncertainty plainly]

## Constraints
- [constraint]

## Known Context
- [fact]

## Open Questions
- [question]

## Optional Review Focus
- [feedback_requested]

## Artifact
- Target: <exact `.agent-artifacts/tech-design/<author_session_id>/rNNN.md` path>

## Archive Target
- Branch: <archive_branch>
```

Send once from the requester address to the author address with subject `tech-design draft: <task_id> r<round>`, then follow the shared Async sender rule.

## Author Execution

On `tech_design_draft_requested`:

1. recover the original requester, reviewer, round, artifact path, archive branch, and optional review focus from the message
2. inspect relevant repository state and user-aligned context
3. write a proportional, implementation-ready design to the named round file
4. ensure accepted constraints and rationale live in the artifact, not only in messages
5. send the exact artifact to the recorded reviewer, stop editing it, then return under the Async sender rule
6. handle later `tech_design_review_report` deliveries until accepted or a user-owned decision is required
7. after acceptance, send the terse final notification; do not archive or commit the design

Do not ask the original requester to supply technical design content that repository inspection and engineering judgment can resolve.

Treat a later `tech_design_draft_requested` as a decision/constraint delta. Reuse both sessions, preserve the archive branch, and create the next immutable round.

## Review-Existing Start

Require committed docs, their design branch, and the recorded base branch. Never guess the base.

Resolve the reviewer id from explicit input, workflow context, then persisted Waypost history. If prior-review context exists but the real id remains missing, stop; do not create a context-free replacement. Create a reviewer only for a clearly new lane, using the shared role `architect` resolver and the same parent/workdir settings as above.

Before each review request, resolve `<reviewed_commit> = git rev-parse <tech_design_branch>`, then apply the review-existing path gate:

1. inspect `git diff --no-renames --name-only <tech_design_base_branch>...<reviewed_commit>`
2. require every changed path to be covered by the explicit `design_docs_in_scope`
3. stop if any implementation or unrelated path appears; branch naming is not proof of scope

## Review Request

Resolve the review sender by lane; that sender owns the returned report:

- `draft-review`: `review_sender_role = architect_author`, `review_sender_session_id = author_session_id`
- `review-existing`: `review_sender_role = requester_role`, `review_sender_session_id = requester_session_id`

For the first round with a reviewer, send the applicable target form and omit empty optional sections:

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <review_sender_role> <review_sender_session_id>
To: architect_reviewer <reviewer_session_id>
Round: <round>

## Problem
[Problem the design solves]

## Goals
- [goal]

## Constraints
- [constraint]

## Review Target
[Use exactly one form]
- Mode: immutable-artifact
- Artifact: <exact `.agent-artifacts/tech-design/<author_session_id>/rNNN.md` path>

or

- Mode: committed-docs
- Base branch: <tech_design_base_branch>
- Branch: <tech_design_branch>
- Commit: <reviewed commit>
- Docs:
  - `path/to/doc.md`

## Optional Review Focus
- [explicit emphasis; never narrow the full review]
```

Later rounds to the same reviewer normally use:

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <review_sender_role> <review_sender_session_id>
To: architect_reviewer <reviewer_session_id>
Round: <round>

## Updated Review Target
[Exact new artifact path, or committed branch/commit/docs]

## Context Delta
- [changed context; restore any context needed for recovery]
```

Do not paste or summarize the design, or hand-write a diff. Send from `agent-deck/<review_sender_session_id>` to `agent-deck/<reviewer_session_id>` with subject `tech-design review: <task_id> r<round>`, then follow the shared Async sender rule.

## Report Handling

The session that sent the request handles the report.

- `NEEDS_INPUT`: correct the reported input and resend with enough context; never mutate a valid dispatched artifact/commit
- `NEEDS_REVISION`: revise and request the next round
  - draft: create the next numbered artifact; never edit the reviewed one
  - existing: update and commit the docs on the same design branch
- `SOUND`: accept
- `SOUND_WITH_CAVEATS`: accept only if every accepted caveat is non-blocking and already recorded in the reviewed artifact/commit; otherwise revise and re-review
- disagreement: send concise rationale to the same reviewer; never silently discard findings

If the same dispute repeats or requires a subjective/strategic choice:

- architect-author sends `tech_design_decision_requested` to the original requester
- a `review-existing` requester asks the user directly

After acceptance:

- draft: author sends `tech_design_delivered`; original requester archives and commits it
- existing:
  1. read the accepted commit from the report's `Reviewed Scope`
  2. require `git rev-parse <tech_design_branch>` to equal that commit; if it differs, stop and review the new tip
  3. rerun the review-existing path gate against the accepted commit
  4. verify the final docs are committed, switch to the recorded base branch, require it as current, then merge the design branch with normal `git merge`

For `review-existing`, do not squash, rebase, cherry-pick, or guess through dirty state, conflicts, detached `HEAD`, or base uncertainty.

## Decision Request

Use only from architect-author to original requester:

```markdown
Task: <task_id>
Action: tech_design_decision_requested
From: architect_author <author_session_id>
To: <requester_role> <requester_session_id>
Round: <round>

## Decision Needed
[One precise user-owned decision]

## Options
- [option]: [material consequence]

## Recommendation
[author recommendation and reviewer position]

## Current Artifact
- <exact `.agent-artifacts/tech-design/<author_session_id>/rNNN.md` path>
```

### Decision Response

After the user answers, send the same author a `tech_design_draft_requested` delta containing only the decision, changed constraints, next artifact path, and unchanged archive branch.

## Final Notification

Do not repeat the design, decisions, caveats, or implementation advice.

```markdown
Task: <task_id>
Action: tech_design_delivered
From: architect_author <author_session_id>
To: <requester_role> <requester_session_id>
Round: final

## Delivered
- Artifact: <accepted `.agent-artifacts/tech-design/<author_session_id>/rNNN.md` path>
- Archive branch: <archive_branch>
- Review: <SOUND | SOUND_WITH_CAVEATS>
- Report: <review message id>
```

Send with subject `tech-design delivered: <task_id>`.

## Original Requester Handling

On `tech_design_decision_requested`, follow `Decision Response`; do not edit the artifact.

On `tech_design_delivered`:

1. verify the artifact exists and the report pointer records acceptance of that exact path
2. if a committed formal doc on the archive branch already represents the accepted design, reuse it and continue with session cleanup and completion
3. require the current branch to equal the delivered archive branch; stop on mismatch or detached `HEAD` and do not switch automatically
4. require a clean index and no merge, rebase, or conflict state; do not clean unrelated worktree changes
5. read the artifact and choose the formal tracked docs path; stop if that path has unrelated uncommitted changes, then copy without substantive design changes
6. if substantive changes are needed, return them to the author for a new reviewed round
7. stage and commit only the archived design doc; this delivery authorizes that archive commit without another routine confirmation
8. after the archive commit succeeds, remove both architect sessions
9. treat the tracked committed doc as authoritative and cite it in later implementation work

Keep the user-facing completion concise: report the tracked doc path and commit, not the design itself.

## Rule

Treat every Waypost send as fire-and-forget; never auto-resend outside explicit troubleshooting.
