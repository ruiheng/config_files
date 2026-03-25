# Agent Mailbox MCP

This local MCP server wraps mailbox transport as structured tool calls and keeps agent-deck-specific session operations separate.

Goals:
- avoid long shell command construction
- reduce transcript noise from large mailbox body sends
- avoid repeated shell-approval churn caused by small command-shape differences
- keep mailbox transport decoupled from workflow-specific orchestration

Command:

```bash
$HOME/.local/bin/agent-mailbox-mcp
```

The server is stdio-based and exposes three groups of tools.

## Mailbox Tools

- `mailbox_bind`
- `mailbox_status`
- `mailbox_deliver`
- `mailbox_send`
- `mailbox_wait`
- `mailbox_recv`
- `mailbox_ack`
- `mailbox_release`
- `mailbox_defer`
- `mailbox_fail`

`mailbox_bind`
- stores one or more mailbox addresses in MCP server state
- optionally stores `default_sender` and `default_workdir`

For an agent-deck-managed session `<id>`, bind both:
- `agent-deck/<id>`
- `codex/<id>`

`mailbox_deliver`
- sends one mailbox message
- auto-notifies a non-local target when the address scheme supports push nudge
- uses `from_address` explicitly, or falls back to the bound `default_sender`

`mailbox_send`
- sends one mailbox message
- uses `from_address` explicitly, or falls back to the bound `default_sender`

`mailbox_wait`
- checks whether mail is available for the bound addresses or explicit override addresses
- does not claim the delivery

`mailbox_recv`
- receives mail for the bound addresses or explicit override addresses
- claims one delivery immediately or returns no message

`mailbox_ack` / `mailbox_release` / `mailbox_defer` / `mailbox_fail`
- wrap the corresponding `agent-mailbox` lifecycle commands

## Agent-Deck Tools

- `agent_deck_resolve_session`
- `agent_deck_ensure_session`

`agent_deck_resolve_session`
- resolves an agent-deck session ref or id
- returns canonical session id, status, and both mailbox addresses

`agent_deck_ensure_session`
- resolves an existing session or creates it when missing
- starts an inactive target when needed
- a newly created or newly started target should run `mailbox_wait` for its first mail before running `check-agent-mail`

## Notify Tool

- `notify_send`

`notify_send`
- sends a push-style nudge to one session address
- currently supports `agent-deck/<id>` and `codex/<id>` by routing through `agent-deck session send`

Typical workflow delivery:
1. `agent_deck_ensure_session`
2. `mailbox_deliver`

## Config Snippets

Codex:

```toml
[mcp_servers.agent_mailbox]
command = "$HOME/.local/bin/agent-mailbox-mcp"
```

Gemini:

```bash
gemini mcp add -s user agent_mailbox "$HOME/.local/bin/agent-mailbox-mcp"
```

Claude Code:

```bash
claude mcp add -s user agent_mailbox -- "$HOME/.local/bin/agent-mailbox-mcp"
```

## Notes

- This server does not change workflow prompts by itself.
- Mailbox transport does not depend on `agent-deck`.
- `agent_deck_*` tools are the only place where session creation / start / ref resolution lives.
- Typical bootstrap for an agent-deck-managed session is:
  1. `agent-deck session current --json`
  2. `mailbox_bind(addresses=["agent-deck/<id>", "codex/<id>"], default_sender="agent-deck/<id>")`
