---
name: check-waypost-messages
description: Claim and process pending Waypost messages with `waypost_recv`, allowing independent deliveries to progress without holding blocked claims.
---

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Steps

1. Start the shared Receiver Contract by running `waypost_recv` first to claim one personal delivery.
2. If no personal message is returned:
   - report no pending agent messages and stop until a later nudge or explicit check
3. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - if `Action: group_message_available`, run the group handler for `Group-Address` and `As-Person`; for `group/roundtable-*`, use `roundtable` Moderator Group Check
   - route `execute_delegated_task` and `delegated_task_result` to `delegate-task`; `execute_delegate_task` to `delegate-code-task`; `closeout_delivered`, `review_completed`, and `code_delivery_complete` to `planner-closeout`
   - otherwise execute that workflow stage immediately
4. Settle the claim when its current disposition is clear:
   - `waypost_ack` after its immediate required action completes, including handing a required decision to the user
   - `waypost_release` or `waypost_defer` only when the delivery itself cannot be handled now
   - `waypost_fail` when it cannot be completed
5. Continue receiving other useful messages; independent deliveries do not need to wait for each other

## Rules

- Use the shared Receiver Contract for claim ownership, recovery, and lifecycle limits
- The current session owns only deliveries it claimed with `waypost_recv`
- A claim is not a global receive lock; receive independent work when useful
- Do not keep a claim open while waiting for the user's answer; continue later from that answer or acknowledged history
- Do not immediately reclaim released or deferred work unless its blocker changed
- Do not `waypost_ack` / `waypost_release` / `waypost_defer` / `waypost_fail` outbound messages that this session sent, or a delivery claimed by another session
- The action skill decides when each delivery is complete or should be returned
- Before ending, settle every delivery still claimed by this session
