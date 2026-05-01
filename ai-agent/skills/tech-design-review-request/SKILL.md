---
name: tech-design-review-request
description: Generates tech-design review requests from committed docs and defines requester-side handling of review reports.
---

# Tech-Design Review Request

Generate a concise mailbox message that asks an architect to review the latest committed tech-design docs on a branch.
Drive the architect-review loop until it reaches a deliverable conclusion or a clear user-decision blocker.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Inputs

Modes:
- request-send mode: use fields below to send `tech_design_review_requested`
- report-handling mode: provide the mailbox body from `tech_design_review_report` and follow `After Report Handling`

Common:
- `task_id`
- `requester_session_id`
- `requester_role`
- `tech_design_branch`
- `tech_design_base_branch`
- `design_docs_in_scope`
- optional `feedback_requested`
- optional `architect_tool`
- optional `architect_tool_profile`
- optional `round`

Later rounds / existing architect lane:
- `architect_session_id`

Round `1` or new architect session:
- optional `architect_session_ref`
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
- the tech-design branch has a known base branch
- if the base branch is unclear, ask instead of guessing

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox/workflow context -> ask
- `requester_session_id`: explicit -> current session id -> ask
- `requester_role`: explicit -> infer from current workflow stage -> default `requester`
- `architect_session_id`: explicit actual id -> workflow context actual id
  - create only for round `1` or an explicitly new architect lane
  - for later rounds to an existing architect lane, missing id is workflow context loss; recover the real session id instead of creating a new session
- `architect_session_ref`: explicit -> workflow context -> default `architect-<task_id>`
  - use only when allocating a new architect session before the first send
- `tech_design_branch`: explicit -> workflow context -> default `tech-design/<task_id>`
- `tech_design_base_branch`: explicit -> branch creation record -> workflow context -> high-confidence merge target -> ask
  - this is the branch the tech-design branch started from and must merge back into after accepted review
  - never assume `main`/`master`; branch names are evidence, not truth
- `architect_tool_cmd`: explicit full `architect_tool` -> workflow context resolved command -> shared tool-resolution contract for role `architect`
- `architect_tool_profile`: explicit -> workflow context -> resolver `tool_profile`
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

Round `1` or new architect session: use the full body below.

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <requester_role> <requester_session_id>
To: architect {{TO_SESSION_ID}}
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
[Short committed-design summary]

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

## Tool Context
- Architect tool profile: [architect_tool_profile or `explicit`]
- Architect tool cmd: [architect_tool_cmd]
```

Round `>1` to the same architect session: send only a minimal pointer.

```markdown
Task: <task_id>
Action: tech_design_review_requested
From: <requester_role> <requester_session_id>
To: architect {{TO_SESSION_ID}}
Round: <round>

## Summary
[One-line review request]

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

## Tool Context
- Architect tool profile: [architect_tool_profile or `existing-session`]
- Architect tool cmd: [architect_tool_cmd or `existing-session`]
```

## Mailbox Send

Subject: `tech-design review: <task_id> r<round>`

Before sending:
1. compose the body with `{{TO_SESSION_ID}}` as a placeholder
2. if round `>1` targets an existing architect lane and `architect_session_id` is missing, stop and recover the real session id
3. if allocating a new architect session, resolve `architect_tool_profile` / `architect_tool_cmd` by the shared tool-resolution contract for role `architect`
   - preserve explicit full `architect_tool` unchanged when provided
   - otherwise resolve the role `architect` command
4. if allocating a new architect session, call `agent_deck_create_session`
   - `ensure_title = <architect_session_ref>`
   - `ensure_cmd = <architect_tool_cmd>`
   - `workdir = <current workspace>`
   - `parent_session_id = <requester_session_id>`
   - `no_parent_link = false`
5. otherwise require the existing `architect_session_id`
6. use the returned session id as authoritative
7. fill the final body and send it with `mailbox_send`
   - `from_address = agent-deck/<requester_session_id>`
   - `to_address = agent-deck/<architect_session_id>`
   - `subject = "tech-design review: <task_id> r<round>"`
   - `body = <tech-design review request body>`

After sending, do not sleep, poll, or proactively check mail just to await the architect report.

## After Report Handling

When the requester receives `tech_design_review_report`:
- treat this as a convergence loop, not a one-off advisory exchange
- the loop ends only when one of these is true:
  - `Decision` is `SOUND`
  - `Decision` is `SOUND_WITH_CAVEATS` and requester explicitly accepts the caveats as non-blocking or records the required follow-up plan
  - requester or architect escalates a subjective, strategic, or stuck disagreement to the user
- if `Decision` is `NEEDS_REVISION`, update and commit docs on `tech_design_branch`; request the next round; do not merge yet
- if `Decision` is `SOUND`, treat the design as deliverable and merge `tech_design_branch` into `tech_design_base_branch`
- if `Decision` is `SOUND_WITH_CAVEATS`:
  - if caveats are blocking, update and commit docs on `tech_design_branch`; request the next round; do not merge yet
  - if caveats are accepted as non-blocking or captured in a follow-up plan, treat the design as deliverable and merge `tech_design_branch` into `tech_design_base_branch`
- use normal `git merge`; do not squash, rebase, cherry-pick, or copy files manually
- preserve the design-doc commits as product history on the base branch
- do not merge merely because the report arrived; merge only after the loop reaches a deliverable conclusion
- merge target is always the recorded `tech_design_base_branch`, not "current branch" unless current branch is explicitly that recorded base branch
- do not merge an implementation task branch here; this lane merges the reviewed `tech_design_branch` only
- if repeated rounds stop converging, or the disagreement becomes subjective/strategic, stop the auto-loop and ask the user to decide
- if later generating implementation work with `delegate-task` from this review, cite the reviewed design docs in the delegate brief
- if merge conflicts, uncommitted changes, or base-branch uncertainty appear, stop and report the blocker instead of guessing
