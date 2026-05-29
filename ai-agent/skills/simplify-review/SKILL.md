---
name: simplify-review
description: Review code and tests for simplification opportunities without making changes. Use when the goal is to reduce AI-written bloat, repeated local fixes, near-duplicate logic, unnecessary abstraction, dead code, excessive branching, deep nesting, verbose tests, low-value assertions, or tests that freeze incidental development mistakes while preserving behavior and compatibility.
---

# Simplify Review

Find what can be deleted, merged, inlined, or made more direct without changing behavior.

This skill is advisory only. Do not edit files, apply patches, or produce commit-ready diffs unless the user explicitly asks later.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.

## Input

Use one of:
1. mailbox body from `simplify_review_requested`
2. direct scope + simplification goal + behavior constraints

Before reviewing, ensure scope and behavior/compatibility boundaries are explicit or safely inferable. If one critical fact is missing, ask one short question in direct-use mode; in mailbox mode, continue and list it under `Scope Gaps`.

## Review Method

1. Establish the contract.
- What observable behavior must remain stable?
- Which tests, snapshots, APIs, schemas, CLI output, or UI states prove it?
- Is legacy compatibility required, or just preserved by inertia?

2. Hunt repeated knowledge.
- same rule encoded in multiple branches, functions, tests, schemas, mappings, validators, or formatters
- duplicated workflows with renamed variables
- wrappers/adapters/helpers that only rename or forward
- patch layers: guards, fallbacks, shims, and compatibility paths added to avoid fixing ownership

3. Hunt unnecessary shape.
- dead code, unused flags, stale branches, one-call helpers
- generic abstractions before a second real use
- classes/modules that only delegate
- deep nesting that can become guard clauses or data tables
- options, modes, strategies, or config surfaces with one live path

4. Judge test signal.
- Keep tests that protect public contracts, real bugs, edge cases, data loss, security, concurrency, migrations, or compatibility.
- Challenge tests that only assert mock calls, wrapper forwarding, private helper internals, trivial defaults, exact call order, or harmless formatting.
- Merge or delete tests whose assertion is redundant, incidental, or weaker than an existing behavior test.

5. Choose the smallest safe move.
- delete unused/obsolete code first
- inline wrappers that add no meaning
- extract only when live callers share one rule
- move code when ownership is wrong
- represent variation as data when only values differ
- keep apparent duplication when cases are likely to evolve differently

## Decision Rules

- `high`: clear net deletion/consolidation is available and behavior can be protected
- `medium`: simplification is useful but proof or sequencing needs care
- `low`: code is already simple enough, or simplification would risk clarity/behavior
- Prefer net code reduction when behavior, clarity, and compatibility are preserved.
- Prefer one simplification that removes many edit sites over many cosmetic cleanups.
- Do not invent an abstraction just because text repeats; identify the shared rule first.
- Do not delete compatibility code until the compatibility scope is known.
- Do not treat test count as quality; prefer fewer tests with stronger behavioral signal.

## Output Format

Mailbox mode uses the full structure below:

```markdown
Task: <task_id_or_N/A>
Action: simplify_review_report
From: simplify-reviewer <simplify_reviewer_session_id_or_N/A>
To: <requester_role_or_user> <requester_session_id_or_N/A>
Planner: <planner_session_id_or_N/A>
Round: <round_or_N/A>

## Simplification Assessment
Verdict: [high / medium / low opportunity]
Scope: [what was reviewed]
Core judgment: [1-2 sentences]

## Scope Gaps
- [missing context or `None`]

## Best Deletions
- [P1] [file or symbol]: What can be removed | Why behavior is preserved | Proof needed
If none, write: `- None.`

## Best Consolidations
- [P1] [file or symbol]: Repeated knowledge | Suggested owner or shape | Expected reduction in edit sites
If none, write: `- None.`

## Over-Engineering
- [P1] [file or symbol]: Extra concept, flag, wrapper, layer, or branch | Why it is not earning its keep | Suggested simplification
If none, write: `- None.`

## Low-Value Tests
- [P1] [test file or case]: Weak/incidental assertion | Why it does not protect meaningful behavior | Delete, merge, or rewrite direction
If none, write: `- None.`

## Keep As-Is
- [Area]: Why simplifying it now is not worth the risk or would reduce clarity
If none, write: `- None.`

## Suggested Simplification Order
1. [First behavior-preserving deletion/consolidation]
2. [Second safe simplification]
3. [Optional follow-up after proof]

## Guardrails
- tests/checks to run
- compatibility boundaries to preserve
- review cautions for broad or subtle changes

## Open Questions
- [Question]
If none, write: `- None.`
```

Direct-use mode skips the mailbox header block and starts at `## Simplification Assessment`.

## Agent Deck Mode

Follow shared protocol in `agent-deck-workflow/SKILL.md`.

Skill-specific context resolution:
- `task_id`: explicit -> mailbox body -> default `N/A`
- `planner_session_id`: explicit -> mailbox body -> default `N/A`
- `simplify_reviewer_session_id`: explicit -> mailbox body `To` header -> bound mailbox sender context -> ask
- `requester_session_id`: explicit -> mailbox body `From` header -> ask
- `requester_role`: explicit -> mailbox body `From` header -> default `requester`
- `round`: explicit -> mailbox body `Round` header -> default `1`

Execution flow in Agent Deck mode:
1. review the requested scope
2. produce one advisory `simplify_review_report`
3. call `agent_deck_require_session` for the requester session in the current workdir
4. send the report with `mailbox_send`
   - `from_address = agent-deck/<simplify_reviewer_session_id>`
   - `to_address = agent-deck/<requester_session_id>`
   - `subject = "simplify review report: <task_id> r<round>"`
   - `body = <simplify review report body>`

## Rules

- keep advice concrete and evidence-backed
- name exact files, symbols, tests, and repeated patterns
- distinguish shared knowledge from coincidental similarity
- distinguish valuable regression tests from assertion inventory
- prefer deletion, inlining, and consolidation before new abstraction
- say directly when code is already simple enough
