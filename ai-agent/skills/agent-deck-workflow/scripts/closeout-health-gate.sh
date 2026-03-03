#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Closeout health gate for agent-deck workflow.

This script runs one-shot post-closeout checks with minimal agent-side orchestration:
1) archive+cleanup executor/reviewer sessions
2) verify cleanup result for this task
3) verify global worker-session cap (to prevent unattended error accumulation)
4) write workflow health report

Usage:
  closeout-health-gate.sh [options]

Options:
  --task-id <id>                 Required task id (YYYYMMDD-HHMM-<slug>)
  --planner-session-id <id|title>   Planner session ref (default: planner)
  --executor-session-id <id|title>  Executor session ref (default: executor-<task_id>)
  --reviewer-session-id <id|title>  Reviewer session ref (default: reviewer-<task_id>)
  --artifact-root <path>         Artifact root (default: .agent-artifacts)
  --profile <name>               Agent-deck profile
  --max-worker-sessions <n>      Max allowed lingering worker sessions (default: 2)
  --strict                       Fail-closed mode. Exit 3 when health gate fails.
  -h, --help                     Show help

Outputs:
  - Health file:
      <artifact-root>/workflow-health/health-<task_id>.json
  - Latest health pointer:
      <artifact-root>/workflow-health/latest.json
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

task_id=""
planner_session_ref="planner"
executor_session_ref=""
reviewer_session_ref=""
artifact_root=".agent-artifacts"
profile=""
max_worker_sessions=2
strict=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --executor-session-id) executor_session_ref="${2:-}"; shift 2 ;;
    --reviewer-session-id) reviewer_session_ref="${2:-}"; shift 2 ;;
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

if [[ -z "$executor_session_ref" ]]; then
  executor_session_ref="executor-${task_id}"
fi
if [[ -z "$reviewer_session_ref" ]]; then
  reviewer_session_ref="reviewer-${task_id}"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

count_worker_sessions() {
  local list_json
  list_json="$(ad list --json 2>/dev/null || true)"
  if [[ -z "$list_json" ]]; then
    echo "-1"
    return 0
  fi
  jq -r '
    if type != "array" then
      -1
    else
      [ .[] | select(((.title // "") | test("^(executor|reviewer)-"))) ] | length
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
  --executor-session-id "$executor_session_ref"
  --reviewer-session-id "$reviewer_session_ref"
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
  residual_count="$(jq -r '[.sessions[]? | select(.found == true and (.delete_status != "deleted" and .delete_status != "not_found"))] | length' "$archive_file" 2>/dev/null || echo 0)"
fi

worker_session_count="$(count_worker_sessions)"

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

health_dir="${artifact_root%/}/workflow-health"
mkdir -p "$health_dir"
health_file="${health_dir}/health-${task_id}.json"
latest_file="${health_dir}/latest.json"
checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

reasons_csv=""
if (( ${#failure_reasons[@]} > 0 )); then
  reasons_csv="$(IFS=,; echo "${failure_reasons[*]}")"
fi

jq -n \
  --arg task_id "$task_id" \
  --arg checked_at "$checked_at" \
  --arg profile_name "${profile:-default}" \
  --arg archive_file "$archive_file" \
  --argjson strict "$strict" \
  --argjson cleanup_exit_code "$cleanup_rc" \
  --argjson archive_exists "$archive_exists" \
  --argjson blocked_count "$blocked_count" \
  --argjson delete_failed_count "$delete_failed_count" \
  --argjson residual_count "$residual_count" \
  --argjson worker_session_count "$worker_session_count" \
  --argjson max_worker_sessions "$max_worker_sessions" \
  --arg reasons_csv "$reasons_csv" \
  --argjson health_ok "$health_ok" \
  '{
    task_id: $task_id,
    checked_at: $checked_at,
    profile_name: $profile_name,
    strict: ($strict == 1),
    cleanup_exit_code: $cleanup_exit_code,
    archive_file: $archive_file,
    archive_exists: $archive_exists,
    blocked_count: $blocked_count,
    delete_failed_count: $delete_failed_count,
    residual_count: $residual_count,
    worker_session_count: $worker_session_count,
    max_worker_sessions: $max_worker_sessions,
    health_ok: $health_ok,
    failure_reasons: (if $reasons_csv == "" then [] else ($reasons_csv | split(",")) end)
  }' >"$health_file"

cp "$health_file" "$latest_file"

if [[ "$health_ok" == "true" ]]; then
  notify_event \
    "health_gate_ok" \
    "info" \
    "Health gate passed: ${task_id}" \
    "Cleanup succeeded and worker sessions are within cap (${worker_session_count}/${max_worker_sessions})."
  echo "health_ok task_id=${task_id} worker_sessions=${worker_session_count}/${max_worker_sessions} file=${health_file}"
  exit 0
fi

notify_event \
  "health_gate_fail" \
  "error" \
  "Health gate failed: ${task_id}" \
  "Reasons: ${reasons_csv:-unknown}. Worker sessions ${worker_session_count}/${max_worker_sessions}."

echo "health_fail task_id=${task_id} reasons=${reasons_csv:-unknown} worker_sessions=${worker_session_count}/${max_worker_sessions} file=${health_file}"
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
