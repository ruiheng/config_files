---
name: roundtable-participant
description: Participate in a roundtable discussion from a personal mailbox control message. Use when a received workflow message has Action `roundtable_participant_turn` or asks this agent to read a roundtable group mailbox and respond as a named participant.
---

# Roundtable Participant

Speak as the assigned participant. The moderator talks to the user; you talk to the group.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Inputs

Read the personal mailbox body first. Resolve:

- `roundtable_id`: `Task:` header
- `group_address`: `Group:` in body
- `participant_person`: `Person:` in body
- `role`: `Role:` in body
- `round`: `Round:` header
- `moderator_request`: `Moderator Request` section

If `group_address`, `participant_person`, or `role` is missing, do not guess. Ask the sender by leaving the personal delivery unacked and using the appropriate mailbox lifecycle step.

## Steps

1. Read the received personal control message.
2. Use `agent_mailbox` MCP `mailbox_recv` with:
   - `addresses = [group_address]`
   - `as_person = participant_person`
3. Repeat group `mailbox_recv` until it returns `no_message`.
   - This loop is only for group stream reads.
   - Stop after 20 messages and note that the response is based on the first 20 unread messages.
4. Compose one group reply.
5. Send the reply with `mailbox_send`:
   - `to_address = group_address`
   - `group = true`
   - `subject = "roundtable: <roundtable_id> r<round> <participant_person>"`
   - `body = <reply>`
6. Mark the participant's own group send read:
   - take the returned `message_id`
   - call `mailbox_recv` with `addresses = [group_address]` and `as_person = participant_person`
   - stop when the returned `message.message_id` matches the sent message id
   - if a different message appears first, keep reading until the sent message is read or report the inconsistency
7. `mailbox_ack` the personal control delivery only after the group reply send succeeds and the own group send is marked read.

## Reply Rules

- Reply to the group, not to the user.
- Stay in the assigned role.
- Address the moderator's request and the most relevant prior group messages.
- Be concise; the moderator will explain context to the user.
- Prefer specific claims, objections, trade-offs, and questions over generic advice.
- Do not restate simple background facts unless they are necessary for the argument.
- If another participant is wrong or missing a premise, say so directly and explain why.

## Reply Format

```markdown
Roundtable: <roundtable_id>
Participant: <participant_person>
Role: <role>
Round: <round>

## Position
[core answer in 1-3 short paragraphs]

## Reasons
- [reason]
- [reason]

## Challenge Or Question
[one challenge to another view, or one question the moderator should consider next]
```

If there were no unread group messages, still answer the moderator request if it is self-contained. If it is not self-contained, send a short group reply saying what context is missing.
