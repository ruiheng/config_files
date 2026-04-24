---
name: delegate-task
description: Use for non-trivial implementation tasks that require meaningful code changes.
---

# Delegate Task

Create one concise, execution-ready mailbox message for another AI agent.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

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

Agent Deck mode:
- Follow shared rules in `agent-deck-workflow/SKILL.md`
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
- `start_branch`: explicit -> context -> ask
- `integration_branch`: explicit -> context -> if `start_branch` is the intended non-task landing line for this delegated change, use `start_branch`; otherwise infer from explicit user intent or recorded workflow context for `start_branch`; if confidence is low, ask rather than guessing
  - integration branch must be the non-task landing branch; never use `task/*` as `integration_branch`
  - if `start_branch` is `task/*`, treat it as the task branch and ask for the real integration branch unless context already records it
  - never assume `main`/`master`; branch names are evidence, not truth
- `coder_session_ref`: explicit -> context -> default `coder-<task_id>`
- `coder_session_id`: explicit actual id -> context actual id -> helper output after target resolution -> omit until known
- `reviewer_session_ref`: explicit -> context -> default `reviewer-<task_id>`
- `reviewer_session_id`: explicit actual id -> context actual id -> resolved by planner before delegate send when `per_task_review = required`; omit only when `per_task_review = skip`
- `task_branch`: explicit -> context -> if `start_branch` is already the intended topic branch for this delegated change, reuse `start_branch`; otherwise default `task/<task_id>` created from `integration_branch`
  - in the normal merge-based workflow, `task_branch` must differ from `integration_branch`
- `coder_tool`: explicit -> context -> default current AI tool
  - preserve full commands unchanged
  - normalize provider-only names:
    - `claude` -> `claude --model sonnet --permission-mode acceptEdits`
    - `codex` -> `codex --model gpt-5.4 --ask-for-approval on-request`
    - `gemini` -> `gemini --model gemini-3.1-pro-preview`
- `reviewer_tool`: explicit -> context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
  - if user/context provides a full reviewer command with arguments, preserve it unchanged
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

## Components to Address
- [component]: [responsibility] | Key question: [...]

## Critical Decisions
- [decision]: Options / trade-offs / recommendation

## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Rationale: [why dedicated task branch vs reused topic branch]

## Constraints & Risks
- [hard constraint / risk / mitigation]

## Implementation Discipline
- Optimize for the smallest conflict surface that still completes the task
- Do not perform unrelated refactors, renames, file moves, or broad cleanups
- Keep touched files and mechanical rewrites to the minimum needed for this task
- If a larger cleanup seems useful, report it back to planner instead of folding it into this task

## Review Policy
- Per-task review: [required | skip]
- Final integration review: [planner-managed | required | skip]

## Context to Acquire
- Read before starting: [...]
- Reference as needed: [...]
- Know it exists: [...]
- Reviewed design docs: [branch + commit + doc paths when this task is based on a tech-design review]

## Escalate Back To Planner
- Ask planner before proceeding if: [scope no longer matches evidence, local optimum appears to hurt the parent goal, or the task needs a material boundary/plan change]
- Keep moving without asking only when: [the remaining uncertainty is local and does not change the parent goal or branch plan]

## Acceptance Criteria
- [testable completion item]

## Required Workflow Step
- If `Per-task review: required`, coder must run the `review-request` skill and send the review-request mailbox message after the delivery commit
- If `Per-task review: skip`, do not start reviewer for this task unless planner explicitly requests review later

## Important Notes
- Coder git writes and commits for this delegated task are pre-authorized
- Coder must follow the recorded branch plan and must not invent a different working branch

## Agent Deck Context
- Planner session: [planner_session_id]
- Coder session id: {{TO_SESSION_ID}}
- Reviewer session id: [reviewer_session_id or `N/A` when `Per-task review: skip`]
- Coder tool: [coder_tool]
- Reviewer tool: [reviewer_tool]

## Workflow Policy
[resolved workflow policy]

## Special Requirements
[only when present]
```

Tool-routing rule:
- preserve full coder/reviewer commands when the user gives them
- normalize provider-only preferences to the recommended full command

## 4) Mailbox Send + Wakeup (When Agent Deck Mode Is On)

Preferred path: use the `agent_mailbox` MCP tools.

Workflow send sequence:
1. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-workspaces.sh --worker-workspace <worker_workspace> --planner-workspace <planner_workspace> --integration-branch <integration_branch> --planner-session-id <planner_session_id>` before dispatch
2. use `agent_mailbox`
3. compose the body with `{{TO_SESSION_ID}}` placeholders where the real coder session id must appear
4. call `agent_deck_create_session`
   - `ensure_title = <coder_session_ref>`
   - `ensure_cmd = <coder_tool>`
   - `workdir = <worker_workspace>`
   - `parent_session_id = <planner_session_id>`
   - `no_parent_link = false`
