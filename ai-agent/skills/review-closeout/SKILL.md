---
name: review-closeout
description: Extracts a concise closeout summary from a full review report and, in Agent Deck mode, sends it to planner through agent-mailbox.
---

# Review Closeout

Extract a closeout summary from a full review report.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines closeout-specific behavior.

## Purpose

Use this skill when a full review report exists and only remaining follow-up items are needed.
For UI-related tasks, carry forward human-run UI confirmation package into closeout output.
Closeout should also give planner a compact summary of residual accepted findings that may need later tracking.

Role intent:
- required role: reviewer role for the current task
- role is task-scoped: the same AI/session may also hold planner role when workflow context explicitly assigns both
- dispatch eligibility must come from resolved reviewer context, not session title naming

## Input

Provide the full review report text.

## Output Mode (Fixed)

- output directly in response
- Agent Deck mode: also send the closeout summary to planner via `agent-mailbox`
- keep output compact and copy/paste friendly
- do not create a closeout Markdown file

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> review report text -> ask
- `planner_session_id`: explicit -> review context -> ask
- `current_session_id`: best-effort from `agent-deck session current --json`
- `reviewer_session_id`: explicit -> review context -> ask
- `workflow_policy` (optional): explicit -> review/report context -> default human-gated
- `special_requirements` (optional fallback): explicit -> review/report context -> omit
- `task_branch`: explicit -> review/report context -> default `task/<task_id>`
- `integration_branch`: explicit -> review/report context -> ask if planner closeout will need it

If required values are resolved:
1. normalize identity values before any comparison:
   - resolve `planner_session_id` / `reviewer_session_id` refs to UUID via `agent-deck session show ... --json`
   - use detected `current_session_id` UUID from `agent-deck session current --json`
   - if normalization fails for required identity, do not send automatically; ask one short clarification question
2. send mode:
   - if `reviewer_session_id == planner_session_id` and target session is current session, skip cross-session wakeup and continue locally
   - otherwise send `closeout_delivered` to planner inbox and wake planner session
3. include planner follow-up recommendation in the closeout body (explicitly recommend `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh`)
4. send the closeout body with `agent-mailbox send --body-file -` via stdin rather than writing a temporary file

Recommended mailbox subject:
- `closeout delivered: <task_id>`

Recommended wakeup text:

```text
You have new workflow mail. Run: agent-mailbox recv --for workflow/session/<planner_session_id> --json
```

## Extraction Rules

Inclusion-first policy:

1. Always keep non-empty items from:
- `Critical Issues`
- `Design Concerns`
- `Minor Suggestions`
- `Verification Questions`
- `UI Manual Confirmation Package`

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
- do not invent issues

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
From: reviewer <reviewer_session_id>
To: planner <planner_session_id>
Planner: <planner_session_id>
Round: final

### Review Closeout
```

Then append only non-empty sections.

```markdown
#### Residual Follow-up For Planner
- Track in progress/todo: [items worth recording for later follow-up, or `None`]
- Consider as next task/subtask: [items worth queueing, or `None`]
- No extra tracking needed: [items intentionally left as informational only, or `None`]

#### UI Manual Confirmation Package
- UI impact: [detected | none detected]
- Changed UI surfaces: [routes/pages/components]
- Manual check steps (human-run): [short checklist]
- Expected visible outcomes: [what user should see]
- Notes: [optional]

#### Planner Follow-up Recommendation
- Required: run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh --task-id <task_id> --task-branch <task_branch> --integration-branch <integration_branch>`.
- Required by script: switch to the target integration branch when needed, then merge the task branch and update planner progress records.
- Before or during closeout, inspect this closeout message and decide whether residual accepted findings should update progress/todo or next-task planning.
- Optional: plan and dispatch next task when appropriate.
- If `workflow_policy.auto_dispatch_next_task=true`, dispatch next queued task automatically after required closeout actions.
- When planner auto-dispatches from a known queue, planner should show dispatch progress in `current/total` form (for example `3/15`) before each newly dispatched task.
```

## Guidelines

1. Prefer completeness over aggressive trimming
2. Keep neutral tone
3. Do not include PASS-only lines
4. Keep section order stable
5. Keep output compact and copy/paste friendly
6. Preserve `workflow_policy` unchanged when sending
7. Preserve `special_requirements` unchanged when sending
8. Make deferred follow-up ownership explicit enough that planner can act without rereading the whole report in the common case
