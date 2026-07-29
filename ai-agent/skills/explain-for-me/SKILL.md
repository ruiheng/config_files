---
name: explain-for-me
description: Create an audience-adapted HTML explainer.
disable-model-invocation: true
---

# Explain for Me

Turn the requested material into an audience-adapted explainer under `.agent-artifacts/`.

## Resolve

- Source: explicit -> task context -> conversation.
- Language, audience, depth: explicit -> clear context; ask only if the result would differ.
- Delegated work: use `Execution / Source` and known context; never assume requester chat is inherited. Missing source -> report blocker; never invent facts.
- A delegated page requires `shared; cleanup=none`; it must survive terminal delivery.
- Distinguish facts, inferences, and open questions.

## Page

- Write `.agent-artifacts/explain-for-me/<id>/index.html`; `<id>` is task id -> active task -> `YYYYMMDD-HHMM-<short-slug>`.
- Produce one ready-to-open HTML page; CDN is allowed.
- Choose the narrative, detail, and visual form that best aid understanding. Include conclusions, rationale, tradeoffs, risks, and questions only when relevant.
- Adapt terminology and examples without losing precision; show sources or caveats when useful. Keep it responsive, readable, and useful without optional interaction.

## Deliver

- Return the page link/path and an invitation to ask about or revise it; do not recap it in chat. Use chat for follow-ups and revise the page on request.

## Show

Only on an explicit request: prefer a harness-provided artifact link. For a remote page, the session handling that request may use the harness's native background task to serve its directory on loopback, then provide SSH tunnel information when needed.
