---
name: tech-design-review-workflow
description: Coordinate Agent Deck technical-design drafting, review, revision, and delivery. Use when starting, continuing, or routing this workflow.
---

# Tech Design Review Workflow

Use agent-deck-workflow for shared transport and session protocol.

## Route First

Route inbound actions before starting a new lane:

- tech_design_draft_requested -> Author Execution
- tech_design_review_report -> Report Handling
- tech_design_decision_requested or tech_design_delivered -> Requester Handling

For a new request, select:

- draft-review when no defensible committed proposal exists or material requirements, interfaces, constraints, or tradeoffs remain unresolved
- review-existing only when the requester already has committed docs, their branch/base, and enough context to defend the proposal

Do not make the requester invent a proposal merely to obtain review.

## Roles

- requester: starts the workflow and owns user-facing handoff
- architect-author: inspects the repository, writes draft rounds, handles reviewer dialogue, and sends the final pointer
- architect-reviewer: independently reviews the requested round without editing it and stops at the review limit

In draft-review, author and reviewer are separate sibling sessions. The reviewer normally replies to the author; limit decisions are user-gated.

## Dispatched Draft Round Contract

Write rounds under .agent-artifacts/tech-design/<author_session_id>/rNNN.md.

- only the author writes this directory
- r001 is complete; for every later round, copy the preceding file to the next path before editing it. Every delivered round must remain a complete, self-contained design, never a delta, diff, or dependency on a prior round
- a round may be edited until its review request is sent; afterward leave it unchanged and write revisions in later numbered rounds
- number revisions monotonically; the named artifact path identifies the round under review
- drafting must not change Git state or workspace ownership

`.agent-artifacts/` is temporary; never add it to Git or write outside the shared workspace.

## Review Limit and User Continuation

Store a positive Max Review Rounds in lane context and carry it across role handoffs; default it to 5 only for a new lane.

A reviewed replacement snapshot uses the next round. NEEDS_INPUT and same-snapshot reconsideration do not advance it.

At the limit, the reviewer asks the user whether to stop or continue. If the user continues, it chooses a suitable next stopping point, returns the normal report with the updated maximum to the existing sender, and that sender resumes the same lane.

## Design Content Gate

As architect-author, record material conclusions in the artifact for:

- core approach, scope, ownership, boundaries, and a direct user-goal link for every material change
- simplicity: exclude user-unrequested scope, unnecessary abstraction, speculative flexibility, duplicate paths, and excessive coupling/change surface
- relevant state, configuration, and compatibility changes: necessity, ownership, migration/rollback, operations, and required interoperability
- material benefits, risks, failure handling, alternatives, and tradeoffs
- unresolved user-owned decisions: options and consequences

Treat unrequested product capabilities as out of scope. Existing support, completeness, or future value does not justify inclusion. Exclude any capability that materially expands product scope or crosses ownership domains unless the stated goal requires it or the user explicitly approves it.

Use `Open Questions` only for architect-owned technical decisions. Resolve user-owned product scope before dispatch; if such a decision emerges later, keep it out of the base design and use Decision Request.

Keep treatment proportional. Cover data, configuration, and compatibility only when relevant; state a no-impact conclusion only when omission would be ambiguous. Do not invent machinery merely to satisfy this gate.

## Start Inputs

Common:

- task_id
- requester session id/role
- problem, goals, constraints
- optional known_context, open_questions, feedback_requested, round, max_review_rounds

New architect sessions:

- optional shared architect_tool / architect_tool_profile
- optional architect_author_tool / architect_author_tool_profile
- optional architect_reviewer_tool / architect_reviewer_tool_profile
- resolver roles: architect_author and architect_reviewer
- resolve each target independently: <target>_tool -> architect_tool -> <target>_tool_profile -> architect_tool_profile -> its resolver-role default

draft-review additionally uses:

- archive_branch: explicit -> current branch only when it is clearly the formal-doc landing branch -> ask
- optional refs; default architect-author-<task_id> and architect-reviewer-<task_id>
- existing real author/reviewer session ids when resuming

review-existing additionally requires:

- tech_design_branch, tech_design_base_branch, committed design_docs_in_scope listing every reviewed doc and design asset
- existing architect_session_id, or optional new architect_session_ref defaulting to architect-<task_id>

## Architect Tool Resolution

Pass the target workdir when resolving:

- author: `--role architect_author`
- reviewer: `--role architect_reviewer`

Do not substitute either role. Record each selected `*_tool_profile`, `*_tool_cmd`, and optional startup message under the shared tool-resolution contract.

## Round Resolution

