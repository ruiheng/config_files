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

If scope is missing or ambiguous, ask a short clarification question and wait.

## Inputs

- Scope type: `uncommitted` | `commit` | `branch`
- Scope value:
  - `uncommitted`: no value required
  - `commit`: commit hash
  - `branch`: branch name
- Optional:
  - `base_branch` (for branch scope)
  - `original_task` (free text)
  - `output_path` (default: project root)

## Data Collection (Read-Only)

Use read-only git commands only.

- **Uncommitted**:
  - `git status --short`
  - `git diff --name-status`
  - `git diff --cached --name-status`
- **Commit**:
  - `git show --name-status --format=fuller <commit>`
- **Branch**:
  - Determine comparison base:
    - Use `base_branch` if provided
    - Otherwise prefer `main`; fallback to `master`
  - `git log --oneline <base>..<branch>`
  - `git diff --name-status <base>...<branch>`

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
[Original task text if provided; otherwise: Not provided]

## Implementation Summary
[Concise summary of what changed and why]

## Files Modified/Created
- `path/to/file1` - [brief description of changes]
- `path/to/file2` - [brief description of changes]

## Known Issues or Limitations
[Known limitations; if none, write: None identified]
```

## Quality Bar

1. Keep it concise and copy/paste friendly.
2. Use neutral language; avoid chat framing and second-person wording.
3. File list should be complete for the selected scope.
4. Prefer factual statements over speculation.
