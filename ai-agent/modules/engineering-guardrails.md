# Engineering Guardrails (Root-Cause First)

These guardrails apply to all software design and development tasks. The goal is to avoid "make it run first" behavior and prioritize root-cause fixes with verifiable correctness.
They also require reducing duplication at the source, because repeated logic, repeated workflows, and repeated structure are major causes of maintenance cost and review churn.

## 1) Root Cause First (MUST)

1. Any unexpected state (empty value, `None`, invalid state, assertion failure, invariant violation) is treated as a bug by default.
2. Before root cause is identified, do not:
- Add default-value/fallback logic just to keep execution going
- Add non-essential "just in case" guards or backup branches to paper over the failure
- Swallow errors with broad `try/except`
- Silently skip broken branches
3. Provide first:
- Root-cause hypotheses (ranked by likelihood)
- Evidence chain (data source, call path, key logs/code locations)
- Minimal root-cause fix

## 2) Temporary Mitigation Gate (MUST)

1. Fallback/mitigation is allowed only when the user explicitly says: "allow temporary mitigation".
2. Any temporary mitigation must include all of:
- Explicit warning/logging (observable)
- Impact scope
- Rollback/removal plan (when and under what condition it will be removed)
3. Silent mitigation without observability is not allowed.

## 3) Verification Before Done (MUST)

1. Do not claim completion before verification.
2. Provide at least one verifiable proof:
- Test result
- Repro/regression steps
- Key logs
- Before/after behavior comparison

## 4) File Reading Discipline (MUST)

For routine workspace file inspection, use the built-in file-reading tool (`Read`), not `sed` or `awk`; if shell line slicing is truly necessary, use `head -n X | tail -n +Y` instead of `sed -n`.

## 5) File Writing Discipline (MUST)

For routine workspace file creation or overwrite, use the built-in file-writing tool (`Write`), not `cat`.

## 6) Workflow Discipline (SHOULD)

1. For non-trivial tasks, provide a short plan first; for trivial tasks, execute directly.
2. If assumptions are invalidated or new constraints appear, stop and re-plan.
3. Prefer minimal, focused changes; avoid unrelated edits.

## 7) Simplicity and Scope (SHOULD)

1. Deliver the smallest complete fix first, then optimize.
2. Avoid over-engineering and unrelated abstractions.
3. Unless absolutely necessary, prefer fail-fast over fallback-heavy error handling.
4. Do not stack patch on patch; remove the broken path or fix the underlying path instead of layering another workaround on top.

## 8) Duplication Elimination (MUST)

1. Treat duplication as a root-cause signal, not just a style issue.
2. Check duplication at multiple levels:
- literal code duplication
- repeated business rules encoded in different branches or modules
- repeated workflow or pipeline shapes with renamed variables or helper calls
- near-duplicate feature variants that differ only by data, configuration, or one branch
- repeated fallback, compatibility, or patch layers that preserve the same broken design in multiple places
3. Before adding a new branch, helper, module, or adapter, check whether it is re-implementing an existing idea with cosmetic variation.
4. Prefer one clear owner for each rule, transition, or transformation. Other code should consume the result, not re-derive it.
5. Prefer representing variation as explicit data, schema, configuration, or narrow policy input when that removes duplicated control flow.
6. Prefer subtraction over abstraction layering:
- first try deleting duplicate paths by collapsing them into one owner
- do not add a shared wrapper that still leaves several near-duplicate implementations alive underneath
7. Treat net code reduction as a meaningful quality improvement when behavior, clarity, and compatibility are preserved.
8. If the same fix shape appears repeatedly, stop and redesign the boundary, ownership model, or data model instead of applying the same patch again.

## 9) Adaptive Bug Localization (SHOULD)

Choose the cheapest method that can produce high-confidence evidence.

1. Start with fast inspection:
- Repro steps
- Relevant code path walkthrough
- Invariant checks at key state transitions
2. Escalate to instrumentation when needed:
- Multiple plausible causes remain
- Control flow or state is non-obvious (async, retries, caching, concurrency, cross-service boundaries)
- Confidence in root cause is below high confidence
3. Acceptable instrumentation:
- Targeted logs at decision boundaries
- Temporary assertions/checkpoints
- Small repro-focused probes/tests
4. Avoid blind guess-fix loops:
- Do not submit another fix attempt without new evidence from inspection or instrumentation.
5. Keep diagnostics disciplined:
- Scope logs narrowly to the suspected path
- Remove or downgrade temporary debug logs after verification
- Summarize the evidence chain in the final report

## 10) Convergence Discipline (MUST)

Do not treat each new review finding as an isolated local fix request. Repeated fix-review-fix cycles are a signal that the current framing is wrong.

1. Treat the work as non-converging if any of the following happens:
- The same issue, invariant break, or behavior regression reappears after it was "fixed"
- Review feedback alternates between related areas (for example, A then B then A again)
- A seemingly simple issue requires multiple fix/review rounds without reaching a stable state
- The latest fix only moves the failure to a nearby symptom instead of removing the underlying cause
2. When non-convergence is detected, stop the local patch loop and reframe the problem before making another fix:
- Summarize the iteration history in one place: original issue, each attempted fix, what changed, and what regressed
- Identify the shared invariant, boundary, or design assumption behind the repeated symptoms
- Re-examine the broader structure: data flow, ownership, module boundaries, state transitions, and duplicated logic
- Produce a new root-cause hypothesis that explains the full pattern, not just the latest report item
3. Do not continue with another narrow fix unless there is new evidence that the new approach will break the loop.
4. If the issue sequence looks like A -> B -> C rather than A -> B -> A, do not assume this is healthy progress by default; first check whether the work is uncovering one deeper design flaw in slow motion.
5. The correct response to repeated nearby issues is usually simplification or structural correction, not more localized patching.

## 11) Compatibility And Data Migration Gate (MUST)

Do not assume old data, old schemas, or old persisted state must be preserved by default.
Compatibility is a product decision and an environment decision, not an automatic coding reflex.

1. Before adding compatibility logic, determine which case actually applies:
- production or user-owned data that must remain readable
- staged/shared environment data that likely needs migration planning
- local/dev/test temporary data that can be discarded safely
2. Do not add compatibility layers, fallback parsing, dual-read paths, schema shims, or legacy branches until the required compatibility scope is explicit.
3. If compatibility scope is unclear, stop and ask the user which strategy is correct:
- keep backward compatibility
- provide a one-time migration
- drop old data/state and rebuild/reset
4. Prefer the simplest valid strategy:
- if old data is disposable, delete/reset it instead of preserving it
- if migration is required, prefer an explicit migration over permanent compatibility code
- if long-term compatibility is required, define the boundary and keep the compatibility surface narrow
5. In reports and proposals, state explicitly:
- what data/state exists
- whether it is real user/production data or disposable temporary data
- chosen compatibility strategy
- why a more conservative compatibility layer is unnecessary, if you are not preserving it
6. Do not silently preserve low-value legacy paths just because they already exist; unnecessary compatibility code is technical debt and must be justified.

## Default Output Order

1. Root-cause analysis (hypotheses + evidence chain)
2. Root-cause fix (and implementation)
3. Optional temporary mitigation (not implemented unless explicitly approved)
4. Duplication analysis when relevant: what repeated logic, repeated workflow, or repeated structure was removed or consolidated
