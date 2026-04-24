---
name: review-closeout
description: Extracts a concise closeout summary from a full review report and, in Agent Deck mode, sends it to planner through workflow transport.
---

# Review Closeout

Extract a closeout summary from a full review report.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Purpose

Use this skill when an accepted full review report exists and only remaining follow-up items are needed.
For UI-related tasks, carry forward any UI confirmation package that exists in the accepted review context into closeout output.
Closeout should also give planner a compact summary of residual accepted findings that may need later tracking.

Input gate:
- run this skill only after acceptance has already been established by workflow policy or explicit decision
- use this skill only for an accepted final review report
- do not run this skill for pending review, iteration requests, or any report that still has unresolved must-fix items
- determine eligibility from accepted review context and workflow policy, not from session title naming

## Input

Provide the accepted full review report text.

## Output Mode (Fixed)

- output directly in response
- Agent Deck mode: also deliver the closeout summary to planner through the workflow transport
- keep output compact and copy/paste friendly
- keep closeout in mailbox body instead of a generated Markdown handoff file

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> review report text -> ask
- `planner_session_id`: explicit -> review context -> ask
- `closeout_sender_session_id`: explicit -> current session id -> review context -> ask
- `closeout_sender_role`: explicit -> current workflow role -> review context -> default `closeout_executor`
- `reviewer_session_id`: explicit -> review context -> ask
- `workflow_policy` (optional): explicit -> review/report context -> default unattended
- `special_requirements` (optional fallback): explicit -> review/report context -> omit
- `start_branch`: explicit -> review report text -> ask
- `task_branch`: explicit -> review report text -> ask
- `integration_branch`: explicit -> review report text -> ask
- `task_dir`: explicit -> review report text -> ask

Branch-plan rule:
- do not infer, rename, or repair branch plan during closeout
- use the recorded branch plan from the accepted review report unchanged
- if recorded `integration_branch` looks like `task/*`, treat the branch plan as invalid and ask for the real integration branch
- if any branch-plan field is missing, ask one short clarification question instead of guessing

If required values are resolved:
1. normalize identity values before any comparison:
   - resolve `planner_session_id` / `closeout_sender_session_id` / `reviewer_session_id` refs to UUID via `agent_deck_resolve_session`
   - if normalization fails for required identity, ask one short clarification question before sending
2. send mode:
   - if `closeout_sender_session_id == planner_session_id`, skip cross-session delivery and continue locally
   - otherwise send `closeout_delivered` to planner through `mailbox_send`
3. use `agent_mailbox`
4. first call `agent_deck_require_session` with:
   - `session_id = <planner_session_id>`
   - `workdir = <current workspace>`
5. use `mailbox_send` with:
   - `from_address = agent-deck/<closeout_sender_session_id>`
   - `to_address = agent-deck/<planner_session_id>`
   - `subject = "closeout delivered: <task_id>"`
   - `body = <closeout mailbox body>`

Recommended mailbox subject:
- `closeout delivered: <task_id>`

## Extraction Rules

Inclusion-first policy:

1. Always keep non-empty items from:
- `Critical Issues`
- `Design Concerns`
- `Minor Suggestions`
- `Verification Questions`
- `UI Manual Confirmation Package`
- `Recorded Branch Plan`

Planner handoff rule:
- when closeout happens after acceptance, convert surviving non-blocking findings into planner-usable follow-up input instead of leaving them as raw review debris
- preserve whether each item looks like `progress/todo`, `next task`, or `no extra tracking`

2. Request/security checks:
- drop `PASS`
- keep `FAIL` and `UNKNOWN`

3. None handling:
- drop `None.` placeholders
- if section has both `None.` and real items, keep real items

4. Wording safety:
- preserve technical meaning
- keep file paths / line references
- report only issues supported by the review report

## Rendering Rules (No Empty Sections)

Bucket order:
1. `Critical Issues`
2. `Design Concerns`
3. `Residual Follow-up For Planner`
4. `Minor Suggestions`
5. `Verification Questions`
6. `UI Manual Confirmation Package`
7. `Remaining Check Alerts (FAIL/UNKNOWN Only)`

Rules:
- render section only when it has at least one item
- never output empty headings
- if all buckets are empty:

```markdown
### Review Closeout
No actionable items.
```

## Output Template (Conditional)

Always start with:

```markdown
Task: <task_id>
Action: closeout_delivered
From: <closeout_sender_role> <closeout_sender_session_id>
To: planner <planner_session_id>
Planner: <planner_session_id>
Round: final
Accepted Review By: reviewer <reviewer_session_id>

### Review Closeout
```

Then append only non-empty sections.

```markdown
#### Residual Follow-up For Planner
- Track in progress/todo: [items worth recording for later follow-up, or `None`]
- Consider as next task/subtask: [items worth queueing, or `None`]
- No extra tracking needed: [items intentionally left as informational only, or `None`]

#### Recorded Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Task dir: [absolute task workspace path]
- Rule: use this recorded branch plan as the authoritative merge target; do not substitute `main`/`master`/current branch unless the user explicitly changed the plan

#### UI Manual Confirmation Package
- UI impact: [detected | none detected]
- Changed UI surfaces: [routes/pages/components]
- Manual check steps (human-run): [short checklist]
- Expected visible outcomes: [what user should see]
- Notes: [optional]
```

## Guidelines

1. Prefer completeness over aggressive trimming
2. Keep neutral tone
3. Include only FAIL/UNKNOWN check lines
4. Keep section order stable
5. Keep output compact and copy/paste friendly
6. Preserve `workflow_policy` unchanged when sending
7. Preserve `special_requirements` unchanged when sending
8. Make deferred follow-up ownership explicit enough that planner can act without rereading the whole report in the common case
9. Use `mailbox_send` for normal cross-session closeout delivery
10. Do not naturally end after drafting the closeout text; this workflow turn is complete only after the required local continuation or `mailbox_send` delivery step has succeeded
