---
name: agent-deck-workflow
description: Human-led planner/coder/reviewer workflow protocol with a per-task architect lane and an optional browser-tester worker, using agent-mailbox as the authoritative message layer and agent-deck only for wakeups.
---

# Agent Deck Workflow

Use this skill as the shared workflow protocol layer for multi-session work.

This file is intentionally an index, not a role playbook.
Keep role-specific behavior in the skill that actually triggers that role/action:
- planner dispatch: `delegate-task`
- coder review handoff: `review-request`
- reviewer decision loop: `review-code`
- reviewer accepted closeout packaging: `review-closeout`
- architect request/report: `tech-design-review-request`, `tech-design-review`
- browser validation request/report: `browser-test-request`, `browser-test`

## Load Order

For any workflow turn:
1. read `references/internal-protocol/shared-protocol.md`
2. read `references/internal-protocol/automation-policy.md` only when `workflow_policy` exists or human-vs-unattended gating matters
3. read only the action skill that owns the current turn's behavior

Interpret references like "follow shared protocol in `agent-deck-workflow/SKILL.md`" as:
- use this file as the entry point
- then load the shared protocol reference files above

## Boundary Rules

- keep only cross-skill protocol here: transport, identity, branch-plan invariants, message contract, closeout contract
- do not add coder/reviewer/architect/browser-tester operating rules here
- when adding a new role, add or update the skill that actually starts or handles that role
- only edit the shared protocol references when the wire contract, lifecycle contract, or cross-skill invariants change
- keep workflow transport content in mailbox body instead of generated Markdown handoff files

## Shared References

- `references/internal-protocol/shared-protocol.md`
- `references/internal-protocol/automation-policy.md`

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

- `scripts/planner-closeout-batch.sh`
- `scripts/closeout-health-gate.sh`
- `scripts/archive-and-remove-task-sessions.sh`
- `scripts/prune-task-branches.sh`
- `scripts/adwf-send-and-wake.sh`
- `scripts/notify-workflow-event.sh`

Do not duplicate script internals into prompt text unless the contract itself changes.
