---
name: dispatch-plan
description: Send a goal to an Agent Deck planner.
---

# Dispatch Plan

Send one supervisor-assigned goal to a planner session.
This creates one planner lane or resumes one existing lane by real `planner_session_id`.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Inputs

- `plan_id`
- `supervisor_session_id`
- `workspace`
- `integration_branch` (planner-owned branch for this dispatched plan; must exist before send)
- optional `review_base` source ref (resolve and store its commit OID for final integration review)
- `goal`
- optional `planner_tool`
- optional `planner_tool_profile`
- optional `per_task_review`
- optional `final_review`
- optional `summary`
- optional `special_requirements`

When resuming an existing planner lane:
- `planner_session_id`

When allocating a new planner lane:
- optional `planner_session_ref`

## Rules

- one planner lane owns one session, workspace lifecycle, integration branch, and serial task decomposition in one workspace
- set `planner_workspace = worker_workspace = workspace`; do not switch workspace or start another active lane there except an explicit resume
- workspace reservation records prepare task closeout; they do not schedule planner-lane exclusivity
- prefer a child session for the dispatched planner when agent-deck can represent the workflow directly that way
- when deeper nesting needs subgroup fallback, keep that inside the session manager; do not expose it in the workflow contract
- when creating a new planner session and no planner title/ref is provided, use `planner-YYYYMMDD-HHMM-<slug>`; do not use bare `planner`
- `integration_branch` is the planner-owned branch for this dispatched plan, not the supervisor landing branch
- for a new plan, resolve `source_ref`: explicit `review_base` -> current supervisor `HEAD`; run `git rev-parse --verify <source_ref>^{commit}`, store its OID as `review_base`, and create a fresh `integration_branch` from it before sending
- on resume, preserve the recorded `review_base`; never derive a new one
- do not silently reuse an existing planner integration branch from an earlier run; reuse is allowed only when the user explicitly says this dispatch is resuming that same unfinished plan
- if the requested or derived `integration_branch` already exists and resume was not explicit, choose a new branch name or ask; do not dispatch onto an old branch tip
- create the planner integration branch without switching the supervisor worktree; start from the recorded `review_base` OID
- if `planner_tool` is omitted, honor an explicit `planner_tool_profile` first; otherwise prefer the current session tool/command from agent-deck session metadata for continuity; otherwise resolve the planner role default through the shared tool-resolution contract
- when `planner_session_id` is already known, treat the planner session as existing and carry forward its recorded `planner_tool_profile` / `planner_tool_cmd`; do not resolve a fresh planner command
- default `per_task_review = required`
- default `final_review = skip`
- blockers stop with a user question; do not add blocker message to supervisor
- planner is not done when implementation is done; planner is done only after the assigned goal is complete or blocked and the required final report has been sent to supervisor
- normal path: resolve inputs, create or require the planner session through MCP, then send the message body
- do not inspect `--help`, environment variables, or repo docs first unless the MCP create/require or send step actually fails

## Waypost Message Body Template

```markdown
Task: <plan_id>
Action: execute_plan
From: supervisor <supervisor_session_id>
To: planner {{TO_SESSION_ID}}
Planner: {{TO_SESSION_ID}}
Round: 1

## Summary
[One-line plan summary]

## Goal
[What this planner must finish in this workspace]

## Workspace Contract
- Workspace path: [workspace]
- Integration branch: [integration_branch]
- Review base: [full commit OID]
  Source commit used to create this integration branch; use it for final integration review.
- Execution model: planner-owned decomposition; serial tasks in one workspace
- Completion rule: planner is complete only after finishing the assigned goal and successfully sending `plan_report_delivered` to supervisor

## Review Policy
- Per-task review: [required | skip]
- Final integration review: [required | skip]

## Tool Policy
- Planner tool profile: [planner_tool_profile or `inherited`]
- Planner tool cmd: [planner_tool_cmd]

## Planning Contract
- Planner owns task decomposition and sequencing inside this workspace
- Keep task execution serial in this workspace
- Do not rely on workspace reservation records as cross-task locks; prepare the workspace again for each task closeout path
- Use `delegate-task` Selection-Only: Direct only after its gate passes; otherwise use a native harness, independently justified persistent Waypost Agent Deck via `delegate-code-task`, or planner-owned nonpersistent delivery. Never generic Dispatch.
- Planner owns branch, commit, review, and closeout for local, harness, and nonpersistent delivery.
- Planner-local execution and any later delegated work both stay in the one workspace recorded above
- Any self-implemented code change still requires workspace prep, explicit task branch from `integration_branch`, commit, any required review, closeout merge, and final supervisor report
- Routine branch, commit, review-request, closeout, and final-report actions are workflow-authorized; ask the user only for real scope/tradeoff decisions or explicit human gates
- Ask the user directly if the goal cannot be completed without a real scope or tradeoff decision

## Special Requirements
[only when present]
```

