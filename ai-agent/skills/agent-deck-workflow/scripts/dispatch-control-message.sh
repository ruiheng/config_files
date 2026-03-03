#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  dispatch-control-message.sh
    --task-id <id>
    --planner-session-id <id|title>
    --to-session-id <id|title>
    --action <name>
    --artifact-path <path>
    [--from-session-id <id|title>]
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
    [--dry-run]

Examples:
  dispatch-control-message.sh \
    --task-id 20260225-1916-expiry-semantics \
    --planner-session-id planner \
    --to-session-id executor-20260225-1916-expiry-semantics \
    --action execute_delegate_task \
    --artifact-path .agent-artifacts/20260225-1916-expiry-semantics/delegate-task-20260225-1916-expiry-semantics.md \
    --cmd codex

Notes:
  - Sender identity is always derived from the current agent-deck session.
  - --from-session-id is optional and used only as an assertion;
    if provided, it must match the current session id.
  - If the target session does not exist and --group is omitted, the script uses the current session's group.
  - Newly created target sessions are always created with planner as parent.
  - For action=closeout_delivered, post-closeout health gate (cleanup + guard checks) is performed automatically after dispatch.
  - --artifact-path must be under .agent-artifacts/ and cannot contain path traversal.
  - --dry-run validates inputs and writes payload file but does not create/start/send sessions.
  - Dispatch notifications are filtered by ADWF_DISPATCH_NOTIFY:
      milestone (default): notify only key workflow milestones.
      all: notify all dispatch actions.
      none: suppress dispatch notifications.
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

