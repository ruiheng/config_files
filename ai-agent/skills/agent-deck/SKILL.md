---
name: agent-deck
description: Local operating rules and references for using agent-deck sessions safely and consistently.
---

# Agent Deck

Use this skill when the task is specifically about `agent-deck` session management, CLI usage, or local helper scripts in this directory.

For normal mailbox workflow, follow `agent-deck-workflow` and the current action skill.
Those paths use `agent_deck_create_session` / `agent_deck_require_session` through MCP for workflow session lifecycle.
Use the CLI rules below for manual `agent-deck` operations, local troubleshooting, or explicit shell fallback.

Primary references live under:
- `references/cli-reference.md`
- `references/config-reference.md`
- `references/troubleshooting.md`
- `references/tui-reference.md`

## Local Rules

When creating a new session from the CLI and delivering its initial instruction, use:

```bash
agent-deck launch <path> --title "<title>" --cmd "<tool>" --message "<prompt>"
```

Do not use the two-step pattern below for that workflow:

```bash
agent-deck add ...
agent-deck session send ...
```

This `add + session send` pattern is forbidden for CLI new-session startup in this repo.

Reasons:
- `launch` is the intended one-shot primitive for create + start + optional initial message.
- The two-step pattern introduces unnecessary readiness races and inconsistent startup behavior.
- Workflow helpers in this repo are standardized around `launch` for missing-session creation.

## Allowed Uses

- Use `agent-deck launch` to create and start a missing session, with or without an initial message.
- Use `agent-deck session send` only for an already existing running/waiting/idle session.
- Use `agent-deck session start` only for an already existing session that is not currently running.
- Use `agent-deck add` only when you intentionally want to pre-register a session without launching it yet.
