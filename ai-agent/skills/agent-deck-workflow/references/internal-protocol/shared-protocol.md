# Shared Workflow Protocol

This document defines only the shared transport, envelope, and lifecycle contract.
It should not define role-specific business semantics, action ownership, branch policy, or lane transitions.
Those belong in the concrete action skill that sends or handles that workflow message.

## Core Transport Rule

- `agent-mailbox` carries the real workflow message
- `agent-deck` is used to create new lifecycle-owned sessions, require existing target sessions before send, and nudge them to check mail
- use the `agent_mailbox` MCP tools as the default transport interface
- use `check-agent-mail` for receiver-side wake handling
- Agent Deck sessions are external workflow peers, not host-internal subagents; do not apply host subagent tool restrictions to `agent_deck_create_session`, `agent_deck_require_session`, `agent-deck`, or mailbox dispatch.

## Core Terms

- `task_id`: stable task identifier when the action skill uses task-scoped workflow context
- `*_session_id`: Agent Deck session UUID used for mailbox addressing
- `*_session_ref`: human-friendly session reference used only before a real session id is allocated
- `*_tool_profile`: logical workflow policy selector for a session tool
- `*_tool_cmd`: concrete resolved command used to create or continue a session
- `inbox_address`: `agent-deck/<agent-deck-session-id>`

## Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:
1. explicit workflow metadata such as `task_id` or a known session id
2. inbound mailbox body already carries workflow metadata
3. user explicitly asks for agent-deck workflow

Session binding rule:
- use mailbox tools directly
- bind only when mailbox context is actually missing

## Context Resolution Priority

Use this priority chain for each field:
`explicit input -> parsed mailbox body / workflow context -> deterministic default -> ask one short clarification question`

Session identity rules:
- use `*_session_ref` only for planned worker titles before a real session exists
- after `agent_deck_create_session` returns, record and propagate the real `*_session_id`
- in normal workflow turns after creation, address and compare sessions by `*_session_id` only
- if a later workflow turn is missing the required `*_session_id`, treat that as workflow context loss/error rather than a normal `session_ref` recovery path
- when `from_session_id == to_session_id`, treat it as an explicit same-session continuation already established by context, not something inferred from matching provider names
- creating or starting an Agent Deck target session is workflow session lifecycle, not use of a host subagent API

Tool resolution rules:
- keep model/provider/version defaults out of concrete action skills when a shared tool profile can own them instead
- resolve `*_tool_profile` to `*_tool_cmd` before `agent_deck_create_session`
- preserve explicit full commands unchanged
- existing sessions keep their original `*_tool_cmd`; do not silently swap a running lane onto a newly resolved command

## Mailbox Transport

Preferred transport interface:
- `mailbox_bind`
- `mailbox_status`
- `mailbox_send`
- `mailbox_recv`
- `mailbox_list`
- `mailbox_read`
- `mailbox_ack`
- `mailbox_release`
- `mailbox_defer`
- `mailbox_fail`
- `agent_deck_resolve_session`
- `agent_deck_create_session`
- `agent_deck_require_session`

Transport rules:
- use `mailbox_send` for normal cross-session workflow delivery
- use `mailbox_recv` to claim mail
- `mailbox_wait` is not recommended for normal workflow; keep it for manual diagnostics or observation
- use `mailbox_read` to reread persisted deliveries after `ack` or other context loss
- use `mailbox_list` to inspect persisted deliveries by inbox/state when you need a specific older delivery id
- use lifecycle tools for `ack` / `release` / `defer` / `fail`
- `mailbox_ack` / `mailbox_release` / `mailbox_defer` / `mailbox_fail` apply only to the currently claimed inbound delivery in this session
- `mailbox_send` has no sender-side `ack`; sender-side completion is the successful `mailbox_send` result
- use `mailbox_bind` only for custom addresses or recovery when mailbox context is missing
- keep the full workflow body in the MCP `body` string instead of generated Markdown handoff files
- use `agent_deck_create_session` only when the current role owns lifecycle allocation of a missing target session
- use `agent_deck_require_session` before sending to an already assigned target session
- in normal workflow delivery, identify an already assigned target by `session_id`, not `session_ref`
- concrete action skills may define a narrow exception for a self-owned reusable helper session whose request body is already self-contained enough to bootstrap that helper; in that case the skill may look up a stable `session_ref` and create the helper only when it is absent
- always pass explicit `workdir`
- leave `listener_message` empty in normal workflow; use it only for rare bootstrap/control cases that must happen before mailbox pickup

