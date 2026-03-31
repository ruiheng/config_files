# Remediation Patterns

Use these patterns to recommend structural corrections without over-prescribing implementation details.

## Consolidate Rule Ownership

Use when:
- the same business rule is re-implemented across files
- the same rule is hidden inside several similar workflows
- reviewers keep finding nearby inconsistencies

Preferred correction:
- move rule evaluation to one clear owner
- make other modules consume the result instead of re-deriving it

## Strengthen Data Contracts

Use when:
- generic maps, dicts, or shape-shifting payloads cross important boundaries
- invariants are described in comments but not enforced in code

Preferred correction:
- replace vague containers with explicit types or schemas
- make invalid states harder to construct
- narrow interfaces so callers cannot pass half-formed data

## Separate Orchestration From Domain Logic

Use when:
- one function or module coordinates workflow, performs IO, and also decides business rules
- tests need to boot too much machinery just to check one rule

Preferred correction:
- isolate pure decision logic from effectful plumbing
- make domain behavior callable without full runtime setup

## Remove Patch Layers

Use when:
- each new fix adds guards around an older fix
- legacy branches remain active only because nobody removed the broken path

Preferred correction:
- rewrite the seam instead of stacking more exceptions
- delete obsolete branches after the correct path is established

## Clarify State Transitions

Use when:
- lifecycle rules are spread across unrelated conditionals
- reviewers keep finding missing edge-case transitions

Preferred correction:
- make allowed states and transitions explicit
- centralize transition checks and side effects

## Reduce Change Amplification

Use when:
- one logical change requires touching many modules
- similar edits must be kept in sync manually

Preferred correction:
- collapse duplicated shaping or routing logic
- introduce one stable boundary where change can terminate

## Collapse Pattern Duplication

Use when:
- several modules implement the same algorithmic shape with renamed variables or helper calls
- feature variants differ mainly in data tables, configuration, or one or two branch conditions
- AI-generated code has expanded one concept into many near-duplicate files or functions

Preferred correction:
- extract the shared model, transition, or pipeline owner first
- represent the variation as data, policy inputs, or narrow extension points
- delete the duplicate flows instead of wrapping them in another abstraction layer

## Prefer Subtraction

Use when:
- a recommendation can remove whole branches, helpers, or modules without losing needed behavior
- the current design is hard mainly because too many near-duplicate paths exist

Preferred correction:
- favor solutions that reduce total code and decision count
- explicitly call out which repeated paths should disappear
- treat code deletion as a primary success metric when the resulting owner and interface stay clear

## Improve Proof Surface

Use when:
- important behavior cannot be verified cheaply
- regressions recur because tests are broad, fragile, or missing

Preferred correction:
- create seams that allow focused tests
- add type assertions, invariants, and narrow regression tests around the corrected design

## Recommendation Rule

Prefer recommendations that:

- eliminate a class of failures, not one instance
- simplify ownership and boundaries
- reduce duplicated structure and total decision surface
- reduce future review churn
- make correctness easier to prove

Avoid recommendations that:

- add abstraction without deleting complexity
- preserve several near-duplicate implementations behind a thin shared wrapper
- introduce framework-like indirection for a small local problem
- rename or reshuffle code without changing the failure mode
