---
name: code-health-review
description: Review codebases from a high-level maintainability and reliability perspective. Use when the goal is to identify systemic design problems rather than local cleanup, especially for repeated bug patterns, high-churn modules, patch-on-patch fixes, weak typing, duplicated decision logic, poor testability, or slow/non-converging fix-review cycles. Return advisory findings without making code changes.
---

# Code Health Review

Review code with a senior-engineer lens focused on maintainability, reliability, and provability.
Prefer structural diagnoses that explain multiple symptoms at once instead of listing isolated cleanup ideas.

This skill is advisory only.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines code-health-review-specific behavior.

## Hard Boundary

- inspect code, history, tests, and surrounding context
- identify systemic design problems, ownership failures, and architectural drift
- recommend high-leverage structural corrections and safe sequencing
- do not edit files
- do not apply patches
- do not implement refactors
- do not produce commit-ready diffs unless the user explicitly asks for them later

## Input

Provide one of:
1. the mailbox body from `code_health_review_requested`
2. direct scope + review goal + known pain signals + constraints

Direct-use mode is valid.
This skill may be run without mailbox workflow when the user wants an immediate advisory review.

Useful pain signals include:
- repeated bugs in the same area
- slow or non-converging fix/review loops
- high-churn modules
- patch-on-patch code
- duplicated decision logic
- weak or vague data contracts
- code that is hard to test with confidence

If history-heavy diagnosis is important, state it explicitly. Otherwise, use git history only when it is likely to change the conclusion.

## Input Completeness Gate

Before reviewing, verify:
- scope is explicit
- review goal is explicit
- known pain signals are explicit or safely inferable
- behavior or compatibility constraints are explicit or safely inferable

If critical context is missing:
- in direct-use mode, ask one short clarification question
- in mailbox mode, continue and mark the missing items in `Scope Gaps`

## Workflow

1. Define the system question.
- What keeps going wrong?
- Is the pain local ugliness or structural instability?
- Is the latest reported issue the real problem or just the latest symptom?

2. Build evidence from the cheapest high-signal sources.
- current code shape
- tests and missing tests
- recent bug-fix history in the same area
- repeated decision patterns across modules
- ownership, data flow, and state transition boundaries

3. Classify the signals before giving advice.
Read `references/signals.md` when deciding whether a symptom points to a structural problem or just local cleanup.

4. Form one or two systemic hypotheses.
Each hypothesis should explain multiple symptoms, not just the latest report item.

5. Stress-test the hypotheses.
- Can the hypothesis explain bug concentration, slow review convergence, and testing pain at the same time?
- Does the proposed direction remove special cases instead of adding guards?
- Does it reduce future change surface instead of moving complexity around?

6. Produce one prioritized report.
Read `references/remediation-patterns.md` when proposing structural corrections.

## History Review Rule

When the current code alone does not explain why the area feels fragile, inspect recent history for:
- repeated fixes in the same module or boundary
- similar bug shapes expressed through different symptoms
- patch-on-patch edits that preserve old complexity
- files that absorb unrelated responsibilities over time

Prefer recent, local history over broad repository archaeology.
Do not summarize commit history mechanically; use history only to strengthen or falsify a structural hypothesis.

## Review Lens

Evaluate code using these lenses:

- ownership: who owns state and who is allowed to change it
- boundaries: whether modules have stable responsibilities and narrow interfaces
- type discipline: whether the data model is explicit, checkable, and hard to misuse
- decision locality: whether business rules live in one place or are re-encoded repeatedly
- testability: whether important behavior can be proven with focused tests
- change amplification: whether small changes spread across too many files or branches
- bug concentration: whether certain modules or patterns keep attracting similar failures

Look for:

- business rules copied across modules with minor variations
- `dict`-shaped or loosely-typed payloads crossing important boundaries
- modules that both orchestrate workflow and implement business rules
- patch layers that preserve a broken design by adding more branching
- high-churn files with repeated bug-fix commits of similar shape
- tests that only verify top-level behavior because the internals are too entangled
- state transitions encoded by scattered conditionals instead of a clear model

