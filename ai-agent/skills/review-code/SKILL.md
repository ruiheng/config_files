---
name: review-code
description: Reviews code changes for logical correctness, design quality, and security. Use after code has been written to validate implementation quality.
---

# Review Code

Review code changes for logical correctness, design quality, and security. Focus on the "what" and "why"—not syntax.

## Process

This review happens in three steps:

### Step 1: Gather Original Task

Ask the user for the original task description given to the implementer.

Once provided, proceed to Step 2.

### Step 2: Gather Implementation Summary

Ask the user for the implementer's summary of what was done and any relevant notes.

Once provided, proceed to Step 3.

### Step 3: Review the Code

Now perform the review using the gathered context.

## What to Review

- **Logic**: Does it correctly implement the requirements?
- **Design**: Are abstractions appropriate? Is coupling minimized?
- **Security**: Any injection risks, unsafe operations, or data leaks?
- **Edge Cases**: Are boundary conditions handled?
- **Maintainability**: Is the code readable and reasonably self-documenting?

## What NOT to Review

- Syntax validity (linters handle this)
- Style/formatting (formatters handle this)
- Typos in comments/strings

## Output Format

```markdown
### Summary
Brief verdict: [APPROVED / NEEDS_REVISION] with 1-2 sentence rationale.

### Critical Issues
Issues that must be fixed before merge:
- [ ] **[CATEGORY]**: [Description] | Suggestion: [How to fix]

### Design Concerns
Questions or suggestions about architecture/decisions:
- **[Concern]**: [Description] | Suggestion: [Alternative approach]

### Minor Suggestions
Optional improvements:
- [ ] [Description]

### Security Check
- [ ] No injection risks identified
- [ ] No unsafe data exposure
- [ ] Input validation is appropriate

### Verification Questions
Questions for the author (if any):
- [Q1] [Question]
```

## Guidelines

1. Be specific: Point to line numbers or function names when possible
2. Explain why: Don't just say "this is wrong"; explain the problem
3. Suggest fixes: Offer concrete improvements, not just criticism
4. Distinguish severity: Clearly separate blockers from suggestions
5. Assume good intent: Review the code, not the author
6. Stay focused: Don't expand scope—review what was asked, not what could be
