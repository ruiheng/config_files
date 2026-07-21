---
name: roundtable-participant
description: Participate in a roundtable discussion from a personal control message. Use when a received workflow message has Action `roundtable_participant_turn` or asks this agent to read a Waypost group and respond as a named participant.
---

# Roundtable Participant

Speak as the assigned participant. The moderator talks to the user; you talk to the group.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Inputs

Read the personal message body first. Resolve:

- `roundtable_id`: `Task:` header
- `group_address`: `Group:` in body
- `participant_person`: `Person:` in body
- `role`: `Role:` in body
- `round`: `Round:` header
- `moderator_request`: `Moderator Request` section

If `group_address`, `participant_person`, or `role` is missing, do not guess. Ask the sender by leaving the personal delivery unacked and using the appropriate message lifecycle step.

## Steps

1. Read the received personal control message.
2. Use `waypost` MCP `waypost_recv` with:
   - `addresses = [group_address]`
   - `as_person = participant_person`
3. Repeat group `waypost_recv` until it returns `no_message`.
   - This loop is only for group stream reads.
   - Stop after 100 messages and note that the response is based on the first 100 unread messages.
4. Compose one group reply.
5. Send the reply with `waypost_send`:
   - `to_address = group_address`
   - `from_address = participant_person`
   - `as_person = participant_person`
   - `group = true`
   - `subject = "roundtable: <roundtable_id> r<round> <participant_person>"`
   - `body = <reply>`
6. `waypost_ack` the personal control delivery only after the group reply send succeeds.

## Reply Rules

- Reply to the group, not to the user.
- Stay in the assigned role.
- Address the moderator's request and the most relevant prior group messages.
- Be concise; the moderator will explain context to the user.
- Prefer specific claims, objections, trade-offs, and questions over generic advice.
- Do not restate simple background facts unless they are necessary for the argument.
- If another participant is wrong or missing a premise, say so directly and explain why.

## Reply Format

Default format:

```markdown
## Position
[core answer in 1-3 short paragraphs]

## Reasons
- [reason]
- [reason]

## Challenge Or Question
[one challenge to another view, or one question the moderator should consider next]
```

Keep envelope metadata out of the body. `roundtable_id`, `round`, and `participant_person` belong in `subject`; participant identity belongs in `from_address`. Include role only when it is part of the argument, not as a header.

If the Moderator Request explicitly requires exact/raw output or a different format, obey that request instead.

If there were no unread group messages, still answer the moderator request if it is self-contained. If it is not self-contained, send a short group reply saying what context is missing.
