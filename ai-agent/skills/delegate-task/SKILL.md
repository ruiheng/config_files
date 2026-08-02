---
name: delegate-task
description: Delegate a bounded outcome to an appropriate worker surface, optionally directing the worker to run a named skill.
---

# Delegate Task

Use `agent-deck-workflow` for Waypost transport, lifecycle, and tool resolution.

Delegate one bounded outcome; do not run it locally or infer a code-delivery lifecycle.

## Code Gate

Classify before selecting a transport or dispatching.

- For named execution, classify from the skill contract; its side effects override task labels.
- `code-changing`: mutates repository code/config/schema/contracts or Git delivery state. Declared non-code artifacts remain generic. Unknown -> ask.
- Waypost code -> `delegate-code-task`. Direct code requires explicit `user-owned direct` and has no automatic delivery lifecycle; otherwise use the code lane or ask.

## Choose Execution Surface

Use the lightest delegated surface that preserves the task's lifecycle:

- During Selection-Only Use, record local execution when the owning action can perform it.
- Use a native harness subagent, when available, for short independent parallel work. It is disposable: the harness owns bounded execution and its result; the caller owns any code delivery. Do not create or address an Agent Deck session for it.
- Use Agent Deck when work needs persistent history, explicit tool/workspace control, later Waypost coordination, or a user-visible session to inspect, steer, or resume.
- State one concrete lifecycle or user-interaction reason for Agent Deck; difficulty or parallelism alone is insufficient.

For a named execution skill, use Agent Deck: Waypost when the requester has an address, otherwise direct. Use a native harness subagent only when the user explicitly requests disposable work.

## Selection-Only Use

When another action owns dispatch, use the selection rules above and stop before `Context` or `Dispatch`.

- Record the selected surface and, for Agent Deck, its concrete `session_reason` for the owning action.
- If the owning action has a stricter direct-execution gate, use it only for that fast path. It may retain a planner-owned nonpersistent fallback without creating a worker.
- Do not resolve sessions, compose a task contract, create a worker, or send `execute_delegated_task`.
- Workflow-owned code -> `delegate-code-task`; record direct user-owned code as a separate surface.

## Scope and Brief

- Brief one outcome with decision-relevant context, boundaries, and completion criteria; let the worker investigate and validate.
- For a named skill, send exact input and only required known files/context. Attach requester-only source inline or by durable ref; do not search merely to enlarge context.
- Ask before splitting only when it changes scope, priority, or tradeoffs.

## Select Transport

- **Direct session:** no addressable requester session, or the user wants to work with the session directly. Start a fresh worker with its task contract as the workflow startup instruction; the shared tool-resolution contract prepends an optional profile startup message. The user observes and steers it in Agent Deck; no automatic Waypost return is expected. Code is allowed only for explicit user-owned direct delivery.
- **Waypost worker:** an addressable requester session exists and later coordination or a returned result is needed. Send `execute_delegated_task`; the worker returns `delegated_task_result`. This is non-code only.

Do not invent a requester address. For a direct continuation, surface the existing session and let the user steer it there rather than injecting a second task from this session.

## Context

Use shared context priority; resolve only fields for the selected transport.

- `task_id`: explicit -> context -> `YYYYMMDD-HHMM-<slug>`
- `execution_skill`: explicit field -> first token of `$delegate-task` input when it is an exact installed skill (`$name` or `name`) -> omit
  - inspect only that token; reject `delegate-task` as its own inner skill
  - `$delegate-task $explain-for-me 中文` -> skill `explain-for-me`, input `中文`
- `execution_input`: explicit -> remainder after the inner skill; otherwise full `$delegate-task` input -> `N/A`
- `source_material`: explicit text/ref -> required requester-chat material -> omit when self-contained; use inline content or a durable worker-readable path
- `task_kind`: skill contract + explicit task/context -> `generic`; code/delivery side effects -> `code-changing`; unclear -> ask
- `worker_tool_role`: explicit -> `explainer` when `execution_skill = explain-for-me` -> `worker`
- Direct code only: `user_owned_code_delivery`: explicit user decision -> `true`; otherwise absent
- `worker_workspace`: explicit -> workflow/current workspace -> ask
  - do not invent a separate workspace
