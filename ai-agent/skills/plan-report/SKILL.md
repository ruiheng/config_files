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
- default action after receiving this report is: surface status, acknowledge the mail, keep the planner group intact, and stop
- do not start supervisor-side integration unless the user explicitly asked to do that in this turn
- when the user explicitly asks to continue supervisor-side integration, use `git merge` for that integration; do not substitute `cherry-pick`, `rebase`, or another git history strategy
- if the report is completed, planner group is present, and supervisor has already integrated that planner result, use `~/.config/ai-agent/skills/agent-deck-workflow/scripts/archive-and-remove-planner-group-sessions.sh --planner-group <planner_group> --apply` to clean up planner-owned sessions
- do not clean up the planner group before supervisor-side integration has actually completed
- if the cleanup script fails, report that failure and stop; do not continue with manual `agent-deck remove` or `group delete` commands unless the user explicitly asks
- do not ask for another workflow step unless the report explicitly says the plan is blocked or follow-up is required
- do not describe the lack of supervisor-side integration as a pending user decision unless the user was explicitly asked whether to integrate now
- keep mailbox JSON internal unless the user explicitly asks

## User-Facing Output

- report whether the plan completed or blocked
- include the planner session id
- include the integration branch
- include the planner group when present
- include any open items that still need user attention