## Evidence Rules

- prefer converging evidence across code shape, history, and tests
- do not treat high churn alone as proof; correlate it with bug patterns or duplicated logic
- do not treat the latest issue report as the whole problem definition
- treat repeated nearby fixes as evidence of a wrong boundary, wrong ownership model, or missing structural simplification
- treat a "simple" issue that takes many review rounds as a design smell, not as normal iteration
- do not infer a redesign need from aesthetics alone; show how the structure reproduces maintenance cost or reliability risk

## Decision Heuristics

- prefer one structural diagnosis that explains many failures over many local style complaints
- prefer stronger types, explicit schemas, and narrower interfaces over "flexible" containers
- prefer single-point ownership of business rules
- prefer designs that make narrow regression tests easy to write
- prefer deleting or consolidating logic before introducing new abstraction layers
- call out when redesign is needed instead of pretending a small refactor will solve it
- if the code is mostly healthy, say so directly instead of inventing work

## Output Format

Use this exact structure for both direct-use output and mailbox report body:

```markdown
Task: <task_id_or_N/A>
Action: code_health_review_report
From: code-health-reviewer <code_health_reviewer_session_id_or_N/A>
To: <requester_role_or_user> <requester_session_id_or_N/A>
Planner: <planner_session_id_or_N/A>
Round: <round_or_N/A>

## Code Health Assessment
Verdict: [critical / concerning / acceptable]
Scope: [what was reviewed]
Core diagnosis: [1-2 sentence structural judgment]

## Scope Gaps
- [missing context or `None`]

## Primary Signals
- [Signal]: Evidence | Why it matters
If none, write: `- None.`

## Systemic Findings
- [P1] [Area]: Symptom pattern | Structural diagnosis | Why it hurts maintainability or reliability | Recommended direction
- [P2] [Area]: Symptom pattern | Structural diagnosis | Why it hurts maintainability or reliability | Recommended direction
If none, write: `- None.`

## Hotspots
- [Module or boundary]: Why this area keeps attracting churn, bugs, or patch layering
If none, write: `- None.`

## Proof and Testability Gaps
- [Gap]: What cannot currently be proven cheaply | What should change
If none, write: `- None.`

## Suggested Structural Order
1. [First high-leverage correction]
2. [Second safe follow-up]
3. [Optional cleanup after the design issue is fixed]

## Guardrails
- tests or checks that must stay green
- compatibility or behavior boundaries that must remain stable
- rollout cautions if the structural change is broad

## Keep As-Is
- [Area]: Why changing it now is not worth the risk
If none, write: `- None.`

## Open Questions
- [Question]
If none, write: `- None.`
```

## References

- Read `references/signals.md` when judging whether a code smell is local or systemic.
- Read `references/remediation-patterns.md` when proposing structural corrections or sequencing.

## Direct-Use Mode

When invoked directly by the user instead of mailbox workflow:

- use `Task: N/A`
- use `From: code-health-reviewer N/A`
- use `To: user N/A`
- use `Planner: N/A`
- use `Round: N/A`
- return the report directly in the conversation

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> default `N/A`
- `planner_session_id`: explicit -> mailbox body -> default `N/A`
- `code_health_reviewer_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow in Agent Deck mode:
1. review the requested scope
2. produce one advisory `code_health_review_report`
3. use `agent_mailbox`
4. first call `agent_deck_ensure_session` with `session_id = <requester_session_id>`
5. send the report back with `mailbox_send`
   - `from_address = agent-deck/<code_health_reviewer_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "code health review report: <task_id> r<round>"`
   - `body = <code health review report body>`

## Rules

- this skill is review-only
- keep findings concrete and evidence-backed
- name exact modules, boundaries, or repeated patterns
- distinguish structural faults from optional cleanup
- prefer high-leverage conclusions over long laundry lists
- do not recommend a design pattern by name unless it clearly reduces complexity here
- tie every recommendation to maintainability, reliability, or testability
- say explicitly when the code is locally messy but not structurally unhealthy
- do not turn advisory findings into implementation work inside this skill