Resolve round: explicit input or inbound message -> latest persisted workflow context -> 1 only for a clearly new lane.

- use the next round for a revised target after NEEDS_REVISION or a decision/constraint delta
- keep the current round for a NEEDS_INPUT repair or same-snapshot reconsideration; use the next round for a replacement target
- after interruption, resume the valid inbound round and target
- do not infer round solely from filenames or reuse a dispatched file as a revised round; stop on conflicting history

## Draft-Review Start

Resolve requester identity from explicit input, then current session context. Resolve archive_branch by the rule above; stop on detached HEAD or an unclear landing branch.

Resolve both deterministic refs with agent_deck_resolve_session. For each target:

- found: verify its workdir and group, then call agent_deck_require_session with its real id and expected workdir
- not found: resolve its command with its resolver role above as <target_tool_cmd>, then call agent_deck_create_session with:
  - ensure_title = <deterministic ref for this target>
  - ensure_cmd = <target_tool_cmd>
  - workdir = <current workspace>
  - parent_session_id = <requester_session_id>
  - group_path = <requester session group; empty string for root>
  - no_parent_link = false

Require distinct author and reviewer real ids; stop if they match. Record both ids and derive the artifact directory from the author id. After interrupted setup, repeat this resolve-first flow; never create a target that resolves. After review history exists, recover missing real ids from Agent Deck or Waypost history and stop if recovery fails.

Send only the author. Omit empty optional sections:

~~~markdown
Task: <task_id>
Action: tech_design_draft_requested
From: <requester_role> <requester_session_id>
To: architect_author <author_session_id>
Reviewer: architect_reviewer <reviewer_session_id>
Round: <round>
Max Review Rounds: <max_review_rounds>

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
- Target: <exact .agent-artifacts/tech-design/<author_session_id>/rNNN.md path>

## Archive Target
- Branch: <archive_branch>
~~~

Send once from the requester address to the author address with subject tech-design draft: <task_id> r<round>, then follow the shared Async sender rule.

## Author Execution

On tech_design_draft_requested:

1. recover the requester, reviewer, round, maximum, artifact path, archive branch, and optional review focus
2. inspect relevant repository state and user-aligned context
3. write the complete, proportional, implementation-ready design to the named round file, following Dispatched Draft Round Contract and Design Content Gate
4. ensure accepted constraints and rationale live in the artifact, not only in messages
5. send the named artifact to the recorded reviewer, leave it unchanged, then return under the Async sender rule
6. handle later tech_design_review_report deliveries until accepted or a user-owned decision is required
7. after acceptance, send the terse final notification; do not archive or commit the design

Do not ask the requester to supply technical design content that repository inspection and engineering judgment can resolve.
Do not resolve user-owned product scope through engineering judgment; exclude optional capability or use Decision Request.

Treat a later tech_design_draft_requested as a decision or constraint delta: reuse the lane and create the next numbered round. A continued review arrives as a normal report with its updated maximum.

## Review-Existing Start

Require committed docs, their design branch, and the recorded base branch. Never guess the base.

Resolve the reviewer id from explicit input, workflow context, then persisted Waypost history. If prior-review context exists but the real id remains missing, stop; do not create a context-free replacement. Create a reviewer only for a clearly new lane, using resolver role `architect_reviewer` and the same parent/workdir settings as above.

Before each review request, resolve <reviewed_commit> = git rev-parse <tech_design_branch>, then apply the review-existing path gate:

1. inspect git diff --no-renames --name-only <tech_design_base_branch>...<reviewed_commit>
2. require every changed path to be covered by the explicit design_docs_in_scope
3. stop if any implementation or unrelated path appears; branch naming is not proof of scope

## Review Request

Resolve the review sender by lane; that sender owns normal returned reports:

- draft-review: review_sender_role = architect_author, review_sender_session_id = author_session_id
- review-existing: review_sender_role = requester_role, review_sender_session_id = requester_session_id

For the first round with a reviewer, send the applicable target form and omit empty optional sections:

~~~markdown
Task: <task_id>
Action: tech_design_review_requested
From: <review_sender_role> <review_sender_session_id>
To: architect_reviewer <reviewer_session_id>
Round: <round>
Max Review Rounds: <max_review_rounds>

## Problem
[Problem the design solves]

## Goals
- [goal]

## Constraints
- [constraint]

## Review Target
[Use exactly one form]
- Mode: draft-round
- Artifact: <named .agent-artifacts/tech-design/<author_session_id>/rNNN.md path>

or

