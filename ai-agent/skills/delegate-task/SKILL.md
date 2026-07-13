---
name: delegate-task
description: Use for non-trivial implementation tasks that require meaningful code changes.
---

# Delegate Task

Create one concise, outcome-oriented mailbox message for another AI agent.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

Use this skill for non-trivial implementation work.

## 1) Quick Check (Required)

Before drafting the delegate message:
- Do not delegate pure docs, wording, summarization, inspection, or other non-code work.
- Do not delegate a small obvious code change that one agent can finish directly.
- Delegate non-trivial implementation work by default.
- If the task is small, local, and obvious enough to finish directly with less coordination, do the work directly.
- If splitting into multiple delegated tasks looks better than one task, ask the user before sending.

Execution mode: strict serial; do not send the next delegated task before closeout completes.

## 2) Output Mode

Keep the delegate brief directly in the mailbox body.
Keep it locally actionable, but include enough upstream context that coder can optimize for the parent goal instead of only the local wording.

Delegate the outcome, not a solution recipe:
- Assume coder and reviewer can investigate, decompose, reason, and validate independently.
- Provide parent intent, known evidence, hard boundaries, fixed upstream decisions, and testable acceptance criteria.
- Omit speculative file/function lists, step-by-step implementation plans, guessed decomposition, and explanations the receiving agent can derive from the workspace.
- Preserve decision provenance: label a choice as fixed only when the user, reviewed design, or existing contract actually fixed it. Otherwise leave the choice to coder.
- Give reviewers scope, artifacts, and criteria without seeding expected findings or verdicts.
- Treat an unusually long brief as a scope/framing smell; remove detail that does not change the outcome, boundary, risk, or acceptance criteria.

Agent Deck mode:
- Use the `agent-deck-workflow` skill for shared rules
- delegate creator is planner sender
- This delegation is Agent Deck mailbox/session workflow, not a host built-in subagent call.

Branch-plan terms:
- `integration_branch` is the existing non-task branch that should receive the completed task at closeout
- `task_branch` is the branch where the delegated implementation is done
- normal closeout merges `task_branch` into `integration_branch`
- `worker_workspace` and `planner_workspace` are workflow roles, not a requirement that the paths differ

Resolve by priority:
- `task_id`: explicit -> context -> generate `YYYYMMDD-HHMM-<slug>`
- `planner_session_id`: explicit -> context -> bound mailbox sender context -> ask
- `planner_workspace`: explicit -> workflow context -> current workspace -> ask
- `worker_workspace`: explicit -> workflow context -> `planner_workspace`
  - do not silently infer, create, or switch to a different worker workspace
  - if a separate or temporary worker workspace seems useful but was not explicit, ask the user before dispatch
  - if you create a temporary worker worktree, remove it after closeout
- `start_branch`: explicit -> context -> ask
- `integration_branch`: explicit -> context -> if `start_branch` is the intended non-task landing line for this delegated change, use `start_branch`; otherwise infer from explicit user intent or recorded workflow context for `start_branch`; if confidence is low, ask rather than guessing
  - integration branch must be the non-task landing branch; never use `task/*` as `integration_branch`
  - if `start_branch` is `task/*`, treat it as the task branch and ask for the real integration branch unless context already records it
  - never assume `main`/`master`; branch names are evidence, not truth
- `coder_session_ref`: explicit -> context -> default `coder-<task_id>`
- `coder_session_id`: explicit actual id -> context actual id -> helper output after target resolution -> omit until known
- `reviewer_session_ref`: explicit -> context -> default `reviewer-<task_id>`
- `reviewer_session_id`: explicit actual id -> context actual id -> omit when the reviewer is not yet created
- `task_branch`: explicit -> context -> if `start_branch` is already the intended topic branch for this delegated change, reuse `start_branch`; otherwise default `task/<task_id>` created from `integration_branch`
  - in the normal merge-based workflow, `task_branch` must differ from `integration_branch`
- `coder_tool_profile`: explicit -> context -> omit when `coder_tool` is already a full command -> default current-tool continuity or resolver role default `coder`
- `coder_tool_cmd`: explicit full command -> context resolved command -> current AI tool when continuity is intended -> shared tool-resolution contract for role `coder`
- `reviewer_tool_profile`: explicit -> context -> omit when `reviewer_tool` is already a full command -> default resolver role default `reviewer`
- `reviewer_tool_cmd`: explicit full command -> context resolved command -> shared tool-resolution contract for role `reviewer`
- keep `reviewer_session_ref` distinct unless same-session reviewer assignment is explicit
- `workflow_policy` (optional): explicit -> context -> default unattended policy
- `per_task_review` (optional): explicit -> context -> default `required`
- `final_review` (optional): explicit -> context -> default `skip`
- `special_requirements` (optional fallback): explicit -> context -> extract user constraints not represented by existing structured fields -> omit when empty
- `big_picture` (required when available): explicit -> context -> infer from current user goal / active plan -> ask only when task framing would otherwise be misleading
- `reviewed_design_docs` (required when task is based on `tech_design_review_report`): explicit -> architect report `Reviewed Scope` -> ask if unavailable
- `escalation_triggers` (optional): explicit -> context -> infer from task risk / boundary uncertainty -> omit when empty

