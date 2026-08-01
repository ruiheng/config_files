---
name: tech-design-assessment
description: Independently assess a completed technical design against its current accepted intent, starting from the original problem. Use only when explicitly asked for a final design assessment, not for drafting, workflow routing, or acceptance closeout.
disable-model-invocation: true
---

# Tech Design Assessment

Start from the original problem; assess the current design against the latest accepted goals, constraints, and decisions—not the drafting history.

## Scope

Require:

- exact readable target set: every document or asset needed to judge the design
- current accepted intent: original problem + latest accepted goals, constraints, and decisions
- exact snapshot/commit when version can change the conclusion

Ask one short question only when missing context would materially change the conclusion. Use available evidence; do not assume.

Stay advisory and read-only. Leave edits, Git, archival, and workflow routing to the caller.

## Assessment

Assess only relevant areas:

- core approach; whether goals/requirements are sound, appropriately scoped, or should be split
- material rationale, user fit, simplicity/over-design, ownership, boundaries, cohesion, and coupling
- flexibility/foresight: readiness for credible future change within demonstrated need
- persisted data/state and configuration: need, migration/rollback, defaults, deployment, and operations
- compatibility in both directions—new-to-old and old-to-new data, configuration, and interfaces—and whether it is necessary
- benefits, risks, mitigations/rollback, alternatives, and key tradeoffs
- user-owned decisions, options, and consequences

Use `None` for no relevant impact or concern; use `Missing information` when evidence is insufficient. Cite targets and evidence with full paths or URIs.

## Report

Keep the report compact. Focus on material issues, tradeoffs, and decisions; do not restate the design.

~~~markdown
# Design Assessment

## Targets And Intent
- Targets:
  - <full path or URI>
- Snapshot/commit: <if relevant>
- Accepted intent: <original problem; latest accepted goals, constraints, and decisions>

## Core And Scope
[approach, fit, simplification/splitting opportunities, or None]

## Flexibility And Foresight
[readiness for credible future change within demonstrated need, or None]

## Material Impacts
- Data/state: [impact, migration/rollback, or None]
- Configuration/operations: [impact, or None]
- Compatibility: [both directions and need, or None]

## Risks And Tradeoffs
[benefits, risks, mitigations, alternatives, and tradeoffs, or None]

## Decisions Needed
- [option and consequence, or None]

## Missing Information
- [evidence needed to conclude, or None]
~~~