## Waypost Message Send

1. resolve the current supervisor branch; if the worktree is detached or the landing branch is unclear, stop and ask instead of guessing
2. for a new plan, resolve `source_ref = explicit review_base -> current supervisor HEAD`; set `review_base = git rev-parse --verify <source_ref>^{commit}`. On resume preserve recorded `review_base`
3. resolve `workspace`
4. set internal `planner_workspace = workspace` and `worker_workspace = workspace`
5. resolve `planner_session_ref`; when creating a new planner and no existing ref/id is provided, generate `planner-YYYYMMDD-HHMM-<slug>` from the workspace or goal
6. resolve planner tool policy only when allocating a new planner lane, following the shared tool-resolution contract for role `planner`
   - if `planner_session_id` is already known, skip this resolution step and carry forward the existing planner tool metadata
   - if explicit `planner_tool` is provided, preserve it unchanged as `planner_tool_cmd`
   - otherwise, if explicit `planner_tool_profile` is provided, resolve role `planner` with that profile
   - otherwise, if current session metadata provides the supervisor's current full tool command, reuse it as `planner_tool_cmd` and record `planner_tool_profile = inherited`
   - otherwise resolve the default role `planner` command
   - record both `planner_tool_profile` and `planner_tool_cmd`
7. resolve `integration_branch`
   - explicit branch name wins
   - otherwise derive a fresh planner-owned branch name from `plan_id`; prefer `plan/<plan_id>`
8. for a new plan, create the planner integration branch from `review_base` OID before dispatch
   - do not switch the supervisor worktree onto that branch
   - if the preferred branch name already exists and resume was not explicit, choose a new unique suffix instead of reusing that ref
   - on resume, preserve the recorded `review_base`
9. use `waypost`
10. if this dispatch is allocating a new planner lane, call `agent_deck_create_session` for the planner target
   - `ensure_title = <planner_session_ref>`
   - `ensure_cmd = <planner_tool_cmd>`
   - `workdir = <planner_workspace>`
   - `parent_session_id = <supervisor_session_id>`
   - `group_path = <supervisor session group; empty string for root>`
   - `no_parent_link = false`
   - record the returned `planner_session_id` and carry it in all later workflow turns for that lane
11. otherwise call `agent_deck_require_session`
   - `session_id = <planner_session_id>`
   - `workdir = <planner_workspace>`
12. use the returned `session_id` as the authoritative `planner_session_id`
13. fill `{{TO_SESSION_ID}}`
14. send with:
   - `from_address = agent-deck/<supervisor_session_id>`
   - `to_address = agent-deck/<planner_session_id>`
   - `subject = "plan dispatch: <plan_id>"`
   - `body = <execute-plan message body>`
15. follow the shared Async sender rule for planner reports

Rules:
- use `agent_deck_create_session` only when allocating a new planner lane; use `agent_deck_require_session` when resuming an existing planner session
- new planner lanes must pass `group_path = <supervisor session group; empty string for root>` with `parent_session_id`; do not rely on path-derived default grouping
- after a planner lane is created, later workflow turns must reuse the real `planner_session_id`; do not resume a normal workflow turn by `planner_session_ref`
- do not create planner sessions through direct `agent-deck` CLI in the normal path
- treat MCP session create/require as a synchronous step; wait for it to return before composing or sending message content
- record both `planner_tool_profile` and `planner_tool_cmd` in workflow context; use the command for session creation and the profile as policy metadata