Workflow policy inference:
- default to unattended => `mode = "unattended"` and `auto_accept_if_no_must_fix = true`
- human-gated only when the user explicitly asks for a human acceptance gate
- unless user says otherwise, unattended keeps `ui_manual_confirmation = "skip"`
- write inferred automation choices into `## Workflow Policy`

## 3) Mailbox Body Template

Use this structure:

```markdown
Task: <task_id>
Action: execute_delegate_task
From: planner <planner_session_id>
To: coder {{TO_SESSION_ID}}
Planner: <planner_session_id>
Round: 1

## Summary
[One-line objective summary]

## Big Picture
- Parent goal: [what larger task or outcome this delegated task serves]
- Why this task exists: [why planner split this piece out]
- Must not break: [upstream constraint, invariant, or user-facing outcome]

## Objective
[One sentence]

## Known Evidence
- [established fact, symptom, or relevant artifact; omit inferred solutions and omit this section when empty]

## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Rationale: [why dedicated task branch vs reused topic branch]

## Constraints & Risks
- [hard constraint / fixed upstream decision with provenance / material risk; omit this section when empty]

## Implementation Discipline
- Own the investigation, local decomposition, design choice, implementation, and validation within this scope
- Optimize for the smallest conflict surface that still completes the task
- Do not perform unrelated refactors, renames, file moves, or broad cleanups
- Keep touched files and mechanical rewrites to the minimum needed for this task
- If a larger cleanup seems useful, report it back to planner instead of folding it into this task

## Review Policy
- Per-task review: [required | skip]
- Final integration review: [planner-managed | required | skip]

## Starting Context
- Read before starting: [binding contracts and required artifacts; include reviewed design docs when applicable]
- Reference as needed: [optional supporting material]
- Know it exists: [useful discovery pointers that need not be read up front]

## Escalate Back To Planner
- Ask planner before proceeding if: [scope no longer matches evidence, local optimum appears to hurt the parent goal, or the task needs a material boundary/plan change]
- Keep moving without asking only when: [the remaining uncertainty is local and does not change the parent goal or branch plan]

## Acceptance Criteria
- [testable outcome; avoid prescribing implementation shape]

## Required Workflow Step
- If `Per-task review: required`, run `review-request` after the delivery commit; then continue only with independent local work or stop after confirming the request was sent
- Do not wait for, inspect, or repair the reviewer in the same turn after sending `review-request`
- If `Per-task review: skip`, do not start reviewer unless planner explicitly requests it later

## Important Notes
- Coder git writes and commits for this delegated task are pre-authorized
- Coder must follow the recorded branch plan and must not invent a different working branch

## Agent Deck Context
- Planner: [planner_session_id] | Coder: {{TO_SESSION_ID}}
- Workspaces: planner=[planner_workspace] worker=[worker_workspace]
- Workspace lifecycle: [shared/existing | temp path=<path> cleanup=planner-after-closeout]
- Coder tool: profile=[coder_tool_profile or `explicit`] cmd=[coder_tool_cmd]
- Reviewer: ref=[reviewer_session_ref or `N/A`] id=[reviewer_session_id or `N/A`]
- Reviewer tool: profile=[reviewer_tool_profile or `N/A`] cmd=[reviewer_tool_cmd or `N/A`]

## Workflow Policy
[resolved workflow policy]

## Special Requirements
[only when present]
```

Tool-routing rule:
- preserve full coder/reviewer commands when the user gives them
- otherwise resolve profile defaults through the shared resolver instead of hardcoding model/version defaults here

## 4) Mailbox Send + Wakeup (When Agent Deck Mode Is On)

Preferred path: use the `agent_mailbox` MCP tools.

