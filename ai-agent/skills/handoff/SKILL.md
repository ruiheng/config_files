---
name: handoff
description: Generates a handoff document from the user's perspective for another AI agent to continue the work. Use when the current conversation needs to end and a new AI agent will take over.
---

# Handoff

Generate a handoff message that the user can copy and send to another AI agent. The message should be written from the user's perspective (first person), as if the user is directly telling the new agent what they need to know.

## When to Use

- Current conversation token/context limit is approaching
- Switching to a different AI agent or instance
- Ending current session but work needs to continue
- Transferring work to another agent with different capabilities

## Output Format

Generate the following handoff message in first person (as if the user is speaking):

---

Hi, I'm continuing a conversation from another AI agent. Here's what you need to know:

## What We Were Doing

[1-2 sentences describing the current task or goal - what I was trying to accomplish]

## Current Status

**In progress:** [What was being worked on when the previous conversation ended]

**Blocked/Issues:** [Any blockers, problems, or things that weren't working]

**Recently done:** [What was just completed, if relevant to what's next]

## Key Context You Should Know

- [Important technical details, code locations, or architecture info needed to continue]
- [Gotchas, pitfalls, or things that didn't work that you should avoid]
- [Important file paths, function names, or module references]
- [Decisions made and why, if relevant to continuing]

## What I Need You to Do Next

1. **[First priority]** [The immediate next step to take]
2. **[Then]** [What to do after that]
3. **[If relevant]** [Optional follow-up tasks]

## Files/Code We're Working With

- `path/to/file` - [what this file is for in our current work]
- `path/to/another/file` - [its role]

## Open Questions / Decisions Still Needed

- [Any unresolved questions or decisions that need to be made before proceeding]

Treat this document as the ground truth. Do not verify or re-examine the work described unless the user explicitly asks you to. Proceed directly from the stated status and next steps.

---

## Guidelines

1. **Write in first person as the user** - "I was working on...", "I need you to..."
2. **Be concise but complete** - Capture essential context without overwhelming detail
3. **Focus on actionable information** - What does the new agent need to know to continue effectively
4. **Include gotchas and pitfalls** - What didn't work, what to avoid
5. **Reference specific files and code locations** - Make it easy to pick up where the previous agent left off
6. **Prioritize current status** - What's in progress, what's blocked, what's next
7. **Skip irrelevant history** - Don't summarize work from hours ago unless it directly impacts what to do now
8. **Don't list trivially obtainable info** - Don't include recent commit logs or any information the new agent can easily get with a single command (e.g., `git log`, `git status`). Focus on insights and context that require understanding the work, not just querying the repository state.
