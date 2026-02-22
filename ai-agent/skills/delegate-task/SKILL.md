---
name: delegate-task
description: Analyzes a task and produces a structured implementation brief file for another AI agent to execute.
---

# Delegate Task

Analyze the user's task and produce a structured implementation brief file for another AI agent to execute.

## Pre-Output Decomposition Check (Required)

Before generating the final task brief, evaluate whether the request should be split into smaller independent tasks.

Use this quick check:
- Can parts be implemented independently with low coupling?
- Can parts be validated independently with clear acceptance criteria?
- Would splitting reduce risk or enable parallel execution?

If the task is **not worth splitting**, proceed directly to "Output File" and "Brief Format".

If the task **is worth splitting**:
1. Provide a short split recommendation (proposed sub-tasks and why).
2. Ask the user to choose:
   - keep as one delegated task, or
   - split into multiple delegated tasks.
3. Stop and wait for the user's decision.
4. After the user's decision, rerun this skill and generate the final brief in the selected mode.

Do not output the full final brief before the user decision when a split recommendation is made.

## Output File (Required)

Create a file named `delegate-task-<unique>.md`.
- `<unique>` can be any short unique suffix.
- Default location is project root unless `output_path` is provided.
- If a filename collision occurs, generate a new unique suffix.

After writing the file:
- Return only a short confirmation with the file path and a one-line summary.
- Do not print the full brief inline unless the user explicitly asks.

## Brief Format

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
- **NO GIT WRITE OPERATIONS**: Do NOT run git commands that modify repository state (for example: `git add`, `git commit`, `git merge`, `git rebase`, `git reset`, `git checkout`).
- **READ-ONLY GIT IS ALLOWED**: Use read-only git commands only when needed for context (for example: `git status`, `git log`, `git diff --name-only`).
- **ANALYZE BEFORE ACTING**: Read all files in "Read Before Starting" first, then acquire remaining context incrementally as needed.
- **ASK IF UNCLEAR**: Ask clarifying questions if needed.

### Optional Follow-up

If a review handoff document is needed, use the dedicated `review-request` skill. Do not force this step in every delegated task.

### Language Guidelines
- Use English by default for all output, including code comments. Switch to the user's local language only when English becomes a communication barrier.
- Keep business/domain terms in original form (e.g., 白金会员, 代金券)
- Use English for technical terms (e.g., constructor, polymorphism)

---

## Guidelines

1. **Focus on problems, not solutions** - Describe what needs solving, not how
2. **Components are logical groupings** - Not ordered steps
3. **Be specific in criteria** - Concrete, observable outcomes
4. **Language** - English primary; keep business terms in original form
5. **Git boundary** - Forbid git write operations; allow read-only git only when needed for context
6. **Context matters** - Specify mandatory files first, then use incremental context acquisition
7. **Review request is optional** - Use the dedicated `review-request` skill only when a review handoff document is actually needed
8. **Decomposition gate** - If splitting is recommended, pause for user decision and only then produce the final brief
9. **File-first output** - Write the final brief to `delegate-task-<unique>.md`; avoid inline full-text output by default
