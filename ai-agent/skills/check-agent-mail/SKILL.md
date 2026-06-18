---
name: check-agent-mail
description: Claim pending agent mail with `mailbox_recv` and immediately execute the requested workflow action.
---

## Steps

1. Run `mailbox_recv` first to claim already-available mail
2. If no personal message is returned:
   - check the roundtable exception below
   - if no visible local work remains and waiting is appropriate, run at most one `mailbox_wait timeout=110s`; if mail is available, immediately run `mailbox_recv`
   - if waiting finds no mail, report no agent mail and stop until a later nudge or explicit check
3. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - execute that workflow stage immediately
4. Only `mailbox_ack` the currently claimed inbound delivery, and only after the message's required workflow action is complete
5. If the message cannot be acted on yet, use `mailbox_release`, `mailbox_defer`, or `mailbox_fail` instead of silently dropping it

## Rules

- Use `mailbox_wait` only for idle waiting after empty `mailbox_recv`; max once per assistant turn, `timeout: "110s"`, no loop/retry
- `mailbox_recv` only reads and claims available mail; do not rely on it to wait
- While a claimed personal delivery is incomplete, do not call `mailbox_recv` for another personal delivery
- After the claimed delivery is complete, do not start another wait/receive cycle in the same check unless the current task explicitly asks for it
- If mailbox context is not bound yet, first run `agent-deck session current --json`, derive the current session inbox address, call `mailbox_bind`, then retry the same `mailbox_recv` first sequence
- Never pass a `group/` address to `mailbox_bind`; group addresses are read only with explicit `mailbox_recv addresses=[...] as_person=...`
- Roundtable exception: if no personal message is returned and the current session has explicit active `roundtable` moderator context, run the `roundtable` skill's moderator group check before reporting no personal mail. This handles group subscriber wakeups, which may not create a personal delivery.
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- The current session owns only the delivery lifecycle of the inbound message it claimed with `mailbox_recv`
- Do not `mailbox_ack` / `mailbox_release` / `mailbox_defer` / `mailbox_fail` outbound mail that this session sent, or a delivery claimed by another session
- The action skill decides the exact serialized completion point for `mailbox_ack` or the alternate lifecycle step
- Determine workflow behavior from this mailbox input plus the current action skill; you do not need to inspect another role's implementation details
- Treat `mailbox_ack` as durable persistence, not as losing the message forever
- If you need to recover the latest acknowledged workflow input after `mailbox_ack`, use `mailbox_read` on the latest `acked` delivery for this session
- If you need an older acknowledged delivery, use `mailbox_list` with `state: acked`, then `mailbox_read` by delivery id
- After `mailbox_recv` returns a workflow message, do not naturally end this turn until the message's required workflow action is complete
- Before ending, explicitly check whether this action still requires `mailbox_send`, `mailbox_ack`, `mailbox_release`, `mailbox_defer`, or `mailbox_fail`
- If compaction or interruption made the workflow obligation unclear, reread the current workflow input from the mailbox body or recover it with `mailbox_read` before deciding to stop
