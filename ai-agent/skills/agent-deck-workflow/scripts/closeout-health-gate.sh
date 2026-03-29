#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Closeout health gate for agent-deck workflow.

This script runs one-shot post-closeout checks with minimal agent-side orchestration:
1) archive+cleanup coder/reviewer/architect sessions
2) verify cleanup result for this task
3) verify global worker-session cap (to prevent unattended error accumulation)

Usage:
  closeout-health-gate.sh [options]

Options:
  --task-id <id>                 Required task id (YYYYMMDD-HHMM-<slug>)
  --planner-session-id <id|title>   Planner session ref (default: current agent-deck session id)
  --coder-session-id <id|title>     Coder session ref (default: coder-<task_id>)
  --reviewer-session-id <id|title>  Reviewer session ref (default: reviewer-<task_id>)
  --architect-session-id <id|title> Architect session ref (default: architect-<task_id>)
  --artifact-root <path>         Artifact root (default: .agent-artifacts)
  --profile <name>               Agent-deck profile
  --max-worker-sessions <n>      Max allowed lingering active task-scoped worker sessions in this workspace (default: 2)
  --strict                       Fail-closed mode. Exit 3 when health gate fails.
  -h, --help                     Show help

Outputs:
  - Summary lines for cleanup and gate result.

Exit codes:
  0: health passed, or health failed in non-strict mode
  2: usage/argument/runtime dependency error
  3: health failed in strict mode

Recommendation:
  - Use --strict for unattended workflow mode.
  - Set ADWF_DEBUG=1 for diagnostic logs.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

debug() {
  if [[ "${ADWF_DEBUG:-0}" == "1" ]]; then
    echo "DEBUG: $*" >&2
  fi
}

resolve_current_session_id() {
  local current_json current_id
  current_json="$(agent-deck session current --json 2>/dev/null || true)"
  current_id="$(jq -r '.id // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_id" ]] || die "failed to resolve current agent-deck session id; pass --planner-session-id"
  echo "$current_id"
}

task_id=""
planner_session_ref=""
coder_session_ref=""
reviewer_session_ref=""
architect_session_ref=""
artifact_root=".agent-artifacts"
profile=""
max_worker_sessions=2
strict=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --coder-session-id) coder_session_ref="${2:-}"; shift 2 ;;
    --reviewer-session-id) reviewer_session_ref="${2:-}"; shift 2 ;;
    --architect-session-id) architect_session_ref="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --max-worker-sessions) max_worker_sessions="${2:-}"; shift 2 ;;
    --strict) strict=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$task_id" ]] || die "--task-id is required"
[[ "$max_worker_sessions" =~ ^[0-9]+$ ]] || die "--max-worker-sessions must be a non-negative integer"

if [[ -z "$coder_session_ref" ]]; then
  coder_session_ref="coder-${task_id}"
fi
if [[ -z "$reviewer_session_ref" ]]; then
  reviewer_session_ref="reviewer-${task_id}"
fi
if [[ -z "$architect_session_ref" ]]; then
  architect_session_ref="architect-${task_id}"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq is required"
if [[ -z "$planner_session_ref" ]]; then
  planner_session_ref="$(resolve_current_session_id)"
fi

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

