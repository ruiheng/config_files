---
name: delegate-task
description: Use for non-trivial implementation tasks that require meaningful code changes.
---

# Delegate Task

Create one concise, execution-ready mailbox message for another AI agent.

Workflow protocol baseline is defined by `agent-deck-workflow/SKILL.md`.
This skill only defines delegate-task-specific behavior.

Use this skill only when delegation is justified. Default bias is not to delegate.
If the task is simple, mostly mechanical, or documentation-only, do the work directly instead of invoking this skill.

## 1) Quick Check (Required)

Before drafting the delegate message:
- Reject delegation immediately when any of these are true:
  - task is pure documentation, wording, summarization, or other non-code work
  - task is a small or obvious code change that one agent can complete directly with low risk
  - task is mostly file reading, inspection, or answering questions
  - expected code change is narrow enough that splitting adds overhead instead of reducing risk
- Delegate only when all of these are true:
  - task requires meaningful code modification, not just docs or prompts
  - task has enough complexity, scope, or validation burden that a separate coder is useful
  - delegated execution creates a clearer ownership boundary or lowers delivery risk
- Check whether splitting is useful:
  - components can be implemented independently
  - components can be validated independently
  - split reduces risk
- If delegation is not clearly worthwhile, do the work directly
- If splitting is recommended, ask user to choose:
  - keep one delegated task, or
  - split into multiple delegated tasks
- Wait for user decision before sending

Execution mode gates:
- Unless there is explicit evidence parallel execution is safe, use serial mode
- In serial mode, if one delegated task is in progress, wait for closeout before generating/sending the next task
- In serial mode, handle only the current next sub-task

## 2) Output Mode

Keep the delegate brief directly in the mailbox body.

Agent Deck mode:
- Follow shared rules in `agent-deck-workflow/SKILL.md`
- Skill-specific planner identity rule:
  - delegate creator is planner sender
  - `planner_session_id` is expected to equal detected `current_session_id`
  - if explicit/context planner id conflicts with detected current session id, ask user to confirm before sending
  - resolve `current_session_id` once and reuse it for the whole delegate-task turn

Resolve by priority:
- `task_id`: explicit -> context -> generate `YYYYMMDD-HHMM-<slug>`
- `planner_session_id`: detected current session id -> explicit -> context -> ask
- `start_branch`: detected current git branch when delegation begins -> explicit -> context -> ask
- `integration_branch`: explicit -> context -> if `start_branch` is the intended landing line for this delegated change, use `start_branch`; otherwise infer from explicit user intent or a high-confidence tracked/base branch for `start_branch`; if confidence is low, ask rather than guessing
  - never assume `main`/`master`; branch names are evidence, not truth
- `coder_session_ref`: explicit -> context -> default `coder-<task_id>`
- `coder_session_id`: explicit actual id -> context actual id -> helper output after target resolution -> omit until known
- `reviewer_session_ref`: explicit -> context -> default `reviewer-<task_id>`
- `reviewer_session_id`: explicit actual id -> context actual id -> omit until known
- `task_branch`: explicit -> context -> if `start_branch` is already the intended topic branch for this delegated change, reuse `start_branch`; otherwise default `task/<task_id>` created from `integration_branch`
  - in the normal merge-based workflow, `task_branch` must differ from `integration_branch`
- `coder_tool`: explicit -> context -> default current AI tool
  - if user/context provides a full command with arguments, preserve it unchanged
  - if it resolves to provider-only `claude`, normalize to `claude --model sonnet --permission-mode acceptEdits`
  - if it resolves to provider-only `codex`, normalize to `codex --model gpt-5.4 --ask-for-approval on-request`
  - if it resolves to provider-only `gemini`, normalize to `gemini --model gemini-2.5-pro`
- `reviewer_tool`: explicit -> context -> default `codex --model gpt-5.4 --ask-for-approval on-request`
  - if user/context provides a full reviewer command with arguments, preserve it unchanged
  - `reviewer_tool` selects how the reviewer session is created/resumed; it does not collapse reviewer role into the current planner/coder session
  - if planner/coder and reviewer all use Codex, still keep `reviewer_session_ref` distinct unless same-session reviewer assignment is explicitly requested in workflow context
- `workflow_policy` (optional): explicit -> context -> omit when not set
- `special_requirements` (optional fallback): explicit -> context -> extract user constraints not represented by existing structured fields -> omit when empty

## 3) Mailbox Body Template

