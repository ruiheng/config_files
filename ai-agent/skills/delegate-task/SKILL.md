---
name: delegate-task
description: Analyzes a task and produces a structured implementation brief for another AI agent to execute. Also requires the executor to generate a review-request file for later review.
---

# Delegate Task

Analyze the user's task and produce a structured implementation brief for another AI agent to execute.

## Output Format

Generate the following sections:

---

### Objective
One sentence describing the core goal.

### Components to Address
Identify 3-6 logical components. For each:
- **Name**: What this component handles
- **Responsibility**: What it must do
- **Key Question**: The critical question it must answer

### Critical Decisions
List 2-4 key decisions. For each:
- **Decision**: What must be decided
- **Options**: 2-3 viable alternatives
- **Trade-offs**: Brief pros/cons
- **Recommendation**: Your suggestion with reasoning

### Constraints & Risks
- **Hard Constraints**: Non-negotiable limits
- **Key Risks**: What could cause failure
- **Mitigation**: How to detect or avoid

### Context to Acquire
Files and resources to know about, categorized by urgency:

- **Read Before Starting**: Files that must be read before implementation
- **Reference as Needed**: Files to consult during implementation
- **Know It Exists**: Files to be aware of but may not need to read immediately

For each, note what information it contains and why it matters.

### Acceptance Criteria
Specific, testable conditions:
- [ ] Criterion 1: [Specific observable outcome]
- [ ] Criterion 2: [Specific observable outcome]

### Important Notes
- **NO GIT OPERATIONS**: Do NOT run any git commands.
- **ANALYZE BEFORE ACTING**: Read all files in "Context to Acquire" first.
- **ASK IF UNCLEAR**: Ask clarifying questions if needed.

### Post-Completion Requirement

After completing the task, create a file named `review-request-{timestamp}.md` in the project root with the following content:

```markdown
# Review Request

## Original Task
[Paste the original task description here]

## Implementation Summary
[What was done, key decisions made, trade-offs or compromises]

## Files Modified/Created
- `path/to/file1` - [brief description of changes]
- `path/to/file2` - [brief description of changes]

## Known Issues or Limitations
[Anything the reviewer should be aware of]
```

### Language Guidelines
- Use English for all output, including code comments
- Keep business/domain terms in original form (e.g., 白金会员, 代金券)
- Use English for technical terms (e.g., constructor, polymorphism)

---

## Guidelines

1. **Focus on problems, not solutions** - Describe what needs solving, not how
2. **Components are logical groupings** - Not ordered steps
3. **Be specific in criteria** - Concrete, observable outcomes
4. **Language** - English primary; keep business terms in original form
5. **Git prohibition** - Include clear no-git instruction
6. **Context matters** - Specify files to read before starting
7. **Review request** - Executor must generate review-request-{timestamp}.md file after completion
