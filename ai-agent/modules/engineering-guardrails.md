# Engineering Guardrails (Root-Cause First)

These guardrails apply to all software design and development tasks. The goal is to avoid "make it run first" behavior and prioritize root-cause fixes with verifiable correctness.

## 1) Root Cause First (MUST)

1. Any unexpected state (empty value, `None`, invalid state, assertion failure, invariant violation) is treated as a bug by default.
2. Before root cause is identified, do not:
- Add default-value/fallback logic just to keep execution going
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

## 4) Workflow Discipline (SHOULD)

1. For non-trivial tasks, provide a short plan first; for trivial tasks, execute directly.
2. If assumptions are invalidated or new constraints appear, stop and re-plan.
3. Prefer minimal, focused changes; avoid unrelated edits.

## 5) Simplicity and Scope (SHOULD)

1. Deliver the smallest complete fix first, then optimize.
2. Avoid over-engineering and unrelated abstractions.
3. Prefer fail-fast over silent masking on error paths.

## Default Output Order

1. Root-cause analysis (hypotheses + evidence chain)
2. Root-cause fix (and implementation)
3. Optional temporary mitigation (not implemented unless explicitly approved)
