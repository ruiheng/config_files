---
name: agent-deck-workflow
description: Shared mailbox transport protocol for Agent Deck workflows.
---

# Agent Deck Workflow

Use this skill as the shared transport, envelope, and lifecycle layer for multi-session work.

## Load Order

For any workflow turn:
1. read `references/internal-protocol/shared-protocol.md`
2. read the action skill for the current workflow step
3. read any extra references that skill requires

Interpret references like "follow shared protocol in `agent-deck-workflow/SKILL.md`" as:
- use this file as the entry point
- then load `references/internal-protocol/shared-protocol.md`

Use `agent-deck/<agent-deck-session-id>` as the default agent-mailbox sender.

## Agent Deck Mode Detection

Read the corresponding section in `references/internal-protocol/shared-protocol.md`.

## Context Resolution Priority

Read the corresponding section in `references/internal-protocol/shared-protocol.md`.

## Error Handling and Diagnostics

Read the corresponding section in `references/internal-protocol/shared-protocol.md`.
