---
name: check-agent-mail
description: Receive pending agent mail and immediately execute the requested workflow action.
---

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
- `mailbox_wait` is not recommended for normal pickup; use `mailbox_recv`
- If mailbox context is not bound yet, first run `agent-deck session current --json`, derive the current session inbox address, call `mailbox_bind`, then retry `mailbox_recv`
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- Treat `mailbox_ack` as durable persistence, not as losing the message forever
- If you need to recover the latest acknowledged workflow input after `mailbox_ack`, use `mailbox_read` on the latest `acked` delivery for this session
- If you need an older acknowledged delivery, use `mailbox_list` with `state: acked`, then `mailbox_read` by delivery id
- Keep lifecycle steps serialized
- If `mailbox_recv` fails because mailbox context is missing, bind and retry
