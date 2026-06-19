---
name: agent-deck-workflow
description: Shared mailbox transport protocol for Agent Deck workflows.
---

# Agent Deck Workflow

Use this skill as the shared transport, envelope, and lifecycle layer for multi-session work.

## Workflow Order

For any workflow turn:
1. follow `references/internal-protocol/shared-protocol.md`
2. use the action skill for the current workflow step
3. use any extra references that skill requires

Interpret references to the shared workflow protocol as:
- use the `agent-deck-workflow` skill as the entry point
- then follow `references/internal-protocol/shared-protocol.md`

Use `agent-deck/<agent-deck-session-id>` as the default agent-mailbox sender.

## Agent Deck Mode Detection

Use the corresponding section in `references/internal-protocol/shared-protocol.md`.

## Context Resolution Priority

Use the corresponding section in `references/internal-protocol/shared-protocol.md`.

## Error Handling and Diagnostics

Use the corresponding section in `references/internal-protocol/shared-protocol.md`.
