---
name: check-agent-mail
description: Claim and process pending agent mail one delivery at a time with `mailbox_recv`.
---

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Steps

1. Start the shared Receiver Contract by running `mailbox_recv` first to claim one personal delivery.
2. If no personal message is returned:
   - if no visible local work remains, finish the shared Receiver Contract's single idle wait path
   - if still no mail, report no agent mail and stop until a later nudge or explicit check
3. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - if `Action: group_message_available`, run the group handler for `Group-Address` and `As-Person`; for `group/roundtable-*`, use `roundtable` Moderator Group Check
   - otherwise execute that workflow stage immediately
4. Only `mailbox_ack` the currently claimed inbound delivery, and only after the message's required workflow action is complete
5. If the message cannot be acted on yet, use `mailbox_release`, `mailbox_defer`, or `mailbox_fail` instead of silently dropping it
6. After a delivery is completed and `mailbox_ack` succeeds, return to step 1. Process mail strictly as `recv one → act → settle → recv next`; do not pre-claim a batch

## Rules

- Use the shared Receiver Contract for recv-first, binding recovery, bounded idle wait, and personal-delivery lifecycle limits
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- The current session owns only the delivery lifecycle of the inbound message it claimed with `mailbox_recv`
- Do not call `mailbox_recv` again while a personal delivery remains claimed
- After a successful `mailbox_ack`, immediately call `mailbox_recv` again; stop the serial receive cycle only when it returns no personal mail
- After `mailbox_release`, `mailbox_defer`, or `mailbox_fail`, follow the action skill's continuation policy; do not blindly re-claim the released delivery
- Do not `mailbox_ack` / `mailbox_release` / `mailbox_defer` / `mailbox_fail` outbound mail that this session sent, or a delivery claimed by another session
- The action skill decides the exact serialized completion point for `mailbox_ack` or the alternate lifecycle step
- Determine workflow behavior from this mailbox input plus the current action skill; you do not need to inspect another role's implementation details
- Treat `mailbox_ack` as durable persistence, not as losing the message forever
- If you need to recover the latest acknowledged workflow input after `mailbox_ack`, use `mailbox_read` on the latest `acked` delivery for this session
- If you need an older acknowledged delivery, use `mailbox_list` with `state: acked`, then `mailbox_read` by delivery id
- After `mailbox_recv` returns a workflow message, do not naturally end this turn until the message's required workflow action is complete
- Before ending, explicitly check whether this action still requires `mailbox_send`, `mailbox_ack`, `mailbox_release`, `mailbox_defer`, or `mailbox_fail`
- If compaction or interruption made the workflow obligation unclear, reread the current workflow input from the mailbox body or recover it with `mailbox_read` before deciding to stop
