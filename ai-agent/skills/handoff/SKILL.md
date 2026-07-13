---
name: handoff
description: Generates a handoff document from the user's perspective for another AI agent to continue the work. Use when the current conversation needs to end and a new AI agent will take over.
disable-model-invocation: true
---

# Handoff

Generate a handoff message that the user can copy and send to another AI agent. The message should be written from the user's perspective (first person), as if the user is directly telling the new agent what they need to know.

If the user describes what the next session will focus on, tailor the handoff to that goal and omit unrelated context.
Treat the receiving agent as continuing the same working memory across a session boundary, not as auditing an untrusted report. State this continuity model explicitly in the generated handoff.

## Output Format

Generate the following handoff message in first person (as if the user is speaking):

---

Hi, I'm continuing a conversation from another AI agent. Here's what you need to know:

## Continuity Model

I am using this handoff to transfer the previous agent's working memory so you can continue seamlessly, not to request a fresh audit.

- Trust recorded facts, checks, and decisions as you would your own immediately preceding verified context. Do not restart investigation merely because the agent instance changed.
- Re-verify only when I ask, direct evidence conflicts with the handoff, or the next action needs a fresh value from inherently time-sensitive state.
- Treat the mandatory first-reply pause below as an authorization boundary, not a reason to distrust or audit this handoff.

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

## First-Reply Contract (Mandatory)

In your first reply to this handoff, do only these:

1. Confirm your understanding in 3-6 bullet points.
2. List any blocking questions (if none, say "No blocking questions.").
3. End with: "I will wait for your explicit next instruction before taking any action."

Do NOT start implementation, run commands, edit files, or produce a step-by-step execution plan in that first reply.

## What I May Ask You To Do Next (Do Not Execute Yet)

1. **[First priority]** [Likely first task after I confirm]
2. **[Then]** [Likely follow-up task]
3. **[If relevant]** [Optional later task]

## Files/Code We're Working With

- `path/to/file` - [what this file is for in our current work]
- `path/to/another/file` - [its role]

## Suggested Skills

- `[skill-name]` - [why the next agent should use it]

## Open Questions / Decisions Still Needed

- [Any unresolved questions or decisions that need to be made before proceeding]

Follow the continuity model above. Most importantly, after reading this handoff, acknowledge understanding only and wait for my explicit next instruction.

---

## Guidelines

1. **Write in first person as the user** - "I was working on...", "I need you to..."
2. **Be concise but complete** - Capture essential context without overwhelming detail
3. **Include a strict first-reply contract** - The receiving agent must acknowledge and wait, not execute
4. **Include gotchas and pitfalls** - What didn't work, what to avoid
5. **Reference specific files and code locations** - Make it easy to pick up where the previous agent left off
6. **Prioritize current status** - What's in progress, what's blocked, and what may come next
7. **Skip irrelevant history** - Don't summarize work from hours ago unless it directly impacts what to do now
8. **Don't list trivially obtainable info** - Don't include recent commit logs or any information the new agent can easily get with a single command (e.g., `git log`, `git status`). Focus on insights and context that require understanding the work, not just querying the repository state.
9. **Reference existing artifacts** - Don't duplicate content already captured in specs, plans, design decisions, issues, commits, or diffs. Reference it by path or URL instead.
10. **Redact sensitive information** - Remove secrets, credentials, tokens, cookies, personal data, and other sensitive information. Use placeholders when the next agent still needs to understand what was present.
11. **Suggest relevant skills only** - Include skills that materially help the next session. Omit the section when none apply.
12. **Omit empty sections** - Include only sections that carry useful continuation context.
