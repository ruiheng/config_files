# Workflow Mailbox MCP

This local MCP server wraps the `agent-deck-workflow` mailbox transport as structured tool calls.

Goals:
- avoid long shell command construction
- reduce transcript noise from large mailbox body sends
- avoid repeated shell-approval churn caused by small command-shape differences

Command:

```bash
~/.local/bin/adwf-mailbox-mcp
```

The server is stdio-based and exposes these tools:
- `workflow_bind_session`
- `workflow_session_status`
- `workflow_send`
- `workflow_wait`
- `workflow_recv`
- `workflow_ack`
- `workflow_release`
- `workflow_defer`
- `workflow_fail`

## Tool Summary

`workflow_bind_session`
- store one caller-provided `agent-deck` session id inside MCP server state
- later `workflow_wait` / `workflow_recv` can omit session id arguments

`workflow_session_status`
- show the currently bound session id

`workflow_send`
- performs the normal workflow delivery sequence inside MCP
- accepts a structured body string instead of shell command assembly
- handles target resolution, optional target creation, mailbox send, and active-session nudge
- uses the bound session id, or explicit `current_session_id`, to decide whether the target is local or needs wakeup

`workflow_wait`
- checks whether mail is available for the bound session, an explicit session, or explicit addresses
- does not claim the delivery

`workflow_recv`
- receives mail for the bound session, an explicit session, or explicit addresses
- with `wait=true`, first waits for mail to appear, then claims one delivery

`workflow_ack` / `workflow_release` / `workflow_defer` / `workflow_fail`
- wrap the corresponding `agent-mailbox` lifecycle commands

## Config Snippets

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.workflow_mailbox]
command = "~/.local/bin/adwf-mailbox-mcp"
```

Gemini (`~/.gemini/settings.json`):

```json
{
  "mcpServers": {
    "workflow_mailbox": {
      "command": "~/.local/bin/adwf-mailbox-mcp"
    }
  }
}
```

Claude Code:

```bash
claude mcp add -s user workflow_mailbox -- ~/.local/bin/adwf-mailbox-mcp
```

## Notes

- This server does not change any workflow prompts by itself.
- `workflow_send` no longer depends on the external shell helper.
- `workflow_recv` and lifecycle tools call `agent-mailbox` directly.
- Intended usage is bind-first: call `workflow_bind_session` once, then reuse that MCP server state for later `workflow_wait` / `workflow_recv`.
- `workflow_send` also expects that bound session context unless `current_session_id` is passed explicitly.
