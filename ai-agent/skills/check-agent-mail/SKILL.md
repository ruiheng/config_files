---
name: check-agent-mail
description: Receive pending agent mail and immediately execute the requested workflow action.
---

# Check Agent Mail

Use this skill to turn a wakeup nudge into actual workflow execution.

## Steps

1. If `agent_mailbox` is not already bound, bind mailbox addresses for this session first
2. Run `mailbox_recv`
3. If no message is waiting, report that no agent mail is available and stop
4. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - execute that workflow stage immediately
5. Only `mailbox_ack` after the message has been incorporated into working state
6. If the message cannot be acted on yet, use `mailbox_release`, `mailbox_defer`, or `mailbox_fail` instead of silently dropping it

## Rules

- Treat the received mailbox body as executable workflow input
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- Keep lifecycle steps serialized
