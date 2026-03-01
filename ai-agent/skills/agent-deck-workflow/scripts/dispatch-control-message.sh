#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  dispatch-control-message.sh
    --task-id <id>
    --planner-session <id|title>
    --to-session <id|title>
    --action <name>
    --artifact-path <path>
    [--from-session <id|title>]
    [--planner-session-id <id|title>]
    [--from-session-id <id|title>]
    [--to-session-id <id|title>]
    [--round <n|final>]
    [--note <text>]
    [--workflow-policy-json <json_object>]
    [--group <group>]
    [--cmd <tool>]
    [--path <project_path>]
    [--profile <profile>]
    [--message-file <path>]
    [--no-ensure-session]
    [--no-start-session]

Examples:
  dispatch-control-message.sh \
    --task-id 20260225-1916-expiry-semantics \
    --planner-session-id planner \
    --to-session-id executor-20260225-1916-expiry-semantics \
    --action execute_delegate_task \
    --artifact-path .agent-artifacts/20260225-1916-expiry-semantics/delegate-task-20260225-1916-expiry-semantics.md \
    --cmd codex

Notes:
  - If the target session does not exist and --group is omitted, the script uses the current session's group.
  - Newly created target sessions are always created with planner as parent.
  - For action=closeout_delivered, post-closeout health gate (cleanup + guard checks) is performed automatically after dispatch.
EOF
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

profile=""
path="."
round="1"
ensure_session=1
start_session=1
task_id=""
planner_session_ref=""
from_session_ref=""
to_session_ref=""
action=""
artifact_path=""
note="Read and follow the artifact file."
workflow_policy_json=""
group=""
cmd=""
message_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="$2"; shift 2 ;;
    --planner-session|--planner-session-id) planner_session_ref="$2"; shift 2 ;;
    --from-session|--from-session-id) from_session_ref="$2"; shift 2 ;;
    --to-session|--to-session-id) to_session_ref="$2"; shift 2 ;;
    --action) action="$2"; shift 2 ;;
    --artifact-path) artifact_path="$2"; shift 2 ;;
    --round) round="$2"; shift 2 ;;
    --note) note="$2"; shift 2 ;;
    --workflow-policy-json) workflow_policy_json="$2"; shift 2 ;;
    --group) group="$2"; shift 2 ;;
    --cmd) cmd="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --profile) profile="$2"; shift 2 ;;
    --message-file) message_file="$2"; shift 2 ;;
    --no-ensure-session) ensure_session=0; shift 1 ;;
    --no-start-session) start_session=0; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$task_id" ]] || die "--task-id is required"
[[ -n "$planner_session_ref" ]] || die "--planner-session (or --planner-session-id) is required"
[[ -n "$to_session_ref" ]] || die "--to-session (or --to-session-id) is required"
[[ -n "$action" ]] || die "--action is required"
[[ -n "$artifact_path" ]] || die "--artifact-path is required"

if [[ -z "$from_session_ref" ]]; then
  from_session_ref="$planner_session_ref"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [[ -n "$workflow_policy_json" ]]; then
  printf '%s' "$workflow_policy_json" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "--workflow-policy-json must be a valid JSON object"
fi

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
notify_script="${script_dir}/notify-workflow-event.sh"

artifact_root=".agent-artifacts"
if [[ "$artifact_path" == *"/${task_id}/"* ]]; then
  artifact_root="${artifact_path%%/${task_id}/*}"
  if [[ -z "$artifact_root" ]]; then
    artifact_root="."
  fi
fi

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