5. use the returned `session_id` as the authoritative `coder_session_id`
6. if `Per-task review: required`, call `agent_deck_create_session` for reviewer before sending coder mail
   - `ensure_title = <reviewer_session_ref>`
   - `ensure_cmd = <reviewer_tool>`
   - `workdir = <worker_workspace>`
   - `parent_session_id = <planner_session_id>`
   - `no_parent_link = false`
7. use the returned `session_id` as the authoritative `reviewer_session_id`
8. fill the final body
9. run `~/.config/ai-agent/skills/agent-deck-workflow/scripts/send-delegate-with-active-task-lock.sh` with:
   - `--workdir <worker_workspace>`
   - `--task-id <task_id>`
   - `--integration-branch <integration_branch>`
   - `--planner-session-id <planner_session_id>`
   - `--coder-session-id <coder_session_id>`
   - `--coder-session-ref <coder_session_ref>`
   - `--task-branch <task_branch>`
   - `--subject "delegate: <task_id> -> coder"`
   - `--body-file <delegate mailbox body file or "-">`
   - the wrapper owns active-task lock acquisition, delegate send, send failure rollback, and target wakeup

Recommended subject:
- `delegate: <task_id> -> coder`

Rules:
- keep the full delegate brief in mailbox body
- do not replace this path with host subagent tools; use `agent_deck_create_session` only for lifecycle allocation, and let `send-delegate-with-active-task-lock.sh` own delegate send and wakeup
- include enough big-picture context that coder can judge whether the delegated task still serves the parent goal during execution
- if the delegated task is based on a tech-design review, cite the reviewed branch, commit, and design-doc paths in `Context to Acquire`
- make conflict-minimizing implementation discipline explicit in the delegate brief when this workspace may later be integrated with parallel work
- keep the workspace planner record aligned with the recorded `integration_branch`; if the session create step reports a mismatch, stop instead of dispatching
- pass `--override-workspaces` only after explicit user confirmation to replace the mirrored `planner-workspace.json` records
- use `coder-<task_id>` and `reviewer-<task_id>` as session refs until planner resolves the real session ids
- create coder and reviewer sessions through `agent_deck_create_session` with `parent_session_id = <planner_session_id>` and `no_parent_link = false`; subgroup fallback, when needed, is handled inside the session manager
- ensure coder and reviewer sessions use the same `<worker_workspace>` passed to `send-delegate-with-active-task-lock.sh`
- `worker_workspace` may be the same path as `planner_workspace`; when they are the same, treat that as an explicit shared-workspace choice, not a workflow error
- send delegated work through `send-delegate-with-active-task-lock.sh`; mailbox transport itself must stay workflow-agnostic
- do not split active-task lock acquisition and delegate send into separate workflow/tool steps
- when `Per-task review: required`, planner must allocate reviewer before coder starts work; coder should receive an existing `reviewer_session_id`, not create reviewer later
- report target readiness only after the resolve/create/send/nudge path that applies has completed
- existing sessions keep their original tool command
- if the delegate send wrapper reports an existing active task, surface that result instead of retrying through another send path
- treat coder/reviewer progress as asynchronous with unbounded duration; do not assume a closeout or reply will arrive within this turn
- after sending, do independent planner work only when it does not depend on coder/reviewer progress; otherwise report current state and stop instead of waiting
- after sending, do not sleep, poll, or proactively check mail just to await coder/reviewer progress
- in the delegated task workspace, treat the active task worktree state as coder-owned until closeout; do not change branch state, modify files, or otherwise alter that workspace state there
- if `worker_workspace == planner_workspace`, planner must still avoid touching that delegated task worktree state outside the delegate/closeout workflow
- if execution evidence suggests the delegated task is framed too narrowly, coder should ask planner instead of forcing a local-only completion

## 5) User-Facing Output Contract

After sending:
- Return short confirmation with:
  - mailbox subject
  - one-line objective summary
  - `task_branch` / `integration_branch`
  - `coder_session_id` / `reviewer_session_id`
  - `coder_tool` / `reviewer_tool`
  - recipient inbox address
  - listener/send/nudge summary
- Keep raw mailbox JSON internal unless user explicitly asks
- If listener/send fails, report stderr summary and include shared diagnostics checklist from `agent-deck-workflow/SKILL.md`
