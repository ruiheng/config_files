---
name: plan-report
description: Handle a final `plan_report_delivered` message from a planner and surface the result to the supervisor session.
---

# Plan Report

Handle one final planner report from `plan_report_delivered`.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide the mailbox body from `plan_report_delivered`.

## Rules

- treat this report as the final summary for that planner-run plan unless the body says it is blocked
- surface completion status, integration branch, planner group, completed tasks, review summary, and open items
- if the report is completed, planner group is present, and supervisor has already integrated that planner result, use `~/.config/ai-agent/skills/agent-deck-workflow/scripts/archive-and-remove-planner-group-sessions.sh --planner-group <planner_group> --apply` to clean up planner-owned sessions
- do not clean up the planner group before the supervisor-side integration decision is done
- do not ask for another workflow step unless the report explicitly says the plan is blocked or follow-up is required
- keep mailbox JSON internal unless the user explicitly asks

## User-Facing Output

- report whether the plan completed or blocked
- include the planner session id
- include the integration branch
- include the planner group when present
- include any open items that still need user attention
