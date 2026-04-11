---
name: tech-design-review-request
description: Generates tech-design review requests from committed docs and defines requester-side handling of review reports.
---

# Tech-Design Review Request

Generate a concise mailbox message that asks an architect to review the latest committed tech-design docs on a branch.
After an accepted report, preserve the docs by merging the design branch into its recorded base branch.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Inputs

Modes:
- request-send mode: use fields below to send `tech_design_review_requested`
- report-handling mode: provide the mailbox body from `tech_design_review_report` and follow `After Report Handling`

Common:
- `task_id`
- `requester_session_id`
- `requester_role`
- `architect_session_ref` or `architect_session_id`
- `tech_design_branch`
- `tech_design_base_branch`
- `design_docs_in_scope`
- optional `feedback_requested`
- optional `planner_session_id`
- optional `architect_tool`
- optional `round`

Round `1` or new architect session:
- `problem`
- `goals`
- `constraints`
- `proposed_tech_design_summary`
- optional `alternatives_considered`
- optional `open_questions`

Round `>1` to the same architect session:
- optional `requester_notes` for non-git context only

## Required Git State

- the review target is the latest committed state on a tech-design branch
- the tech-design branch has a known base branch where the docs should be retained after accepted review
- default branch is `tech-design/<task_id>`
- use read-only git commands only when needed to collect context
- if the base branch is unclear, ask instead of guessing

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
- `tech_design_base_branch`: explicit -> branch creation record -> workflow context -> high-confidence merge target -> ask
  - this is the branch the tech-design branch started from and must merge back into after accepted review
  - never assume `main`/`master`; branch names are evidence, not truth
- `architect_tool`: explicit -> workflow context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
- `round`: explicit -> workflow context -> default `1`

Continuity rule:
- round `1` uses the full body below
- later rounds to the same architect session send only the minimal review pointer
- do not hand-write doc diffs in the request body; the architect derives changes from git
- if the architect session changed or continuity is unknown, fall back to the full body
- architect feedback is advisory; later rounds may explicitly disagree with earlier architect feedback and explain why

## Mailbox Body

The body is a review brief plus committed-doc pointers only.
Do not paste full design docs into the mailbox body.
The authoritative review target is the latest committed docs on the stated branch.

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

## Proposed Tech Design Summary
[Short committed-design summary; do not paste doc contents]

## Alternatives Considered
- [alternative or `None identified`]

## Open Questions
- [question or `None`]

## Tech Design Snapshot
- Base branch: [branch the tech-design branch started from]
- Branch: [tech-design branch]
- Design docs in scope:
  - `path/to/doc1.md`
  - `path/to/doc2.md`

## Feedback Requested
- [what kind of feedback is wanted]

## Known Risks or Gaps
[Current known risks, tradeoffs, or `None identified`]
```

Round `>1` to the same architect session: send only a minimal pointer.
Do not summarize doc diffs manually.

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <requester_role> <requester_session_id>
To: architect {{TO_SESSION_ID}}
Planner: <planner_session_id_or_N/A>
Round: <round>

## Summary
[One-line review request; no manual doc diff]

## Updated Tech Design Snapshot
- Base branch: [branch the tech-design branch started from]
- Branch: [tech-design branch]
- Design docs in scope:
  - `path/to/doc1.md`
  - `path/to/doc2.md`

## Feedback Requested
- [what remains unresolved in this round]

## Requester Notes
- [Optional non-git context, feedback disagreement, or `None`]
```

## Mailbox Send

Recommended subject:
- `tech-design review: <task_id> r<round>`

Use the `agent_mailbox` MCP tools:
1. use `agent_mailbox`
2. compose the body with `{{TO_SESSION_ID}}` where the real architect session id must appear
3. call `agent_deck_ensure_session`
   - identify target with `session_id` or `session_ref = <architect_session_ref>`
   - when creation may be needed, also pass:
     - `ensure_title = <architect_session_ref>`
     - `ensure_cmd = <architect_tool>`
     - `workdir = <current workspace>`
     - `parent_session_id = <requester_session_id>`
     - `no_parent_link = false`
4. use the returned `session_id` as the authoritative `architect_session_id`
5. fill the final body and call `mailbox_send` with:
   - `from_address = agent-deck/<requester_session_id>`
   - `to_address = agent-deck/<architect_session_id>`
   - `subject = "tech-design review: <task_id> r<round>"`
   - `body = <tech-design review request body>`

## After Report Handling

When the requester/planner receives `tech_design_review_report`:
- if `Decision` is `NEEDS_REVISION`, update and commit docs on `tech_design_branch`; request the next round; do not merge yet
- if `Decision` is `SOUND`, merge `tech_design_branch` into `tech_design_base_branch`
- if `Decision` is `SOUND_WITH_CAVEATS`, merge only after requester/planner accepts the caveats or records the follow-up plan
- use normal `git merge`; do not squash, rebase, cherry-pick, or copy files manually
- preserve the design-doc commits as product history on the base branch
- if later generating implementation work with `delegate-task` from this review, cite the reviewed design docs in the delegate brief
- if merge conflicts, uncommitted changes, or base-branch uncertainty appear, stop and report the blocker instead of guessing

## Rules

- send tech-design review from committed docs only
- branch name is the authoritative review target; do not require a full commit hash
- base branch is the authoritative post-review merge target; do not substitute `main`/`master`/current branch
- keep workflow context self-contained; architect should not need workflow files
- do not embed full design docs in the body; use branch + in-scope doc paths as the source of truth
- do not embed hand-written doc diffs in later-round bodies; git is the source of truth for changes
- architect is review-only in this lane
- keep later rounds to the same architect session pointer-only
- if architect continuity changes, resend full context
- treat architect feedback as advisory input, not as a user decision
- treat architect progress as asynchronous with unbounded duration; do not assume a report will arrive within this turn
- after sending, do independent requester work only when it does not depend on architect feedback; otherwise report current state and stop instead of waiting
- after sending, do not sleep, poll, or proactively check mail just to await the architect report
- when disagreeing, state only the disagreement and rationale in `Requester Notes`; do not summarize document changes manually
- either requester or architect may ask the user to decide when the disagreement becomes subjective or stuck
- create architect sessions through `agent_deck_ensure_session` with `parent_session_id = <requester_session_id>` and `no_parent_link = false`
