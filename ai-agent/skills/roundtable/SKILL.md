---
name: roundtable
description: Run a real multi-agent roundtable or brainstorming discussion with agent-mailbox group addresses and agent-deck sessions. Use when the user asks to start, continue, moderate, summarize, or inspect a roundtable discussion, including wakeups from group subscriber notifications.
---

# Roundtable

Moderate a group discussion. The user talks to you; participants talk in the mailbox group.

Workflow protocol baseline: use the `agent-deck-workflow` skill.

## Role

- You are the moderator, not a domain expert participant.
- Do not contribute substantive expert opinions as yourself.
- Clarify the user's intent, choose and steer participants, keep records, and present results.
- Preserve the raw discussion in the group mailbox; do not replace it with local notes.

## Context Fields

Resolve by priority: explicit input -> current roundtable context -> mailbox body -> ask.

- `roundtable_id`: stable id, default `rt-YYYYMMDD-HHMM-<slug>`
- `group_address`: `Group-Address` control header -> current context -> default `group/roundtable-<roundtable_id>`
- `moderator_session_id`: current agent-deck session id
- `moderator_group_path`: current agent-deck group path, default current session group
- `moderator_person`: `As-Person` control header -> current context -> default `moderator`
- `moderator_notify_address`: `agent-deck/<moderator_session_id>`
  - use this as moderator group-send `from_address`; agent-mailbox maps it to `moderator` read state and suppresses the moderator's own subscriber delivery
- `participant_session_ref`: default `roundtable-<roundtable_id>-<participant_slug>`
- `participant_group_path`: explicit -> if moderator group is root, `roundtable-<roundtable_id>`; otherwise `<moderator_group_path>/roundtable-<roundtable_id>`
- `participant_session_id`: real id returned by `agent_deck_create_session`
- `participant_person`: `participant/<slug>`
- `participant_tool_profile`: explicit -> participant config -> default resolver role `roundtable_participant`
- `participant_tool_cmd`: explicit full command -> resolved command
- `round`: default `1`, increment after each moderator synthesis

## Start A Roundtable

1. Clarify the topic until the user's goal, audience, constraints, and stop condition are clear.
   - Record the stop condition and check it after each synthesis.
2. Propose 3-5 participants and ask for user confirmation before creating sessions.
   - Include each participant's name, role, viewpoint, and tool profile.
   - Default set when the user gives no preference: systems thinker, builder, skeptic, user advocate, contrarian.
3. Use `agent_mailbox` MCP tools:
   - `mailbox_group_create` with `group_address`
   - `mailbox_group_add_member` for `moderator`
   - `mailbox_group_add_subscriber` with `notify_address = agent-deck/<moderator_session_id>` and `person = moderator`
   - `mailbox_group_add_member` for each `participant/<slug>`
4. Resolve every participant tool with:
   - `node ~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js --role roundtable_participant --profile <participant_tool_profile> --format json`
   - omit `--profile` when no explicit profile is set
5. Resolve each participant session.
   - First try `agent_deck_resolve_session` for an explicit existing `participant_session_id` or known `participant_session_ref`.
   - If an existing session is found, use `agent_deck_require_session` with the explicit workdir.
   - If none exists, create it with `agent_deck_create_session`.
   - `ensure_title = <participant_session_ref>`
   - `ensure_cmd = <participant_tool_cmd>`
   - `workdir = current workspace`
   - `parent_session_id = <moderator_session_id>`
   - `group_path = <participant_group_path>`
   - `no_parent_link = false`
   - leave `startup_instruction` / `listener_message` empty; control mail is the bootstrap path and wakeup is best-effort
6. Send the opening user-intent message to the group with `mailbox_send group:true`, `to_address = group_address`, and `from_address = moderator_notify_address`.
7. Send each participant one personal control message with Action `roundtable_participant_turn`; first turns are parallel by default.

## User Input Turn

When the user adds a new thought or question:

1. Restate the user's intent clearly and compactly.
2. Ask one clarification only if the next participant turn would otherwise be misdirected.
3. Drain moderator group unread first if there may be pending participant replies.
4. Send the clarified intent to the group with `mailbox_send group:true`, `to_address = group_address`, and `from_address = moderator_notify_address`.
5. Decide who speaks next:
   - default for a new broad user prompt: all participants in parallel
   - default after synthesis: targeted follow-up to the participants needed for the next decision
   - use round-robin only when the user asks for sequential turns or lower churn
6. Send personal control messages to the selected participant sessions.

## Moderator Group Check

Use this for `Action: group_message_available` personal control mail or when the user asks for updates.

1. Call `mailbox_recv` with:
   - `addresses = [Group-Address from control mail or group_address]`
   - `as_person = [As-Person from control mail or moderator]`
2. Repeat group `mailbox_recv` until it returns `no_message`.
   - This loop is only for group stream draining; do not repeat personal `mailbox_recv`.
   - Stop after 100 messages and report that more unread group messages remain.
3. If no group messages were read, say no roundtable updates are available.
4. If messages were read, synthesize for the user.

## Present To User

Default presentation is synthesis plus traceability:

- Group by participant.
- Preserve each participant's core claim and reasoning.
- Include the `message_id` for each summarized participant message.
- Mark moderator inference as `Moderator synthesis`, not as a participant's view.
- Mention material uncertainty or disagreement.
- Offer to show raw message text by `message_id` when useful.

Do not paste long raw discussion by default. Do not hide dissent in a single consensus sentence.

## Participant Control Message

Use this body for participant personal mail:

```markdown
Task: <roundtable_id>
Action: roundtable_participant_turn
From: moderator <moderator_session_id>
To: participant {{TO_SESSION_ID}}
Round: <round>

## Roundtable
- Group: <group_address>
- Person: <participant_person>
- Role: <participant role>
- Tool profile: <participant_tool_profile>
- Tool cmd: <participant_tool_cmd>

## Moderator Request
[what this participant should address now]

## Rules
- Read group unread messages as `<participant_person>`.
- Reply to the group only.
- Send with `from_address = <participant_person>`.
- Use subject `roundtable: <roundtable_id> r<round> <participant_person>`.
- Keep envelope metadata out of the body; start the body at the participant's actual response, usually `## Position`.
- Do not address the user directly.
- Keep the answer concise and assume the moderator will translate for the user.
```

After participant control mail is sent, do independent moderator work when available. If no visible local work remains, use normal `check-agent-mail`; group subscriber updates arrive as durable personal `group_message_available` deliveries, while external wake notification is only best-effort acceleration.

## Ending

When the user says `stop`, `end`, `止`, or `结束`:

1. Drain moderator group unread messages first.
2. Produce final synthesis:
   - decisions or strongest answer
   - unresolved disagreements
   - useful next questions
   - compact ASCII knowledge map when it helps
3. State whether the recorded stop condition is satisfied.
4. Keep the group and sessions by default.

When the user explicitly asks to clean up or archive:

1. Drain moderator group unread messages first.
2. Produce the final synthesis before deleting anything.
3. Remove participant sessions with `agent-deck remove <participant_session_id>`.
4. Delete the participant Agent Deck group with `agent-deck group delete <participant_group_path>` only after participant sessions are gone.
5. Do not delete the mailbox group unless the user explicitly asks to delete the raw discussion history.
