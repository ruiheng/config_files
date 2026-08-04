---
name: delegate-code-task
description: Delegate Waypost code work to an Agent Deck coder.
---

# Delegate Code Task

Use `agent-deck-workflow` for shared transport, lifecycle, and tool resolution.
Use `delegate-task` in Selection-Only Use first when another action owns surface selection. A direct Code Gate transfer may enter here without generic dispatch. This skill owns the workflow code lane; do not dispatch a generic worker first.

## Code Scope

- Use this only for the workflow-owned Waypost code lane. Local, harness-subagent, and explicit user-owned direct Deck work retain their own lifecycle.
- Keep code tasks serial. Decompose locally; ask only if splitting changes scope, priority, or tradeoffs.

## Brief Quality

Delegate the outcome, not a solution recipe.

- Give the coder only decision-relevant context: parent goal when it affects local choices, hard boundaries, established evidence, non-obvious fixed decisions with source, and testable acceptance criteria.
- Let the coder investigate, decompose, choose the implementation, and validate it.
- Optimize for the smallest conflict surface that still completes the task; exclude unrelated refactors, renames, moves, and cleanup.
- List only required reading and useful references. Omit empty optional sections rather than inventing context. Do not pin a commit unless an exact historical snapshot is explicitly required.
- Treat an unusually long brief as a framing smell. Remove detail that does not change the outcome, boundary, risk, or acceptance criteria.

## Workflow Context

Use the shared context priority. Resolve before dispatch:

- `task_id`: explicit -> context -> generate `YYYYMMDD-HHMM-<slug>`
- `planner_session_id`: explicit -> context -> bound Waypost sender -> ask
- `planner_workspace`: explicit -> workflow context -> current workspace -> ask
- `worker_workspace`: explicit -> workflow context -> `planner_workspace`
  - do not invent a separate workspace
  - from `execute-plan`, keep `worker_workspace = planner_workspace`
- `task_dir`: explicit -> workflow context -> `worker_workspace`
  - for `temporary; cleanup=planner`, it must resolve to the same path as `worker_workspace`; stop on mismatch
- `workspace_lifecycle`: explicit -> `shared; cleanup=none`
  - a temporary worktree needs explicit user confirmation and `temporary; cleanup=planner`
- `session_reason`: explicit -> infer one concrete persistence, control, or user-interaction reason -> ask
- branch plan:
  - `integration_branch`: the existing non-task landing branch; never `task/*`
  - `start_branch`: explicit/context; ask when the starting line is unclear
  - `task_branch`: reuse `start_branch` only when it is an explicitly recorded unfinished task branch; otherwise `task/<task_id>` from `integration_branch`
  - normal merge flow requires `task_branch != integration_branch`; never guess through ambiguity
- `coder_session_ref`: `coder-<task_id>`
- reviewer routing:
  - `reviewer_session_ref`: explicit -> workflow context -> `reviewer-<task_id>`
  - `reviewer_session_id`: explicit actual id -> workflow context -> omit
  - tool selection: explicit full command or profile -> workflow context -> omit; do not resolve a default here
- review policy: `per_task_review = required`, `final_review = skip` unless explicitly changed
- workflow policy: unattended with automatic acceptance when no must-fix finding; use a human gate only when explicitly requested
- `special_requirements`: explicit -> delegated context; preserve verbatim; omit when absent

Resolve a tool command only when creating a session:

- coder: explicit full command -> intended current-tool continuity -> shared role `coder`
- preserve existing session tool metadata
- do not create the reviewer during delegate dispatch; preserve explicit reviewer routing in the body. `review-request` resolves or reuses it on demand.

## Message Body

Use this structure. Keep required fields exact. Omit empty optional sections and lines rather than filling them with `None`.

```markdown
Task: <task_id>
Action: execute_delegate_task
From: planner <planner_session_id>
To: coder {{TO_SESSION_ID}}
Planner: <planner_session_id>
Planner workspace: <planner_workspace>
Worker workspace: <worker_workspace>
Task dir: <task_dir>
Workspace lifecycle: <shared; cleanup=none | temporary; cleanup=planner>
Round: 1

## Task
[One sentence]

## Session Contract
- Why Agent Deck: <session_reason>

## Context
- Parent goal: [only if it affects local choices]
- Must preserve: [upstream invariant]
- Established facts: [facts the coder can rely on]
- Read first: [required repository paths]
- Optional references: [useful supporting paths]

## Branch Plan
- Start branch: <start_branch>
- Integration branch: <integration_branch>
- Task branch: <task_branch>

## Boundaries
- [fixed decision or hard constraint]
- Watch for: [material risk]

## Execution Guardrails
- Work on the recorded task branch; create or attach it from the integration branch if needed. Never commit detached HEAD.
- Own investigation, local decomposition, implementation choices, and validation within this scope
- Make the smallest complete change; keep unrelated work out
- Keep the recorded branch plan
- If work would materially change the objective, a boundary, acceptance criteria, external behavior/contract, or add unrelated scope, ask the user before applying or committing it
- Keep every user scope decision for this task. Include the accumulated decisions in the next message to reviewer or coder under `## User Decisions`

## Acceptance Criteria
- [testable outcome]