Workflow send sequence:
1. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-workspaces.sh --worker-workspace <worker_workspace> --planner-workspace <planner_workspace> --integration-branch <integration_branch> --planner-session-id <planner_session_id>` before dispatch
   - never substitute a new temp directory for unclear workspace context without user confirmation; resolve the workspace fields first
2. use `agent_mailbox`
3. compose the body with `{{TO_SESSION_ID}}` placeholders where the real coder session id must appear
4. resolve `coder_tool_profile` / `coder_tool_cmd` using the shared tool-resolution contract for role `coder`
   - preserve explicit full `coder_tool` unchanged when provided
   - otherwise, if continuity with the current session tool is intended, preserve the current full tool command as `coder_tool_cmd` and record `coder_tool_profile = inherited`
   - otherwise resolve the role `coder` command
5. call `agent_deck_create_session`
   - `ensure_title = <coder_session_ref>`
   - `ensure_cmd = <coder_tool_cmd>`
   - `workdir = <worker_workspace>`
   - `parent_session_id = <planner_session_id>`
   - `group_path = <planner session group; empty string for root>`
   - `no_parent_link = false`
6. use the returned `session_id` as the authoritative `coder_session_id`
7. if `Per-task review: required`, resolve `reviewer_tool_profile` / `reviewer_tool_cmd` using the shared tool-resolution contract for role `reviewer`
   - preserve explicit full `reviewer_tool` unchanged when provided
   - otherwise resolve the role `reviewer` command
8. do not create the reviewer during delegate dispatch; pass `reviewer_session_ref`, `reviewer_tool_profile`, and `reviewer_tool_cmd` so `review-request` can create it on demand
9. fill the final body
10. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/send-delegate-with-active-task-lock.sh` outside the restricted shell with:
   - `--workdir <worker_workspace>`
   - `--task-id <task_id>`
   - `--integration-branch <integration_branch>`
   - `--planner-session-id <planner_session_id>`
   - `--coder-session-id <coder_session_id>`
   - `--coder-session-ref <coder_session_ref>`
   - `--task-branch <task_branch>`
   - `--subject "delegate: <task_id> -> coder"`
   - `--body-file <delegate mailbox body file or "-">`
     - prefer `-` and pipe the body through stdin
     - if a real file is needed, write it under this agent's `.agent-artifacts/mailbox/`
   - use the wrapper for active-task lock acquisition, delegate send, send failure rollback, and target wakeup

Recommended subject:
- `delegate: <task_id> -> coder`

Rules:
- keep the full delegate brief in mailbox body
- do not replace this path with host subagent tools; use `agent_deck_create_session` only for lifecycle allocation, and let `send-delegate-with-active-task-lock.sh` own delegate send and wakeup
- include enough big-picture context that coder can judge whether the delegated task still serves the parent goal during execution
- if the delegated task is based on a tech-design review, cite the reviewed branch, commit, and design-doc paths under `Starting Context` -> `Read before starting`
- make conflict-minimizing implementation discipline explicit in the delegate brief when this workspace may later be integrated with parallel work
- keep the workspace planner record aligned with the recorded `integration_branch`; if the session create step reports a mismatch, stop instead of dispatching
- pass `--override-workspaces` only after explicit user confirmation to replace the mirrored `planner-workspace.json` records
- do not silently create ad hoc temporary workspaces; separate worker workspaces require explicit context or user confirmation
- record path and cleanup responsibility for any temporary worktree you create
- use `coder-<task_id>` and `reviewer-<task_id>` as session refs until the real session ids are allocated
- create coder sessions through `agent_deck_create_session` with `parent_session_id = <planner_session_id>`, `group_path = <planner session group; empty string for root>`, and `no_parent_link = false`; do not rely on path-derived default grouping
- do not pre-create reviewer sessions during delegate dispatch; when review is required, `review-request` creates or reuses `reviewer-<task_id>` on demand with `parent_session_id = <planner_session_id>` and `group_path = <planner session group; empty string for root>`
- ensure coder and reviewer sessions use the same `<worker_workspace>` passed to `send-delegate-with-active-task-lock.sh`
- `worker_workspace` may be the same path as `planner_workspace`; when they are the same, treat that as an explicit shared-workspace choice, not a workflow error
- send delegated work through `send-delegate-with-active-task-lock.sh`; mailbox transport itself must stay workflow-agnostic
- do not split active-task lock acquisition and delegate send into separate workflow/tool steps
- when `Per-task review: required`, coder should receive enough reviewer routing policy to create/reuse the reviewer later through `review-request`; reviewer must be planner-scoped, never coder-scoped
- report target readiness only after the resolve/create/send path that applies has completed
- if the delegate send wrapper reports an existing active task, surface that result instead of retrying through another send path
- treat coder/reviewer progress as asynchronous with unbounded duration; delegated implementation is expected to outlive this dispatch turn
- follow the shared Async sender rule for coder/reviewer progress
- in the delegated task workspace, treat the active task worktree state as coder-owned until closeout; do not change branch state, modify files, or otherwise alter that workspace state there
- if `worker_workspace == planner_workspace`, planner must still avoid touching that delegated task worktree state outside the delegate/closeout workflow
- if execution evidence suggests the delegated task is framed too narrowly, coder should ask planner instead of forcing a local-only completion

## 5) User-Facing Output Contract

After sending:
- Return short confirmation with:
  - mailbox subject
  - one-line objective summary
  - `task_branch` / `integration_branch`
  - `coder_session_id` / `reviewer_session_ref` and any known `reviewer_session_id`
  - `coder_tool_profile` / `reviewer_tool_profile`
  - `coder_tool_cmd` / `reviewer_tool_cmd`
  - temporary worktree path/cleanup, if created
  - recipient inbox address
  - listener/send summary, including any best-effort nudge if reported
- Keep raw mailbox JSON internal unless user explicitly asks
- If listener/send fails, report stderr summary and include the shared diagnostics checklist from the `agent-deck-workflow` skill
