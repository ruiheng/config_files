# Error Handling and Diagnostics

Use this shared checklist after listener, send, worker-start, or closeout failure.

1. Report a concise stderr summary.
2. Resolve the sender or target with `agent_deck_resolve_session`.
3. Confirm the command runs in the expected workflow session context.
4. Check the relevant send, receive, or lifecycle tool result.

- Explain a sandbox-external approval prompt as a host-shell permission requirement.
- Treat target status as diagnostic only; retry a nudge or resend only during explicit troubleshooting.
- For closeout or cleanup failure, include the blocker, generated artifact path, and exact manual unblock step.