count_worker_sessions() {
  local workspace_path="$1"
  local list_json
  list_json="$(ad list --json 2>/dev/null || true)"
  if [[ -z "$list_json" ]]; then
    echo "-1"
    return 0
  fi
  jq -r --arg workspace_path "$workspace_path" '
    if type != "array" then
      -1
    else
      [
        .[]
        | select(
            ((.title // "") | test("^(coder|reviewer|architect)-[0-9]{8}-[0-9]{4}-"))
            and (.path // "") == $workspace_path
            and ((.status // "") | test("^(running|waiting|idle)$"))
          )
      ] | length
    end
  ' <<<"$list_json" 2>/dev/null || echo "-1"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cleanup_script="${script_dir}/archive-and-remove-task-sessions.sh"
[[ -x "$cleanup_script" ]] || die "cleanup script not found or not executable: $cleanup_script"
notify_script="${script_dir}/notify-workflow-event.sh"

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

cleanup_cmd=(
  "$cleanup_script"
  --task-id "$task_id"
  --planner-session-id "$planner_session_ref"
  --coder-session-id "$coder_session_ref"
  --reviewer-session-id "$reviewer_session_ref"
  --architect-session-id "$architect_session_ref"
  --artifact-root "$artifact_root"
  --apply
)
if [[ -n "$profile" ]]; then
  cleanup_cmd+=(--profile "$profile")
fi

set +e
debug "cleanup_cmd=${cleanup_cmd[*]}"
cleanup_output="$("${cleanup_cmd[@]}" 2>&1)"
cleanup_rc=$?
set -e
echo "$cleanup_output"

archive_file="${artifact_root%/}/${task_id}/session-archive-${task_id}.json"
blocked_count=0
delete_failed_count=0
residual_count=0
archive_exists=false

if [[ -f "$archive_file" ]]; then
  archive_exists=true
  blocked_count="$(jq -r '[.sessions[]? | select(.delete_status == "blocked_missing_provider_session_id")] | length' "$archive_file" 2>/dev/null || echo 0)"
  delete_failed_count="$(jq -r '[.sessions[]? | select(.delete_status == "delete_failed")] | length' "$archive_file" 2>/dev/null || echo 0)"
  residual_count="$(jq -r '[.sessions[]? | select(.found == true and (.delete_status != "deleted" and .delete_status != "not_found" and .delete_status != "skipped_non_disposable_session"))] | length' "$archive_file" 2>/dev/null || echo 0)"
fi

workspace_path="$(pwd -P)"
worker_session_count="$(count_worker_sessions "$workspace_path")"

health_ok=true
failure_reasons=()

if (( cleanup_rc != 0 )); then
  health_ok=false
  failure_reasons+=("cleanup_exit_${cleanup_rc}")
fi
if [[ "$archive_exists" != "true" ]]; then
  health_ok=false
  failure_reasons+=("archive_missing")
fi
if (( blocked_count > 0 )); then
  health_ok=false
  failure_reasons+=("provider_guard_blocked")
fi
if (( delete_failed_count > 0 )); then
  health_ok=false
  failure_reasons+=("delete_failed")
fi
if (( residual_count > 0 )); then
  health_ok=false
  failure_reasons+=("residual_worker_sessions_for_task")
fi
if (( worker_session_count < 0 )); then
  health_ok=false
  failure_reasons+=("worker_count_unavailable")
elif (( worker_session_count > max_worker_sessions )); then
  health_ok=false
  failure_reasons+=("worker_cap_exceeded")
fi

checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

reasons_csv=""
if (( ${#failure_reasons[@]} > 0 )); then
  reasons_csv="$(IFS=,; echo "${failure_reasons[*]}")"
fi

if [[ "$health_ok" == "true" ]]; then
  notify_event \
    "health_gate_ok" \
    "info" \
    "Health gate passed: ${task_id}" \
    "Cleanup succeeded and worker sessions are within cap (${worker_session_count}/${max_worker_sessions})."
  echo "health_ok task_id=${task_id} checked_at=${checked_at} archive_file=${archive_file} worker_sessions=${worker_session_count}/${max_worker_sessions}"
  exit 0
fi

notify_event \
  "health_gate_fail" \
  "error" \
  "Health gate failed: ${task_id}" \
  "Reasons: ${reasons_csv:-unknown}. Worker sessions ${worker_session_count}/${max_worker_sessions}."

echo "health_fail task_id=${task_id} checked_at=${checked_at} reasons=${reasons_csv:-unknown} archive_file=${archive_file} worker_sessions=${worker_session_count}/${max_worker_sessions}"
if (( strict )); then
  notify_event \
    "unattended_halt" \
    "error" \
    "Unattended halted: ${task_id}" \
    "Auto-dispatch halted due to health gate failure."
  exit 3
fi
echo "health_non_strict_continue task_id=${task_id} strict=0"
exit 0
