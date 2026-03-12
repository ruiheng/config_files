---
name: review-closeout
description: Extracts a concise review closeout from a full review report, keeping actionable items and any FAIL/UNKNOWN checks, and outputs directly for copy/paste.
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
- Required role: reviewer role for the current task.
- Role is task-scoped: the same AI/session may also hold planner role when workflow context explicitly assigns both.
- Dispatch eligibility must come from resolved reviewer context, not session title naming.

## Input

Provide one of:
1. full review report text
2. review report file path

## Output Mode (Fixed)

- Output directly in response.
- Default: no file creation.
- Agent Deck mode: also write closeout artifact for cross-session handoff.
- Keep output compact and copy/paste friendly.

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`:
- `Agent Deck Mode Detection`
- `Context Resolution Priority`
- `Dispatch Helper Usage`
- `Error Handling and Diagnostics`

Skill-specific context resolution:
- `task_id`: explicit -> review-report path `.agent-artifacts/<task_id>/...` -> ask
- `planner_session_id`: explicit/context -> ask
- `current_session_id`: best-effort from `agent-deck session current --json`
- `reviewer_session_id`: explicit -> review context -> ask
- `workflow_policy` (optional): explicit -> review/report context -> default human-gated
- `special_requirements` (optional fallback): explicit -> review/report context -> omit

If required values are resolved:
1. write closeout to `.agent-artifacts/<task_id>/closeout-<task_id>.md`
2. normalize identity values before any comparison:
   - resolve `planner_session_id` / `reviewer_session_id` refs to UUID via `agent-deck session show ... --json`
   - use detected `current_session_id` UUID from `agent-deck session current --json`
   - if normalization fails for required identity, do not dispatch automatically; ask one short clarification question
3. dispatch mode:
   - if `reviewer_session_id == planner_session_id` and target session is current session, skip cross-session dispatch and continue locally
   - otherwise dispatch `closeout_delivered` to planner
4. include planner follow-up recommendation in closeout output (explicitly recommend `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh`)

Dispatch example:

```bash
~/.config/ai-agent/skills/agent-deck-workflow/scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session-id "<planner_session_id>" \
  --from-session-id "<reviewer_session_id>" \
  --to-session-id "<planner_session_id>" \
  --round "final" \
  --action "closeout_delivered" \
  --artifact-path ".agent-artifacts/<task_id>/closeout-<task_id>.md" \
  --note "Task review loop is complete after closeout acceptance (user or policy). Planner should run ~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh to complete required closeout actions. When --integration-branch is supplied, the script is expected to switch there before merge if the worktree is safe. Planning next task is optional." \
  --workflow-policy-json '<workflow_policy_json_optional>' \
  --special-requirements-json '<special_requirements_json_optional>' \
  --no-ensure-session \
  --no-start-session
```

Keep helper output concise (for example `dispatch_ok ...`).
Keep raw control JSON internal unless user explicitly asks.

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
- if the source review report path is known, include it explicitly so planner can inspect full context when needed

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
  - Agent Deck OFF:

```markdown
### Review Closeout
No actionable items.
```

  - Agent Deck ON: output `No actionable items.` and still append planner follow-up recommendation

## Output Template (Conditional)

Always start with:

```markdown
### Review Closeout
```

Then append only non-empty sections.

In Agent Deck mode, append planner follow-up recommendation.
If UI package content exists, include UI package before planner follow-up.

```markdown
#### Residual Follow-up For Planner (Only when any accepted non-blocking items remain)
- Source review report: `.agent-artifacts/<task_id>/review-report-r<round>.md`
- Track in progress/todo: [items worth recording for later follow-up, or `None`]
- Consider as next task/subtask: [items worth queueing, or `None`]
- No extra tracking needed: [items intentionally left as informational only, or `None`]

#### UI Manual Confirmation Package (Only when UI package content exists)
- UI impact: [detected | none detected]
- Changed UI surfaces: [routes/pages/components]
- Manual check steps (human-run): [short checklist]
- Expected visible outcomes: [what user should see]
- Notes: [optional]

#### Planner Follow-up Recommendation (After Closeout Acceptance)
- Required: run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/planner-closeout-batch.sh --task-id <task_id> --integration-branch <integration_branch>`.
- Required by script: switch to the target integration branch when needed, then merge `task/<task_id>` and update planner progress records.
- Before or during closeout, inspect the source review report and decide whether residual accepted findings should update progress/todo or next-task planning.
- Optional: plan and dispatch next task when appropriate.
- If `workflow_policy.auto_dispatch_next_task=true`, dispatch next queued task automatically after required closeout actions.
```

## Guidelines

1. Prefer completeness over aggressive trimming.
2. Keep neutral tone.
3. Do not include PASS-only lines.
4. Keep section order stable.
5. Keep output compact and copy/paste friendly.
6. Preserve `workflow_policy` unchanged when dispatching.
7. Preserve `special_requirements` unchanged when dispatching.
8. Make deferred follow-up ownership explicit enough that planner can act without rereading the whole report in the common case.
