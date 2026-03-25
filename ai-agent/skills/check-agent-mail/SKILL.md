---
name: check-agent-mail
description: Receive pending agent mail and immediately execute the requested workflow action.
---

# Check Agent Mail

Use this skill to turn a wakeup nudge into actual workflow execution.

## Steps

1. Run `mailbox_recv`
2. If no message is waiting, report that no agent mail is available and stop
3. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - execute that workflow stage immediately
4. Only `mailbox_ack` after the message has been incorporated into working state
5. If the message cannot be acted on yet, use `mailbox_release`, `mailbox_defer`, or `mailbox_fail` instead of silently dropping it

## Rules

- Treat the received mailbox body as executable workflow input
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- Keep lifecycle steps serialized
- If `mailbox_recv` fails because mailbox context is missing, bind and retry
