---
name: check-workflow-mail
description: Receive pending workflow mail and immediately execute the requested workflow action.
---

# Check Workflow Mail

Use this skill to turn a startup bind or wakeup nudge into actual workflow execution.

## Mode

- `wait=False` (default): check once and return immediately when no mail is waiting
- `wait=True`: wait until mail appears, then `recv` once to claim it

## Steps

1. If `workflow_mailbox` is not already bound, read `session_id` from the startup context and call `workflow_bind_session`
2. Run one of these MCP calls:
   - `wait=False`: `workflow_recv`
   - `wait=True`: `workflow_wait`, then `workflow_recv`
3. If no message is waiting, report that no workflow mail is available and stop
4. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - execute that workflow stage immediately
5. Only `workflow_ack` after the message has been incorporated into working state
6. If the message cannot be acted on yet, use `workflow_release`, `workflow_defer`, or `workflow_fail` instead of silently dropping it

## Rules

- Treat the received mailbox body as executable workflow input
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- Keep lifecycle steps serialized
