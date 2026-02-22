---
name: review-request
description: Generates a review-request document for code review from uncommitted changes, a specific commit, or a branch.
---

# Review Request

Generate a copy/paste-friendly review handoff document for later code review.

## Required Scope Selection

Before generating the document, determine one scope:
1. **Uncommitted changes**
2. **Specific commit**
3. **Branch**

Workflow continuity rule:
- In an ongoing implementation session, if scope is not explicitly provided, inherit the scope of the **most recently completed task in this workflow**.
- The inherited scope can be `uncommitted`, `commit`, or `branch` depending on what was actually delivered.
- Do not force a scope-selection question when one scope is clearly implied by recent workflow context.
- Ask a clarification question only when:
  - multiple scopes are similarly plausible, or
  - no reliable scope can be inferred.

## Inputs

- Scope type: `uncommitted` | `commit` | `branch`
- Scope value:
  - `uncommitted`: no value required
  - `commit`: commit hash
  - `branch`: branch name
- Optional:
  - `base_branch` (for branch scope)
  - `original_task` (free text)
  - `delegate_task_path` (path to `delegate-task-<unique>.md`)
  - `output_path` (default: project root)

## Original Task Source (Required)

Populate `## Original Task` using this priority order:
1. `original_task` input (if explicitly provided)
2. Current session context (the delegated task currently being executed in this agent conversation)
3. `delegate_task_path` (if explicitly provided), extract task objective from that file
4. If none are available, ask one short clarification question before finalizing

Do not default to `Not provided` when delegated-task context is already available in the same workflow.

## Data Collection (Read-Only)

Use read-only git commands only.

- **Uncommitted**:
  - `git status --short`
  - `git diff --name-status`
  - `git diff --cached --name-status`
  - `git ls-files --others --exclude-standard`
- **Commit**:
  - `git show --name-status --format=fuller <commit>`
- **Branch**:
  - Determine comparison base:
    - Use `base_branch` if provided
    - Otherwise prefer `main`; fallback to `master`
  - `git log --oneline <base>..<branch>`
  - `git diff --name-status <base>...<branch>`

## Scope Hygiene and Noise Control (Required)

Before writing the document, classify changes into:
- **In-Scope**: directly related to the original task and intended for this review.
- **Noise/Out-of-Scope**: unrelated local files, scratch artifacts, environment files, temporary outputs, or other incidental working-tree changes.

Rules:
1. In `Files Modified/Created`, include **In-Scope files only**.
2. Do **not** list every unrelated untracked file one by one.
3. For uncommitted scope, summarize unrelated working-tree noise in one short optional section with count + up to 3 examples.
4. If there is uncertainty about relevance, ask a short clarification question before finalizing.

## Output File

Create a file named `review-request-<unique>.md`.
- `<unique>` can be any short unique suffix.
- Default location is project root unless `output_path` is provided.
- If a filename collision occurs, generate a new unique suffix.

## Output Template

Use this exact structure:

```markdown
# Review Request

## Scope
- Type: [uncommitted | commit | branch]
- Target: [working tree | commit hash | branch name]
- Base (if branch): [base branch or N/A]

## Original Task
[Original task text from explicit input or active session context (optionally from `delegate_task_path` if provided). Use `Not provided` only after explicit clarification that no task text is available.]

## Review Focus
- [Primary risk/review angle 1]
- [Primary risk/review angle 2]

## Implementation Summary
[Concise summary of what changed and why]

## Files Modified/Created (In-Scope Only)
- `path/to/file1` - [brief description of changes]
- `path/to/file2` - [brief description of changes]

## Verification Evidence
- Commands/Checks: [tests, type-check, lint, manual checks; if unknown write: Not provided]
- Result Summary: [pass/fail/high-level outcomes; if unknown write: Not provided]
- Coverage Gaps: [known missing tests or validation gaps; if none write: None identified]

## Working Tree Noise Summary (Optional, mostly for uncommitted scope)
- Excluded unrelated items: [count]
- Examples (max 3): [`path/a`, `path/b`]

## Known Issues or Limitations
[Known limitations; if none, write: None identified]
```

## Quality Bar

1. Keep it concise and copy/paste friendly.
2. Use neutral language; avoid chat framing and second-person wording.
3. File list should be complete for the **in-scope review target**, not for all local noise.
4. Prefer factual statements over speculation.
5. Do not dump raw untracked-file inventories unless explicitly requested.
6. Always include `Review Focus` and `Verification Evidence` fields, even when values are `Not provided`.
7. In delegated workflows, `Original Task` should be inherited from active delegated-task context whenever possible.
8. Prefer workflow continuity over re-onboarding questions; avoid asking for scope when recent context already implies the completed task scope.
