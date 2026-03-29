#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Planner closeout batch with strict required-action ordering.

Required actions (hard-fail):
1) merge task branch into integration branch
2) update planner progress record

Optional actions (soft-fail):
- prune stale task branches
- dispatch next task command
- desktop notifications
- post-closeout health gate and disposable worker cleanup

Usage:
  planner-closeout-batch.sh [options]

Options:
  --task-id <id>                   Required task id (YYYYMMDD-HHMM-<slug>)
  --task-branch <ref>              Task branch (default: task/<task_id>; pass explicitly when reusing an existing topic branch)
  --integration-branch <ref>       Integration branch (default: current branch; planner should normally pass the branch resolved at delegate start)
  --artifact-root <path>           Artifact root (default: .agent-artifacts)
  --progress-file <path>           Progress jsonl path (default: <artifact-root>/workflow-progress/progress.jsonl)
  --planner-session-id <id|title>  Planner session ref (default: current agent-deck session id)
  --coder-session-id <id|title>    Coder session ref (default: coder-<task_id>)
  --reviewer-session-id <id|title> Reviewer session ref (default: reviewer-<task_id>)
  --architect-session-id <id|title> Architect session ref (default: architect-<task_id>)
  --profile <name>                 Agent-deck profile (used by optional health gate)
  --max-worker-sessions <n>        Max allowed lingering active task-scoped worker sessions in this workspace for health gate (default: 2)
  --merge-mode <mode>              ff-only|ff|no-ff (default: ff-only)
  --allow-dirty                    Allow dirty git worktree (default: false)
  --run-prune                      Run prune-task-branches.sh after required actions
  --prune-apply                    Apply deletion when --run-prune is set (default: dry-run)
  --run-health-gate                Run closeout-health-gate.sh after required actions
  --skip-health-gate               Skip closeout-health-gate.sh
  --next-dispatch-cmd <command>    Optional command executed after required actions
  -h, --help                       Show help

State/outputs:
  - Appends one json line to progress file when required actions complete.
  - Writes per-task idempotency state:
      <artifact-root>/workflow-progress/closeout-state-<task_id>.json

Exit codes:
  0: required actions completed (optional actions may fail but are reported)
  2: usage/dependency/runtime precondition error
  3: required merge/progress action failed
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

required_fail() {
  echo "REQUIRED_ACTION_FAILED: $*" >&2
  exit 3
}

warn() {
  echo "WARN: $*" >&2
}

resolve_current_session_id() {
  local current_json current_id
  current_json="$(agent-deck session current --json 2>/dev/null || true)"
  current_id="$(jq -r '.id // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_id" ]] || die "failed to resolve current agent-deck session id; pass --planner-session-id"
  echo "$current_id"
}

debug() {
  if [[ "${ADWF_DEBUG:-0}" == "1" ]]; then
    echo "DEBUG: $*" >&2
  fi
}

task_id=""
task_branch=""
integration_branch=""
artifact_root=".agent-artifacts"
progress_file=""
planner_session_ref=""
coder_session_ref=""
reviewer_session_ref=""
architect_session_ref=""
profile=""
max_worker_sessions=2
merge_mode="ff-only"
allow_dirty=0
integration_branch_source="inferred_current_branch"
run_prune=0
prune_apply=0
run_health_gate=1
next_dispatch_cmd=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="${2:-}"; shift 2 ;;
    --task-branch) task_branch="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; integration_branch_source="explicit"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --progress-file) progress_file="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --coder-session-id) coder_session_ref="${2:-}"; shift 2 ;;
    --reviewer-session-id) reviewer_session_ref="${2:-}"; shift 2 ;;
    --architect-session-id) architect_session_ref="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --max-worker-sessions) max_worker_sessions="${2:-}"; shift 2 ;;
    --merge-mode) merge_mode="${2:-}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift 1 ;;
    --run-prune) run_prune=1; shift 1 ;;
    --prune-apply) prune_apply=1; shift 1 ;;
    --run-health-gate) run_health_gate=1; shift 1 ;;
    --skip-health-gate) run_health_gate=0; shift 1 ;;
    --next-dispatch-cmd) next_dispatch_cmd="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$task_id" ]] || die "--task-id is required"
[[ "$max_worker_sessions" =~ ^[0-9]+$ ]] || die "--max-worker-sessions must be a non-negative integer"

case "$merge_mode" in
  ff-only|ff|no-ff) ;;
  *) die "--merge-mode must be one of: ff-only|ff|no-ff" ;;
esac

if (( prune_apply == 1 && run_prune == 0 )); then
  die "--prune-apply requires --run-prune"
fi

if [[ -z "$task_branch" ]]; then
  task_branch="task/${task_id}"
fi
if [[ -z "$progress_file" ]]; then
  progress_file="${artifact_root%/}/workflow-progress/progress.jsonl"
fi
if [[ -z "$coder_session_ref" ]]; then
  coder_session_ref="coder-${task_id}"
fi
if [[ -z "$reviewer_session_ref" ]]; then
  reviewer_session_ref="reviewer-${task_id}"
fi
if [[ -z "$architect_session_ref" ]]; then
  architect_session_ref="architect-${task_id}"