## Review & Handoff
- Per-task review: [required | skip]
- Coder git writes and the delivery commit are pre-authorized
- If required: after commit and validation, run `review-request` with `review_lane = task`; preserve any User Decisions, the recorded Branch Plan, and Workspace Handoff
- If skipped: after commit and validation, send `code_delivery_complete` to planner
- On a blocker before an accepted task review: send `code_delivery_complete` to planner under either policy
- After any successful review request or terminal handoff above, end this turn. Do nothing until the next instruction.
- Reviewer routing: ref=<reviewer_session_ref>; id=<reviewer_session_id>; profile=<reviewer_tool_profile>; cmd=<reviewer_tool_cmd> [required only; omit absent values]
- Workflow policy: [only when non-default]

## Special Requirements
[verbatim; only when present]
```

## Dispatch

For `temporary; cleanup=planner`, require `task_dir` and `worker_workspace` to resolve to the same path before dispatch.

1. Prepare workspace records:

   ```bash
   ~/.config/ai-agent/skills/agent-deck-workflow/scripts/prepare-workspaces.sh \
     --worker-workspace <worker_workspace> \
     --planner-workspace <planner_workspace> \
     --integration-branch <integration_branch> \
     --planner-session-id <planner_session_id>
   ```

   Stop on workspace or integration-branch mismatch. Use `--override-workspaces` only after explicit user confirmation.

2. Resolve the coder id/ref:

   - found: `agent_deck_require_session` with its real id and `worker_workspace`
   - not found: resolve its tool command, then call `agent_deck_create_session` with:
     - `ensure_title = <coder_session_ref>`
     - `ensure_cmd = <coder_tool_cmd>`
     - `workdir = <worker_workspace>`
     - `parent_session_id = <planner_session_id>`
     - `group_path = <planner group; empty for root>`
     - `no_parent_link = false`

   Use the returned real id. Do not create the reviewer; `review-request` resolves or reuses it on demand.

3. Fill `{{TO_SESSION_ID}}`, then send through the lock-owning wrapper:

   ```bash
   ~/.config/ai-agent/skills/agent-deck-workflow/scripts/send-delegate-with-active-task-lock.sh \
     --workdir <worker_workspace> \
     --task-id <task_id> \
     --integration-branch <integration_branch> \
     --planner-session-id <planner_session_id> \
     --coder-session-id <coder_session_id> \
     --coder-session-ref <coder_session_ref> \
     --task-branch <task_branch> \
     --subject "delegate code: <task_id> -> coder" \
     --body-file -
   ```

   Prefer stdin. If a body file is necessary, place it under the caller's `.agent-artifacts/message/`.

The wrapper owns active-task lock acquisition, send rollback, delivery, and wakeup. Do not split or duplicate those operations. If it reports an existing active task, surface that state instead of retrying another send path.

After dispatch:

- follow the shared Async sender rule
- treat the worker worktree as coder-owned until closeout, even when planner and worker paths are equal
- leave the coder session usable until closeout; closeout removes it when possible and reports `cleanup=pending` on failure
- keep any reviewer planner-scoped and in the same worker workspace
- planner attempts recorded temporary-worktree cleanup after closeout and reports `cleanup=complete` or `cleanup=pending`; neither changes delivery completion

## Coder Receive

On `Action: execute_delegate_task`, treat the body as the code-task contract. Own the recorded branch, implementation, validation, and commit; keep the session legible for user steering.

The contract must include `Worker workspace`, `Task dir`, and `Workspace lifecycle`; if any is missing, report a blocker instead of inferring it.

- If a material scope change or uncertainty appears, ask the user immediately and wait before applying or committing it. A user instruction that resolves it is the decision.
- Keep all such decisions and copy the accumulated list into the next review request or terminal handoff under `## User Decisions`; omit the section when no decision exists.
- After a delivery commit, run `review-request` when per-task review is required.
- Send this terminal handoff after commit and validation when review is skipped, or on a blocker before an accepted task review:

```markdown
Task: <task_id>
Action: code_delivery_complete
From: coder <coder_session_id>
To: planner <planner_session_id>
Planner: <planner_session_id>
Planner workspace: <planner_workspace>
Worker workspace: <worker_workspace>
Task dir: <task_dir>
Workspace lifecycle: <workspace_lifecycle>
Per-task review: <required | skip>
Delivery commit: <short_commit | `None` when blocked>
Round: final

## Branch Plan
- Start branch: <start_branch>
- Integration branch: <integration_branch>
- Task branch: <task_branch>

## User Decisions
[all temporary user scope decisions for this task; only when present]

## Outcome
[completed | blocked summary]

## Checks
- [command/result or `None`]
```

- Omit `## User Decisions` when no temporary scope decision exists.
- For `Outcome: completed`, send only when review is skipped. For `Outcome: blocked`, send under either policy; include any existing delivery commit. Send from `agent-deck/<coder_session_id>` to `agent-deck/<planner_session_id>`, subject `code delivery complete: <task_id>`; ack the claimed instruction only after send succeeds. The planner reports the blocker or runs closeout; do not run `review-closeout` or claim an accepted review.

## User-Facing Result

Return only:

- delegated objective
- Agent Deck reason
- task and integration branches
- coder session id
- temporary workspace and cleanup status, when applicable
- any blocker or send failure

Keep tool commands, addresses, raw JSON, and routine wakeup details internal. Use shared diagnostics internally; report only the concise failure cause.
