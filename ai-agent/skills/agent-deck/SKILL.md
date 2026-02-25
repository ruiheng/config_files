---
name: agent-deck
description: Operate agent-deck sessions safely in a human-led workflow. Use for basic session control, role handoff, and light automation across planner/executor/reviewer.
---

# Agent Deck Basics

Use this skill when tasks involve `agent-deck` session orchestration.
This skill is intentionally conservative: human-led, low-automation, auditable.

## Scope

- Workflow shape: one long-lived `planner`, per-task `executor` + `reviewer`.
- Runtime shape: single shared workspace (no mandatory worktree isolation in this skill).
- Automation level: only low-risk automation; keep user confirmation gates.

## Source of Truth

- Command reference: `references/cli-reference.md`
- Message templates: `references/message-templates.md`
- If command details are uncertain, read that file first and follow it exactly.

## Execution Environment (Required)

All `agent-deck` commands in this skill must be executed outside sandbox (host shell with real tmux/session context).
Do not rely on sandboxed shell execution for `agent-deck` detection or control.

## Operating Principles

1. Human remains the final decision-maker.
2. Do not auto-merge or auto-delete sessions.
3. Prefer file artifacts for long context (`delegate-task`, `review-request`, `review-report`, `closeout`).
4. Use `agent-deck session send` for short control messages and pointers to artifact files.
4.1 Prefer JSON message format from `references/message-templates.md` for machine-readable session coordination.
4.2 Never send artifact body text via `session send`; send pointer-only control messages.
4.3 `session send` payload should be JSON control messages whenever protocol fields are available.
4.4 Prefer `scripts/dispatch-control-message.sh` to collapse multi-step control operations into one command.
5. Keep role boundaries strict:
- `planner`: planning and orchestration
- `executor`: implementation
- `reviewer`: review loop and stop recommendation
6. If host-side `agent-deck session current --json` fails, treat it as missing session context and ask for explicit metadata (`task_id`, `planner_session`).

## Naming and Metadata Convention

Use a stable task id:

`task_id = YYYYMMDD-HHMM-<slug>`

Use it everywhere:

- Executor session: `executor-<task_id>`
- Reviewer session: `reviewer-<task_id>`
- Branch: `task/<task_id>`
- Artifacts directory: `.agent-artifacts/<task_id>/`

Minimum message header fields for cross-session communication:

- `Task-ID`
- `planner_session` (required; immutable per task)
- `From-Session`
- `To-Session`
- `Round` (for review iterations)
- `Action`
- `Artifact-Path` (if applicable)

## Essential Commands

Commonly used commands (see `references/cli-reference.md` for full flags):

```bash
agent-deck list
agent-deck status -v

agent-deck launch . --title "<session>" --group "<group>" --cmd "<tool>" --message "<msg>"
agent-deck session send "<session>" "<message>"
agent-deck session output "<session>"
agent-deck session show "<session>" --json

agent-deck skill list
agent-deck skill attach "<session>" "<skill>" --restart
agent-deck skill attached "<session>"
```

Preferred dispatch helper:

```bash
scripts/dispatch-control-message.sh \
  --task-id "<task_id>" \
  --planner-session "<planner_session>" \
  --to-session "<session>" \
  --action "<action>" \
  --artifact-path "<artifact_path>" \
  --group "<group>" \
  --cmd "<tool>"
```

Path resolution rule:
- Resolve `scripts/dispatch-control-message.sh` relative to this skill directory.

## Human-Led Three-Role Flow (Single Workspace)

### 1) Planner Creates Task and Starts Executor

Planner prepares:

- `.agent-artifacts/<task_id>/delegate-task-<task_id>.md`

Then launch executor:

```bash
agent-deck launch . \
  --title "executor-<task_id>" \
  --group "<group>" \
  --cmd "<tool>" \
  --message "Task-ID: <task_id>. Planner session is <planner_session>. Read and follow .agent-artifacts/<task_id>/delegate-task-<task_id>.md."
```

Notes:

- `<tool>` can be `codex`, `claude`, `gemini`, etc.
- Default tool should be the current agent tool unless user specifies otherwise.

### 2) Executor Preflight Before Coding

Executor should verify tracked workspace cleanliness before branch work:

```bash
git status --porcelain
```

Policy:

- Untracked files are allowed.
- Tracked uncommitted changes are not allowed for task start.

Practical check:

```bash
git status --porcelain | rg -v '^\?\?' || true
```

Then create/switch task branch:

```bash
git switch -c "task/<task_id>" || git switch "task/<task_id>"
```

### 3) Executor Starts Reviewer and Sends Review Request

Executor creates:

- `.agent-artifacts/<task_id>/review-request-r1.md`

Then start reviewer session:

```bash
agent-deck launch . \
  --title "reviewer-<task_id>" \
  --group "<group>" \
  --cmd "<tool>" \
  --message "Task-ID: <task_id>. Read and follow .agent-artifacts/<task_id>/review-request-r1.md. Report findings back to executor-<task_id>."
```

Review loop communication stays file-based (`review-report-rN.md`) with short `session send` pointers.

After executor dispatches `review_requested`:

- Executor enters waiting state.
- Reviewer is responsible for sending the next control message (`rework_required` to executor, or stop recommendation path).
- Executor should not continuously poll reviewer output unless user explicitly asks for a status check.

### 4) Reviewer Loop and Stop

Reviewer drives loop recommendations, but does not finalize without user confirmation.

Suggested stop conditions:

- No `must-fix` issues remain, or
- Iteration cap reached (default max: 3 rounds), or
- Progress stalls in repeated rounds

On stop, reviewer waits for explicit user decision, then follows the corresponding branch.

User-decision branches after stop recommendation:

1. User chooses closeout:
- Reviewer runs `review-closeout` and delivers closeout to planner.

2. User chooses another iteration:
- Reviewer sends a control message to `executor-<task_id>` with action `user_requested_iteration`.
- Executor resumes implementation and later sends a new review request.

### 5) Planner Receives Closeout

Planner receives the closeout first, but must wait for explicit user confirmation before finalizing task closure.

After user confirms acceptance, planner should run one **batch closeout step**:

1. Merge `task/<task_id>` into the integration branch (follow repo/user merge policy).
2. Record task progress (status, merged branch, residual concerns).
3. Plan and dispatch the next task if needed.

## Attach Skills Per Role

Suggested role-skill mapping:

- Planner: `delegate-task`, `handoff`
- Executor: `review-request`
- Reviewer: `review-code`, `review-closeout`

Use:

```bash
agent-deck skill attach "<session>" "<skill>" --restart
```

## Do / Do Not

Do:

- keep artifacts in `.agent-artifacts/<task_id>/`
- include task id in every cross-session message
- use `session output` as a durable handoff source

Do not:

- send large review documents inline in a single `session send`
- auto-merge branches
- run planner closeout batch (merge/progress/next-task) before user confirmation
- keep proactive reviewer-output polling loops after review dispatch
- auto-remove sessions without user confirmation
