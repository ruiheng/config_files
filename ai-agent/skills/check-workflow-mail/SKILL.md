---
name: check-workflow-mail
description: Receive pending workflow mail for the current agent-deck session and immediately execute the requested workflow action.
---

# Check Workflow Mail

Use this skill to turn a wakeup nudge into actual workflow execution.

## Mode

- `wait=False` (default): check once and return immediately when no mail is waiting
- `wait=True`: block on `recv --wait` until a message becomes claimable or the process is interrupted

## Steps

1. Run `agent-deck session current --json` outside sandbox once and read `.id`
2. Derive inbox address as `agent-deck/<current_session_id>`
3. Run one of these outside sandbox:
   - `wait=False`: `agent-mailbox recv --for agent-deck/<current_session_id> --json`
   - `wait=True`: `agent-mailbox recv --for agent-deck/<current_session_id> --wait --json`
4. If no message is waiting, report that no workflow mail is available and stop
5. If a message is returned:
   - treat `body` as executable workflow input, not as a notification
   - parse the `Action:` header
   - execute that workflow stage immediately
6. Only `ack` after the message has been incorporated into working state
7. If the message cannot be acted on yet, use `release`, `defer`, or `fail` outside sandbox instead of silently dropping it

## Rules

- Treat the received mailbox body as executable workflow input
- Ask the user for the next step only when the mailbox body explicitly requires a user decision
- Read external files only when the mailbox body explicitly says they are needed
- Keep mailbox lifecycle commands outside sandbox
- Keep mailbox state-mutating commands serialized
