---
name: delegate-task
description: Create one bounded persistent Agent Deck worker, directly or through Waypost. Use when history must survive restarts, explicit tool or workspace control, later coordination, or user-visible and steerable work justifies its cost; use a native harness subagent for short disposable parallel work.
---

# Delegate Task

Use `agent-deck-workflow` for Waypost transport, lifecycle, and tool resolution.

Create a controlled session for one bounded outcome. Do not infer a code-delivery lifecycle, branches, commits, review, or closeout.

## Code Gate

Classify before selecting a transport or dispatching.

- A task is code-changing when it changes repository code, runtime/build configuration, schema, or a programmatic contract.
- Never send a code-changing task as generic `execute_delegated_task`. Before creating a generic worker, transfer a workflow-owned code task to `delegate-code-task`.
- Allow a direct Deck code session only when the user explicitly asks for it and takes delivery ownership. Record `user-owned direct`; do not infer it from user visibility alone.
- A user-owned direct code session has no automatic branch, commit, review, merge, or closeout contract. If that ownership is not explicit, use the code lane or ask.

## Choose Execution Surface

Use the lightest surface that preserves the task's lifecycle:

- Work locally for an immediate task this session can complete.
- Use a native harness subagent, when available, for short independent parallel work. It is disposable: the harness owns bounded execution and its result; the caller owns any code delivery. Do not create or address an Agent Deck session for it.
- Use Agent Deck for a named persistent worker when history must survive restarts, explicit tool or workspace control, later Waypost coordination, or user-visible work the user may inspect, steer, or resume matters.
- Difficulty or parallelism alone is not an Agent Deck reason. State one concrete lifecycle or user-interaction reason before creating a session.

## Selection-Only Use

When another action owns dispatch, use the selection rules above and stop before `Context` or `Dispatch`.

- Record the selected surface and, for Agent Deck, its concrete `session_reason` for the owning action.
- If the owning action has a stricter direct-execution gate, use it only for that fast path. It may retain a planner-owned nonpersistent fallback without creating a worker.
- Do not resolve sessions, compose a task contract, create a worker, or send `execute_delegated_task`.
- For workflow-owned code that selects an Agent Deck worker, hand off directly to `delegate-code-task`; generic Waypost dispatch is prohibited.
- A direct user-owned code session is a separate surface. Record that ownership; do not turn it into a generic Waypost task.

## Scope and Brief

Delegate one outcome, not a solution recipe.

- Let the worker investigate, decompose, choose local implementation, and validate within scope.
- Give only decision-relevant context: parent goal when it changes choices, hard boundaries, established evidence, non-obvious fixed decisions with source, and testable completion criteria.
- List required reading and useful references only. Omit empty sections and detail that does not change the outcome, boundary, risk, or done condition.
- Ask before splitting only when it changes scope, priority, or tradeoffs.

## Select Transport

- **Direct session:** no addressable requester session, or the user wants to work with the session directly. Start a fresh worker with its task contract as `startup_instruction`. The user observes and steers it in Agent Deck; no automatic Waypost return is expected. Code is allowed only for explicit user-owned direct delivery.
- **Waypost worker:** an addressable requester session exists and later coordination or a returned result is needed. Send `execute_delegated_task`; the worker returns `delegated_task_result`. This is non-code only.

Do not invent a requester address. For a direct continuation, surface the existing session and let the user steer it there rather than injecting a second task from this session.

## Context

Use shared context priority; resolve only fields for the selected transport.

- `task_id`: explicit -> context -> `YYYYMMDD-HHMM-<slug>`
- `task_kind`: explicit -> task/context -> `generic` (`generic | code-changing`); ask if unclear
- Direct code only: `user_owned_code_delivery`: explicit user decision -> `true`; otherwise absent
- `worker_workspace`: explicit -> workflow/current workspace -> ask
  - do not invent a separate workspace
- `workspace_lifecycle`: explicit -> `shared; cleanup=none`
  - a temporary worktree is Waypost-only; require explicit user confirmation, `temporary; cleanup=requester`, and `cleanup_workspace`; requester owns closeout
- Waypost temporary only: `cleanup_workspace`: explicit -> requester workspace that owns the worktree -> ask
- `session_reason`: explicit -> infer one concrete reason -> ask
- `worker_session_ref`: explicit -> context -> `worker-<task_id>`
- `worker_session_id`: explicit real id -> workflow context -> omit
- Waypost only: `requester_session_id`: explicit -> live Agent Deck/Waypost context -> ask; `requester_role`: explicit -> workflow role -> `requester`
- `special_requirements`: explicit -> delegated context; preserve verbatim; omit when absent

Resolve a command only when creating a worker: explicit full command -> intended current-tool continuity -> shared `worker` role. Preserve an existing session's recorded command.

## Task Contract

Use this for a direct `startup_instruction`; prepend the Waypost envelope below for a Waypost worker. For a temporary worktree, include its cleanup owner and workspace.

