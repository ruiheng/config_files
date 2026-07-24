# Shared Workflow Protocol

Use this contract for session identity, message boundaries, and delivery lifecycle.
Action skills own role behavior; companion references own shared execution policy.

## Agent Deck Mode Detection

Enter Agent Deck mode when any condition matches:

- workflow metadata includes a task or session id
- an inbound message carries workflow metadata
- the user explicitly requests Agent Deck workflow

## Context Resolution Priority

`explicit input -> message/workflow context -> deterministic default -> ask`

- Resolve the current session from live Agent Deck or Waypost context.
- Use a session ref only before a real id exists; record and use the real id afterward.
- Treat a missing required session id as context loss unless the action declares its target on demand.

## Target Lifecycle Gate

- At first dispatch, or when target identity/workdir is uncertain, create or require the target session.
- Otherwise send to the confirmed session id.
- The action skill owns target-specific creation and reuse; follow the shared tool-resolution contract before creating a session without a full command.
- Creating an Agent Deck session is workflow lifecycle, not a host-subagent API call.

## Message Envelope

Every workflow message has:

- `subject`: one-line triage summary
- `body`: full task input

Use this header when the action needs shared routing metadata:

```markdown
Task: <task_id_or_N/A>
Action: <action_name>
From: <role_or_sender_label> <from_session_id>
To: <role_or_receiver_label> <to_session_id>
```

`Action:` is a stable token. The action skill owns its meaning and any extra fields.

## Delivery Contract

1. Follow Target Lifecycle Gate.
2. Queue the message with `waypost_send`.
3. Follow Async sender rule.

## Async sender rule

- `waypost_send` completes delivery; replies are later inbound work.
- Continue only with independent local work; otherwise return the action's confirmation/status.
- Keep target execution receiver-owned; inspect, repair, or resend only during explicit troubleshooting.

## Receiver Contract

On a wakeup nudge or explicit user message check:

1. Call `waypost_recv` first.
2. If no personal message is returned, report no message and end.
3. Use `body` as the primary input, parse `Action:`, and run the matching action skill.
4. After the action completes, settle the claimed delivery with `waypost_ack`, `waypost_release`, `waypost_defer`, or `waypost_fail`.
5. After `waypost_ack`, return to step 1; process one delivery at a time. After another lifecycle result, follow the action skill's continuation policy.

## Natural End Gate

End only after required handoff and lifecycle steps are settled. If message context is lost, recover it with `waypost_read`; if work is blocked, use the appropriate lifecycle or reporting step first.