resolve_session_id() {
  local ref="$1"
  local shown
  shown="$(ad session show "$ref" --json 2>/dev/null || true)"
  if [[ -z "$shown" ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$shown" | jq -r '.id // empty'
}

resolve_current_group() {
  local current
  current="$(ad session current --json 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$current" | jq -r '.group // empty'
}

created=0
planner_session_id="$(resolve_session_id "$planner_session_ref")"
[[ -n "$planner_session_id" ]] || die "failed to resolve planner session id from ref: $planner_session_ref"

if (( ensure_session )); then
  if ! ad session show "$to_session_ref" --json >/dev/null 2>&1; then
    if [[ -z "$group" ]]; then
      group="$(resolve_current_group)"
    fi
    [[ -n "$group" ]] || die "session missing and failed to resolve group from current session; pass --group explicitly"
    [[ -n "$cmd" ]] || die "session missing and --cmd not provided for creation"
    # Force a stable tree shape: all task sessions are children of planner.
    ad add "$path" --title "$to_session_ref" --group "$group" --cmd "$cmd" --parent "$planner_session_id" >/dev/null
    created=1
  fi
fi

from_session_id="$(resolve_session_id "$from_session_ref")"
to_session_id="$(resolve_session_id "$to_session_ref")"

[[ -n "$from_session_id" ]] || die "failed to resolve from session id from ref: $from_session_ref"
[[ -n "$to_session_id" ]] || die "failed to resolve to session id from ref: $to_session_ref"

if [[ -z "$message_file" ]]; then
  safe_from="${from_session_id//[^a-zA-Z0-9_.-]/_}"
  safe_to="${to_session_id//[^a-zA-Z0-9_.-]/_}"
  message_file=".agent-artifacts/${task_id}/messages/${safe_from}-to-${safe_to}-r${round}.json"
fi

mkdir -p "$(dirname "$message_file")"
cat >"$message_file" <<EOF
{
  "task_id": "$(json_escape "$task_id")",
  "planner_session_id": "$(json_escape "$planner_session_id")",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "$(json_escape "$from_session_id")",
  "to_session_id": "$(json_escape "$to_session_id")",
  "round": "$(json_escape "$round")",
  "action": "$(json_escape "$action")",
  "artifact_path": "$(json_escape "$artifact_path")",
  "note": "$(json_escape "$note")"
}
EOF

if [[ -n "$workflow_policy_json" ]]; then
  tmp_payload="$(mktemp)"
  jq --argjson workflow_policy "$workflow_policy_json" '. + {workflow_policy: $workflow_policy}' "$message_file" >"$tmp_payload"
  mv "$tmp_payload" "$message_file"
fi

started=0
if (( start_session )); then
  if ad session start "$to_session_id" >/dev/null 2>&1; then
    started=1
  fi
fi

ad session send "$to_session_id" "$(cat "$message_file")" >/dev/null
show_json="$(ad session show "$to_session_id" --json)"

id=""
status=""
if command -v jq >/dev/null 2>&1; then
  id="$(printf '%s' "$show_json" | jq -r '.id // empty')"
  status="$(printf '%s' "$show_json" | jq -r '.status // empty')"
fi

echo "dispatch_ok to=${to_session_id} created=${created} started=${started} payload=${message_file}"
if [[ -n "$id" || -n "$status" ]]; then
  echo "session id=${id} status=${status}"
else
  echo "$show_json"
fi

dispatch_event="action_dispatched"
dispatch_severity="info"
dispatch_title="Workflow dispatch: ${task_id}"
dispatch_message="${action} ${from_session_ref} -> ${to_session_ref}"
case "$action" in
  execute_delegate_task)
    dispatch_event="delegate_dispatched"
    dispatch_title="Task delegated: ${task_id}"
    dispatch_message="Planner dispatched task to executor session ${to_session_ref}."
    ;;
  review_requested)
    dispatch_event="review_requested"
    dispatch_title="Review requested: ${task_id}"
    dispatch_message="Executor requested review from session ${to_session_ref}."
    ;;
  rework_required)
    dispatch_event="rework_required"
    dispatch_severity="warn"
    dispatch_title="Rework required: ${task_id}"
    dispatch_message="Reviewer requested executor rework."
    ;;
  stop_recommended)
    dispatch_event="stop_recommended"
    dispatch_severity="warn"
    dispatch_title="Stop recommended: ${task_id}"
    dispatch_message="Reviewer recommends stop and waits for user decision."
    ;;
  user_requested_iteration)
    dispatch_event="user_requested_iteration"
    dispatch_title="Iteration requested: ${task_id}"
    dispatch_message="User requested another implementation iteration."
    ;;
  closeout_delivered)
    dispatch_event="closeout_delivered"
    dispatch_title="Closeout delivered: ${task_id}"
    dispatch_message="Reviewer delivered closeout to planner."
    ;;
esac
notify_event "$dispatch_event" "$dispatch_severity" "$dispatch_title" "$dispatch_message"

# Automatic post-closeout cleanup:
# Once closeout is delivered to planner, archive provider resume metadata and remove task sessions.
if [[ "$action" == "closeout_delivered" ]]; then
  health_gate_script="${script_dir}/closeout-health-gate.sh"
  if [[ ! -x "$health_gate_script" ]]; then
    echo "health_gate_warn missing_script=${health_gate_script}"
    exit 0
  fi

  unattended_mode=0
  if [[ -n "$workflow_policy_json" ]]; then
    if jq -e '(.mode // "") == "unattended" or (.auto_dispatch_next_task == true)' >/dev/null 2>&1 <<<"$workflow_policy_json"; then
      unattended_mode=1
    fi
  fi

  health_gate_cmd=(
    "$health_gate_script"
    --task-id "$task_id"
    --planner-session "$planner_session_ref"
    --executor-session "executor-${task_id}"
    --reviewer-session "$from_session_ref"
    --artifact-root "$artifact_root"
    --max-worker-sessions 2
  )
  if [[ -n "$profile" ]]; then
    health_gate_cmd+=(--profile "$profile")
  fi
  if (( unattended_mode )); then
    health_gate_cmd+=(--strict)
  fi

  if health_output="$("${health_gate_cmd[@]}" 2>&1)"; then
    echo "health_gate_ok task_id=${task_id} unattended=${unattended_mode}"
    echo "$health_output"
  else
    echo "health_gate_warn task_id=${task_id} unattended=${unattended_mode} status=failed"
    echo "$health_output"
    if (( unattended_mode )); then
      echo "unattended_halt task_id=${task_id} reason=health_gate_failed"
      exit 4
    fi
  fi
fi