- Mode: committed-docs
- Base branch: <tech_design_base_branch>
- Branch: <tech_design_branch>
- Commit: <reviewed commit>
- Docs:
  - path/to/doc.md

## Optional Review Focus
- [explicit emphasis; never narrow the full review]
~~~

Later rounds use the same header, plus:

~~~markdown
## Updated Review Target
[Exact new artifact path, or committed branch/commit/docs]

## Context Delta
- [changed context; restore any context needed for recovery]
~~~

Do not paste or summarize the design, or hand-write a diff. Send from agent-deck/<review_sender_session_id> to agent-deck/<reviewer_session_id> with subject tech-design review: <task_id> r<round>, then follow the shared Async sender rule.

## User Completion

After the accepted design becomes authoritative, report only final design path(s) and authoritative commit.

## Report Handling

The session that sent the request handles every review report. A report received after user-approved continuation resumes the same lane with its updated maximum.

- NEEDS_INPUT: correct the reported input and resend with enough context; do not change a valid dispatched artifact/commit
- NEEDS_REVISION: preserve Max Review Rounds, revise, and request the next round
  - draft: copy the reviewed artifact to the next numbered path, revise that copy, and leave the reviewed one unchanged
  - existing: update and commit the docs on the same design branch
- SOUND: accept
- SOUND_WITH_CAVEATS: accept only if every accepted caveat is non-blocking and already recorded in the reviewed artifact/commit; otherwise revise and re-review
- disagreement: send concise rationale to the same reviewer for the same round; do not create a new target or increment the round

If the same dispute repeats or requires a subjective/strategic choice:

- architect-author sends tech_design_decision_requested to the requester
- a review-existing requester asks the user directly

After acceptance:

- draft: author sends tech_design_delivered; requester archives and commits it
- existing:
  1. read the accepted commit from the report's Reviewed Scope
  2. require git rev-parse <tech_design_branch> to equal that commit; if it differs, stop and review the new tip
  3. rerun the review-existing path gate against the accepted commit
  4. verify the final docs are committed, switch to the recorded base branch, require it as current, then merge the design branch with normal git merge
  5. follow User Completion with design_docs_in_scope and the resulting base HEAD

For review-existing, do not squash, rebase, cherry-pick, or guess through dirty state, conflicts, detached HEAD, or base uncertainty.

## Decision Request

Use only from architect-author to requester:

~~~markdown
Task: <task_id>
Action: tech_design_decision_requested
From: architect_author <author_session_id>
To: <requester_role> <requester_session_id>
Round: <round>
Max Review Rounds: <max_review_rounds>

## Decision Needed
[One precise user-owned decision]

## Options
- [option]: [material consequence]

## Recommendation
[author recommendation and reviewer position]

## Current Artifact
- <exact .agent-artifacts/tech-design/<author_session_id>/rNNN.md path>
~~~

### Decision Response

After the user answers, send the same author a tech_design_draft_requested delta containing the decision, changed constraints, next artifact path, unchanged archive branch, and unchanged Max Review Rounds.

## Final Notification

Do not repeat the design, decisions, caveats, or implementation advice.

~~~markdown
Task: <task_id>
Action: tech_design_delivered
From: architect_author <author_session_id>
To: <requester_role> <requester_session_id>
Round: final

## Delivered
- Artifact: <accepted .agent-artifacts/tech-design/<author_session_id>/rNNN.md path>
- Archive branch: <archive_branch>
- Review: <SOUND | SOUND_WITH_CAVEATS>
- Report: <review message id>
~~~

Send with subject tech-design delivered: <task_id>.

## Requester Handling

On tech_design_decision_requested, follow Decision Response; do not edit the artifact.

On tech_design_delivered:

1. verify the artifact exists and the report pointer records acceptance of that named path
2. if a committed formal doc on the archive branch already represents the accepted design, reuse it and continue with session cleanup and completion
3. require the current branch to equal the delivered archive branch; stop on mismatch or detached HEAD and do not switch automatically
4. require a clean index and no merge, rebase, or conflict state; do not clean unrelated worktree changes
5. choose the formal tracked docs path; stop if it has unrelated uncommitted changes
6. if substantive changes are needed, return them to the author for a new reviewed round while preserving Max Review Rounds
7. copy the accepted artifact to the formal tracked docs path, resolve trivial non-substantive issues locally, and commit that file only
8. after the archive commit succeeds, remove both architect sessions
9. treat the tracked committed doc as authoritative and cite it in later implementation work
10. follow User Completion with the tracked doc and archive commit

## Rule

Treat every Waypost send as fire-and-forget; never auto-resend outside explicit troubleshooting.