Worker wake rule:
- after `mailbox_send`, the normal non-local nudge should already be handled
- a newly created or newly started target should use the same wake path as any other target: receive the sender nudge, then run `check-agent-mail`
- long-running agent-mail polling processes are not recommended for delivery

Inbox rule:
- derive inbox address as `agent-deck/<agent-deck-session-id>`
- no separate registration step is needed
- when a workflow turn needs multiple lifecycle steps, execute them sequentially, not in parallel

## Mailbox Envelope

Every workflow message has two parts:
- `subject`: one-line summary for quick triage
- `body`: full Markdown task content and the main source of truth

Recommended body header:

```markdown
Task: <task_id_or_N/A>
Action: <action_name>
From: <role_or_sender_label> <from_session_id>
To: <role_or_receiver_label> <to_session_id>
Planner: <planner_session_id_or_N/A>
Round: <round_or_final>
```

Envelope rules:
- `Action:` must be a stable machine-readable token chosen by the concrete action skill
- when a role has a dedicated action skill for that workflow action, treat that skill as the runtime handler for the received message
- `closeout_delivered` is a planner-handled workflow action; use a planner-side closeout skill for it
- `execute_plan` is a planner-handled workflow action; use a planner-side execution skill for it
- `plan_report_delivered` is a supervisor-handled workflow action; use a supervisor-side report skill for it
- body is the primary task input
- file paths may appear in body, but only as supplemental references
- receiver should not go hunting for external files unless the body explicitly says they are needed
- user-facing responses should provide readable decisions, not raw mailbox JSON

## Delivery Order Contract

Use `mailbox_send` for the normal mailbox delivery path.

Expected behavior:
1. if the current role is allocating a new workflow-owned target session, call `agent_deck_create_session`
   - use create only in the role that owns target lifecycle allocation
   - always pass `workdir`
   - normal workflow: do not pass `listener_message`
2. otherwise call `agent_deck_require_session` for the existing target session before send
   - always pass `workdir`
   - normal workflow: do not pass `listener_message`
3. queue the mailbox body with `mailbox_send`

## Receiver Contract

When a workflow session is woken:
1. run `mailbox_recv`
2. treat the returned `body` as the primary task input
3. parse the `Action:` header and immediately hand control to the concrete action skill for that action
4. only read supplemental files when the body explicitly requires them
5. `mailbox_ack` only after the message's required workflow action has completed
6. use `mailbox_release` / `mailbox_defer` / `mailbox_fail` instead of silently dropping leased work
7. keep mailbox lifecycle steps serialized

Complete the message's required workflow action before `ack`ing the claimed inbound delivery.
Do not `ack` outbound mail that this session just sent.

Idle behavior:
- long-running wait loops are not recommended for workflow continuity
- `mailbox_wait` is not the recommended receiver entrypoint
- use `check-agent-mail` when a wakeup nudge arrives or when a human explicitly asks for a mailbox check

## Natural End Gate

Do not naturally end a workflow turn just because the main task work looks finished.

Natural end is allowed only when one of these is true:
- all required workflow actions for this turn are already done, including any required `mailbox_send` / `mailbox_ack` / `mailbox_release` / `mailbox_defer` / `mailbox_fail`
- this turn is an explicit same-session continuation and control has already been handed to the next local step
- this turn was only a mailbox check and `mailbox_recv` returned no message

Before ending a workflow turn, check:
- did I finish the required send-back or handoff step for this action?
- did I finish the required mailbox lifecycle step for the message I received?
- if context feels incomplete after compaction or interruption, can I recover the current workflow input from the mailbox body or `mailbox_read` before deciding to stop?

If the task work is done but the required workflow send-back step is still pending, do not end. Send the required mailbox message first.
If the task is blocked and cannot continue, do not end silently. Use the appropriate lifecycle/reporting step first.

## Error Handling And Diagnostics

If workflow send or worker start fails, report concise stderr summary and run these checks:
1. is sender or target session reachable via `agent_deck_resolve_session`?
2. is the command running in the expected workflow session context?
3. did `mailbox_send` / `mailbox_recv` / lifecycle tools return success?

If sandbox-external execution triggers an approval prompt, explain it as a host-shell permission requirement.
If a target missed mailbox work, retry the nudge path instead of resending mailbox content.

If closeout or cleanup helpers fail, include:
1. blocked reason
2. any generated artifact path
3. exact manual action to unblock

## Execution Environment

Use the `agent_mailbox` MCP tools as the default workflow transport surface.
When shell fallback is unavoidable, run `agent-deck` and `agent-mailbox` commands in host shell.
When workflow commands create sessions via `--cmd`, use full commands instead of bare provider names when the concrete action skill defines one.
