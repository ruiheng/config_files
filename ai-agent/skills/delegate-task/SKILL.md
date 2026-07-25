---
name: delegate-task
description: Delegate non-trivial implementation work to an Agent Deck coder session through Waypost. Use when meaningful code changes should be assigned to another agent rather than completed in the current session.
---

# Delegate Task

Use `agent-deck-workflow` for shared transport, lifecycle, and tool resolution.

Create one concise `execute_delegate_task` message. The planner owns framing and dispatch; the coder owns delegated implementation.

## Delegation Gate

- Do not delegate pure docs, wording, summarization, inspection, or other non-code work.
- Delegate non-trivial implementation work by default.
- For a small, local, obvious code change, use `Direct Planner Implementation` when called from `execute-plan`; otherwise handle it locally only if this session owns implementation, or return it to the requester.
- Dispatch one task at a time. Ask the requester before splitting one requested outcome into multiple delegated tasks.

## Brief Quality

Delegate the outcome, not a solution recipe.

- Give the coder the parent goal, why this task exists, hard boundaries, known evidence, fixed decisions with provenance, and testable acceptance criteria.
- Let the coder investigate, decompose, choose the implementation, and validate it.
- Keep reviewer context neutral; do not seed expected findings or verdicts.
- Optimize for the smallest conflict surface that still completes the task; exclude unrelated refactors, renames, moves, and cleanup.
- Put relevant repository paths under `Starting Context`; use `None` when no document is required. Do not pin a commit unless an exact historical snapshot is explicitly required.
- Treat an unusually long brief as a framing smell. Remove detail that does not change the outcome, boundary, risk, or acceptance criteria.

## Workflow Context

Use the shared context priority. Resolve before dispatch:

- `task_id`: explicit -> context -> generate `YYYYMMDD-HHMM-<slug>`
- `planner_session_id`: explicit -> context -> bound Waypost sender -> ask
- `planner_workspace`: explicit -> workflow context -> current workspace -> ask
- `worker_workspace`: explicit -> workflow context -> `planner_workspace`
  - do not invent a separate workspace
  - from `execute-plan`, keep `worker_workspace = planner_workspace`
  - otherwise, a new temporary worktree requires explicit user confirmation; record cleanup ownership
- branch plan:
  - `integration_branch`: the existing non-task landing branch; never `task/*`
  - `start_branch`: explicit/context; ask when the starting line is unclear
  - `task_branch`: reuse `start_branch` when it is already the intended topic branch; otherwise `task/<task_id>` from `integration_branch`
  - normal merge flow requires `task_branch != integration_branch`; never guess through ambiguity
- session refs: `coder-<task_id>`, `reviewer-<task_id>`
- review policy: `per_task_review = required`, `final_review = skip` unless explicitly changed
- workflow policy: unattended with automatic acceptance when no must-fix finding; use a human gate only when explicitly requested
- `special_requirements`: explicit -> delegated context; preserve verbatim; omit when absent

Resolve tool commands only for sessions being created:

- coder: explicit full command -> intended current-tool continuity -> shared role `coder`
- reviewer, when per-task review is required: explicit full command -> shared role `reviewer`
- preserve existing session tool metadata
- do not create the reviewer during delegate dispatch; pass its ref/tool metadata for `review-request`

## Message Body

Use this structure. Keep concise; write `None` rather than inventing empty context.

```markdown
Task: <task_id>
Action: execute_delegate_task
From: planner <planner_session_id>
To: coder {{TO_SESSION_ID}}
Planner: <planner_session_id>
Planner workspace: <planner_workspace>
Round: 1

## Summary
[One-line objective]

## Big Picture
- Parent goal: [larger outcome]
- Why this task exists: [reason for delegation]
- Must not break: [upstream invariant or `None`]

## Objective
[One sentence]

## Known Evidence
- [established facts or `None`]

## Branch Plan
- Start branch: <start_branch>
- Integration branch: <integration_branch>
- Task branch: <task_branch>
- Rationale: [reuse or dedicated branch reason]

## Constraints & Risks
- [fixed constraint with provenance, material risk, or `None`]

## Starting Context
- Read before starting: [required repository paths or `None`]
- Reference as needed: [supporting paths or `None`]
- Know it exists: [discovery pointers or `None`]

## Execution Guardrails
- Own investigation, local decomposition, implementation choices, and validation within this scope
- Make the smallest complete change; keep unrelated work out
- Ask planner before changing scope, parent intent, or branch plan; resolve local implementation uncertainty independently

## Acceptance Criteria
- [testable outcome]

## Review & Handoff
- Per-task review: [required | skip]
- Final integration review: [planner-managed | required | skip]
- If per-task review is required, run `review-request` after the delivery commit and follow its async return rule
- Coder git writes and the delivery commit are pre-authorized; keep the recorded branch plan unless planner updates it

## Agent Deck Context
- Workspaces: planner=<planner_workspace> worker=<worker_workspace>
- Workspace lifecycle: [shared/existing | temp path=<path> cleanup=<owner>]
- Coder tool: profile=<profile or explicit> cmd=<coder_tool_cmd>
- Reviewer: ref=<reviewer_session_ref or N/A> id=<reviewer_session_id or N/A>
- Reviewer tool: profile=<profile or N/A> cmd=<reviewer_tool_cmd or N/A>

## Workflow Policy
<resolved workflow policy>

## Special Requirements
[only when present]
```

## Dispatch

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

   Use the returned real id. If review is required, resolve reviewer tool metadata but do not create the reviewer.

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
     --subject "delegate: <task_id> -> coder" \
     --body-file -
   ```

   Prefer stdin. If a body file is necessary, place it under the caller's `.agent-artifacts/message/`.

The wrapper owns active-task lock acquisition, send rollback, delivery, and wakeup. Do not split or duplicate those operations. If it reports an existing active task, surface that state instead of retrying another send path.

After dispatch:

- follow the shared Async sender rule
- treat the worker worktree as coder-owned until closeout, even when planner and worker paths are equal
- keep any reviewer planner-scoped and in the same worker workspace
- remove planner-created temporary worktrees after closeout

## User-Facing Result

Return only:

- delegated objective
- task and integration branches
- coder session id
- temporary workspace and cleanup owner, when applicable
- any blocker or send failure

Keep tool commands, addresses, raw JSON, and routine wakeup details internal. Use shared diagnostics internally; report only the concise failure cause.