```markdown
## Objective
[One sentence]

## Session Contract
- Why Agent Deck: <session_reason>
- Task kind: <generic | code-changing>
- Code delivery: <N/A | user-owned direct>
- Worker workspace: <worker_workspace>
- Workspace lifecycle: <shared; cleanup=none | temporary; cleanup=requester>
- Cleanup owner: <requester; temporary only>
- Cleanup workspace: <cleanup_workspace; temporary only>
- The user may inspect or steer this session; make material choices and blockers legible.

## Context
- Parent goal: [only if it affects local choices]
- Must preserve: [upstream invariant]
- Established facts: [facts the worker can rely on]
- Read first: [required repository paths]
- Optional references: [useful supporting paths]

## Boundaries
- [fixed decision or hard constraint]
- Watch for: [material risk]

## Done When
- [testable outcome]
- Report: [result, evidence, and open items]

## Special Requirements
[verbatim; only when present]
```

Waypost envelope:

```markdown
Task: <task_id>
Action: execute_delegated_task
From: <requester_role> <requester_session_id>
To: worker {{TO_SESSION_ID}}
Task kind: generic
Round: 1

<task contract>
```

## Dispatch

Before dispatch, apply the Code Gate:

- if `task_kind` is code-changing and transport is Waypost, stop generic dispatch and run `delegate-code-task`
- if `task_kind` is code-changing and transport is direct, require `user_owned_code_delivery = true`; otherwise ask or transfer

1. Resolve the worker by real id or ref with `agent_deck_resolve_session`.

2. For a direct session:

   - require `shared; cleanup=none`; a temporary lifecycle must use a Waypost worker
   - found: call `agent_deck_require_session` with its real id and workspace; report it for the user to continue
   - absent: resolve its tool command, then call `agent_deck_create_session` with `ensure_title`, `ensure_cmd`, `workdir`, `no_parent_link = true`, and `startup_instruction = <task contract>`

3. For a Waypost worker:

   - found: call `agent_deck_require_session` with its real id and workspace
   - absent: resolve its tool command, then call `agent_deck_create_session` with `ensure_title`, `ensure_cmd`, `workdir`, `parent_session_id = <requester_session_id>`, `group_path = <requester group; empty for root>`, and `no_parent_link = false`; leave `startup_instruction` empty
   - fill `{{TO_SESSION_ID}}`, then call `waypost_send` from `agent-deck/<requester_session_id>` to `agent-deck/<worker_session_id>`, subject `delegate: <task_id> -> worker`
   - follow the shared Async sender rule

Keep the session available for user inspection, intervention, and later follow-up. Until completion or explicit transfer, do not alter a worker-owned shared workspace; temporary cleanup is best-effort after terminal delivery.

## Worker Receive

On `Action: execute_delegated_task`:

- treat the body as the task contract and own local execution within it
- this action is generic/non-code. If it requires code changes, return it for `delegate-code-task`; do not edit the repository under this contract
- follow user steering within scope; report a material scope conflict to the requester
- preserve the recorded workspace lifecycle in the terminal result
- for a temporary workspace, also preserve its cleanup owner and workspace
- when complete or blocked, send this result through Waypost:

```markdown
Task: <task_id>
Action: delegated_task_result
From: worker <worker_session_id>
To: <requester_role> <requester_session_id>
Worker workspace: <worker_workspace>
Workspace lifecycle: <workspace_lifecycle>
Cleanup owner: <requester; temporary only>
Cleanup workspace: <cleanup_workspace; temporary only>
Round: final

## Outcome
[completed | blocked summary]

## Evidence
- [result, checks, or artifact pointers]

## Open Items
- [item or `None`]
```

- Call `waypost_send` from `agent-deck/<worker_session_id>` to `agent-deck/<requester_session_id>`, subject `delegated task result: <task_id>`; ack the claimed input only after it succeeds. On failure, do not ack; settle it under the shared Receiver Contract.

For direct user-owned code sessions only:

- user owns branch, commit, review, merge, and closeout decisions
- on a user review request, run `review-request` with `review_lane = standalone`; return it here without closeout
- make code progress and blockers legible, but do not claim workflow delivery or invent a Waypost result

## Requester Receive

On `delegated_task_result`, treat it as the worker's terminal update and continue requester-owned work. Do not infer a code, review, commit, or closeout workflow.

- For `temporary; cleanup=requester`, record and ACK the terminal result, then try to remove or rehome sessions using `Worker workspace`; remove the listed non-primary worktree only when none remains. Report `cleanup=complete` on success; on failure retain it and report `cleanup=pending`. Do not delay or reopen delivery.

## User-Facing Result

Return only:

- delegated objective and Agent Deck reason
- worker session id, title, and workspace
- temporary-workspace cleanup status, when applicable
- any blocker or send failure

Keep tool commands, addresses, raw JSON, and routine wakeup details internal.
