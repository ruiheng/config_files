# Agent Mailbox MCP

This local MCP server wraps mailbox transport as structured tool calls and keeps agent-deck-specific session operations separate.

Goals:
- avoid long shell command construction
- reduce transcript noise from large mailbox body sends
- avoid repeated shell-approval churn caused by small command-shape differences
- keep mailbox transport decoupled from workflow-specific orchestration

Command:

```bash
agent-mailbox mcp
```

The server is stdio-based and exposes three groups of tools.

## Mailbox Tools

- `mailbox_bind`
- `mailbox_status`
- `mailbox_send`
- `mailbox_forward`
- `mailbox_wait`
- `mailbox_recv`
- `mailbox_list`
- `mailbox_read`
- `mailbox_ack`
- `mailbox_release`
- `mailbox_defer`
- `mailbox_fail`

`mailbox_bind`
- stores one or more mailbox addresses in MCP server state
- optionally stores `default_sender` and `default_workdir`
- use this for custom addresses or recovery when mailbox context is missing

For an agent-deck-managed session `<id>`, bind:
- `agent-deck/<id>`
- when the host Codex session id is detectable, auto-bind may also add `codex/<codex-session-id>`

`mailbox_send`
- sends one mailbox message
- auto-notifies a non-local `agent-deck/...` target
- `codex/...` addresses can be used for mailbox delivery, but do not currently imply an agent-deck wakeup target
- uses `from_address` explicitly, or falls back to the bound `default_sender`
- follows the compact default `agent-mailbox send` receipt and returns the resulting `delivery_id`
- wakeup text is fixed
- set `disable_notify_message = true` to disable notify for that send
- does not enforce workflow-specific locks or inspect workflow body content; workflow helpers must do that before send when required

`mailbox_wait`
- checks whether mail is available for the bound addresses or explicit override addresses
- optional `timeout` uses duration-string format accepted by `agent-mailbox wait --timeout`, for example `30s`, `5m`, `120ms`, or `1m30s`
- does not claim the delivery
- optional diagnostic/manual observation tool; not recommended for normal workflow

`mailbox_recv`
- if `addresses` is omitted, receives mail for all bound addresses
- if `addresses` is provided, uses only that explicit override address list for this call
- claims one delivery immediately or returns no message
- calls `agent-mailbox recv --max 1` explicitly so the MCP contract stays single-message even if CLI defaults change
- after the delivery is acknowledged, use `mailbox_read` rather than asking the sender to resend when context is lost

`mailbox_list`
- lists persisted deliveries for one inbox
- use `state: "acked"` to find deliveries that were already received and acknowledged
- use this when you need a specific older `delivery_id` before calling `mailbox_read`

`mailbox_read`
- reads persisted messages or deliveries by id, or rereads the latest deliveries for one or more inboxes
- use `latest: true` with `state: "acked"` to recover the most recent acknowledged mail after context loss
- if `addresses` is omitted in `latest` mode, the tool reads from the currently bound inbox addresses

`mailbox_forward`
- forwards exactly one stored personal message selected by `message_id` or `delivery_id`
- reuses the original body, `content_type`, and `schema_version`
- prefixes the original subject with `Fwd: ` unless an explicit override subject is provided

`mailbox_ack` / `mailbox_release` / `mailbox_defer` / `mailbox_fail`
- wrap the corresponding `agent-mailbox` lifecycle commands
- acknowledged deliveries remain readable later through `mailbox_read`

## Agent-Deck Tools

- `agent_deck_resolve_session`
- `agent_deck_create_session`
- `agent_deck_require_session`

`agent_deck_resolve_session`
- resolves an agent-deck session ref or id
- returns canonical session id, status, and the agent-deck mailbox address

`agent_deck_create_session`
- creates a new agent-deck session
- if an exact same-title target already exists in the same workdir, returns that target so interrupted create-before-send retries can continue safely
- when returning an exact same-title target, still reconciles the requested group placement before handing it back
- requires explicit `workdir` for every call
- can place the new session into an explicit `group_path`
- can derive and ensure a child group under `group_parent_session_id` by using `child_group_name`
- can create sessions with `no_parent_link = true` so workflow grouping does not depend on one-level parent-child session depth
- when creating under a non-root `parent_session_id`, can derive a nested child group from that parent's existing group automatically
- a newly created target should follow the same wake path as any other target and run `check-agent-mail` when notified
- `startup_instruction` is an optional startup-only instruction passed to `agent-deck launch --message`; do not use it for task payloads or normal wakeups

`agent_deck_require_session`
- requires an existing agent-deck session
- resolves `session_id` or `session_ref`
- verifies the existing session already matches the requested `workdir`
- starts an inactive target when needed
- `startup_instruction` is an optional startup-only instruction passed to `agent-deck session start -m`; do not use it for task payloads or normal wakeups
- does not create sessions or accept create-only lifecycle parameters

Typical workflow patterns:
1. lifecycle allocation: `agent_deck_create_session`
2. send-time guard for an existing target: `agent_deck_require_session`
3. delivery: `mailbox_send`

Retry note:
- if a turn dies after `agent_deck_create_session` succeeds but before `mailbox_send`, retry the same create call with the same title and workdir; the MCP server will return the exact existing target instead of failing

## Config Snippets

Codex:

```toml
[mcp_servers.agent_mailbox]
command = "agent-mailbox"
args = ["mcp"]
```

Gemini:

```bash
gemini mcp add -s user agent_mailbox agent-mailbox mcp
```

Claude Code:

```bash
claude mcp add -s user agent_mailbox -- agent-mailbox mcp
```

## Notes

- This server does not rewrite mailbox body content. `startup_instruction` is only passed to session launch/start as direct startup input.
- Worker-target wake hints may also tell the agent to use `mailbox_read` for the latest `acked` delivery after `ack`.
- Mailbox transport does not depend on `agent-deck`.
- `agent_deck_*` tools are the only place where session creation / start / ref resolution lives.
- In normal Codex/agent-deck use, call mailbox tools directly; bind only when you need custom addresses or recovery from missing mailbox context.
