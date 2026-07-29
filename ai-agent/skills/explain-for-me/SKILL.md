---
name: explain-for-me
description: Create an audience-adapted HTML explainer.
disable-model-invocation: true
---

# Explain for Me

## Resolve

- Source: explicit -> task contract -> conversation.
- Language, audience, depth: explicit -> context; ask only when material.
- Delegated: source = `Execution / Source` + known context; require `shared; cleanup=none`; missing source -> block.
- Separate facts, inferences, and open questions.

## Page

- Write `.agent-artifacts/explain-for-me/<id>/index.html`; `<id>` is task id -> active task -> `YYYYMMDD-HHMM-<short-slug>`.
- Produce one HTML page; CDN is allowed.
- Adapt structure, language, examples, and visuals to the audience without losing precision. Cite sources or caveats when useful.

## Deliver

- Return the full page path or URI.

## Show

On request, expose it via a harness artifact URI or loopback server; add SSH tunnel instructions when remote.
