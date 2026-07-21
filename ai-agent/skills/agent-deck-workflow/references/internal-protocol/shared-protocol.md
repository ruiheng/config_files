# Shared Workflow Protocol

This document defines only the shared transport, envelope, and lifecycle contract.
Use concrete action skills for role-specific business semantics, action ownership, branch policy, and lane transitions.

## Core Transport Rule

- `waypost` carries the real workflow message
- `agent-deck` manages workflow-owned sessions
- notification nudges are best-effort acceleration only; receiver-side message pickup is the reliable continuity path
- target session status is not reliable progress evidence across agent types; treat Waypost message delivery and later receiver reports as authoritative
- use the `waypost` MCP tools as the default transport interface
- use `check-waypost-messages` for receiver-side wake handling
- Agent Deck sessions are external workflow peers, not host-internal subagents; do not apply host subagent tool restrictions to `agent_deck_create_session`, `agent_deck_require_session`, `agent-deck`, or message dispatch.

## Core Terms

- `task_id`: stable task identifier when the action skill uses task-scoped workflow context
- `*_session_id`: Agent Deck session UUID used for message addressing
- `*_session_ref`: human-friendly session reference used only before a real session id is allocated
- `*_tool_profile`: logical workflow policy selector for a session tool
- `*_tool_cmd`: concrete resolved command used to create or continue a session
- `inbox_address`: `agent-deck/<agent-deck-session-id>`
- `.agent-artifacts/planner-workspace.json`: task-closeout workspace reservation record, not identity source and not a cross-task scheduler lock

## Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:
1. explicit workflow metadata such as `task_id` or a known session id
2. inbound message body already carries workflow metadata
3. user explicitly asks for agent-deck workflow

Session binding rule:
- use Waypost MCP tools directly
- bind only when Waypost message context is actually missing

## Context Resolution Priority

Use this priority chain for each field:
`explicit input -> parsed message body / workflow context -> deterministic default -> ask one short clarification question`

Session identity rules:
- use live Agent Deck or Waypost message context for current-session identity; never use `planner-workspace.json`
- use `*_session_ref` only for planned worker titles before a real session exists
- after `agent_deck_create_session` returns, record and propagate the real `*_session_id`
- in normal workflow turns after creation, address and compare sessions by `*_session_id` only
- if a later workflow turn is missing the required `*_session_id`, treat that as workflow context loss/error rather than a normal `session_ref` recovery path
- concrete action skills may define a target as intentionally on-demand; in that case the missing `*_session_id` is normal until the action creates or reuses that target
- when `from_session_id == to_session_id`, treat it as an explicit same-session continuation already established by context, not something inferred from matching provider names
- creating or starting an Agent Deck target session is workflow session lifecycle, not use of a host subagent API

## Target Lifecycle Gate

This section overrides conflicting action-skill send sequencing.

- Confirmation is scoped to a task/lane + workdir; it requires create/require or explicit matching `session_id` + workdir
- At first dispatch, creation/takeover/recovery, uncertain identity/workdir, or explicit immediate activation: create the target or `require` the existing target; batch same-workdir requires
- Otherwise, send normal follow-ups directly to the confirmed `session_id`; this only guarantees the delivery is queued
- Treat `waypost_send` notification fields as diagnostics only

Tool resolution rules:
- keep model/provider/version defaults out of concrete action skills when a shared tool profile can own them instead
- preserve explicit full commands unchanged
- existing sessions keep their original `*_tool_cmd`; do not silently swap a running lane onto a newly resolved command
- resolve `*_tool_profile` to `*_tool_cmd` only when creating a new session
- default resolver: `node ~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js --role <role> --profile <profile> --format json`; omit `--profile` when no profile is set
- keep `*_tool_profile` as workflow policy metadata and `*_tool_cmd` as the concrete session-create input
- if session creation fails because the resolved command is unusable and the chosen profile has more candidates, rerun the resolver once with `--exclude-command <failed_tool_cmd>` and retry with the next candidate
- concrete action skills own only role-specific differences: role name, parent session, workspace, reusable-session policy, and create/require choice

## Waypost Message Transport

Preferred transport interface:
- `waypost_bind`
- `waypost_status`
- `waypost_send`
- `waypost_wait`
- `waypost_recv`
- `waypost_list`
- `waypost_read`
- `waypost_ack`
- `waypost_release`
- `waypost_defer`
- `waypost_fail`
- `agent_deck_resolve_session`
- `agent_deck_create_session`
- `agent_deck_require_session`

