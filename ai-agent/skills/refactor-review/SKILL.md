---
name: refactor-review
description: Reviews existing code for duplication, unnecessary abstraction, and simplification opportunities, then returns prioritized refactoring advice without making changes.
---

# Refactor Review

Review existing code for duplication, unnecessary abstraction, and simplification opportunities.

This skill is advisory only.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Hard Boundary

- inspect code and surrounding context
- identify duplication, simplification opportunities, and refactoring risks
- suggest changes, sequencing, and guardrails
- do not edit files
- do not apply patches
- do not implement refactors
- do not produce commit-ready diffs unless the user explicitly asks for them later

## Input

Provide one of:
1. the mailbox body from `refactor_review_requested`
2. direct scope + refactoring goal + constraints

Direct-use mode is valid.

## Input Completeness Gate

Before reviewing, verify:
- scope is explicit
- refactoring objective is explicit
- behavior/compatibility constraints are explicit or safely inferred

If critical context is missing:
- in direct-use mode, ask one short clarification question
- in mailbox mode, continue and mark the missing items in `Scope Gaps`

## Review Discipline

Judge code by these principles:

- DRY: repeated logic, branching, data shaping, and tests
- Explicit: intent should be clear without comments compensating for structure
- Simple: prefer direct code over speculative abstraction
- Cohesive: related behavior should live together
- Decoupled: unrelated concerns should change independently
- Present-day: avoid preserving complexity for hypothetical future needs
- No hooks without need: avoid extension points that serve no current requirement

Look for:

- copy-pasted blocks with minor variations
- functions that differ only in literals, field names, or formatting
- long functions mixing orchestration, parsing, validation, IO, and formatting
- repeated condition ladders or switch branches encoding the same rules
- wrappers or helper layers that add indirection without reducing complexity
- generic abstractions that are harder to understand than the concrete cases
- repeated test fixture and assertion patterns
- dead code, stale compatibility shims, and pass-through layers

Prefer:

- deleting duplication before introducing new abstraction
- local consolidation before cross-module frameworking
- concrete helper names over generic utility buckets
- fewer concepts over more flexible concepts
- preserving local style unless it is the problem being reviewed
- leaving code alone when the payoff is weak or the refactor is high-risk

## Output Format

Use this exact structure for both direct-use output and mailbox report body:

```markdown
Task: <task_id_or_N/A>
Action: refactor_review_report
From: refactor-reviewer <refactor_reviewer_session_id_or_N/A>
To: <requester_role_or_user> <requester_session_id_or_N/A>
Planner: <planner_session_id_or_N/A>
Round: <round_or_N/A>

## Refactor Assessment
Verdict: [high / medium / low opportunity]
Scope: [what was reviewed]

## Scope Gaps
- [missing context or `None`]

## Priority Findings
- [P1] [file or symbol]: Problem | Why it hurts changeability | Suggested simplification
- [P2] [file or symbol]: Problem | Why it hurts changeability | Suggested simplification
If none, write: `- None.`

## Consolidation Opportunities
- [Opportunity]: What can be merged, extracted, deleted, or relocated
If none, write: `- None.`

## Keep As-Is
- [Area]: Why refactoring is not worth it yet
If none, write: `- None.`

## Suggested Refactor Order
1. [First safe step]
2. [Second safe step]
3. [Optional follow-up]

## Guardrails
- tests or checks to rely on before touching behavior
- compatibility boundaries that must stay stable
- rollout cautions if the refactor is broad

## Open Questions
- [Question]
If none, write: `- None.`
```

## Direct-Use Mode

When invoked directly by the user instead of mailbox workflow:

- use `Task: N/A`
- use `From: refactor-reviewer N/A`
- use `To: user N/A`
- use `Planner: N/A`
- use `Round: N/A`
- return the report directly in the conversation

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> default `N/A`
- `planner_session_id`: explicit -> mailbox body -> default `N/A`
- `refactor_reviewer_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow in Agent Deck mode:
1. review the requested scope
2. produce one advisory `refactor_review_report`
3. use `agent_mailbox`
4. first call `agent_deck_ensure_session` with `session_id = <requester_session_id>`
5. send the report back with `mailbox_send`
   - `from_address = agent-deck/<refactor_reviewer_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "refactor review report: <task_id> r<round>"`
   - `body = <refactor review report body>`

## Rules

- this skill is review-only
- keep the advice concrete, not generic
- name exact files, symbols, or repeated patterns
- explain why the duplication exists and what change surface it creates
- distinguish structural problems from optional cleanup
- prefer high-leverage suggestions over long laundry lists
- if the code is already reasonably simple, say so directly
- do not turn advisory findings into implementation work inside this skill
- Do not naturally end after drafting the report; this workflow turn is complete only after the required `mailbox_send` back to the requester has succeeded