Use this structure:

```markdown
Task: <task_id>
Action: execute_delegate_task
From: planner <planner_session_id>
To: coder {{TO_SESSION_ID}}
Planner: <planner_session_id>
Round: 1

## Summary
[One-line objective summary]

## Objective
[One sentence]

## Components to Address
- [component]: [responsibility] | Key question: [...]

## Critical Decisions
- [decision]: Options / trade-offs / recommendation

## Branch Plan
- Start branch: [start_branch]
- Integration branch: [integration_branch]
- Task branch: [task_branch]
- Rationale: [why dedicated task branch vs reused topic branch]

## Constraints & Risks
- [hard constraint / risk / mitigation]

## Context to Acquire
- Read before starting: [...]
- Reference as needed: [...]
- Know it exists: [...]

## Acceptance Criteria
- [testable completion item]

## Important Notes
- Coder git writes for this delegated task are pre-authorized
- Coder must follow the recorded branch plan and must not invent a different working branch
- After first delivery commit, coder runs `review-request` unless user waives review
- Matching provider names do not merge roles: "reviewer uses codex" means use/create the recorded `reviewer_session_ref` with a Codex command unless workflow context explicitly says planner and reviewer are the same session

## Agent Deck Context
- Planner session: [planner_session_id]
- Coder session ref: [coder_session_ref]
- Coder session id: {{TO_SESSION_ID}}
- Reviewer session ref: [reviewer_session_ref]
- Coder tool: [coder_tool]
- Reviewer tool: [reviewer_tool]

## Workflow Policy
[only when present]

## Special Requirements
[only when present]
```

Tool-routing rule:
- If user specifies a full coder/reviewer command, persist it unchanged in the message body
- If user specifies only provider preference (for example `claude`, `codex`, `gemini`), persist the normalized full command with recommended arguments

## 4) Mailbox Send + Wakeup (When Agent Deck Mode Is On)

Preferred path: use the installed helper `adwf-send-and-wake`.

Workflow send sequence:
1. compose the body with `{{TO_SESSION_ID}}` placeholders where the real coder session id must appear
2. run `adwf-send-and-wake` outside sandbox:
   - `--from-session-id "<planner_session_id>"`
   - `--to-session-ref "<coder_session_ref>"`
   - `--ensure-target-title "<coder_session_ref>"`
   - `--ensure-target-cmd "<coder_tool>"`
   - `--parent-session-id "<planner_session_id>"`
   - `--subject "delegate: <task_id> -> coder"`
   - `--body-file -`
3. let the helper resolve the coder session, `agent-deck launch` a missing target directly into `check-workflow-mail wait=True`, or nudge the existing active session after mailbox send
4. use the helper result as the authoritative `coder_session_id` in user-facing status

Exact command shape:

```bash
adwf-send-and-wake \
  --from-session-id "<planner_session_id>" \
  --to-session-ref "<coder_session_ref>" \
  --ensure-target-title "<coder_session_ref>" \
  --ensure-target-cmd "<coder_tool>" \
  --parent-session-id "<planner_session_id>" \
  --subject "delegate: <task_id> -> coder" \
  --body-file - \
  --json
```

Codex-style execution rule:
- launch `adwf-send-and-wake ... --body-file -` in a background terminal / PTY session
- then write the composed delegate body to that session's stdin
- keep freshly generated body in stdin
- feed stdin directly, without `printf`, `cat`, heredoc, shell pipes, or redirection

Recommended subject:
- `delegate: <task_id> -> coder`

Rules:
- keep the full delegate brief in mailbox body
- use `coder-<task_id>` and `reviewer-<task_id>` as session refs until the helper resolves real session ids
- use the exact command shape above when it already matches the task
- report target readiness only after the helper completes the full launch-or-detect/send/nudge path that applies
- `--cmd` only matters when creating a missing target session; existing sessions keep their original tool command

## 5) User-Facing Output Contract

After sending:
- Return short confirmation:
  - mailbox subject
  - one-line objective summary
  - selected `task_branch` / `integration_branch`
  - selected `coder_session_id` / `reviewer_session_ref`
  - selected `coder_tool` / `reviewer_tool`
  - recipient inbox address (`agent-deck/<coder_session_id>`)
  - listener/send/nudge summary
- Keep raw mailbox JSON internal unless user explicitly asks
- If listener/send fails, report stderr summary and include shared diagnostics checklist from `agent-deck-workflow/SKILL.md`