Transport rules:
- use `waypost_send` for normal cross-session workflow delivery
- for `waypost_send group:true`, waypost marks the sender's own group message read and queues durable personal `group_message_available` deliveries for active subscribers other than the sender
- when a group sender has a known group `person`, pass `as_person`; waypost validates active membership and marks that person's stream read without relying on address/person inference
- keep outbound message bodies in the `waypost_send` body string or pipe them through stdin when a shell helper requires `--body-file -`
- if a shell helper requires a real body file, write it under this agent's `.agent-artifacts/message/`; do not use target workdirs or global temp dirs
- for receiver-side wake handling or explicit message checks, call `waypost_recv` first to claim one already-available personal delivery
- if idle after an empty `waypost_recv`, call at most one `waypost_wait timeout=10m` per assistant turn
- on timeout/no-message, report no message and stop checking until a later nudge or user-triggered message check
- after `waypost_wait` reports available message, immediately follow with `waypost_recv`
- never pass `group/` addresses to `waypost_bind`; group streams are read with explicit `waypost_recv addresses=[...] as_person=...`
- use `waypost_read` to reread persisted deliveries after `ack` or other context loss
- use `waypost_list` to inspect persisted deliveries by inbox/state when you need a specific older delivery id
- after outbound `waypost_send` succeeds, use independent local work if available; otherwise end with the concrete action skill's user-facing confirmation/status
- a timeout means no reply yet, not a receiver failure
- after a timeout, report that no message is available; do not inspect or repair the target session
- do not poll, inspect, or reason from the target Agent Deck session's `running` / `waiting` / `idle` status to infer whether the receiver is working
- ignore best-effort target status hints reported by message tooling for sender-side progress decisions; they are diagnostic noise unless explicit troubleshooting asks for them
- `waypost_read` / `waypost_list` are for recovering this session's prior workflow input, not for diagnosing why a just-requested reply has not arrived
- use lifecycle tools for `ack` / `release` / `defer` / `fail`
- `waypost_ack` / `waypost_release` / `waypost_defer` / `waypost_fail` apply only to the currently claimed inbound delivery in this session
- `waypost_send` has no sender-side `ack`; sender-side completion is the successful `waypost_send` result
- use `waypost_bind` only for custom addresses or recovery when Waypost message context is missing
- keep the full workflow body in the MCP `body` string instead of generated Markdown handoff files
- use `agent_deck_create_session` only when the current role owns lifecycle allocation of a missing target session
- in normal workflow delivery, identify an already assigned target by `session_id`, not `session_ref`
- concrete action skills may define a narrow exception for a self-owned reusable helper session whose request body is already self-contained enough to bootstrap that helper; in that case the skill may look up a stable `session_ref` and create the helper only when it is absent
- always pass explicit `workdir` to create/require session tools
- when creating a parent-linked workflow session, pass explicit `group_path` from the parent session; root group is the empty string and is valid
- leave `listener_message` empty in normal workflow; use it only for rare bootstrap/control cases that must happen before message pickup

Worker wake rule:
- after `waypost_send`, the normal non-local nudge may be handled by Waypost message transport or sender tooling
- nudges are optional optimization; receivers should use `waypost_recv` first, then at most one bounded `waypost_wait` only when idle and no message was already available
- Waypost message transport may suppress redundant nudges when the message is claimed quickly
- do not build correctness on nudge delivery

Sender/receiver turn rule:
- communication boundary is Waypost message delivery; do not cross it by observing or repairing the receiver's execution
- sender turn ends after the required outbound `waypost_send` or local continuation succeeds
- expected replies are future inbound work; do not wait for them in the sender's same turn unless the concrete action skill explicitly requires a synchronous message check
- do not treat missing replies after a wait timeout as actionable failure evidence
- never use repeated status checks, session inspection, or target workspace inspection to explain or repair a missing reply
- do not escalate or resend because Agent Deck or Waypost message status metadata labels the target `idle`; non-Claude session status can be stale or wrong while the agent is already working
- receiver execution problems belong to the receiver's next report, lifecycle response, or user-directed troubleshooting, not sender-side correction

Async sender rule:
- after sending an asynchronous request, continue only with independent local work
- if no local work remains, return the concrete action skill's confirmation/status
- do not call `waypost_wait` / `waypost_recv` for the expected reply in the same sender turn
- do not inspect or repair the target session merely because no immediate reply is present

Inbox rule:
- derive inbox address as `agent-deck/<agent-deck-session-id>`
- no separate registration step is needed
- when a workflow turn needs multiple lifecycle steps, execute them sequentially, not in parallel

Workspace lifecycle rule:
- if you create a temporary worktree/workspace, remove it after workflow closeout

## Waypost Message Envelope

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
- `group_message_available` is an waypost generated control action; read `Group-Address` with `As-Person`, then `ack` the personal delivery only after the group handler completes
- when a role has a dedicated action skill for that workflow action, treat that skill as the runtime handler for the received message
- `closeout_delivered` is a planner-handled workflow action; use a planner-side closeout skill for it
- `execute_plan` is a planner-handled workflow action; use a planner-side execution skill for it
- `plan_report_delivered` is a supervisor-handled workflow action; use a supervisor-side report skill for it
- body is the primary task input
- file paths may appear in body, but only as supplemental references
- receiver should not go hunting for external files unless the body explicitly says they are needed
- user-facing responses should provide readable decisions, not raw message JSON