- `workspace_lifecycle`: require `shared; cleanup=none` for `explain-for-me`; otherwise explicit -> `shared; cleanup=none`
  - a temporary worktree is Waypost-only; require explicit user confirmation, `temporary; cleanup=requester`, and `cleanup_workspace`; requester owns closeout
- Waypost temporary only: `cleanup_workspace`: explicit -> requester workspace that owns the worktree -> ask
- `session_reason`: explicit -> infer one concrete reason -> ask
- `worker_session_ref`: explicit -> context -> `worker-<task_id>`
- `worker_session_id`: explicit real id -> workflow context -> omit
- Waypost only: `requester_session_id`: explicit -> live Agent Deck/Waypost context -> ask; `requester_role`: explicit -> workflow role -> `requester`
- `special_requirements`: explicit -> delegated context; preserve verbatim; omit when absent

Resolve a command only when creating a worker: explicit full command -> intended current-tool continuity -> shared `<worker_tool_role>` role. Preserve an existing session's recorded command.

## Task Contract

Use this as the direct workflow startup instruction; prepend the Waypost envelope below for a Waypost worker. The shared tool-resolution contract prepends an optional profile startup message. For a temporary worktree, include its cleanup owner and workspace.

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

## Execution
- Skill: <$skill-name | N/A>
- Input: [verbatim skill input or `N/A`]
- Source: [inline material or durable worker-readable ref; omit when Input is self-contained]
- If Task kind is `generic` and Skill would change repository or code-delivery state, report a lane mismatch; do not run it.
- If Skill is not `N/A`, load and run it with Input plus this task contract. Missing skill -> report blocker.

## Context
- Parent goal: [only if it affects local choices]
- Must preserve: [upstream invariant]
- Established facts: [facts the worker can rely on]
- Known files: [already-known relevant paths; mark required reading; omit when absent]
- Other known context: [refs, excerpts, and facts; omit when absent]

## Boundaries
- [fixed decision or hard constraint]
- Watch for: [material risk]

## Done When
- [testable outcome]
- Report: [result, evidence, and open items; artifact locations as full paths or URIs]

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

- Apply the Code Gate.
- require `source_material` when execution depends on requester-only material
- if `execution_skill = explain-for-me`, require `shared; cleanup=none`; do not dispatch a temporary worker

1. Resolve the worker by real id or ref with `agent_deck_resolve_session`.

2. For a direct session:

   - require `shared; cleanup=none`; a temporary lifecycle must use a Waypost worker
   - found: call `agent_deck_require_session` with its real id and workspace; report it for the user to continue
   - absent: resolve its tool command by the shared tool-resolution contract, then call `agent_deck_create_session` with `ensure_title`, `ensure_cmd`, `workdir`, `no_parent_link = true`, and `startup_instruction = <optional tool startup message followed by task contract>`

3. For a Waypost worker:

   - found: call `agent_deck_require_session` with its real id and workspace
   - absent: resolve its tool command by the shared tool-resolution contract, then call `agent_deck_create_session` with `ensure_title`, `ensure_cmd`, `workdir`, `parent_session_id = <requester_session_id>`, `group_path = <requester group; empty for root>`, `no_parent_link = false`, and the optional resolved `startup_instruction`; do not add workflow task text there
   - fill `{{TO_SESSION_ID}}`, then call `waypost_send` from `agent-deck/<requester_session_id>` to `agent-deck/<worker_session_id>`, subject `delegate: <task_id> -> worker`
   - follow the shared Async sender rule

Until completion or explicit transfer, do not alter a worker-owned shared workspace; temporary cleanup is best-effort after terminal delivery.

## Worker Receive

On `Action: execute_delegated_task`:

- treat the body as the task contract and own local execution within it
- this action excludes repository/code-delivery mutation. If required, return it for `delegate-code-task`; do not edit code or Git delivery state under this contract
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

For initial dispatch, return only:

- delegated objective and Agent Deck reason
- worker session id, title, and workspace
- temporary-workspace cleanup status, when applicable
- any blocker or send failure

For a terminal worker result, return only its concise outcome, full artifact path/URI when present, and material open item or blocker.

Keep tool commands, addresses, raw JSON, and routine wakeup details internal.
