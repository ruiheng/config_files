---
name: plan-report
description: Handle a final `plan_report_delivered` message from a planner, integrate completed results, and clean up planner sessions.
---

# Plan Report

Handle one final planner report from `plan_report_delivered`.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Provide the mailbox body from `plan_report_delivered`.

## Rules

- treat this report as the final summary for that planner lane unless the body says it is blocked
- surface completion status, integration branch, completed tasks, review summary, and open items
- default completed-plan action is: merge the planner integration branch into the current supervisor branch, then clean up the planner-owned structure recorded for that lane
- skip supervisor-side integration only when the report is blocked, the report has unresolved open items, the user explicitly requested report-only handling, or a concrete git precondition blocks the merge
- use `git merge` for supervisor-side integration; do not substitute `cherry-pick`, `rebase`, or another git history strategy
- treat the current supervisor worktree branch as the integration target unless explicit user/workflow context says otherwise; if the target branch is unclear or the worktree is dirty, stop and report the blocker
- after supervisor-side integration succeeds, run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/archive-and-remove-planner-group-sessions.sh --planner-session-id <planner_session_id> --apply`
- planner cleanup relies on live `agent-deck` state for `<planner_session_id>`; if that live scope is unavailable, keep the result as best-effort/no-op instead of trying to recover scope from old records
- do not clean up the planner-owned structure before supervisor-side integration has actually completed
- if the cleanup script exits non-zero, report that failure and stop; best-effort subgroup cleanup warnings are non-fatal and should be surfaced as warnings; do not continue with manual `agent-deck remove` or `group delete` commands unless the user explicitly asks
- do not ask for another workflow step unless the report explicitly says the plan is blocked, follow-up is required, or a concrete merge/cleanup blocker needs user action
- keep mailbox JSON internal unless the user explicitly asks

## User-Facing Output

- report whether the plan completed or blocked
- include the planner session id
- include the integration branch
- include whether supervisor-side merge ran
- include whether planner cleanup ran
- include any open items that still need user attention
