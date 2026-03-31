---
name: agent-deck-workflow
description: Shared transport and mailbox workflow protocol for multi-session AI collaboration, using agent-mailbox as the authoritative message layer and agent-deck only for wakeups. Use when workflow tasks need cross-session message delivery, mailbox lifecycle handling, or a common workflow envelope format.
---

# Agent Deck Workflow

Use this skill as the shared transport, envelope, and lifecycle layer for multi-session work.

This file is intentionally an index, not a role playbook.
Keep role-specific behavior in the concrete action skill that actually triggers that role or action.
This protocol layer should not depend on concrete skill names.

## Load Order

For any workflow turn:
1. read `references/internal-protocol/shared-protocol.md`
2. read only the concrete action skill that owns the current turn's behavior
3. read any extra references that concrete action skill requires

Interpret references like "follow shared protocol in `agent-deck-workflow/SKILL.md`" as:
- use this file as the entry point
- then load `references/internal-protocol/shared-protocol.md`

## Boundary Rules

- keep only cross-skill protocol here: transport, envelope, session identity, and mailbox lifecycle
- do not add lane-specific or action-specific operating rules here
- when adding a new role, add or update the concrete skill that actually starts or handles that role
- only edit the shared protocol references when the transport contract, envelope contract, or lifecycle contract changes
- keep workflow transport content in mailbox body instead of generated Markdown handoff files
- keep automation and business semantics in concrete action skills or their own references, not in this protocol layer

## Shared References

- `references/internal-protocol/shared-protocol.md`

## Agent Deck Mode Detection

Compatibility anchor for existing workflow skills.
Read the real section in `references/internal-protocol/shared-protocol.md`.

## Context Resolution Priority

Compatibility anchor for existing workflow skills.
Read the real section in `references/internal-protocol/shared-protocol.md`.

## Error Handling and Diagnostics

Compatibility anchor for existing workflow skills.
Read the real section in `references/internal-protocol/shared-protocol.md`.

## Local Scripts

Helper scripts may live under `scripts/`, but they are implementation details rather than protocol.
Do not duplicate script internals into the protocol layer unless the transport contract itself changes.
