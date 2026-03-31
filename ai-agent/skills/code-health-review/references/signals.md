# Signals

Use these signals to decide whether the problem is local cleanup or systemic design trouble.

## Git And History Signals

- repeated bug-fix commits in the same module
- similar commit messages over time: `fix`, `follow-up`, `edge case`, `again`, `hotfix`
- churn concentrated in a few files without clear feature growth
- alternating fixes across neighboring modules or layers
- fixes that repeatedly add guards, fallbacks, or compatibility branches

Interpretation rule:
- treat history as supporting evidence, not proof by itself
- history becomes high-signal when the same area also shows duplicated rules, weak boundaries, or testing pain

## Code Structure Signals

- the same business rule is encoded in multiple condition trees
- the same control-flow shape appears in several modules with renamed helpers or field names
- multiple features rebuild the same pipeline or state transition logic with small parameter changes
- multiple modules reshape the same payload in slightly different ways
- important boundaries pass generic maps, dicts, or loosely-typed blobs
- orchestration, validation, IO, and business rules are mixed together
- modules require knowledge of each other's internal state details
- new branches exist mainly to preserve old broken branches

Interpretation rule:
- repeated decision logic is usually more important than repeated lines
- structural repetition counts even when names, file layout, or helper extraction make the code look different
- if three places solve the same problem with slightly different branch trees, treat that as one ownership failure
- branch-heavy code is not the disease by itself; the disease is often missing ownership or a missing model

## Testability Signals

- narrow unit tests are hard to write because setup is too wide or stateful
- tests depend on large fixtures, extensive mocking, or full-stack integration for basic logic
- regressions recur without focused regression tests being added
- critical invariants are not represented in types, assertions, or helper APIs

Interpretation rule:
- if correctness is expensive to prove, maintenance will stay expensive too
- hard-to-test code often points to bad seams, vague contracts, or mixed responsibilities

## Iteration Signals

- `A -> B -> A` fix/review loops
- `A -> B -> C` symptom drift on a supposedly simple issue
- each fix moves failure to a nearby location instead of removing it
- review rounds keep rediscovering variations of the same rule mismatch

Interpretation rule:
- non-converging or slow-converging work is itself evidence
- when a simple issue takes many rounds, suspect the framing, boundary, or data model

## Synthesis Rule

Prioritize structural diagnosis when multiple signal classes point at the same area:

- churn + repeated bug shape + duplicated logic
- churn + pattern-level repetition + manual sync edits across near-duplicate flows
- patch layering + weak typing + poor testability
- review churn + scattered state rules + unclear ownership

Do not escalate every ugly area into a redesign.
Escalate when the evidence suggests the current structure keeps reproducing the same class of problems.

## Counter-Signals

Be careful not to over-diagnose.
These signals often mean the problem is local or transitional rather than architectural:

- churn is explained by active feature delivery, not repeated bug repair
- fixes converge quickly and stay fixed
- the same module changes often because it is the intended single owner
- tests are narrow and strong even if the code style is imperfect
- complexity is isolated at a real boundary such as protocol translation or compatibility adaptation
- superficially similar code exists for genuinely different invariants or external protocol requirements

Use counter-signals to keep recommendations proportional.