fi

command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
if [[ -z "$planner_session_ref" ]]; then
  command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required to infer planner session id; pass --planner-session-id"
  planner_session_ref="$(resolve_current_session_id)"
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "must run inside a git repository"
fi

if [[ -z "$integration_branch" ]]; then
  integration_branch="$(git symbolic-ref --quiet --short HEAD || true)"
fi
[[ -n "$integration_branch" ]] || die "failed to resolve current branch; pass --integration-branch"

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
[[ "$task_branch" != "$integration_branch" ]] || die "--task-branch must differ from integration branch"
task_scoped_integration_branch=0
if [[ "$integration_branch" == task/* && "$integration_branch" != "$task_branch" ]]; then
  task_scoped_integration_branch=1
  if [[ "$integration_branch_source" == "inferred_current_branch" ]]; then
    die "refusing implicit task-scoped integration branch '${integration_branch}' for task branch '${task_branch}'; pass the recorded --integration-branch explicitly"
  fi
  warn "task-scoped integration branch recorded explicitly: integration=${integration_branch} task_branch=${task_branch}"
fi

git rev-parse --verify "$integration_branch" >/dev/null 2>&1 || die "integration branch does not exist: $integration_branch"
git rev-parse --verify "$task_branch" >/dev/null 2>&1 || die "task branch does not exist: $task_branch"

if (( allow_dirty == 0 )); then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "dirty worktree/index; commit or stash first (or pass --allow-dirty)"
  fi
fi

started_branch="${current_branch:-detached}"
switched_integration_branch=0
if [[ "$current_branch" != "$integration_branch" ]]; then
  echo "auto_switch_integration_branch from=${started_branch} to=${integration_branch}"
  set +e
  switch_output="$(git switch "$integration_branch" 2>&1)"
  switch_rc=$?
  set -e
  if (( switch_rc != 0 )); then
    echo "$switch_output" >&2
    die "failed to switch from '${started_branch}' to integration branch '${integration_branch}'"
  fi
  echo "$switch_output"
  switched_integration_branch=1
  current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
  [[ "$current_branch" == "$integration_branch" ]] || die "branch switch reported success but current branch is '${current_branch:-detached}', expected '${integration_branch}'"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
notify_script="${script_dir}/notify-workflow-event.sh"
prune_script="${script_dir}/prune-task-branches.sh"
health_gate_script="${script_dir}/closeout-health-gate.sh"

notify_event() {
  local event="$1"
  local severity="$2"
  local title="$3"
  local message="$4"
  if [[ -x "$notify_script" ]]; then
    "$notify_script" \
      --event "$event" \
      --task-id "$task_id" \
      --title "$title" \
      --message "$message" \
      --severity "$severity" \
      --artifact-root "$artifact_root" >/dev/null 2>&1 || true
  fi
}

mkdir -p "$(dirname "$progress_file")"
state_file="${artifact_root%/}/workflow-progress/closeout-state-${task_id}.json"
mkdir -p "$(dirname "$state_file")"

debug "required.start task_id=${task_id} integration=${integration_branch} task_branch=${task_branch} merge_mode=${merge_mode}"
notify_event \
  "planner_closeout_start" \
  "info" \
  "Planner closeout started: ${task_id}" \
  "Required actions started on ${integration_branch} <- ${task_branch}."

merge_cmd=(git merge)
case "$merge_mode" in
  ff-only) merge_cmd+=(--ff-only "$task_branch") ;;
  ff) merge_cmd+=(--ff "$task_branch") ;;
  no-ff) merge_cmd+=(--no-ff "$task_branch") ;;
esac

set +e
merge_output="$("${merge_cmd[@]}" 2>&1)"
merge_rc=$?
set -e
if (( merge_rc != 0 )); then
  notify_event \
    "planner_closeout_required_fail" \
    "error" \
    "Planner closeout failed: ${task_id}" \
    "Required merge failed on ${integration_branch} <- ${task_branch}."
  echo "$merge_output" >&2
  required_fail "merge failed integration='${integration_branch}' task_branch='${task_branch}'"
fi

merged_sha="$(git rev-parse HEAD)"
echo "$merge_output"

progress_record="$(jq -nc \
  --arg task_id "$task_id" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg integration_branch "$integration_branch" \
  --arg task_branch "$task_branch" \
  --arg integration_branch_source "$integration_branch_source" \
  --arg started_branch "$started_branch" \
  --arg merged_sha "$merged_sha" \
  --arg status "required_complete" \
  --argjson switched_integration_branch "$switched_integration_branch" \
  --argjson task_scoped_integration_branch "$task_scoped_integration_branch" \
  '{
    task_id: $task_id,
    timestamp: $timestamp,
    status: $status,
    started_branch: $started_branch,
    integration_branch: $integration_branch,
    task_branch: $task_branch,
    integration_branch_source: $integration_branch_source,
    task_scoped_integration_branch: $task_scoped_integration_branch,
    merged_sha: $merged_sha,
    closeout_source: "mailbox_message",
    switched_integration_branch: $switched_integration_branch
  }'
)"

if [[ -f "$state_file" ]] && jq -e --arg merged_sha "$merged_sha" '.required_actions.progress_updated == true and .required_actions.merged_sha == $merged_sha' "$state_file" >/dev/null 2>&1; then
  debug "progress.skip reason=state_idempotent state_file=${state_file}"
else
  printf '%s\n' "$progress_record" >>"$progress_file" || required_fail "failed to append progress record to ${progress_file}"
fi

prune_status="skipped"
health_gate_status="skipped"
next_dispatch_status="skipped"
optional_fail_count=0

if (( run_prune )); then
  if [[ -x "$prune_script" ]]; then
    prune_cmd=("$prune_script")
    if (( prune_apply )); then
      prune_cmd+=(--apply)
    fi
    set +e
    prune_output="$("${prune_cmd[@]}" 2>&1)"
    prune_rc=$?
    set -e
    echo "$prune_output"
    if (( prune_rc == 0 )); then
      prune_status="ok"
    else
      prune_status="failed"
      optional_fail_count=$((optional_fail_count + 1))
      warn "optional prune failed rc=${prune_rc}"
    fi
  else
    prune_status="missing_script"
    optional_fail_count=$((optional_fail_count + 1))
    warn "optional prune script missing: ${prune_script}"
  fi
fi

if (( run_health_gate )); then
  if [[ -x "$health_gate_script" ]]; then
    health_cmd=(
      "$health_gate_script"
      --task-id "$task_id"
      --planner-session-id "$planner_session_ref"
      --coder-session-id "$coder_session_ref"
      --reviewer-session-id "$reviewer_session_ref"
      --architect-session-id "$architect_session_ref"
      --artifact-root "$artifact_root"
      --max-worker-sessions "$max_worker_sessions"
    )
    if [[ -n "$profile" ]]; then
      health_cmd+=(--profile "$profile")
    fi
    set +e
    health_output="$("${health_cmd[@]}" 2>&1)"
    health_rc=$?
    set -e
    echo "$health_output"
    if (( health_rc == 0 )); then
      health_gate_status="ok"
    else
      health_gate_status="failed"
      optional_fail_count=$((optional_fail_count + 1))
      warn "optional health gate failed rc=${health_rc}"
    fi
  else
    health_gate_status="missing_script"
    optional_fail_count=$((optional_fail_count + 1))
    warn "optional health gate script missing: ${health_gate_script}"
  fi
fi

if [[ -n "$next_dispatch_cmd" ]]; then
  set +e
  next_output="$(bash -lc "$next_dispatch_cmd" 2>&1)"
  next_rc=$?
  set -e
  echo "$next_output"
  if (( next_rc == 0 )); then
    next_dispatch_status="ok"
  else
    next_dispatch_status="failed"
    optional_fail_count=$((optional_fail_count + 1))
    warn "optional next-dispatch command failed rc=${next_rc}"
  fi
fi

tmp_state="$(mktemp)"
jq -nc \
  --arg task_id "$task_id" \
  --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg started_branch "$started_branch" \
  --arg integration_branch "$integration_branch" \
  --arg task_branch "$task_branch" \
  --arg integration_branch_source "$integration_branch_source" \
  --arg progress_file "$progress_file" \
  --arg merged_sha "$merged_sha" \
  --arg merge_mode "$merge_mode" \
  --argjson switched_integration_branch "$switched_integration_branch" \
  --argjson task_scoped_integration_branch "$task_scoped_integration_branch" \
  --arg prune_status "$prune_status" \
  --arg health_gate_status "$health_gate_status" \
  --arg next_dispatch_status "$next_dispatch_status" \
  --argjson optional_fail_count "$optional_fail_count" \
  '{
    task_id: $task_id,
    updated_at: $updated_at,
    started_branch: $started_branch,
    integration_branch: $integration_branch,
    task_branch: $task_branch,
    integration_branch_source: $integration_branch_source,
    task_scoped_integration_branch: $task_scoped_integration_branch,
    closeout_source: "mailbox_message",
    progress_file: $progress_file,
    required_actions: {
      switched_integration_branch: $switched_integration_branch,
      merge_mode: $merge_mode,
      merge_completed: true,
      merged_sha: $merged_sha,
      progress_updated: true
    },
    optional_actions: {
      prune: $prune_status,
      health_gate: $health_gate_status,
      next_dispatch: $next_dispatch_status
    },
    optional_fail_count: $optional_fail_count
  }' >"$tmp_state"
mv "$tmp_state" "$state_file"

if (( optional_fail_count > 0 )); then
  notify_event \
    "planner_closeout_required_ok_optional_warn" \
    "warn" \
    "Planner closeout required actions done: ${task_id}" \
    "Required actions succeeded; ${optional_fail_count} optional action(s) failed."
  echo "planner_closeout_ok_with_optional_warn task_id=${task_id} state=${state_file} optional_fail_count=${optional_fail_count}"
  exit 0
fi

notify_event \
  "planner_closeout_ok" \
  "info" \
  "Planner closeout completed: ${task_id}" \
  "Required and optional actions completed."
echo "planner_closeout_ok task_id=${task_id} state=${state_file} optional_fail_count=0"
exit 0