validate_artifact_path() {
  local p="$1"
  [[ -n "$p" ]] || die "--artifact-path is required"
  [[ "$p" != /* ]] || die "--artifact-path must be a relative path under .agent-artifacts/"
  [[ "$p" == .agent-artifacts/* ]] || die "--artifact-path must start with .agent-artifacts/"
  [[ "$p" != *"../"* && "$p" != "../"* && "$p" != *"/.." ]] || die "--artifact-path must not contain path traversal"
}

profile=""
path="."
round="1"
ensure_session=1
start_session=1
dry_run=0
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
    --planner-session-id) planner_session_ref="$2"; shift 2 ;;
    --from-session-id) from_session_ref="$2"; shift 2 ;;
    --to-session-id) to_session_ref="$2"; shift 2 ;;
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
    --dry-run) dry_run=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$task_id" ]] || die "--task-id is required"
[[ -n "$planner_session_ref" ]] || die "--planner-session-id is required"
[[ -n "$to_session_ref" ]] || die "--to-session-id is required"
[[ -n "$action" ]] || die "--action is required"
validate_artifact_path "$artifact_path"

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [[ -n "$workflow_policy_json" ]]; then
  printf '%s' "$workflow_policy_json" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "--workflow-policy-json must be a valid JSON object"
fi

if (( dry_run )); then
  ensure_session=0
  start_session=0
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

should_notify_dispatch() {
  local action_name="$1"
  local mode="${ADWF_DISPATCH_NOTIFY:-milestone}"
  case "$mode" in
    none)
      return 1
      ;;
    all)
      return 0
      ;;
    milestone|"")
      case "$action_name" in
        execute_delegate_task|rework_required|stop_recommended|closeout_delivered)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      # Unknown mode: fail safe to milestone behavior.
      case "$action_name" in
        execute_delegate_task|rework_required|stop_recommended|closeout_delivered)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
  esac
}

resolve_session_id() {
  local ref="$1"
  local shown
  debug "resolve_session_id ref=${ref}"
  shown="$(ad session show "$ref" --json 2>/dev/null || true)"
  if [[ -z "$shown" ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$shown" | jq -r '.id // empty'
}

resolve_current_group() {
  local current
  debug "resolve_current_group"
  current="$(ad session current --json 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$current" | jq -r '.group // empty'
}

resolve_current_session_json() {
  debug "resolve_current_session_json"
  ad session current --json 2>/dev/null || true
}

created=0
planner_session_id="$(resolve_session_id "$planner_session_ref")"
[[ -n "$planner_session_id" ]] || die "failed to resolve planner session id from ref: $planner_session_ref"

current_session_json="$(resolve_current_session_json)"
[[ -n "$current_session_json" ]] || die "failed to resolve current agent-deck session; check tmux/session context with: agent-deck session current --json"

current_session_id="$(printf '%s' "$current_session_json" | jq -r '.id // empty')"
current_session_title="$(printf '%s' "$current_session_json" | jq -r '.title // empty')"
[[ -n "$current_session_id" ]] || die "current agent-deck session id is empty"

if [[ -n "$from_session_ref" ]]; then
  asserted_from_session_id="$(resolve_session_id "$from_session_ref")"
  [[ -n "$asserted_from_session_id" ]] || die "failed to resolve from session id from ref: $from_session_ref"
  if [[ "$asserted_from_session_id" != "$current_session_id" ]]; then
    die "--from-session-id assertion mismatch: expected current session id ${current_session_id}, got ${asserted_from_session_id}"
  fi
fi

from_session_id="$current_session_id"
if [[ -z "$from_session_ref" ]]; then
  from_session_ref="${current_session_title:-$current_session_id}"
fi

if (( ensure_session )); then
  debug "ensure_session enabled to_ref=${to_session_ref}"
  if ! ad session show "$to_session_ref" --json >/dev/null 2>&1; then
    if [[ -z "$group" ]]; then
      group="$(resolve_current_group)"
    fi
    [[ -n "$group" ]] || die "session missing and failed to resolve group from current session; pass --group explicitly"
    [[ -n "$cmd" ]] || die "session missing and --cmd not provided for creation"
    # Force a stable tree shape: all task sessions are children of planner.
    debug "creating session title=${to_session_ref} group=${group} parent=${planner_session_id} cmd=${cmd}"
    ad add "$path" --title "$to_session_ref" --group "$group" --cmd "$cmd" --parent "$planner_session_id" >/dev/null
    created=1
  fi
fi

to_session_id="$(resolve_session_id "$to_session_ref")"
[[ -n "$to_session_id" ]] || die "failed to resolve to session id from ref: $to_session_ref"

if [[ "$from_session_id" == "$to_session_id" ]]; then
  if [[ -n "$current_session_id" && "$current_session_id" == "$from_session_id" ]]; then
    echo "Receiver is this session; skipping dispatch. Continue locally."
    exit 0
  fi
  if [[ "${ADWF_DEBUG:-0}" == "1" ]]; then
    echo "DEBUG: inter-role dispatch within session ${from_session_id} (current=${current_session_id})" >&2
  fi
fi

if [[ -z "$message_file" ]]; then
  safe_from="${from_session_id//[^a-zA-Z0-9_.-]/_}"
  safe_to="${to_session_id//[^a-zA-Z0-9_.-]/_}"
  message_file=".agent-artifacts/${task_id}/messages/${safe_from}-to-${safe_to}-r${round}.json"
fi

mkdir -p "$(dirname "$message_file")"
# Build payload with jq --arg for robust JSON escaping (tabs, CR, control chars, etc.).
jq -n \
  --arg task_id "$task_id" \
  --arg planner_session_id "$planner_session_id" \
  --arg from_session_id "$from_session_id" \
  --arg to_session_id "$to_session_id" \
  --arg round "$round" \
  --arg action "$action" \
  --arg artifact_path "$artifact_path" \
  --arg note "$note" \
  '{
    task_id: $task_id,
    planner_session_id: $planner_session_id,
    required_skills: ["agent-deck-workflow"],
    from_session_id: $from_session_id,
    to_session_id: $to_session_id,
    round: $round,
    action: $action,
    artifact_path: $artifact_path,
    note: $note
  }' >"$message_file"

if [[ -n "$workflow_policy_json" ]]; then
  tmp_payload="$(mktemp)"
  jq --argjson workflow_policy "$workflow_policy_json" '. + {workflow_policy: $workflow_policy}' "$message_file" >"$tmp_payload"
  mv "$tmp_payload" "$message_file"
fi

started=0
if (( start_session )); then
  debug "starting to_session_id=${to_session_id}"
  if ad session start "$to_session_id" >/dev/null 2>&1; then
    started=1
  fi
fi

if (( dry_run )); then
  echo "dry_run_ok to=${to_session_id} created=${created} started=${started} payload=${message_file}"
  exit 0
fi

payload_json="$(cat "$message_file")"
if ! ad session send "$to_session_id" "$payload_json" >/dev/null 2>&1; then
  echo "dispatch_error action=${action} to=${to_session_id}" >&2
  echo "diagnostic_hint check_sender='agent-deck session current --json'" >&2
  echo "diagnostic_hint check_target='agent-deck session show ${to_session_ref} --json'" >&2
  echo "diagnostic_hint check_artifact='${artifact_path}'" >&2
  exit 5
fi
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
if should_notify_dispatch "$action"; then
  notify_event "$dispatch_event" "$dispatch_severity" "$dispatch_title" "$dispatch_message"
fi

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
    --planner-session-id "$planner_session_id"
    --executor-session-id "executor-${task_id}"
    --reviewer-session-id "$from_session_id"
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