## Delivery Order Contract

Use `waypost_send` for the normal Waypost message delivery path.

Expected behavior:
1. follow Target Lifecycle Gate
2. queue the message body with `waypost_send`

After send:
- if immediate local continuation remains, do it
- if no visible local work remains, end with the concrete action skill's user-facing confirmation/status
- do not wait for a reply in the sender's same turn unless the concrete action skill explicitly requires a synchronous message check
- do not inspect or repair the target session because a wait timed out

## Receiver Contract

When a workflow session is woken:
1. run `waypost_recv` first to claim one available personal delivery; if no message is returned and no visible local work remains, run at most one `waypost_wait` with timeout `10m`, then `waypost_recv` if message becomes available
2. treat the returned `body` as the primary task input
3. parse the `Action:` header and immediately hand control to the concrete action skill for that action
4. only read supplemental files when the body explicitly requires them
5. `waypost_ack` only after the message's required workflow action has completed
6. use `waypost_release` / `waypost_defer` / `waypost_fail` instead of silently dropping leased work
7. keep message lifecycle steps serialized
8. after a delivery is completed and `waypost_ack` succeeds, return to step 1 to claim the next delivery; process personal message as `recv one → act → settle → recv next`

Complete the message's required workflow action before `ack`ing the claimed inbound delivery.
Do not `ack` outbound message that this session just sent.

Idle behavior:
- one bounded `waypost_wait` after an empty `waypost_recv` is recommended for workflow continuity when no other visible work remains; max once per assistant turn
- use `check-waypost-messages` for message pickup after a wakeup nudge, an explicit human message-check request, or idle workflow waiting
- call `waypost_recv` first; use `waypost_wait` with timeout `10m` only for idle waiting after no message is immediately available
- if the wait times out or `waypost_recv` returns no message, report no message and wait for a later nudge or user-triggered check instead of waiting again
- while a claimed personal delivery is incomplete, do not fetch another personal delivery
- after a delivery is completed and `waypost_ack` succeeds, immediately call `waypost_recv` again; do not pre-claim a batch of personal deliveries
- after `waypost_release`, `waypost_defer`, or `waypost_fail`, follow the concrete action skill's continuation policy; do not blindly re-claim a released delivery
- only start `waypost_wait` after `waypost_recv` returns no message
- a just-sent outbound message is not by itself a reason for sender-side waiting

## Natural End Gate

Do not naturally end a workflow turn just because the main task work looks finished.

Natural end is allowed only when one of these is true:
- all required workflow actions for this turn are already done, including any required `waypost_send` / `waypost_ack` / `waypost_release` / `waypost_defer` / `waypost_fail`
- this turn is an explicit same-session continuation and control has already been handed to the next local step
- this turn was only a message check, `waypost_recv` returned no message, and there is visible non-message work or a user-facing reason to stop

Before ending a workflow turn, check:
- did I finish the required send-back or handoff step for this action?
- did I finish the required message lifecycle step for the message I received?
- after a successfully acknowledged personal delivery, did I run the required next `waypost_recv` and receive no more message before ending?
- if context feels incomplete after compaction or interruption, can I recover the current workflow input from the message body or `waypost_read` before deciding to stop?

If the task work is done but the required workflow send-back step is still pending, do not end. Send the required Waypost message first.
If the required workflow send-back step has succeeded and no other visible work remains, end with the concrete action skill's user-facing confirmation/status unless the current task explicitly requires a synchronous message check.
If the task is blocked and cannot continue, do not end silently. Use the appropriate lifecycle/reporting step first.

## Error Handling And Diagnostics

If workflow send or worker start fails, report concise stderr summary and run these checks:
1. is sender or target session reachable via `agent_deck_resolve_session`?
2. is the command running in the expected workflow session context?
3. did `waypost_send` / `waypost_recv` / lifecycle tools return success?

If sandbox-external execution triggers an approval prompt, explain it as a host-shell permission requirement.
If a target appears idle, do not resend message content or poll harder; rely on receiver-side message pickup, and retry a nudge only as explicit troubleshooting.

If closeout or cleanup helpers fail, include:
1. blocked reason
2. any generated artifact path
3. exact manual action to unblock

## Execution Environment

Use the `waypost` MCP tools as the default workflow transport surface.
When shell fallback is unavoidable, run `agent-deck` and `waypost` commands in host shell.
When workflow commands create sessions via `--cmd`, use full commands instead of bare provider names when the concrete action skill defines one.
