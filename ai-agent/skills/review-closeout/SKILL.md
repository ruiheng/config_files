---
name: review-closeout
description: Extracts a concise review closeout from a full review report, keeping actionable items and any FAIL/UNKNOWN checks, and outputs directly for copy/paste.
---

# Review Closeout

Extract a closeout summary from a full review report.

## Purpose

Use this skill when a full review report already exists and only the remaining follow-up items are needed for handoff/closure.

## Input

Provide one of the following:
1. A full review report text, OR
2. A path to a review report file

## Output Mode (Fixed)

- Output directly in the response.
- By default, do NOT create files.
- In Agent Deck mode, also write a closeout artifact file for cross-session handoff.
- Keep output copy/paste friendly Markdown.

Agent Deck mode (context-first, compatibility-safe):
- Enter Agent Deck mode if any is true:
  1. `task_id` or `planner_session` is explicitly provided
  2. input/report context already carries Agent Deck metadata
  3. user asks for agent-deck flow
- Run `agent-deck session current --json` in host shell (outside sandbox) to detect session context when possible.
- If detection fails (for example `not in a tmux session`), continue with explicit/context metadata only.

In Agent Deck mode:
- This skill depends on `agent-deck` skill script:
  - `scripts/dispatch-control-message.sh` (from the `agent-deck` skill directory, not this skill directory)
- Required dependency behavior:
  1. ensure `agent-deck` skill is available/loaded
  2. resolve `agent-deck` skill directory
  3. invoke `<agent_deck_skill_dir>/scripts/dispatch-control-message.sh`
  4. if unresolved, stop and ask user to attach/install `agent-deck` skill

In Agent Deck mode, resolve:
- `task_id`: explicit input -> parse from review-report path `.agent-artifacts/<task_id>/...` -> ask if missing
- `planner_session`: explicit input -> parse from review context/metadata -> host-shell detection from `agent-deck session current --json` -> ask if missing

If both values are resolved:
1. write the closeout markdown to `.agent-artifacts/<task_id>/closeout-<task_id>.md`
2. construct one JSON control payload for reviewer -> planner handoff (internal protocol, not user-facing output)
3. include explicit planner follow-up recommendation in closeout output:
   - after user confirmation, planner should batch: merge task branch, update progress, plan next task
4. dispatch to planner via helper script:

```bash
AGENT_DECK_DISPATCH_SCRIPT="<agent_deck_skill_dir>/scripts/dispatch-control-message.sh"
"$AGENT_DECK_DISPATCH_SCRIPT" \
  --task-id "<task_id>" \
  --planner-session "<planner_session>" \
  --from-session "reviewer-<task_id>" \
  --to-session "<planner_session>" \
  --round "final" \
  --action "closeout_delivered" \
  --artifact-path ".agent-artifacts/<task_id>/closeout-<task_id>.md" \
  --note "Task review loop is complete after user confirmation. Planner should batch closeout actions: merge task branch, update progress, and plan next task." \
  --no-ensure-session \
  --no-start-session
```

For concise logs, report helper output summary only.
- Do not print raw JSON payload in user-facing output unless user explicitly requests the control payload.
- Control payload schema reference (internal only; do not print to user by default):

```json
{
  "schema_version": "1.0",
  "task_id": "<task_id>",
  "planner_session": "<planner_session>",
  "from_session": "reviewer-<task_id>",
  "to_session": "<planner_session>",
  "round": "final",
  "action": "closeout_delivered",
  "artifact_path": ".agent-artifacts/<task_id>/closeout-<task_id>.md",
  "note": "Task review loop is complete after user confirmation. Planner should batch closeout actions: merge task branch, update progress, and plan next task."
}
```

## Extraction Rules

Keep content with **inclusion-first** policy (prefer keeping over dropping):

1. **Always keep non-empty items from**:
- `Critical Issues`
- `Design Concerns`
- `Minor Suggestions`
- `Verification Questions`

2. **Request/Security checks**:
- Remove `PASS` lines.
- Keep any line marked `FAIL` or `UNKNOWN`.

3. **None handling**:
- Remove `None.` placeholders.
- If a section has both `None.` and real items, keep real items only.

4. **Wording safety**:
- Preserve original technical meaning.
- Keep file paths / line references when present.
- Do not invent new issues.

## Rendering Rules (No Empty Sections)

Render output with **conditional sections**:

1. Build 5 section buckets in this fixed order:
- `Critical Issues`
- `Design Concerns`
- `Minor Suggestions`
- `Verification Questions`
- `Remaining Check Alerts (FAIL/UNKNOWN Only)`

2. Add items to each bucket using the extraction rules above.
3. Remove empty items / placeholders (`None.` / PASS-only lines).
4. **Only render a section when its bucket has at least 1 item.**
5. **Never output a heading with no bullet items under it.**
6. If all 5 buckets are empty:
   - when Agent Deck mode is OFF, output exactly:

```markdown
### Review Closeout
No actionable items.
```

   - when Agent Deck mode is ON, output `No actionable items.` and still append `Planner Follow-up Recommendation (After User Confirmation)`.

## Output Template (Conditional)

Always start with:

```markdown
### Review Closeout
```

Then append only non-empty sections, for example:

```markdown
### Review Closeout

#### Design Concerns
- [item]

#### Verification Questions
- [item]
```

The above is just an example of sparse rendering; do not force missing sections to appear.

In Agent Deck mode, append this final section after all extracted buckets:

```markdown
#### Planner Follow-up Recommendation (After User Confirmation)
- Merge `task/<task_id>` into the target integration branch (follow repo/user merge policy).
- Update planner progress records with execution status and residual concerns.
- Plan and dispatch the next task when appropriate.
```

## Guidelines

1. Prefer completeness over aggressive trimming.
2. Keep neutral tone and avoid chat framing.
3. Do not include PASS-only status lines.
4. Keep ordering stable: Critical -> Design -> Minor -> Questions -> Alerts.
5. Output must be compact and copy/paste friendly; no empty sections.
6. In Agent Deck mode, include planner follow-up recommendation as actionable guidance, but do not claim planner actions were executed.
