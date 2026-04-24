# Prompt Writing Notes

Maintenance notes for writing `SKILL.md` and related workflow prompts.

This file is for prompt authors, not for the executing agent.

## Core Rule

Write the smallest prompt that is still unambiguous at runtime.

Good prompt writing optimizes for all three:
- low token cost
- easy parsing by the model
- low chance of role or workflow confusion

## Checklist

### 1. Write for the real reader

- `SKILL.md` is runtime text for the agent executing that skill now
- do not write from the prompt maintainer's point of view
- do not leave author notes such as:
  - "this file intentionally..."
  - "move this later..."
  - "future cleanup..."
  - "the script below is for planner only"

If a note is for maintainers, put it in `README.md` or another maintenance doc.

### 2. Keep it short, but easier to execute

- prefer short, direct wording
- remove repeated restatements
- prefer one clear rule over several near-duplicates
- use structure, bullets, and light pseudo-code when that makes execution clearer
- do not compress so hard that the runtime path becomes implicit

Good:

```text
recv -> execute action -> send/closeout if required -> ack claimed inbound delivery
```

Bad:

```text
After incorporating the message into working state...
```

That wording is shorter than a full rule, but too vague to execute safely.

### 3. Do not mix protocol with role logic

- shared protocol files define transport, envelope, lifecycle, and common sequencing
- action skills define role-specific business behavior
- requester mailbox bodies should carry task facts and constraints, not the receiver's own prompt

### 4. Do not leak another role's implementation details

- a role should not need to inspect another role's script to decide what to do
- if role A needs runtime guidance, put it in role A's action skill
- do not mention another role's internal script flags unless the current role really executes that script

### 5. Make the normal path explicit

- the default happy path must be obvious
- do not make the agent discover the path by reading `--help`, scanning env vars, or searching the repo first
- write what to do first, then mention fallback exploration only on failure

Good:
- require target session through MCP
- send mailbox
- stop

Bad:
- check `--help`
- inspect env
- read docs
- then maybe send

### 6. Remove false choices

If the workflow only supports one valid strategy, write that strategy directly.

Do not leave room for the agent to improvise between several "possible" options.

### 7. Prefer positive defaults over unnecessary prohibitions

- when a clear positive default is enough, write the default behavior directly
- do not pile on negative constraints unless they prevent a real, observed misunderstanding
- too many "do not ..." rules make prompts noisy and can accidentally suggest the forbidden path
- add a negative constraint only when the positive rule alone has proved insufficient or ambiguous

### 8. Be precise about completion and `ack`

- default rule: `mailbox_ack` only after the message's required workflow action is complete
- when you mean mailbox lifecycle, say `ack claimed inbound delivery`, not just `ack`
- never imply a sender-side `ack` after `mailbox_send`; sender-side completion is `mailbox_send` success
- do not use vague wording such as:
  - "incorporated into working state"
  - "picked up"
  - "processed enough"
- if a specific action has a serialized `ack` point, that action skill should name it precisely

### 9. Respect asynchronous work

- cross-session work is asynchronous and may take unbounded time
- prompts must not imply:
  - active waiting
  - sleep/poll loops
  - speculative closeout
  - "it should finish soon"
- after dispatch, the normal choices are:
  - do independent work
  - or stop

### 10. Protect shared workspace state

- when another agent may still be working in the same workspace, do not tell the current agent to alter that workspace state
- "do not switch branch" is too narrow
- the real rule is: do not change shared workspace state unless this role now owns it

That includes:
- branch state
- file contents
- cleanup that can disrupt another active agent

### 11. Prefer authoritative tools over narrated procedures

- if correctness depends on a script/tool, tell the agent to use that script/tool
- do not describe a loose manual equivalent alongside it
- otherwise the agent may decide its own version is "close enough"

### 12. Avoid duplicated guidance

- one rule should have one owner
- repeated wording across protocol, action skill, mailbox template, and README will drift
- if a rule must be repeated, keep one source authoritative and keep the repeat minimal

Repeated near-duplicates are dangerous because the model may synthesize a third meaning.

### 13. Distinguish runtime docs from maintenance docs

Use runtime docs for:
- execution steps
- runtime constraints
- decision rules
- command/tool invocation

Use maintenance docs for:
- why the prompt is shaped this way
- pitfalls we have seen before
- future cleanup ideas
- authoring guidance

## Common Failure Modes

Before landing a prompt change, check for these:

- Did this text accidentally become maintainer notes instead of runtime instructions?
- Did we make the agent infer a choice that should be fixed by policy?
- Did we duplicate another skill's logic instead of referencing it?
- Did we tell the receiver how another role works internally?
- Did we leave room for active waiting or polling?
- Did we allow the agent to mutate shared workspace state while another agent may still own it?
- Did we describe manual steps where a script/tool should be authoritative?
- Did we make `ack` happen before the workflow action is actually complete?
- Did we create a new place where policy can drift?

## Review Standard

Prompt changes should be reviewed like code:
- ambiguous wording is a bug
- duplicated rules are a bug
- wrong-reader text is a bug
- hidden strategy choice is a bug
- runtime/maintenance leakage is a bug
